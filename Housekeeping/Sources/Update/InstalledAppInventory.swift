import Foundation

// Housekeeping — Update inventory
//
// The list of things that could be updated is built from two sources that are
// asked separately and then joined: the `.app` bundles on disk, and Homebrew's
// own record of what it installed. Neither is trusted to describe the other. The
// bundles say what exists; Homebrew says what it owns; the join is by the app's
// filename *inside the bundle path*, because that is the value Homebrew's own
// artifact list carries. Matching on the bundle identifier would look tidier and
// would be wrong — Homebrew does not record it.
//
// Nothing here launches an application or reads a version by asking the app. An
// `Info.plist` is a file, and reading a file is what Housekeeping already knows
// how to do safely.

/// Everything one pass over the machine produced. The notes are for the screen:
/// the reasons a source could not be read belong in front of the reader, not in
/// a log.
struct UpdateInventory {
    let applications: [InstalledApplication]
    let packages: [BrewPackage]
    let notes: [String]
    /// True when `brew` was found. False turns every Homebrew row into an honest
    /// "Homebrew is not installed here" rather than a silent omission.
    let homebrewAvailable: Bool
}

enum AppInventory {
    /// The folders searched. `/System/Applications` is included so the sheet can
    /// list what belongs to macOS and say plainly that it will not be touched;
    /// an omission would leave a reader wondering where those apps went.
    static func scanDirectories(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            homeDirectory.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
        ]
    }

    /// Walks the folders, joins against Homebrew, and classifies each bundle. The
    /// work is serial: every classification runs `codesign` and `xattr`, and
    /// running those against a whole machine at once would spawn hundreds of
    /// processes to no benefit.
    static func scan(
        using runner: ProcessRunner,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) async throws -> UpdateInventory {
        var notes: [String] = []

        // Homebrew first, so its answers are in hand when the bundles are read.
        var caskTokenByApp: [String: String] = [:]
        var caskPackages: [BrewPackage] = []
        var formulaPackages: [BrewPackage] = []
        var homebrewAvailable = false

        if let brew = ProcessRunner.brewPath(fileManager: fileManager) {
            homebrewAvailable = true
            let caskResult = try await readCasks(brew: brew, runner: runner)
            caskTokenByApp = caskResult.byApp
            caskPackages = caskResult.packages
            if let note = caskResult.note { notes.append(note) }
            let formulaResult = try await readFormulae(brew: brew, runner: runner)
            formulaPackages = formulaResult
        } else {
            notes.append("Homebrew is not installed on this Mac, so its packages are not listed.")
        }

        // Then the bundles.
        var applications: [InstalledApplication] = []
        var seenPaths = Set<String>()
        let directories = scanDirectories(homeDirectory: homeDirectory)

        for directory in directories {
            try Task.checkCancellation()
            let entries = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries where entry.pathExtension == "app" {
                try Task.checkCancellation()
                let standardized = entry.standardizedFileURL.resolvingSymlinksInPath()
                guard !seenPaths.contains(standardized.path) else { continue }
                seenPaths.insert(standardized.path)
                if let application = await readApplication(
                    at: entry,
                    caskToken: caskTokenByApp[entry.lastPathComponent],
                    runner: runner,
                    fileManager: fileManager
                ) {
                    applications.append(application)
                }
            }
        }

        // A cask whose bundle is not on disk — the helper casks with no `.app`,
        // and the cases where the app was removed by hand. Only the ones that
        // were never matched to a bundle become rows of their own.
        let matchedTokens = Set(caskTokenByApp.values)
        let unmatchedCasks = caskPackages.filter { !matchedTokens.contains($0.name) }

        applications.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let packages = (unmatchedCasks + formulaPackages)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return UpdateInventory(
            applications: applications,
            packages: packages,
            notes: notes,
            homebrewAvailable: homebrewAvailable
        )
    }

    // MARK: - One bundle

    static func readApplication(
        at url: URL,
        caskToken: String?,
        runner: ProcessRunner,
        fileManager: FileManager = .default
    ) async -> InstalledApplication? {
        guard let info = readInfoPlist(bundleAt: url, fileManager: fileManager) else { return nil }
        let identifier = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A bundle with no identifier is not offered for update: every key this
        // feature uses to recognise an application a second time would be absent.
        guard !identifier.isEmpty else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? ""
        let build = info["CFBundleVersion"] as? String
        let feedURL = (info["SUFeedURL"] as? String).flatMap { URL(string: $0) }

        let facts = BundleFacts(
            url: url,
            bundleIdentifier: identifier,
            name: name,
            version: version,
            build: build,
            feedURL: feedURL,
            homebrewCaskToken: caskToken,
            githubRepo: AppUpdateEngine.knownGitHubRepos[identifier]
        )
        let (provenance, evidence) = await AppProvenance.assess(facts: facts, using: runner)
        let signature = await AppProvenance.readSignature(bundleAt: url, using: runner)

        return InstalledApplication(
            bundleIdentifier: identifier,
            name: name,
            path: url.path,
            version: version,
            build: build,
            team: signature.teamIdentifier,
            isAdHoc: signature.isAdHoc || !signature.isSigned,
            feedURL: feedURL,
            provenance: provenance,
            evidence: evidence
        )
    }

    /// Reads `Contents/Info.plist` without opening the application. A bundle is a
    /// directory of files and this is one of them; `Bundle(url:)` would also work
    /// but caches, which is the last thing wanted when the point is to observe
    /// what is on disk right now.
    static func readInfoPlist(bundleAt url: URL, fileManager: FileManager = .default) -> [String: Any]? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return parsed as? [String: Any]
    }

    // MARK: - Homebrew

    private struct CaskRead {
        let byApp: [String: String]
        let packages: [BrewPackage]
        let note: String?
    }

    private static func readCasks(brew: String, runner: ProcessRunner) async throws -> CaskRead {
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: brew,
                arguments: ["info", "--json=v2", "--installed", "--cask"],
                timeout: 60
            )
        } catch {
            return CaskRead(byApp: [:], packages: [], note: "Homebrew's list of installed applications could not be read.")
        }
        guard result.succeeded else {
            return CaskRead(byApp: [:], packages: [], note: "Homebrew returned an error while listing installed applications.")
        }
        guard let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else {
            return CaskRead(byApp: [:], packages: [], note: "Homebrew's list of installed applications was not in the expected form.")
        }

        var byApp: [String: String] = [:]
        var packages: [BrewPackage] = []
        for cask in casks {
            guard let token = cask["token"] as? String else { continue }
            let installed = (cask["installed"] as? String) ?? ""
            let versions = cask["versions"] as? [String: Any]
            let current = (versions?["stable"] as? String) ?? installed

            var appFilenames: [String] = []
            for artifact in (cask["artifacts"] as? [[String: Any]]) ?? [] {
                if let apps = artifact["app"] as? [String] {
                    appFilenames.append(contentsOf: apps.map { ($0 as NSString).lastPathComponent })
                }
            }

            if appFilenames.isEmpty {
                packages.append(BrewPackage(
                    name: token, isCask: true,
                    installedVersion: installed, currentVersion: current, isPinned: false
                ))
            } else {
                for filename in appFilenames { byApp[filename] = token }
            }
        }
        return CaskRead(byApp: byApp, packages: packages, note: nil)
    }

    private static func readFormulae(brew: String, runner: ProcessRunner) async throws -> [BrewPackage] {
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: brew,
                arguments: ["info", "--json=v2", "--installed"],
                timeout: 60
            )
        } catch {
            return []
        }
        guard result.succeeded,
              let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]] else {
            return []
        }

        var packages: [BrewPackage] = []
        for formula in formulae {
            guard let name = formula["name"] as? String else { continue }
            let installedList = (formula["installed"] as? [[String: Any]]) ?? []
            let installed = installedList.compactMap { $0["version"] as? String }.last ?? ""
            let versions = formula["versions"] as? [String: Any]
            let current = (versions?["stable"] as? String) ?? installed
            let isPinned = (formula["pinned"] as? Bool) ?? false
            packages.append(BrewPackage(
                name: name, isCask: false,
                installedVersion: installed, currentVersion: current, isPinned: isPinned
            ))
        }
        return packages
    }
}
