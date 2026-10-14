// Housekeeping — the command line
//
// This is the same program as the window, reached a different way. It is not a
// second program built from the same code: it is the app's own binary, asked a
// question from a terminal instead of from a window, and it answers and exits
// before AppKit is ever started. Nothing is drawn, no dock icon appears, and no
// window is created — `main.swift` decides which of the two lives this launch is
// before either of them begins.
//
// That shape is deliberate. The alternative — a separate command-line program
// compiled from a subset of these sources — means every engine has to keep a
// second, narrower interface, and the subset is not clean anyway: the safety
// policy and the rule engine are the same objects whether a window is looking at
// them or not. So the CLI is a *view* of the app, in the same sense the window is.
// It reads the same rules, runs the same scanner, and asks the same policy for a
// verdict, which is the whole point: a verdict a script gets from here is the
// verdict the app would have shown.
//
// What the CLI will not do is act. There is no verb that quarantines or deletes.
// A program that can remove files on the say-so of another program is a program
// whose safety story is somebody else's; the cleanup verbs are deliberately left
// to a person looking at a screen. `quarantine restore` is the one exception,
// and it only ever puts things back.

import Foundation

@MainActor
enum HousekeepingCLI {

    // MARK: - Entry

    /// Whether this launch is a command rather than a window.
    ///
    /// Empty means the reader double-clicked the app, which is the window. The
    /// `-psn_` and `-NSDocumentRevisionsDebugMode` arguments are the system's own
    /// and arrive without anyone typing them, so a launch carrying only those is
    /// still a launch of the app.
    ///
    /// `nonisolated` because of where it is asked. `main.swift` is top-level code
    /// rather than a type's body, so it is not on the main actor, and the question
    /// has to be answered before there is any actor to hop to. It reads an array
    /// and returns a `Bool`; there is nothing here that could need one.
    nonisolated static func wantsCommandLine(_ arguments: [String]) -> Bool {
        let meaningful = arguments.filter { argument in
            !argument.hasPrefix("-psn_") && argument != "-NSDocumentRevisionsDebugMode"
        }
        guard let first = meaningful.first else { return false }
        return !first.hasPrefix("-") || first == "-h" || first == "--help" || first == "--version"
    }

    /// Runs the command and returns the exit status. `main.swift` hands this to
    /// `exit`, so every path through here ends the process rather than returning
    /// into a window that was never built.
    static func run() async -> Int32 {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            return try await dispatch(arguments)
        } catch let failure as Failure {
            // A failure the reader caused — a path that is not there, an unknown
            // verb. Said in one line, to stderr, with nothing pretending to be a
            // result on stdout.
            complain(failure.message)
            if let hint = failure.hint { complain("  \(hint)") }
            return failure.status
        } catch {
            complain(error.localizedDescription)
            return 1
        }
    }

    // MARK: - Dispatch

    private static func dispatch(_ arguments: [String]) async throws -> Int32 {
        var rest = arguments
        let verb = rest.removeFirst()

        switch verb {
        case "scan":       return try await scan(rest)
        case "explain":    return try explain(rest)
        case "where":      return whereIs(rest)
        case "version":    return version(rest)
        case "quarantine": return try await quarantine(rest)
        case "help":       return help()
        default:
            if verb.hasPrefix("-") {
                switch verb {
                case "-h", "--help": return help()
                case "--version":    return version(rest)
                default: throw Failure.unknownVerb(verb)
                }
            }
            throw Failure.unknownVerb(verb)
        }
    }

    private static func help() -> Int32 {
        say("""
        Housekeeping — the app's own command line.

        Look through a Mac, explain a folder in plain words, or see what is being
        held. Nothing here removes anything: the verbs that clean are in the app,
        where somebody can look at what is about to go.

          housekeeping scan [--quick] [--json]
              Look through this Mac and list what it found, with Housekeeping's
              own verdict on each thing.

          housekeeping explain <path> [--json]
              Everything Housekeeping knows about one file or folder — what it is,
              why it is there, whether it is needed, and what it would cost you.

          housekeeping quarantine [list|restore] [--json]
              What is being held, and putting things back. `restore` needs --yes.

          housekeeping where [--json]
              Where Housekeeping keeps what it keeps.

          housekeeping version
          housekeeping help

        Options

          --json    Print the result as JSON instead of prose, for a program to
                    read. Anything on stdout is then JSON and nothing else;
                    progress and complaints go to stderr.

          --quick   Read less of the disk and answer sooner. It still reads every
                    place it knows about, it just does not look inside folders to
                    see what is in them.

        Exit status

          0  it worked
          1  something went wrong
          2  the command was not one Housekeeping knows
        """)
        return 0
    }

    private static func version(_ arguments: [String]) -> Int32 {
        let json = arguments.contains("--json")
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        if json {
            printJSON(["name": "Housekeeping", "version": short, "build": build])
        } else {
            say("Housekeeping \(short) (build \(build))")
        }
        return 0
    }

    private static func whereIs(_ arguments: [String]) -> Int32 {
        let json = arguments.contains("--json")
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let support = CleanupEngine.supportDirectoryURL(homeDirectory: home)
        let quarantine = CleanupEngine.quarantineURL(homeDirectory: home)
        let leftAlone = ProtectionList.defaultFileURL(homeDirectory: home)

        if json {
            printJSON([
                "support": support.path,
                "quarantine": quarantine.path,
                "left_alone": leftAlone.path,
                "rules": rulesDirectoryPath() ?? "",
            ])
            return 0
        }

        say("Housekeeping keeps things in three places, all of them readable:\n")
        say("  Quarantine    \(quarantine.homeAbbreviatedPath)")
        say("  Left alone    \(leftAlone.homeAbbreviatedPath)")
        say("  Its own notes \(support.homeAbbreviatedPath)")
        say("\nAnything Housekeeping takes sits in the quarantine folder, whole, until you delete it yourself.")
        return 0
    }

    // MARK: - Scanning

    private static func scan(_ arguments: [String]) async throws -> Int32 {
        let options = Options(arguments)
        let verbose = options.has("--verbose")
        let deep = !options.has("--quick")

        loadRules()

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let scanner = Scanner(
            applications: RuleEngine.shared.applications,
            homeDirectory: home,
            deepSweep: deep
        )
        let policy = CleanupSafetyPolicy(protectedPaths: ProtectionList().entries.map(\.path))

        if !options.json {
            Section.head("Looking through this Mac…")
        }

        let started = Date()
        let results = try await scanner.scan { progress in
            guard !options.json, verbose else { return }
            note(progress.title)
        }
        let elapsed = Date().timeIntervalSince(started)

        let rows = results.foundItems.map { item in
            Row(item: item, assessment: policy.assess(item))
        }

        if options.json {
            printJSON(scanDocument(results: results, rows: rows, seconds: elapsed))
        } else {
            printScan(results: results, rows: rows, seconds: elapsed, deep: deep)
        }
        return 0
    }

    private static func scanDocument(
        results: ScanResults,
        rows: [Row],
        seconds: TimeInterval
    ) -> [String: Any] {
        let ready = rows.filter { $0.verdict == .ready }
        var document: [String: Any] = [
            "scanned": results.scannedPaths.map(\.path),
            "seconds": (seconds * 10).rounded() / 10,
            "counts": [
                "found": rows.count,
                "ready_to_clean": ready.count,
                "look_at_first": rows.filter { $0.verdict == .inspect }.count,
                "leave_alone": rows.filter { $0.verdict == .leave }.count,
            ],
            "bytes": [
                "found": rows.reduce(Int64(0)) { $0 + $1.item.size },
                "ready_to_clean": ready.reduce(Int64(0)) { $0 + $1.item.size },
            ],
            "items": rows.map(\.document),
        ]
        document["notes"] = results.scanNotes.map { ["phase": $0.phase, "message": $0.message] }
        return document
    }

    /// The prose scan. It leads with the answer to the question the reader
    /// actually asked — how much is there, and how much of it is safe — and puts
    /// the list underneath, because a list of forty paths with no total above it
    /// is a wall rather than an answer.
    private static func printScan(results: ScanResults, rows: [Row], seconds: TimeInterval, deep: Bool) {
        let ready = rows.filter { $0.verdict == .ready }
        let inspect = rows.filter { $0.verdict == .inspect }
        let leave = rows.filter { $0.verdict == .leave }
        let readyBytes = ready.reduce(Int64(0)) { $0 + $1.item.size }

        Section.head("Done. Housekeeping looked for \(String(format: "%.1f", seconds))s and found \(rows.count) things.")
        say("")

        if rows.isEmpty {
            say("  Nothing it would offer you. Your Mac has no leftovers it can name well")
            say("  enough to be sure about, which is the answer it would rather give than a")
            say("  guess.")
            return
        }

        say("  \(pad("\(ready.count)", 4)) ready to clean        \(bytes(readyBytes))")
        say("  \(pad("\(inspect.count)", 4)) it would rather you looked at first   \(bytes(inspect.reduce(Int64(0)) { $0 + $1.item.size }))")
        say("  \(pad("\(leave.count)", 4)) best left alone      \(bytes(leave.reduce(Int64(0)) { $0 + $1.item.size }))")
        say("")

        if !deep {
            say("  This was a quick look, so sizes are as much as it could see without opening")
            say("  every folder. Run it again without --quick for the whole figure.")
            say("")
        }

        if !ready.isEmpty {
            Section.head("Ready to clean")
            say("")
            for row in ready.sorted(by: { $0.item.size > $1.item.size }) {
                printRow(row)
            }
        }

        if !inspect.isEmpty {
            say("")
            Section.head("Look at these first")
            say("")
            for row in inspect.sorted(by: { $0.item.size > $1.item.size }) {
                printRow(row)
            }
        }

        say("")
        say("  To have any one of them explained in full:")
        say("      housekeeping explain \"<path>\"")
        say("")
        say("  Nothing has been changed. Housekeeping only looks — the app is where")
        say("  anything is ever moved.")
    }

    private static func printRow(_ row: Row) {
        let item = row.item
        say("  \(pad(bytes(item.size), 10))  \(item.path.lastPathComponent)")
        var detail = "            \(item.path.deletingLastPathComponent().homeAbbreviatedPath)"
        if let app = item.primaryApplication?.name {
            detail += "  ·  \(app)"
        }
        say(detail)
    }

    // MARK: - Explaining one thing

    private static func explain(_ arguments: [String]) throws -> Int32 {
        let options = Options(arguments)
        guard let raw = options.positional.first else {
            throw Failure(2, "Housekeeping needs to be told what to explain.", "housekeeping explain \"/Users/you/Library/Caches/something\"")
        }

        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw Failure(1, "There is nothing at \(url.homeAbbreviatedPath).", "Check the spelling — Housekeeping only explains things that are actually there.")
        }

        loadRules()

        let item = explainItem(for: url)
        let assessment = CleanupSafetyPolicy(protectedPaths: ProtectionList().entries.map(\.path)).assess(item)
        let row = Row(item: item, assessment: assessment)

        if options.json {
            printJSON(row.document)
        } else {
            printExplanation(row)
        }
        return 0
    }

    /// A `FoundItem` for a path the reader named, which is the same shape the
    /// scanner produces — the guide, the category, and the verdict all come from
    /// the app's own tables, so this is the app's answer and not a second opinion.
    ///
    /// It is built the way a scan builds one: the item arrives carrying only what
    /// the filesystem can say about it — where it is, how big it is, when it
    /// changed — and the app's own classifier fills in the rest. Classifying it
    /// here rather than guessing at a category is what keeps `explain` from
    /// becoming a second, quietly different opinion about the same folder.
    private static func explainItem(for url: URL) -> FoundItem {
        let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
        ])
        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        let rule = RuleEngine.shared.findBestMatch(for: url)

        let application = rule.map { rule in
            ApplicationRef(
                name: rule.name,
                bundleIdentifier: rule.bundleIdentifier,
                isInstalled: rule.bundleIdentifier.map { RuleEngine.shared.isInstalled(bundleIdentifier: $0) } ?? false
            )
        }

        let raw = FoundItem(
            path: url,
            size: size,
            modified: values?.contentModificationDate,
            lastAccessed: values?.contentAccessDate,
            category: ruleCategory(rule: rule, url: url),
            safetyLevel: .unknown,
            association: .unknown,
            primaryApplication: application,
            isUndeclared: rule == nil
        )

        return Classifier().classify(items: [raw]).first ?? raw
    }

    /// The category the matching rule declares for this exact path, taken from the
    /// rule's own known paths rather than from anywhere else. A rule lists several
    /// folders and each carries its own category — caches are not preferences —
    /// so the longest declared path that contains this one is the one that knows.
    /// With no rule, the classifier decides; a `.unknown` here is what tells it to.
    private static func ruleCategory(rule: ApplicationRule?, url: URL) -> ItemCategory {
        guard let rule else { return .unknown }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let target = url.standardizedFileURL.path

        let match = rule.knownPaths
            .filter { known in
                var declared = known.relativePath
                if declared.hasPrefix("~") {
                    declared = home + declared.dropFirst()
                } else if !declared.hasPrefix("/") {
                    declared = home + "/" + declared
                }
                let standard = URL(fileURLWithPath: declared).standardizedFileURL.path
                return target == standard || target.hasPrefix(standard + "/")
            }
            .max { $0.relativePath.count < $1.relativePath.count }

        return match?.category ?? .unknown
    }

    private static func printExplanation(_ row: Row) {
        let item = row.item
        let guide = item.readerGuide

        Section.head(item.path.lastPathComponent)
        say("")

        say("  \(pad("Path", 14))\(item.path.homeAbbreviatedPath)")
        say("  \(pad("Size", 14))\(row.isFolder ? "A folder — scan to have it counted" : bytes(item.size))")
        if let app = item.primaryApplication?.name {
            say("  \(pad("Belongs to", 14))\(app)")
        }
        say("  \(pad("Kind", 14))\(item.category.displayName)")
        say("  \(pad("Verdict", 14))\(row.verdict.shortLabel)")
        say("  \(pad("Why", 14))\(row.assessment.reason)")
        say("")

        say(wrapped(guide.whatItIs, indent: "  "))
        say("")
        say(wrapped(guide.whyItExists, indent: "  "))
        say("")
        say(wrapped(guide.necessity, indent: "  "))
        say("")
        say(wrapped("\(guide.risk.rawValue) — \(guide.riskExplanation)", indent: "  "))

        if item.isUndeclared {
            say("")
            say(wrapped("Housekeeping has no description of this path in the rules it ships with, so it treats it with more caution than usual and will not offer it for cleaning.", indent: "  "))
        }
    }

    // MARK: - Quarantine

    private static func quarantine(_ arguments: [String]) async throws -> Int32 {
        var rest = arguments
        let sub = rest.first?.hasPrefix("-") == false ? rest.removeFirst() : "list"
        let options = Options(rest)
        let engine = CleanupEngine()

        switch sub {
        case "list":
            let entries = engine.quarantineEntries()
            if options.json {
                printJSON([
                    "folder": CleanupEngine.quarantineURL().path,
                    "count": entries.count,
                    "entries": entries.map { entry in
                        [
                            "original_path": entry.originalPath,
                            "quarantine_path": entry.quarantinePath,
                            "bytes": entry.size,
                            "moved": isoDate(entry.date),
                            "belongs_to": entry.appName ?? "",
                            "still_there": entry.existsInQuarantine,
                        ] as [String: Any]
                    },
                ])
                return 0
            }

            if entries.isEmpty {
                say("Nothing is being held. Housekeeping has not moved anything, or everything it moved has been put back.")
                return 0
            }

            Section.head("\(entries.count) things being held, \(bytes(entries.reduce(Int64(0)) { $0 + $1.size }))")
            say("")
            for entry in entries.sorted(by: { $0.date > $1.date }) {
                say("  \(pad(bytes(entry.size), 10))  \((entry.originalPath as NSString).lastPathComponent)")
                say("            moved \(isoDate(entry.date))\(entry.existsInQuarantine ? "" : "  ·  no longer there")")
            }
            say("")
            say("  They are in \(CleanupEngine.quarantineURL().homeAbbreviatedPath)")
            say("  Nothing is deleted until you delete it. Put everything back with:")
            say("      housekeeping quarantine restore --yes")
            return 0

        case "restore":
            guard options.has("--yes") else {
                say("This puts every held item back where it came from.")
                say("Run it again with --yes if that is what you want.")
                return 2
            }
            let result: RestoreResult
            do {
                result = try await engine.undoLastCleanup()
            } catch {
                // The engine throws when there is no record of a cleanup to undo,
                // which is not a malfunction and should not read like one.
                throw Failure(1, "There is nothing held to put back.")
            }

            let names = result.restoredItems.map { entry -> [String: Any] in
                let record = entry.item
                var object: [String: Any] = ["bytes": record.size]
                if let moved = record.quarantinePath { object["from"] = moved }
                if let original = record.originalPath { object["to"] = original }
                if case .failed(_, let reason) = entry { object["problem"] = reason }
                return object
            }

            if options.json {
                printJSON([
                    "restored": result.totalRestored,
                    "bytes": result.totalSize,
                    "items": names,
                ])
            } else if result.totalRestored == 0 {
                say("Nothing needed putting back.")
            } else {
                say("Put back \(result.totalRestored) thing\(result.totalRestored == 1 ? "" : "s"), \(bytes(result.totalSize)).")
                for entry in result.restoredItems where !entry.success {
                    if case .failed(_, let reason) = entry {
                        note("Could not put back \(entry.item.quarantinePath ?? "one item"): \(reason)")
                    }
                }
            }
            return 0

        default:
            throw Failure.unknownVerb("quarantine \(sub)")
        }
    }

    // MARK: - Shared helpers

    private static func loadRules() {
        let engine = RuleEngine.shared
        guard engine.applications.isEmpty else { return }
        engine.loadRules()
    }

    private static func rulesDirectoryPath() -> String? {
        Bundle.main.resourceURL?.appendingPathComponent("Rules").path
    }

    private static func bytes(_ count: Int64) -> String {
        count == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// `nonisolated` because `Row` is a plain struct with no actor of its own,
    /// and building a JSON object out of one is not work that needs the main
    /// thread. Formatting a date is the same job wherever it is asked for.
    nonisolated private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    /// Breaks a sentence at spaces so prose read in a terminal keeps a straight
    /// left edge. Word-wrapping is done here rather than left to the terminal
    /// because a paragraphs-worth of text arriving as one line is unreadable in a
    /// pipe and unreadable in a wide terminal.
    private static func wrapped(_ text: String, indent: String, width: Int = 76) -> String {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty {
                line = String(word)
            } else if line.count + word.count + 1 <= width - indent.count {
                line += " " + word
            } else {
                lines.append(indent + line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(indent + line) }
        return lines.joined(separator: "\n")
    }

    private static func say(_ text: String) {
        print(text)
    }

    /// Everything that is not the answer goes to stderr, so `--json` output can be
    /// handed straight to another program without a progress line landing in it.
    private static func note(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static func complain(_ text: String) {
        FileHandle.standardError.write(Data(("housekeeping: " + text + "\n").utf8))
    }

    private static func printJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            complain("could not put the answer into JSON")
            return
        }
        print(text)
    }

    // MARK: - One finding, as everything here wants it

    /// A finding and the app's verdict on it, together — because the two are never
    /// wanted apart, and pairing them here is what keeps a printed row, a JSON
    /// object, and the app's own list from drifting into three opinions.
    struct Row {
        let item: FoundItem
        let assessment: CleanupSafetyPolicy.Assessment

        var verdict: Verdict { Verdict.of(assessment.decision) }

        /// Whether this is a folder rather than a file.
        ///
        /// It matters because a folder has no size of its own — the filesystem
        /// will hand back the few bytes the directory entry occupies, which reads
        /// as an empty folder and is simply wrong. Asked of the filesystem rather
        /// than trusted from the path's spelling, since a trailing slash is not
        /// something a caller should have to remember.
        var isFolder: Bool {
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: item.path.path, isDirectory: &directory)
            return exists && directory.boolValue
        }

        var document: [String: Any] {
            let guide = item.readerGuide
            var object: [String: Any] = [
                "path": item.path.path,
                "name": item.path.lastPathComponent,
                "category": item.category.displayName,
                "verdict": verdictKey,
                "verdict_label": verdict.shortLabel,
                "why": assessment.reason,
                "what_it_is": guide.whatItIs,
                "why_it_is_there": guide.whyItExists,
                "needed": guide.necessity,
                "risk": guide.risk.rawValue,
                "risk_explained": guide.riskExplanation,
                "undeclared": item.isUndeclared,
            ]
            if let app = item.primaryApplication?.name { object["belongs_to"] = app }
            if let modified = item.modified { object["modified"] = isoDate(modified) }
            // A folder carries `is_folder` and no `bytes`, rather than a size of
            // zero that a caller would reasonably read as "empty". The same rule
            // as the printed version, said in the shape a program wants.
            if isFolder {
                object["is_folder"] = true
            } else {
                object["bytes"] = item.size
            }
            return object
        }

        /// The verdict as a word a program can branch on, rather than as the
        /// sentence a reader wants. The sentence is beside it.
        private var verdictKey: String {
            switch verdict {
            case .ready: return "ready"
            case .inspect: return "look_first"
            case .leave: return "leave_alone"
            }
        }
    }

    // MARK: - Arguments

    struct Options {
        private(set) var flags: Set<String> = []
        private(set) var positional: [String] = []

        init(_ arguments: [String]) {
            for argument in arguments {
                if argument.hasPrefix("-") {
                    flags.insert(argument)
                } else {
                    positional.append(argument)
                }
            }
        }

        func has(_ flag: String) -> Bool { flags.contains(flag) }
        var json: Bool { flags.contains("--json") }
    }

    struct Failure: Error {
        let status: Int32
        let message: String
        var hint: String?

        init(_ status: Int32, _ message: String, _ hint: String? = nil) {
            self.status = status
            self.message = message
            self.hint = hint
        }

        static func unknownVerb(_ verb: String) -> Failure {
            Failure(2, "Housekeeping does not know the command \"\(verb)\".", "housekeeping help")
        }
    }

    enum Section {
        /// A heading with a rule under it, so the answer reads as a page rather
        /// than as one long scroll.
        static func head(_ text: String) {
            print(text)
            print(String(repeating: "─", count: min(text.count, 78)))
        }
    }
}
