// Housekeeping — the tools pipx, uv and npm installed
//
// Homebrew's own copies are already covered by `EnvironmentAudit`: it compares
// what Homebrew installed with what the search path actually reaches. This file
// answers the same question for the other three managers, because they fail in a
// way Homebrew's own report never sees.
//
// pipx and uv install each Python tool into a folder of its own and leave a
// small launcher in `~/.local/bin`. npm leaves links in Homebrew's `bin`. The
// launcher is a file on the search path like any other, so an older copy of the
// same name from anywhere — a python.org framework installer, a hand-run `pip
// install`, a second package manager — quietly wins, and the tool you updated
// is the one that never runs. That is the whole shape of the pymobiledevice3
// case this file was written for.
//
// The rules from the rest of the audit hold here. A duplicate is not a fault:
// two Python versions side by side are ordinary, and are reported as a fact
// rather than a warning. A finding is only made when the copy that wins is a
// *different installation* from the one the manager owns, and only when the
// managed copy is the same version or newer. Reordering a line in the reader's
// own profile is offered as the fix; nothing inside a system framework is
// touched, and nothing is installed or removed.

import Foundation

/// One command a package manager installed, and where its launcher should be.
struct ManagedTool {
    let command: String
    let manager: String
    let package: String
    let version: String?
    let launcherDirectory: String
    let launcherExists: Bool
    /// The folder the manager actually keeps the tool in. A file that resolves
    /// into here is the manager's own copy, wherever the launcher is.
    let managedRoot: String
}

struct LanguageToolAudit: Sendable {
    let runner: ProcessRunner
    let homePath: String
    let brewPath: String?
    let brewPrefix: String?

    func findings(shell: ShellPathModel) async -> (findings: [EnvironmentFinding], notes: [String]) {
        var findings: [EnvironmentFinding] = []
        var notes: [String] = []
        let home = homePath
        let localBin = "\(home)/.local/bin"
        let searchDirectories = shell.searchDirectories

        let pipx = await pipxTools(searchDirectories: searchDirectories, localBin: localBin, notes: &notes)
        let uv = await uvTools(searchDirectories: searchDirectories, localBin: localBin, notes: &notes)
        let npm = await npmTools(searchDirectories: searchDirectories, notes: &notes)
        let managed = pipx + uv + npm

        for tool in managed {
            if !tool.launcherExists {
                findings.append(missingLauncher(tool))
                continue
            }
            if let finding = await shadowed(tool, shell: shell) {
                findings.append(finding)
            }
        }

        findings.append(contentsOf: await pythonFindings(shell: shell, notes: &notes))
        findings.append(contentsOf: await keyCommandFindings(shell: shell))
        findings.append(contentsOf: globalPackageFindings(home: home))

        return (findings, notes)
    }

    // MARK: - pipx

    private func pipxTools(
        searchDirectories: [String],
        localBin: String,
        notes: inout [String]
    ) async -> [ManagedTool] {
        guard let pipxPath = firstExecutable(named: "pipx", in: searchDirectories) else { return [] }

        var versions: [String: String] = [:]
        do {
            let result = try await runner.run(
                executable: pipxPath,
                arguments: ["list", "--json"],
                environment: environment(path: searchDirectories),
                timeout: 30
            )
            if result.succeeded,
               let data = result.stdout.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let venvs = json["venvs"] as? [String: Any] {
                for (tool, raw) in venvs {
                    let dictionary = raw as? [String: Any]
                    let metadata = dictionary?["metadata"] as? [String: Any]
                    let main = metadata?["main_package"] as? [String: Any]
                    if let version = main?["package_version"] as? String {
                        versions[tool] = version
                    }
                }
            } else {
                notes.append("pipx is installed but did not list its tools, so only the launchers that are on disk were read.")
            }
        } catch {
            notes.append("pipx could not be asked about its tools: \(error.localizedDescription)")
        }

        var tools: [ManagedTool] = []
        let managedRoot = "\(homePath)/.local/pipx/venvs"

        // The launchers are what matter, so they are read first. A symlink into
        // a pipx venv is proof of both the tool and the name it answers to,
        // including packages whose program name differs from the package name.
        if let names = try? FileManager.default.contentsOfDirectory(atPath: localBin) {
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = "\(localBin)/\(name)"
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { continue }
                let resolved = target.hasPrefix("/") ? target : "\(localBin)/\(target)"
                guard resolved.contains("/pipx/venvs/") else { continue }
                let package = Self.component(after: "/pipx/venvs/", in: resolved) ?? name
                tools.append(ManagedTool(
                    command: name,
                    manager: "pipx",
                    package: package,
                    version: versions[package],
                    launcherDirectory: localBin,
                    launcherExists: true,
                    managedRoot: managedRoot
                ))
            }
        }

        // pipx can also create wrapper scripts rather than symlinks. The list's
        // own names are the fallback, and whether the wrapper is there is read
        // from disk rather than assumed.
        if tools.isEmpty {
            for (package, version) in versions.sorted(by: { $0.key < $1.key }) {
                let launcher = "\(localBin)/\(package)"
                tools.append(ManagedTool(
                    command: package,
                    manager: "pipx",
                    package: package,
                    version: version,
                    launcherDirectory: localBin,
                    launcherExists: FileManager.default.isExecutableFile(atPath: launcher),
                    managedRoot: managedRoot
                ))
            }
        }
        return tools
    }

    // MARK: - uv

    private func uvTools(
        searchDirectories: [String],
        localBin: String,
        notes: inout [String]
    ) async -> [ManagedTool] {
        guard let uvPath = firstExecutable(named: "uv", in: searchDirectories) else { return [] }

        var versions: [String: String] = [:]
        if let result = try? await runner.run(
            executable: uvPath,
            arguments: ["tool", "list"],
            environment: environment(path: searchDirectories),
            timeout: 20
        ), result.succeeded {
            // Plain output is one tool per line ("name v1.2.3") with its
            // programs indented beneath it. Only the tool lines are read.
            for line in result.stdout.split(separator: "\n").map(String.init) {
                guard line.first != " ", line.first != "\t" else { continue }
                let parts = line.split(separator: " ").map(String.init)
                guard let name = parts.first else { continue }
                let version = parts.dropFirst().first { $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }
                versions[name] = version.map { String($0.dropFirst()) }
            }
        }

        var tools: [ManagedTool] = []
        let managedRoot = "\(homePath)/.local/share/uv/tools"

        if let names = try? FileManager.default.contentsOfDirectory(atPath: localBin) {
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = "\(localBin)/\(name)"
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { continue }
                let resolved = target.hasPrefix("/") ? target : "\(localBin)/\(target)"
                guard resolved.contains("/uv/tools/") else { continue }
                let package = Self.component(after: "/uv/tools/", in: resolved) ?? name
                tools.append(ManagedTool(
                    command: name,
                    manager: "uv",
                    package: package,
                    version: versions[package],
                    launcherDirectory: localBin,
                    launcherExists: true,
                    managedRoot: managedRoot
                ))
            }
        }

        if tools.isEmpty {
            for (package, version) in versions.sorted(by: { $0.key < $1.key }) {
                let launcher = "\(localBin)/\(package)"
                tools.append(ManagedTool(
                    command: package,
                    manager: "uv",
                    package: package,
                    version: version,
                    launcherDirectory: localBin,
                    launcherExists: FileManager.default.isExecutableFile(atPath: launcher),
                    managedRoot: managedRoot
                ))
            }
        }
        return tools
    }

    // MARK: - npm

    private func npmTools(
        searchDirectories: [String],
        notes: inout [String]
    ) async -> [ManagedTool] {
        guard let prefix = brewPrefix else { return [] }
        let bin = "\(prefix)/bin"
        let modules = "\(prefix)/lib/node_modules"
        guard FileManager.default.fileExists(atPath: modules) else { return [] }
        guard let npmPath = firstExecutable(named: "npm", in: searchDirectories) else { return [] }

        var versions: [String: String] = [:]
        if let result = try? await runner.run(
            executable: npmPath,
            arguments: ["ls", "-g", "--depth=0", "--json"],
            environment: environment(path: searchDirectories),
            timeout: 40
        ), let data = result.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dependencies = json["dependencies"] as? [String: Any] {
            for (package, raw) in dependencies {
                if let version = (raw as? [String: Any])?["version"] as? String {
                    versions[package] = version
                }
            }
        } else {
            notes.append("npm is installed but did not list its global packages; the links in Homebrew's bin folder were read instead.")
        }

        var tools: [ManagedTool] = []
        if let names = try? FileManager.default.contentsOfDirectory(atPath: bin) {
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = "\(bin)/\(name)"
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { continue }
                let resolved = target.hasPrefix("/") ? target : "\(bin)/\(target)"
                guard resolved.contains("/lib/node_modules/"),
                      let package = Self.npmPackage(after: "/lib/node_modules/", in: resolved) else { continue }
                tools.append(ManagedTool(
                    command: name,
                    manager: "npm",
                    package: package,
                    version: versions[package],
                    launcherDirectory: bin,
                    launcherExists: true,
                    managedRoot: modules
                ))
            }
        }
        return tools
    }

    // MARK: - A managed tool losing its name

    private func shadowed(_ tool: ManagedTool, shell: ShellPathModel) async -> EnvironmentFinding? {
        let copies = executableCopies(named: tool.command, in: shell.searchDirectories)
        guard let winner = copies.first else { return nil }

        // The copy that wins is the manager's own, reached through its launcher.
        // That is the state the tool is supposed to be in.
        let winnerResolved = URL(fileURLWithPath: winner).resolvingSymlinksInPath().path
        guard !winnerResolved.contains(tool.managedRoot) else { return nil }

        guard let managedLauncher = copies.first(where: { copy in
            let resolved = URL(fileURLWithPath: copy).resolvingSymlinksInPath().path
            return resolved.contains(tool.managedRoot)
        }) else { return nil }

        let winnerVersion = await version(of: winner, path: shell.searchDirectories)
        let managedVersion: String?
        if let recorded = tool.version {
            managedVersion = recorded
        } else {
            managedVersion = await version(of: managedLauncher, path: shell.searchDirectories)
        }

        // A newer copy winning is not a fault. Only an older one is, and an
        // unknown version on either side is not enough to make that claim.
        if let winnerVersion, let managedVersion,
           !Self.isNewer(managedVersion, than: winnerVersion) {
            return nil
        }

        let managerNote: String
        switch tool.manager {
        case "pipx": managerNote = "the one pipx installed"
        case "uv": managerNote = "the one uv installed"
        default: managerNote = "the one npm installed"
        }

        let positions = [
            "Runs when you type \(tool.command): \(winner)" + (winnerVersion.map { " (version \($0))" } ?? ""),
            "Installed by \(tool.manager): \(managedLauncher)" + (managedVersion.map { " (version \($0))" } ?? "") + " — never reached",
            "The folder that would put the managed copy first: \(tool.launcherDirectory)"
        ]

        let promotion = promotionFix(for: tool.launcherDirectory, shell: shell)
        let steps = promotion == nil ? [
            "# The folder that holds the managed copy is not added by any of your profile files,",
            "# so putting it first is a line you have to add yourself:",
            "export PATH=\"\(tool.launcherDirectory):$PATH\"",
            "# Put that in ~/.zprofile (or ~/.zshrc) above the line that adds \(URL(fileURLWithPath: winner).deletingLastPathComponent().path)."
        ] : []

        return EnvironmentFinding(
            id: "tool:\(tool.manager):\(tool.command)",
            category: .languageTools,
            severity: .shadowed,
            title: "\(tool.command) runs a different copy than \(managerNote)",
            summary: "The \(tool.command) that answers in a terminal is \(ManagedTool.describe(winner))"
                + (winnerVersion.map { " version \($0)" } ?? "")
                + ", not the one \(tool.manager) manages at \(managedLauncher)"
                + (managedVersion.map { " (version \($0))" } ?? "")
                + ". Type `which -a \(tool.command)` in a terminal to see both.",
            evidence: positions,
            steps: steps,
            fix: promotion,
            isSelected: false,
            verifyCommand: tool.command
        )
    }

    /// The shadowed-launcher row for a tool whose launcher has gone missing. No
    /// fix: putting it back means asking the manager to reinstall, which reaches
    /// the network and is the reader's decision.
    private func missingLauncher(_ tool: ManagedTool) -> EnvironmentFinding {
        let command: String
        switch tool.manager {
        case "pipx": command = "pipx reinstall \(tool.package)"
        case "uv": command = "uv tool install --force \(tool.package)"
        default: command = "npm install -g \(tool.package)"
        }

        return EnvironmentFinding(
            id: "launcher:\(tool.manager):\(tool.command)",
            category: .languageTools,
            severity: .broken,
            title: "\(tool.command) is installed but no longer answers",
            summary: "\(tool.manager) still has \(tool.package) in its own folder, but the launcher that puts \(tool.command) on your path is missing, so typing the name does nothing.",
            evidence: [
                "Manager: \(tool.manager)",
                "Package: \(tool.package)" + (tool.version.map { " version \($0)" } ?? ""),
                "Expected launcher: \(tool.launcherDirectory)/\(tool.command) — not there",
                "Tool's own folder: \(tool.managedRoot)"
            ],
            steps: [
                "# This downloads and reinstalls the tool, so Housekeeping leaves it to you:",
                command
            ],
            fix: nil,
            isSelected: false,
            verifyCommand: tool.command
        )
    }

    // MARK: - Python and the key commands

    /// Every Python the search path can reach, plus the python.org frameworks
    /// installed for this machine. Reported as one fact, not one fault per
    /// version: several Pythons on a Mac is ordinary, and the useful sentence is
    /// which one answers.
    private func pythonFindings(shell: ShellPathModel, notes: inout [String]) async -> [EnvironmentFinding] {
        var candidates: [String] = executableCopies(named: "python3", in: shell.searchDirectories)
        let frameworks = "/Library/Frameworks/Python.framework/Versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: frameworks) {
            for version in versions.sorted() where !version.hasPrefix(".") {
                let path = "\(frameworks)/\(version)/bin/python3"
                guard FileManager.default.isExecutableFile(atPath: path) else { continue }
                let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                if !candidates.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }) {
                    candidates.append(path)
                }
            }
        }
        guard candidates.count > 1 else { return [] }

        var readings: [(path: String, version: String)] = []
        for path in candidates.prefix(6) {
            if let version = await version(of: path, path: shell.searchDirectories) {
                readings.append((path, version))
            }
        }
        guard Set(readings.map(\.version)).count > 1 else { return [] }

        let winner = readings.first
        let evidence = readings.map { "\($0.path) — Python \($0.version)" }

        if let winner, let newest = readings.max(by: { Self.isNewer($1.version, than: $0.version) }),
           newest.path != winner.path, Self.isNewer(newest.version, than: winner.version) {
            let directory = URL(fileURLWithPath: newest.path).deletingLastPathComponent().path
            return [EnvironmentFinding(
                id: "python-older-wins",
                category: .languageTools,
                severity: .shadowed,
                title: "python3 runs Python \(winner.version), but Python \(newest.version) is installed",
                summary: "The copy earlier on your search path is the older one, so the newer Python at \(directory) never runs unless you name it by its full path.",
                evidence: evidence,
                steps: promotionFix(for: directory, shell: shell) == nil ? [
                    "# No profile file adds \(directory), so put it in front yourself:",
                    "export PATH=\"\(directory):$PATH\"",
                    "# Add that line to ~/.zprofile above the one that puts the older Python first."
                ] : [],
                fix: promotionFix(for: directory, shell: shell),
                isSelected: false,
                verifyCommand: "python3"
            )]
        }

        let used = winner.map { "It answers as Python \($0.version) from \($0.path)." } ?? ""
        return [EnvironmentFinding(
            id: "python-versions",
            category: .languageTools,
            severity: .untidy,
            title: "\(readings.count) different Pythons are installed",
            summary: "That is normal on a Mac, not a fault. \(used) The other copies only matter if something names them by path. Libraries belong in a virtual environment per project, and standalone Python utilities belong in pipx.",
            evidence: evidence,
            steps: [
                "# Which one runs, and which others are reachable:",
                "which -a python3",
                "# A tool you want to keep but not let loose in a Python:",
                "pipx install <name>"
            ],
            fix: nil,
            isSelected: false,
            verifyCommand: "python3"
        )]
    }

    /// `pip3` and `pipx` can lose the same way Python can: an older framework
    /// copy earlier on the search path. This is deliberately narrow — only the
    /// commands the reader is most likely to type, and only when their versions
    /// are actually different and the winner is actually older.
    private func keyCommandFindings(shell: ShellPathModel) async -> [EnvironmentFinding] {
        var findings: [EnvironmentFinding] = []
        for name in ["pip3", "pipx"] {
            let copies = executableCopies(named: name, in: shell.searchDirectories)
            guard copies.count > 1 else { continue }

            var readings: [(path: String, version: String)] = []
            for path in copies.prefix(4) {
                if let version = await version(of: path, path: shell.searchDirectories) {
                    readings.append((path, version))
                }
            }
            guard let winner = readings.first,
                  let newest = readings.max(by: { Self.isNewer($1.version, than: $0.version) }),
                  newest.path != winner.path,
                  Self.isNewer(newest.version, than: winner.version) else { continue }

            let directory = URL(fileURLWithPath: newest.path).deletingLastPathComponent().path
            findings.append(EnvironmentFinding(
                id: "key:\(name)",
                category: .languageTools,
                severity: .shadowed,
                title: "\(name) runs version \(winner.version), but \(newest.version) is installed",
                summary: "The older copy at \(winner.path) comes first on your search path, so the newer one at \(directory) never runs by name.",
                evidence: readings.map { "\($0.path) — version \($0.version)" },
                steps: promotionFix(for: directory, shell: shell) == nil ? [
                    "# No profile file adds \(directory), so put it in front yourself:",
                    "export PATH=\"\(directory):$PATH\""
                ] : [],
                fix: promotionFix(for: directory, shell: shell),
                isSelected: false,
                verifyCommand: name
            ))
        }
        return findings
    }

    // MARK: - Packages installed into a Python directly

    /// `pip install --user` still works even where the system Python refuses
    /// ordinary installs, and it scatters packages into a folder no virtual
    /// environment owns. The report is a fact, not a repair: moving them would
    /// break whatever imports them, and nothing here is broken today.
    private func globalPackageFindings(home: String) -> [EnvironmentFinding] {
        let fileManager = FileManager.default
        var roots: [String] = []

        let localLib = "\(home)/.local/lib"
        if let entries = try? fileManager.contentsOfDirectory(atPath: localLib) {
            for entry in entries where entry.hasPrefix("python") {
                let site = "\(localLib)/\(entry)/site-packages"
                if fileManager.fileExists(atPath: site) { roots.append(site) }
            }
        }

        let macPython = "\(home)/Library/Python"
        if let versions = try? fileManager.contentsOfDirectory(atPath: macPython) {
            for version in versions where !version.hasPrefix(".") {
                let site = "\(macPython)/\(version)/lib/python/site-packages"
                if fileManager.fileExists(atPath: site) { roots.append(site) }
            }
        }

        var packages: [String] = []
        for root in roots {
            guard let names = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for name in names where !name.hasPrefix(".") && !name.hasPrefix("_")
                && !name.contains(".dist-info") && !name.contains(".egg-info")
                && name != "__pycache__" {
                packages.append("\(name) — \(root)")
            }
        }
        guard !packages.isEmpty else { return [] }

        return [EnvironmentFinding(
            id: "global-pip-packages",
            category: .languageTools,
            severity: .untidy,
            title: "\(packages.count) Python package\(packages.count == 1 ? " is" : "s are") installed outside a virtual environment",
            summary: "These sit in a user-wide Python folder, not in an environment of their own. That is not broken — Python's own \"externally managed\" refusal is normal for Homebrew Python, not damage. But packages installed this way are shared by every project and are the usual source of version clashes. A library belongs in a virtual environment; a standalone tool belongs in pipx.",
            evidence: Array(packages.prefix(30)) + (packages.count > 30 ? ["…and \(packages.count - 30) more"] : []),
            steps: [
                "# See what is there, and where:",
                "python3 -m pip list --user",
                "# For a command-line tool that should live on its own:",
                "pipx install <name>",
                "# For a library: a virtual environment per project.",
                "python3 -m venv .venv && source .venv/bin/activate"
            ],
            fix: nil,
            isSelected: false
        )]
    }

    // MARK: - Reordering the search path

    /// Builds the one-file fix that moves a directory to the front, if any of
    /// the reader's own profile files already adds it. The last file that does
    /// is used, because a later file appending the directory again would undo an
    /// earlier promotion (zsh's `typeset -U path` keeps the last occurrence).
    private func promotionFix(for directory: String, shell: ShellPathModel) -> EnvironmentFix? {
        for file in shell.files.reversed() {
            if let contents = shell.promoting(directory, in: file) {
                return .rewriteShellConfig(path: file, newContents: contents)
            }
        }
        return nil
    }

    // MARK: - Small readings

    private func firstExecutable(named name: String, in directories: [String]) -> String? {
        for directory in directories {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Every reachable copy, in the order a shell would try them, deduplicated
    /// by what each link resolves to — a launcher counted twice is not a second
    /// installation.
    private func executableCopies(named name: String, in directories: [String]) -> [String] {
        var seen = Set<String>()
        var copies: [String] = []
        for directory in directories {
            let path = "\(directory)/\(name)"
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if seen.insert(resolved).inserted { copies.append(path) }
        }
        return copies
    }

    private func version(of path: String, path directories: [String]) async -> String? {
        guard let result = try? await runner.run(
            executable: path,
            arguments: ["--version"],
            environment: environment(path: directories),
            timeout: 10
        ) else { return nil }
        let text = result.stdout.isEmpty ? result.stderr : result.stdout
        return Self.versionNumber(in: text)
    }

    private func environment(path directories: [String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directories.joined(separator: ":")
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        return environment
    }

    static func versionNumber(in text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",;()[]"))
        for token in text.components(separatedBy: separators) {
            var candidate = token
            if candidate.first == "v" || candidate.first == "V" { candidate.removeFirst() }
            let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.count > 0,
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { continue }
            // A bare year or build number is a version too; it is kept because
            // the caller compares only like with like.
            if parts.count == 1 && candidate.count < 2 { continue }
            return candidate
        }
        return nil
    }

    /// True when `a` is a later version than `b`. Missing components count as
    /// zero, so 3.10 equals 3.10.0 and 3.14 beats 3.10.11.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0) ?? 0 }
        let right = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func component(after marker: String, in path: String) -> String? {
        guard let range = path.range(of: marker) else { return nil }
        return path[range.upperBound...].split(separator: "/").first.map(String.init)
    }

    /// The package name in a path like
    /// `/opt/homebrew/lib/node_modules/@scope/name/dist/index.js`.
    static func npmPackage(after marker: String, in path: String) -> String? {
        guard let range = path.range(of: marker) else { return nil }
        let parts = path[range.upperBound...].split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@"), parts.count > 1 { return "\(first)/\(parts[1])" }
        return first
    }
}

private extension ManagedTool {
    /// `pymobiledevice3 (from /opt/homebrew/bin)` is more use in a sentence than
    /// a bare path, but the path is what makes it checkable.
    static func describe(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
