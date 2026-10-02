// Housekeeping — reading the shape of a Mac
//
// This file answers four questions, and every finding on the screen comes out of
// one of them:
//
//   1. When you type a command, which file actually runs?
//   2. Which of those files is not where its owner thinks it is?
//   3. What does the shell's own search path look like once the profile files
//      have had their say?
//   4. What does each package manager say about itself?
//
// The order is not arbitrary. Question 1 has to be answered *first*, and
// answered the way a shell would answer it, because every later question is
// phrased in terms of it — "Homebrew installed a yt-dlp" only means something
// once you know which yt-dlp your typed command reaches. So the search path is
// assembled from the profile files, in load order, before anything is compared.
//
// What the app does not do is guess. It does not decide that two files with the
// same name are duplicates of each other: it resolves both and compares the
// results. It does not read a warning and assume what it means: every name a
// tool reports is checked against a list of what is actually installed before it
// becomes a finding. A wrong finding on a screen like this is not a wasted
// click, it is a reason to stop reading.

import Foundation

struct EnvironmentAudit: Sendable {

    let runner: ProcessRunner
    let homePath: String
    /// Resolved once by the caller, because a windowed app launched from Finder
    /// has no shell profile behind it and `brew` is frequently not on its own
    /// PATH at all.
    let brewPath: String?

    // MARK: - The reading

    /// Never throws. A reading that dies on one unreadable folder would throw
    /// away everything the other four questions found, so each part records what
    /// went wrong in `notes` and carries on.
    func run() async -> EnvironmentReport {
        var findings: [EnvironmentFinding] = []
        var notes: [String] = []
        let fileManager = FileManager.default
        let home = URL(fileURLWithPath: homePath, isDirectory: true)

        guard fileManager.fileExists(atPath: home.path) else {
            return EnvironmentReport(findings: [], notes: ["The home folder could not be read."])
        }

        let brewPrefix: String? = brewPath.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
        }

        // 1. The search path, assembled the way a shell assembles it.
        let shell = ShellPathModel.read(home: home, brewPrefix: brewPrefix)
        if shell.files.isEmpty {
            notes.append("None of the usual profile files exist, so there was no search path to read.")
        } else {
            notes.append("Search path assembled from \(shell.files.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")) in the order a login shell reads them.")
        }
        if !shell.zshUniquesPath, shell.files.contains(where: { ($0 as NSString).lastPathComponent.hasPrefix(".zsh") }) {
            notes.append("These files have no `typeset -U path`, so zsh does not remove repeated entries for you — a repeat is a repeat.")
        }
        notes.append(contentsOf: shell.notes)

        if let brewPrefix, !shell.searchDirectories.contains("\(brewPrefix)/bin") {
            notes.append("\(brewPrefix)/bin is not on the search path these files build, so Homebrew's own programs are not reachable by name in a new shell.")
        }

        // 2. What each package manager has installed, and what it says is wrong.
        var formulae: [BrewFormula] = []
        var doctor = DoctorReport.empty
        if let brewPath {
            formulae = await readFormulae(brewPath: brewPath, prefix: brewPrefix, notes: &notes)
            doctor = await readDoctor(brewPath: brewPath, notes: &notes)
        } else {
            notes.append("Homebrew is not installed, so its own checks were skipped.")
        }

        // 3. The findings themselves.
        findings.append(contentsOf: shell.findings())
        findings.append(contentsOf: shadowedCommands(
            formulae: formulae,
            searchDirectories: shell.searchDirectories,
            brewPrefix: brewPrefix
        ))
        findings.append(contentsOf: brokenLinks(
            searchDirectories: shell.searchDirectories,
            brewPrefix: brewPrefix,
            home: home
        ))
        findings.append(contentsOf: deadReferences(home: home, shell: shell, notes: &notes))
        findings.append(contentsOf: homebrewHealth(
            formulae: formulae,
            doctor: doctor,
            brewPath: brewPath,
            brewPrefix: brewPrefix,
            searchDirectories: shell.searchDirectories
        ))
        findings.append(contentsOf: packageManagers(
            formulae: formulae,
            searchDirectories: shell.searchDirectories,
            brewPrefix: brewPrefix,
            shell: shell
        ))
        findings.append(contentsOf: handInstalledRuntimes(
            home: home,
            shell: shell,
            searchDirectories: shell.searchDirectories
        ))

        // A fix is only offered for something this reading actually saw. If the
        // subject has gone since, the row is dropped rather than shown, because
        // a button for a file that is no longer there can only fail.
        let live = findings.filter { finding in
            guard let subject = finding.subjectPath else { return true }
            return Self.isPresent(subject)
        }

        return EnvironmentReport(findings: live, notes: notes)
    }

    // MARK: - What Homebrew has installed

    /// `brew list --formula` and `brew info --json=v2 --installed`, in that
    /// order so a package Homebrew has stopped knowing about cannot come back
    /// from the second command's cache.
    ///
    /// The JSON is read defensively: every key is optional here, because this
    /// parses another program's output and a schema change should cost the
    /// screen one group, not the whole reading.
    private func readFormulae(brewPath: String, prefix: String?, notes: inout [String]) async -> [BrewFormula] {
        let result = try? await runner.run(
            executable: brewPath,
            arguments: ["info", "--json=v2", "--installed"],
            timeout: 120
        )
        guard let result, result.succeeded, let data = result.stdout.data(using: .utf8) else {
            notes.append("Homebrew's list of installed packages could not be read, so the checks that need it were skipped.")
            return []
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["formulae"] as? [[String: Any]] else {
            notes.append("Homebrew's list of installed packages came back in a shape this version does not recognise.")
            return []
        }

        var formulae: [BrewFormula] = []
        for entry in entries {
            guard let name = entry["name"] as? String else { continue }
            let installed = entry["installed"] as? [[String: Any]]
            let version = (installed?.last?["version"] as? String)
                ?? ((entry["versions"] as? [String: Any])?["stable"] as? String)
            formulae.append(BrewFormula(
                name: name,
                tap: entry["tap"] as? String,
                version: version,
                isKegOnly: (entry["keg_only"] as? Bool) ?? false,
                isDeprecated: (entry["deprecated"] as? Bool) ?? false,
                isDisabled: (entry["disabled"] as? Bool) ?? false,
                binDirectory: prefix.map { URL(fileURLWithPath: $0).appendingPathComponent("opt/\(name)/bin").path }
            ))
        }
        return formulae
    }

    /// Homebrew's own report, plus `brew missing`, which doctor only summarises.
    ///
    /// Doctor's output is kept whole rather than reduced to the parts this app
    /// acts on, because what it says is Homebrew's own assessment of itself and
    /// the reader is entitled to all of it. What is *acted* on is narrowed to
    /// the warnings this app has a fix for, and each name is checked against the
    /// installed list first.
    private func readDoctor(brewPath: String, notes: inout [String]) async -> DoctorReport {
        let doctor = try? await runner.run(executable: brewPath, arguments: ["doctor"], timeout: 180)
        let missing = try? await runner.run(executable: brewPath, arguments: ["missing"], timeout: 120)

        guard let doctor else {
            notes.append("`brew doctor` could not be run, so Homebrew's own warnings are missing from this reading.")
            return .empty
        }

        // Both streams, joined — not "whichever one has something in it".
        // Homebrew writes the report to stderr and leaves a single newline on
        // stdout, so a pick between the two streams does not merely prefer the
        // wrong one, it prefers a one-character one and throws the report away.
        // Measured on this machine: stdout 1 byte, stderr 1766 bytes. Concatenating
        // is also what a terminal shows, which is the reading the reader can check.
        let text = Self.meaningful(doctor.stdout, doctor.stderr)
        guard !text.isEmpty else {
            notes.append("`brew doctor` returned nothing, so Homebrew's own warnings are missing from this reading.")
            return .empty
        }
        let missingText = missing.map { Self.meaningful($0.stdout, $0.stderr) } ?? ""
        return DoctorReport(output: text, missingOutput: missingText)
    }

    /// The two streams joined, with the blank ones left out. A stream holding
    /// only whitespace counts as blank: it carries no report, and keeping it
    /// would put a blank line at the top of a section that is matched by prefix.
    static func meaningful(_ streams: String...) -> String {
        streams
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - 1. Commands that run the wrong copy

    /// The yt-dlp shape, found generally.
    ///
    /// For every installed formula with programs in it, this walks the search
    /// path and asks which file would answer the name. If the file that wins is
    /// not a link into that formula's own cellar, the typed command is running
    /// something Homebrew does not know about.
    ///
    /// Two deliberate refusals to report:
    ///
    ///   * `keg_only` formulae are skipped entirely. Homebrew installs those
    ///     precisely so they do *not* take a name on the path — a `python3` from
    ///     a versioned formula is not being shadowed, it is being declined.
    ///   * a name that wins from one of Apple's own folders is skipped, because
    ///     `/usr/bin/git` is not a stray copy of Homebrew's git, it is macOS's.
    private func shadowedCommands(
        formulae: [BrewFormula],
        searchDirectories: [String],
        brewPrefix: String?
    ) -> [EnvironmentFinding] {
        guard !searchDirectories.isEmpty else { return [] }
        let fileManager = FileManager.default
        var findings: [EnvironmentFinding] = []
        var seen = Set<String>()

        for formula in formulae where !formula.isKegOnly {
            guard let binDirectory = formula.binDirectory,
                  let names = try? fileManager.contentsOfDirectory(atPath: binDirectory) else { continue }

            for name in names where !name.hasPrefix(".") {
                guard let winner = firstHit(named: name, in: searchDirectories) else { continue }
                let resolved = URL(fileURLWithPath: winner).resolvingSymlinksInPath().path

                // The copy that wins is Homebrew's own: nothing to say.
                if let prefix = brewPrefix,
                   resolved.hasPrefix("\(prefix)/Cellar/\(formula.name)/") { continue }
                // macOS ships a program by the same name. Not a duplicate.
                if Self.appleDirectories.contains(where: { winner.hasPrefix("\($0)/") }) { continue }

                let key = "shadow:\(name)"
                guard seen.insert(key).inserted else { continue }

                let strayIsInHomebrewFolder = brewPrefix.map { winner.hasPrefix("\($0)/bin/") || winner.hasPrefix("\($0)/sbin/") } ?? false
                findings.append(EnvironmentFinding(
                    id: key,
                    category: .shadowing,
                    severity: .shadowed,
                    title: "`\(name)` runs a copy Homebrew did not install",
                    summary: strayIsInHomebrewFolder
                        ? "The file that answers `\(name)` is in Homebrew's own folder but is not a link to the \(formula.name) in its cellar — usually a copy an installer left behind, which is what stops Homebrew's version ever being reached."
                        : "The file that answers `\(name)` comes earlier in your search path than Homebrew's \(formula.name), so the installed package is never reached by name.",
                    evidence: [
                        "`\(name)` resolves to: \(winner)",
                        "…which is: \(resolved)",
                        "Homebrew's \(formula.name) lives in: \(binDirectory)",
                        "Search order: \(searchDirectories.joined(separator: " : "))"
                    ],
                    steps: [],
                    fix: .unshadow(
                        formula: formula.name,
                        stray: strayIsInHomebrewFolder ? nil : winner
                    ),
                    isSelected: strayIsInHomebrewFolder
                ))
            }
        }
        return findings
    }

    /// The first file a shell would find for a name, treating a link that leads
    /// nowhere as absent — which is exactly what a shell does, because
    /// `isExecutableFile` follows links and a link to nothing is not executable.
    private func firstHit(named name: String, in directories: [String]) -> String? {
        let fileManager = FileManager.default
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static let appleDirectories = [
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        "/System/Cryptexes/App/usr/bin", "/Library/Apple/usr/bin",
        "/var/run/com.apple.security.cryptexd"
    ]

    /// Whether a path is there. A symlink that leads nowhere counts as there,
    /// because a dangling link is exactly what two of these groups are about,
    /// and `fileExists` follows links and would call it absent.
    static func isPresent(_ path: String) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) { return true }
        return (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    // MARK: - 2. Links that lead nowhere

    /// Every symlink in a standard binary folder whose target has gone.
    ///
    /// When the link points into an application bundle that is still installed,
    /// the file it was reaching for can usually be found a folder or two away —
    /// the application updated and moved its own binary, which is precisely the
    /// cua-driver case in the Hermes logs. That is repaired, because the target
    /// is unambiguous: same bundle, same file name. Anything else is offered to
    /// Quarantine, because guessing at a replacement for a name like `prlctl`
    /// would be inventing an answer.
    private func brokenLinks(
        searchDirectories: [String],
        brewPrefix: String?,
        home: URL
    ) -> [EnvironmentFinding] {
        let fileManager = FileManager.default
        var directories = ["\(homePath)/.local/bin", "\(homePath)/bin"]
        if let brewPrefix { directories.append(contentsOf: ["\(brewPrefix)/bin", "\(brewPrefix)/sbin"]) }
        directories.append("/usr/local/bin")
        directories.append("/opt/local/bin")

        var findings: [EnvironmentFinding] = []
        var seen = Set<String>()
        let userOwned = ["\(homePath)/.local/bin", "\(homePath)/bin"]

        for directory in directories {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = "\(directory)/\(name)"
                guard let rawTarget = try? fileManager.destinationOfSymbolicLink(atPath: path) else { continue }
                let target = rawTarget.hasPrefix("/")
                    ? rawTarget
                    : URL(fileURLWithPath: directory).appendingPathComponent(rawTarget).standardized.path
                guard !fileManager.fileExists(atPath: target) else { continue }

                let key = "link:\(path)"
                guard seen.insert(key).inserted else { continue }

                let outcome = Self.replacement(forBrokenTarget: target)
                let isOwn = userOwned.contains(where: { path.hasPrefix("\($0)/") })

                findings.append(EnvironmentFinding(
                    id: key,
                    category: .brokenLinks,
                    severity: .broken,
                    title: "`\(name)` points at something that is not there",
                    summary: outcome == nil
                        ? "The link is still in \(directory), but its target has gone, so typing `\(name)` fails with \"no such file or directory\" from a program that looks installed."
                        : "The application it belongs to is still installed, but it moved the file the link was reaching for. The link can be pointed at where the file is now.",
                    evidence: [
                        "Link: \(path)",
                        "Points at: \(target)",
                        "That path does not exist."
                    ] + (outcome.map { ["Replacement found: \($0)"] } ?? []),
                    steps: outcome == nil && !isOwn ? [
                        "If you still use the application, its own installer usually puts this link back:",
                        "ls -l \(path)"
                    ] : [],
                    fix: outcome.map { EnvironmentFix.repointSymlink(path: path, target: $0) }
                        ?? .quarantine(path: path),
                    isSelected: isOwn
                ))
            }
        }
        return findings
    }

    /// A file inside the same application bundle with the same name as the one
    /// the link was reaching for. This is the only replacement the app treats as
    /// certain, because it is the same program in the same bundle.
    private static func replacement(forBrokenTarget target: String) -> String? {
        let components = target.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let bundleIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let bundlePath = "/" + components.prefix(through: bundleIndex).joined(separator: "/")
        let wanted = URL(fileURLWithPath: target).lastPathComponent
        guard FileManager.default.fileExists(atPath: bundlePath) else { return nil }

        let candidates = ["Contents/MacOS", "Contents/Resources", "Contents/Helpers", "Contents/SharedSupport"]
        for candidate in candidates {
            let path = "\(bundlePath)/\(candidate)/\(wanted)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - 3. Configuration that names a program that has gone

    /// Files that start other programs by absolute path: the agent configuration
    /// files, the Hermes configuration, the launch agents, and the shell profile
    /// files themselves — a wrapper function calling a path that no longer
    /// exists fails the same way, and is the same class of problem.
    ///
    /// Read-only, and offered as read-only. Housekeeping has no business
    /// rewriting another application's configuration: the file belongs to a
    /// program that will write it again, and a rewritten file it does not
    /// understand is worse than a broken reference the reader can see.
    private func deadReferences(home: URL, shell: ShellPathModel, notes: inout [String]) -> [EnvironmentFinding] {
        let fileManager = FileManager.default
        var files: [String] = shell.files
        files.append(contentsOf: [
            "\(homePath)/.claude.json",
            "\(homePath)/.claude/settings.json",
            "\(homePath)/.claude/settings.local.json",
            "\(homePath)/Library/Application Support/Claude/claude_desktop_config.json",
            "\(homePath)/.hermes/config.yaml",
            "\(homePath)/.hermes/.env",
            "\(homePath)/.config/mcp/config.json"
        ])
        if let agents = try? fileManager.contentsOfDirectory(atPath: "\(homePath)/Library/LaunchAgents") {
            files.append(contentsOf: agents.filter { $0.hasSuffix(".plist") }
                .map { "\(homePath)/Library/LaunchAgents/\($0)" })
        }

        var references: [String: [String]] = [:]
        var skippedLarge: [String] = []

        for file in Set(files).sorted() {
            guard let size = (try? fileManager.attributesOfItem(atPath: file))?[.size] as? Int else { continue }
            // A configuration file worth reading is small. Anything this large is
            // a transcript or a database, and walking it would cost seconds for
            // matches that are quotations rather than settings.
            guard size < 2_000_000 else { skippedLarge.append(file); continue }
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }

            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for value in Self.referencedValues(in: String(line)) {
                    guard Self.looksLikeAProgram(value) else { continue }
                    // A path that is there as a *link* is not missing, even when
                    // the link leads nowhere: that is the other group's finding,
                    // and reporting it twice under two headings is how a reader
                    // learns to stop reading.
                    guard !Self.isPresent(value) else { continue }
                    references[value, default: []].append("\(file):\(index + 1)")
                }
            }
        }

        if !skippedLarge.isEmpty {
            notes.append("Not read for missing programs, because they are too large to be configuration: \(skippedLarge.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")).")
        }

        return references.sorted { $0.key < $1.key }.map { path, places in
            EnvironmentFinding(
                id: "deadref:\(path)",
                category: .brokenLinks,
                severity: .broken,
                title: "\(URL(fileURLWithPath: path).lastPathComponent) is referred to, but is not there",
                summary: "\(places.count == 1 ? "One file starts" : "\(places.count) places start") this program by its full path. Whatever they are, they will fail until it exists again — or until the reference is removed.",
                evidence: ["Missing: \(path)"] + places.prefix(6).map { "Named in: \(($0 as NSString).abbreviatingWithTildeInPath)" },
                steps: [],
                fix: nil,
                isSelected: false
            )
        }
    }

    /// The complete values on one line that could name a program: quoted
    /// strings, plist `<string>` elements, and bare words that begin with a
    /// slash.
    ///
    /// Whole values, and that is the whole point of this function. An earlier
    /// version walked the line for runs of path characters, which necessarily
    /// stops at a space — so a real reference to
    /// `/Applications/Kindle Previewer 3.app/Contents/MacOS/KPR_NCD` came back
    /// as `3.app/Contents/MacOS/KPR_NCD` and was reported as a missing program
    /// that was sitting exactly where it belonged. On this machine that one
    /// mistake produced four findings in three shapes: a quoted JSON value, a
    /// plist `<string>`, and a path containing a space. The quotes and the
    /// element tags are the file format saying where a value ends, so they are
    /// read rather than stepped over.
    ///
    /// Three refusals to report, all learned from the same machine:
    ///
    ///   * Comment lines are skipped. A `#` line in `~/.hermes/config.yaml`
    ///     showing the command to run by hand mentioned `<venv>/bin/python` and
    ///     was reported as a missing interpreter, which it never was.
    ///   * A value with a `$`, `{` or leading `~` in it is skipped: that is a
    ///     template, not a path, and what it expands to is not something a
    ///     reading can know.
    ///   * Only values that *begin* with a slash are kept. Without that, the
    ///     tail of a path that has a space in it — `Support/Dropbox/Dropbox…`
    ///     out of `/Users/…/Application Support/Dropbox/…` — is itself a string
    ///     ending in `.app/Contents/MacOS`, which passes every test for being a
    ///     program and is really half of one.
    private static func referencedValues(in line: String) -> [String] {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { return [] }

        var raw: [String] = []
        var unquoted = ""
        var rest = Substring(line)

        while let start = rest.firstIndex(where: { $0 == "\"" || $0 == "'" || $0 == "<" }) {
            let element = rest[start...]
            let opener = rest[start]

            if opener == "<" {
                // A plist value is `<string>…</string>`: the angle bracket at
                // the end of the opening tag is not the end of the value, so
                // the closing tag is what is searched for. Any other element
                // (`<key>`, `<dict>`, `<true/>`) names no path and is dropped
                // along with its tag.
                if element.hasPrefix("<string>"), let close = element.range(of: "</string>") {
                    raw.append(String(element[element.index(element.startIndex, offsetBy: 8)..<close.lowerBound]))
                    unquoted += rest[..<start]
                    rest = element[close.upperBound...]
                } else if let tag = element.firstIndex(of: ">") {
                    unquoted += rest[...tag]
                    rest = element[element.index(after: tag)...]
                } else {
                    break
                }
                continue
            }

            let afterOpen = rest.index(after: start)
            guard let end = rest[afterOpen...].firstIndex(of: opener) else { break }
            raw.append(String(rest[afterOpen..<end]))
            unquoted += rest[..<start]
            rest = rest[rest.index(after: end)...]
        }
        unquoted += rest

        // What is left outside the quotes: YAML values, `export X=/a/b`, plist
        // text between elements. Split on the punctuation that separates one
        // value from the next, so a bare path arrives as one word.
        raw.append(contentsOf: unquoted.split(whereSeparator: { " \t,=:".contains($0) }).map(String.init))

        return raw.compactMap { value in
            guard !value.isEmpty, value.hasPrefix("/"),
                  !value.contains("$"), !value.contains("{") else { return nil }

            // A quoted value can be a command line rather than a path —
            // `"/Users/…/sessioncost --hook"` is a program and its arguments.
            // The program is the first word, but it is only read as one when the
            // value as a whole is not there: a path with a space in it must not
            // be cut down to its first word on the way past.
            if value.contains(" "), !isPresent(value),
               let first = value.split(separator: " ").first, first.hasPrefix("/") {
                return String(first)
            }
            return value
        }
    }

    /// Whether a missing path is worth reporting: something a program would be
    /// started from, or a runtime a program would run inside. A missing image,
    /// log, or document is not this app's business.
    private static func looksLikeAProgram(_ path: String) -> Bool {
        if path.contains(".app/Contents/") { return true }
        if path.contains(".venv/") || path.contains("/venv/") { return true }
        if path.contains("/bin/") || path.contains("/sbin/") { return true }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.hasSuffix(".py") || name.hasSuffix(".sh") { return true }
        if name.hasPrefix("python") || name.hasPrefix("node") || name == "uv" { return true }
        return false
    }

    // MARK: - 4. Homebrew's own health

    private func homebrewHealth(
        formulae: [BrewFormula],
        doctor: DoctorReport,
        brewPath: String?,
        brewPrefix: String?,
        searchDirectories: [String]
    ) -> [EnvironmentFinding] {
        var findings: [EnvironmentFinding] = []
        let installedNames = Set(formulae.map(\.name))

        // Unlinked packages: Homebrew has files in its cellar and no link in its
        // own folders, so the program is installed and unreachable. The names
        // come from `brew doctor`, and every one is checked against the list of
        // what is installed before it is used — a parser reading a report in
        // prose has no business creating a finding on its own.
        for name in doctor.unlinkedKegs where installedNames.contains(name) {
            findings.append(EnvironmentFinding(
                id: "unlinked:\(name)",
                category: .homebrew,
                severity: .broken,
                title: "\(name) is installed but not linked",
                summary: "Homebrew has \(name) in its cellar and has not put it in its shared folders, so the program is there on disk and not reachable by name.",
                evidence: doctor.sectionLines(containing: "unlinked kegs", mentioning: name).map { "brew doctor: \($0)" },
                steps: [],
                fix: .brewLink(formula: name, overwrite: false),
                isSelected: true
            ))
        }

        // Dependencies Homebrew knows are absent. `brew missing` is the tool's
        // own answer to this and needs no parsing beyond the colon it prints.
        for (name, missing) in doctor.missingDependencies.sorted(by: { $0.key < $1.key }) {
            for dependency in missing {
                findings.append(EnvironmentFinding(
                    id: "missing:\(name):\(dependency)",
                    category: .homebrew,
                    severity: .broken,
                    title: "\(name) is missing \(dependency)",
                    summary: "\(name) was installed without one of the packages it needs, which usually means something it links against is absent.",
                    evidence: ["`brew missing` reports: \(name) needs \(dependency)"],
                    steps: [],
                    fix: .brewInstall(formula: dependency),
                    isSelected: false
                ))
            }
        }

        for name in doctor.deprecatedFormulae where installedNames.contains(name) {
            guard let formula = formulae.first(where: { $0.name == name }) else { continue }
            findings.append(EnvironmentFinding(
                id: "deprecated:\(name)",
                category: .homebrew,
                severity: .untidy,
                title: "Homebrew has deprecated \(name)",
                summary: "Homebrew is no longer maintaining this package and will remove it in a future release. Nothing is broken today.",
                evidence: [
                    formula.version.map { "Installed version: \($0)" } ?? "Installed version unknown",
                    "Homebrew's own wording: \(doctor.lines(containing: name).first ?? "marked deprecated or disabled")"
                ],
                steps: [],
                fix: .brewUninstall(formula: name),
                isSelected: false
            ))
        }

        for tap in doctor.untrustedTaps {
            findings.append(EnvironmentFinding(
                id: "tap:\(tap)",
                category: .homebrew,
                severity: .untidy,
                title: "\(tap) is tapped and not trusted",
                summary: "A third-party collection of packages is being tracked. Packages from a tap are not reviewed by Homebrew, so anything installed from it came from its author.",
                evidence: doctor.sectionLines(containing: "trust").map { "brew doctor: \($0)" },
                steps: [],
                fix: .brewUntap(tap: tap),
                isSelected: false
            ))
        }

        // Files in Homebrew's prefix that Homebrew did not put there — usually
        // headers left by a manual `make install`. They live in a system folder,
        // so this one is handed over rather than done.
        let unbrewed = doctor.unbrewedFiles
        if !unbrewed.isEmpty {
            findings.append(EnvironmentFinding(
                id: "unbrewed",
                category: .homebrew,
                severity: .untidy,
                title: "Files in Homebrew's folders that Homebrew did not put there",
                summary: "Something was installed by hand into a folder Homebrew manages. It is harmless on its own, and it is the kind of thing that makes a later Homebrew problem harder to read.",
                evidence: unbrewed.prefix(12).map { "brew doctor: \($0)" } + (unbrewed.count > 12 ? ["…and \(unbrewed.count - 12) more"] : []),
                steps: [
                    "# These need an administrator, so Housekeeping will not run them.",
                    "# This moves them aside rather than deleting them:",
                    "sudo mv \(unbrewed.first ?? "/usr/local/include/node") \"$HOME/.Trash/unbrewed-$(date +%F)\""
                ],
                fix: nil,
                isSelected: false
            ))
        }

        return findings
    }

    // MARK: - 5. Two package managers

    /// Homebrew and MacPorts both installed is not an error, it is an ambiguity:
    /// each keeps its own copy of common tools, and whichever folder comes first
    /// wins for every one of them. The app names the collisions and offers the
    /// one change it can undo — moving MacPorts later in the path.
    ///
    /// It does not offer to remove a package manager. Taking a package manager
    /// off a Mac is a system-wide change that needs an administrator and that
    /// nothing here can put back, so it is written out as commands in `steps`
    /// instead of offered as a button.
    private func packageManagers(
        formulae: [BrewFormula],
        searchDirectories: [String],
        brewPrefix: String?,
        shell: ShellPathModel
    ) -> [EnvironmentFinding] {
        let fileManager = FileManager.default
        let macPortsBin = "/opt/local/bin"
        guard fileManager.fileExists(atPath: macPortsBin),
              let brewPrefix,
              let portNames = try? fileManager.contentsOfDirectory(atPath: macPortsBin),
              let brewNames = try? fileManager.contentsOfDirectory(atPath: "\(brewPrefix)/bin") else {
            return []
        }

        let brewSet = Set(brewNames)
        let overlap = portNames.filter { brewSet.contains($0) && !$0.hasPrefix(".") }.sorted()
        guard !overlap.isEmpty else { return [] }

        let macPortsIndex = searchDirectories.firstIndex(of: macPortsBin)
        let brewIndex = searchDirectories.firstIndex(of: "\(brewPrefix)/bin")
        let macPortsWins = (macPortsIndex ?? .max) < (brewIndex ?? .max)

        let line = shell.lineIntroducing(macPortsBin)
        return [EnvironmentFinding(
            id: "macports-overlap",
            category: .packageManagers,
            severity: .shadowed,
            title: "MacPorts and Homebrew both provide \(overlap.count) of the same commands",
            summary: macPortsWins
                ? "MacPorts's folder comes first in your search path, so for these \(overlap.count) names it is MacPorts's copy that runs, not Homebrew's."
                : "Homebrew's folder comes first in your search path, so Homebrew wins these \(overlap.count) names. MacPorts's copies are installed and unreachable.",
            evidence: [
                "MacPorts: \(macPortsBin)",
                "Homebrew: \(brewPrefix)/bin",
                "Provided by both: \(overlap.prefix(25).joined(separator: ", "))\(overlap.count > 25 ? " …and \(overlap.count - 25) more" : "")",
                macPortsIndex.map { "MacPorts is at position \($0 + 1) of \(searchDirectories.count) on the search path." } ?? "MacPorts is not on the search path these files build."
            ],
            steps: [
                "# Removing MacPorts is a system-wide change and needs an administrator.",
                "# Housekeeping will not run these. Port's own uninstall is:",
                "sudo port -fp uninstall installed",
                "sudo rm -rf /opt/local /Applications/DarwinPorts /Applications/MacPorts",
                "sudo rm -rf /Library/LaunchDaemons/org.macports.* /Library/LaunchAgents/org.macports.*",
                "sudo rm -rf /Library/Receipts/MacPorts* /Library/Receipts/DarwinPorts*"
            ],
            fix: (macPortsWins ? line.map {
                .rewriteShellConfig(path: $0.file, newContents: shell.demoting(macPortsBin, in: $0.file))
            } : nil),
            isSelected: false
        )]
    }

    // MARK: - 6. Runtimes installed by hand

    /// Language runtimes that did not come from a package manager: the python.org
    /// framework installer is the common one, and the reason it matters is that
    /// it edits the shell profile to put itself first. The app's job here is not
    /// to remove it. It is to answer the question the installer never did — what
    /// on this Mac still points at it — and to state, in plain words, that
    /// removing it is a decision with consequences rather than tidying.
    private func handInstalledRuntimes(
        home: URL,
        shell: ShellPathModel,
        searchDirectories: [String]
    ) -> [EnvironmentFinding] {
        let fileManager = FileManager.default
        let frameworks = "/Library/Frameworks/Python.framework/Versions"
        guard let versions = try? fileManager.contentsOfDirectory(atPath: frameworks) else { return [] }

        var findings: [EnvironmentFinding] = []
        for version in versions.sorted() where !version.hasPrefix(".") {
            let root = "\(frameworks)/\(version)"
            // `Versions/Current` sits in this folder and is a link to whichever
            // version is current, not a version of its own. Reporting it would
            // say the same install twice and offer a `sudo mv` of a symlink that
            // the real version's own folder already covers.
            guard (try? fileManager.destinationOfSymbolicLink(atPath: root)) == nil else { continue }
            let bin = "\(root)/bin"
            guard fileManager.fileExists(atPath: bin) else { continue }

            var users: [String] = []
            if let onPath = searchDirectories.firstIndex(of: bin) {
                users.append("Your search path, at position \(onPath + 1) of \(searchDirectories.count)")
            }
            users.append(contentsOf: shell.filesMentioning(root).map { "\(($0 as NSString).abbreviatingWithTildeInPath) mentions it" })

            // Anything in /usr/local/bin or ~/.local/bin pointing into it: the
            // leftover links a pip install outside a virtual environment creates.
            for directory in ["/usr/local/bin", "\(homePath)/.local/bin"] {
                guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
                let pointing = names.filter { name in
                    guard let target = try? fileManager.destinationOfSymbolicLink(atPath: "\(directory)/\(name)") else { return false }
                    let resolved = target.hasPrefix("/") ? target : "\(directory)/\(target)"
                    return resolved.contains(root)
                }
                if pointing.count > 0 {
                    users.append("\(pointing.count) link\(pointing.count == 1 ? "" : "s") in \(directory) point into it (\(pointing.prefix(6).joined(separator: ", "))\(pointing.count > 6 ? " …" : ""))")
                }
            }

            let name = "Python \(version)"
            findings.append(EnvironmentFinding(
                id: "runtime:\(root)",
                category: .runtimes,
                severity: users.isEmpty ? .untidy : .shadowed,
                title: "\(name) was installed by hand outside Homebrew",
                summary: users.isEmpty
                    ? "Nothing on this Mac points at it any more. It is still in a system folder, taking up room."
                    : "\(name) is not managed by a package manager, and things still refer to it: \(users.count == 1 ? "one thing does" : "several things do"). Removing it would break them until they are pointed somewhere else.",
                evidence: ["\(root)"] + users,
                steps: users.isEmpty ? [
                    "# Needs an administrator, so Housekeeping will not run it.",
                    "# This moves it aside rather than deleting it, and puts nothing back:",
                    "sudo mv \(root) \(root)-disabled"
                ] : [
                    "# Needs an administrator, so Housekeeping will not run it.",
                    "# Change whatever still points at it first — the lines named above:",
                    "grep -rn \"Versions/\(version)\" ~/.zshrc ~/.zprofile ~/.zshenv ~/.profile 2>/dev/null"
                ],
                fix: nil,
                isSelected: false
            ))
        }
        return findings
    }
}

// MARK: - What Homebrew says about itself

/// `brew doctor` read as sections. Doctor's prose is not a format, so nothing
/// here is trusted on its own: each section is handed to the group that knows
/// what to do with it, and the names inside are checked against the installed
/// list before they are used.
struct DoctorReport {
    let output: String
    /// `brew missing`, which doctor only points at. Read separately because it
    /// prints one machine-readable line per package and doctor prints prose.
    let missingOutput: String

    static let empty = DoctorReport(output: "", missingOutput: "")

    /// Warning sections, keyed by their header line, holding the indented lines
    /// beneath each one.
    private var sections: [(header: String, lines: [String])] {
        var result: [(String, [String])] = []
        var header: String?
        var lines: [String] = []

        func flush() {
            if let header { result.append((header, lines)) }
            header = nil
            lines = []
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("Warning: ") || line.hasPrefix("Error: ") {
                flush()
                header = line
            } else if header != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { lines.append(line) }
            }
        }
        flush()
        return result
    }

    func sectionLines(containing needle: String) -> [String] {
        sections
            .filter { $0.header.lowercased().contains(needle.lowercased()) }
            .flatMap { section in ([section.header] + section.lines).prefix(6) }
    }

    /// The same section, narrowed to the lines that name one entry: the sentence
    /// introducing the list, and this entry's own line. The unlinked-kegs
    /// warning ends in a list of nine names, and showing all nine under each of
    /// the nine rows says nothing nine times over and makes it look as though
    /// every row is about the whole list.
    func sectionLines(containing needle: String, mentioning name: String) -> [String] {
        sections
            .filter { $0.header.lowercased().contains(needle.lowercased()) }
            .flatMap { section -> [String] in
                let lines = section.lines.map { $0.trimmingCharacters(in: .whitespaces) }
                return [section.header] + lines.filter { $0.contains("brew link` on these") || $0 == name }
            }
    }

    func lines(containing needle: String) -> [String] {
        output.split(separator: "\n").map(String.init)
            .filter { $0.lowercased().contains(needle.lowercased()) }
    }

    /// The bare names under a warning, taken from the line after the marker
    /// doctor uses to introduce them.
    ///
    /// The marker matters. Doctor's warning bodies are prose — "Leaving kegs
    /// unlinked can lead to build-trouble and cause formulae that depend on"
    /// sits in exactly the same section as the list — so the only reliable way
    /// to know where the list starts is the sentence that introduces it. Without
    /// the marker the parser would have to guess from line shape, and a single
    /// unspaced word in a sentence would become a package name.
    private func names(in sectionContaining: String, after marker: String, matching shape: (String) -> Bool) -> [String] {
        sections
            .filter { $0.header.lowercased().contains(sectionContaining.lowercased()) }
            .flatMap { section -> [String] in
                let lines = section.lines.map { $0.trimmingCharacters(in: .whitespaces) }
                guard let markerIndex = lines.firstIndex(where: { $0.contains(marker) }) else { return [] }
                return Array(lines.dropFirst(markerIndex + 1))
            }
            .filter(shape)
    }

    /// Packages Homebrew has installed into its cellar and not linked.
    var unlinkedKegs: [String] {
        names(in: "unlinked kegs", after: "brew link` on these") { line in
            !line.isEmpty && !line.contains(" ") && !line.hasPrefix("#")
        }
    }

    /// The leading run of body lines that all satisfy `shape`, under the section
    /// whose header contains the phrase.
    ///
    /// Some of doctor's lists have no marker sentence in the body at all. For
    /// untrusted taps the phrase appears *only* in the header ("Warning: The
    /// following taps are not trusted:") — the body is bare `owner/name` entries
    /// and then paragraphs of explanation. Searching the body for the marker, as
    /// `names(in:after:)` does, therefore finds nothing, which is why this one
    /// reads the unbroken run at the top instead: the first line that is not a
    /// tap name ends the list, and the paragraph that follows is left behind.
    private func leadingNames(in sectionContaining: String, matching shape: (String) -> Bool) -> [String] {
        sections
            .filter { $0.header.lowercased().contains(sectionContaining.lowercased()) }
            .flatMap { section -> [String] in
                let lines = section.lines.map { $0.trimmingCharacters(in: .whitespaces) }
                return Array(lines.prefix(while: shape))
            }
    }

    /// The taps doctor says are not trusted, as bare `owner/name` entries.
    var untrustedTaps: [String] {
        leadingNames(in: "taps are not trusted", matching: Self.isTapName)
    }

    /// Exactly `owner/name`: one slash, no spaces, nothing but letters, digits,
    /// dots, dashes and underscores. Strict on purpose — doctor prints a
    /// documentation URL in the same section, and anything looser reports
    /// `docs.brew.sh` as a tap the reader should untap.
    static func isTapName(_ line: String) -> Bool {
        let parts = line.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !line.contains(" "), !line.contains(":") else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
        }
    }

    /// Names doctor lists as deprecated or disabled. The caller checks each
    /// against what is installed.
    var deprecatedFormulae: [String] {
        names(in: "deprecated or disabled", after: "replacements for the following formulae") { line in
            !line.isEmpty && !line.contains(" ")
        }
    }

    /// Files in Homebrew's prefix that Homebrew did not install. Doctor prints
    /// them as absolute paths, often ending in `/*` because it is reporting a
    /// glob it matched; the glob is stripped so the path names the folder the
    /// reader would actually move.
    var unbrewedFiles: [String] {
        var seen = Set<String>()
        return names(in: "unbrewed", after: "Unexpected header files") { $0.hasPrefix("/") }
            .map { $0.hasSuffix("/*") ? String($0.dropLast(2)) : $0 }
            .filter { seen.insert($0).inserted }
    }

    /// `brew missing`, which prints one package per line as
    /// `formula: dependency dependency`.
    var missingDependencies: [String: [String]] {
        var result: [String: [String]] = [:]
        for line in missingOutput.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].contains(" ") else { continue }
            let dependencies = parts[1].split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard !dependencies.isEmpty else { continue }
            result[parts[0]] = dependencies
        }
        return result
    }
}

// MARK: - What Homebrew has installed, as far as this screen needs it

struct BrewFormula: Sendable {
    let name: String
    let tap: String?
    let version: String?
    let isKegOnly: Bool
    let isDeprecated: Bool
    let isDisabled: Bool
    let binDirectory: String?
}
