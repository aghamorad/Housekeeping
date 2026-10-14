import Foundation

// Housekeeping — the self-update itself
//
// This repository publishes source, not builds, and its release page lags far
// behind `main`. So "update" here cannot mean downloading anything: it means
// fast-forwarding the folder this copy was built from and building it again.
//
// That is a heavier action than anything else in the app, and the one that can
// end with no Housekeeping at all if it is done carelessly. Three rules keep
// that from happening, and every step below exists to serve one of them:
//
//  1. Nothing is replaced until a complete, signed new copy is sitting on disk
//     and has been verified.
//  2. The old copy is moved aside rather than deleted, and is put back if the
//     new one fails to go in.
//  3. The replacement happens in a detached script that waits for this process
//     to exit. An app cannot overwrite itself while it is running, and a helper
//     launched by it can.

// MARK: - Finding the tree

/// Finds the source folder this copy was built from.
///
/// It has to be found rather than assumed: the folder may have been moved,
/// renamed, or never existed on this machine at all — the app could have been
/// built elsewhere and copied here. When it cannot be found, the honest answer is
/// to say so and offer to be pointed at it, which is what the screen does.
enum SourceTreeLocator {
    private static let rememberedKey = "SelfUpdateSourceTree"

    /// Every place worth looking, in the order worth looking in. The bundle's own
    /// ancestors come first: a copy run straight out of `dist/` inside the tree
    /// should update the tree it is standing in, which is the case where the
    /// answer is already known and nothing needs to be guessed.
    static func candidates(bundle: Bundle = .main) -> [URL] {
        var found: [URL] = []

        if let remembered = UserDefaults.standard.string(forKey: rememberedKey) {
            found.append(URL(fileURLWithPath: remembered))
        }

        var ancestor = bundle.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            found.append(ancestor)
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { break }
            ancestor = parent
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        for relative in ["Claude/Housekeeping", "Documents/Housekeeping", "Desktop/Housekeeping", "Housekeeping"] {
            found.append(home.appendingPathComponent(relative))
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func locate(bundle: Bundle = .main) -> SelfUpdateSource? {
        for candidate in candidates(bundle: bundle) where isSourceTree(candidate) {
            return SelfUpdateSource(
                tree: candidate,
                remoteMatches: remoteMatches(candidate),
                destination: bundle.bundleURL
            )
        }
        return nil
    }

    /// Records a folder the reader picked by hand, so the next check does not ask
    /// again.
    static func remember(_ tree: URL) {
        UserDefaults.standard.set(tree.path, forKey: rememberedKey)
    }

    static func isSourceTree(_ url: URL) -> Bool {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        // All three have to be there. `.git` alone would match any checkout of
        // any repository, and a folder that is not this project cannot build it.
        return manager.fileExists(atPath: url.appendingPathComponent(".git").path)
            && manager.fileExists(atPath: url.appendingPathComponent("script/package_release.sh").path)
            && manager.fileExists(atPath: url.appendingPathComponent("Housekeeping/Info.plist").path)
    }

    /// Whether `origin` points at the published repository.
    ///
    /// Read straight out of `.git/config` rather than by running `git`: this is
    /// called while the window is being built, and spawning a process to answer
    /// a question that is written down in a text file would be a poor trade.
    static func remoteMatches(_ tree: URL) -> Bool {
        guard let config = gitConfig(at: tree),
              let text = try? String(contentsOf: config, encoding: .utf8) else {
            return false
        }
        return text.lowercased().contains(SelfUpdateChecker.slug.lowercased())
    }

    private static func gitConfig(at tree: URL) -> URL? {
        let manager = FileManager.default
        let dotGit = tree.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }

        if isDirectory.boolValue {
            return dotGit.appendingPathComponent("config")
        }
        // A worktree or a submodule: `.git` is a file holding the real path.
        guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = pointer.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else {
            return nil
        }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let base = path.hasPrefix("/") ? URL(fileURLWithPath: path) : tree.appendingPathComponent(path)
        return base.appendingPathComponent("config")
    }
}

// MARK: - Doing the work

/// Runs an update: fast-forward the tree, build a new copy, verify it, then hand
/// the swap to a detached script and quit.
@MainActor
final class SelfUpdateEngine {
    private let runner = ProcessRunner()
    private let git = "/usr/bin/git"

    /// Everything the update needs to be sure of before it starts. Produced by
    /// the screen, shown to the reader, and then executed unchanged — the plan
    /// and the run read the same values so they cannot drift apart.
    struct Plan {
        let source: SelfUpdateSource
        let behindBy: Int?
        let remoteCommit: String
        let version: String
    }

    /// Runs the plan. `progress` is called on the main actor for every step
    /// transition, so the screen can show the same list it showed as a plan with
    /// ticks appearing against it.
    func perform(
        plan: Plan,
        progress: @escaping (SelfUpdateStep, SelfUpdateStepState) -> Void
    ) async throws -> URL {
        let tree = plan.source.tree
        let branch = SelfUpdateChecker.branch

        // 1. Fetch. Done before anything is touched, so a network failure costs
        //    nothing at all.
        progress(.fetch, .running)
        let fetched = try await runner.run(
            executable: git,
            arguments: ["fetch", "--prune", "origin", branch],
            currentDirectory: tree,
            timeout: 300
        )
        guard fetched.succeeded else {
            throw SelfUpdateFailure.commandFailed(step: .fetch, message: message(from: fetched))
        }
        progress(.fetch, .done(plan.remoteCommit.isEmpty ? "up to date" : String(plan.remoteCommit.prefix(7))))

        // 2. Refuse to update over uncommitted work.
        //
        //    Only *tracked* modifications stop this. Untracked files are almost
        //    always build output — `dist/`, `.build/` — and a fast-forward cannot
        //    collide with something git is not tracking, so treating them as
        //    dirt would refuse every update on a tree that has ever been built.
        let status = try await runner.run(
            executable: git,
            arguments: ["status", "--porcelain", "--untracked-files=no"],
            currentDirectory: tree,
            timeout: 60
        )
        let dirty = status.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard dirty.isEmpty else {
            throw SelfUpdateFailure.dirtyTree(files: dirty)
        }

        // 3. Fast-forward only. Never a merge commit, never a rebase: if the
        //    folder has its own history this stops and says so, because deciding
        //    how to reconcile two histories is not a decision an update button
        //    gets to make.
        progress(.pull, .running)
        let pulled = try await runner.run(
            executable: git,
            arguments: ["merge", "--ff-only", "origin/\(branch)"],
            currentDirectory: tree,
            timeout: 120
        )
        guard pulled.succeeded else {
            let said = message(from: pulled)
            if said.lowercased().contains("not possible to fast-forward") {
                throw SelfUpdateFailure.notFastForward
            }
            throw SelfUpdateFailure.commandFailed(step: .pull, message: said)
        }
        let shortHead = (try? await runner.run(
            executable: git,
            arguments: ["rev-parse", "--short", "HEAD"],
            currentDirectory: tree,
            timeout: 30
        )).map { $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        progress(.pull, .done(shortHead))

        // 4. Build.
        let staging = try makeStagingDirectory()
        progress(.build, .running)
        let built = try await runner.run(
            executable: "/bin/bash",
            arguments: ["script/package_release.sh", staging.path],
            environment: buildEnvironment(),
            currentDirectory: tree,
            timeout: 1800
        )
        let newBundle = staging.appendingPathComponent("Housekeeping.app")
        guard built.succeeded else {
            throw SelfUpdateFailure.commandFailed(step: .build, message: message(from: built))
        }
        progress(.build, .done("built"))

        // 5. Verify before anything is believed about it. A copy that is not
        //    signed, or has no executable inside, is not a copy worth swapping in.
        progress(.verify, .running)
        guard FileManager.default.fileExists(atPath: newBundle.appendingPathComponent("Contents/MacOS/Housekeeping").path) else {
            throw SelfUpdateFailure.buildProducedNothing(path: newBundle.path)
        }
        let verified = try await runner.run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", newBundle.path],
            timeout: 180
        )
        guard verified.succeeded else {
            throw SelfUpdateFailure.commandFailed(step: .verify, message: message(from: verified))
        }
        progress(.verify, .done("signed"))

        // 6. Hand off the swap.
        let destination = plan.source.destination
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw SelfUpdateFailure.stageUnwritable(path: staging.path)
        }

        progress(.swap, .running)
        let script = try writeSwapScript(staged: newBundle, staging: staging)
        let keep = keepPath(version: plan.version)
        progress(.swap, .done("ready"))
        launchSwapper(script: script, staged: newBundle, destination: destination, keep: keep, staging: staging)

        // The sixth step is not ticked here. It is not done until the new copy is
        // open, and this process is not going to be around to see it — the script
        // it just launched is the only thing that will know.
        return newBundle
    }

    // MARK: - Pieces

    private func message(from result: ProcessRunner.Result) -> String {
        if result.timedOut {
            return "It ran past its time limit and was stopped."
        }
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? result.stdout : err
    }

    /// A build folder under Housekeeping's own Application Support directory.
    /// Same volume as the application, which keeps the final copy a move rather
    /// than a copy across disks.
    private func makeStagingDirectory() throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let staging = support
            .appendingPathComponent("Housekeeping", isDirectory: true)
            .appendingPathComponent("Staged", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// A windowed app launched from the Finder inherits almost nothing. `swiftc`
    /// and `xcrun` live in `/usr/bin`, but the release script also reaches for
    /// tools under Homebrew's prefixes on some configurations, so the search path
    /// is stated rather than inherited.
    private func buildEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        environment["PATH"] = (extra + existing).joined(separator: ":")
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        return environment
    }

    /// A build artifact carries no quarantine flag, so `xattr` in the script is
    /// belt and braces — but the flag has appeared on bundles copied across
    /// volumes before, and a quarantined app fails to open with a dialog rather
    /// than an explanation.
    private func writeSwapScript(staged: URL, staging: URL) throws -> URL {
        let script = staging.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/sh
        # Written by Housekeeping at update time. Waits for the running copy to
        # exit, moves it aside, puts the new one in its place, and reopens it.
        # Nothing here deletes the old copy — it stays in Application Support.
        set -u
        PID="$1"
        NEW="$2"
        DEST="$3"
        KEEP="$4"
        STAGE="$5"

        waited=0
        while kill -0 "$PID" 2>/dev/null; do
            waited=$((waited + 1))
            [ "$waited" -gt 300 ] && break
            sleep 0.2
        done

        /bin/mkdir -p "$(/usr/bin/dirname "$KEEP")" || exit 1

        if [ -e "$DEST" ]; then
            /bin/mv "$DEST" "$KEEP" || exit 1
        fi

        if /bin/cp -R "$NEW" "$DEST"; then
            /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
            /usr/bin/open "$DEST"
            /bin/rm -rf "$STAGE"
        else
            # Put the old copy back rather than leaving the machine with neither.
            if [ -e "$KEEP" ]; then /bin/mv "$KEEP" "$DEST"; fi
            exit 1
        fi
        """

        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    /// The old copy is kept, not overwritten. If a name is already taken the
    /// previous one is left alone and this update gets its own.
    private func uniqueName(version: String) -> String {
        let manager = FileManager.default
        let support = (try? manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
        let previous = support?
            .appendingPathComponent("Housekeeping", isDirectory: true)
            .appendingPathComponent("Previous", isDirectory: true)
        let label = version.isEmpty ? "Housekeeping" : "Housekeeping-\(version)"
        var candidate = "\(label).app"
        var counter = 2
        while let previous, manager.fileExists(atPath: previous.appendingPathComponent(candidate).path) {
            candidate = "\(label)-\(counter).app"
            counter += 1
            if counter > 50 { break }
        }
        return candidate
    }

    private func launchSwapper(script: URL, staged: URL, destination: URL, keep: String, staging: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(getpid()), staged.path, destination.path, keep, staging.path]
        // Detached: this process is about to exit, and the child has to outlive
        // it. Pointing all three streams at the null device is what stops the
        // child dying of a broken pipe the moment its parent goes away.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Where the outgoing copy is kept. The script is handed this as an argument
    /// rather than deriving it, so the path the app reports and the path the
    /// script moves to are the same string.
    private func keepPath(version: String) -> String {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Housekeeping", isDirectory: true)
            .appendingPathComponent("Previous", isDirectory: true)
            .appendingPathComponent(uniqueName(version: version))
            .path
    }
}
