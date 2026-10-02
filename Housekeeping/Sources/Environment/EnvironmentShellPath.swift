// Housekeeping — what your shell's search path actually is
//
// On macOS, "my PATH" is not one value. It is `/etc/paths` and `/etc/paths.d`,
// then a `path_helper` call Apple puts in `/etc/zprofile`, then every profile
// file in the home folder in the order a login shell reads them, each of which
// may prepend, append, or splice the value it inherited. The value that matters
// is the one at the end of that sequence, in a new terminal window.
//
// So this reads the files in that order and simulates it, token by token. The
// simulation is the whole point: a folder is not "on the PATH", it is on the
// PATH *at a position*, and position is what decides which `yt-dlp` runs. Any
// screen about duplicates that lists folders rather than their order cannot
// answer the only question worth asking.
//
// Two things this deliberately does not do.
//
// It does not run anything. `export PATH="$(some-tool init)"` is real and
// common, and the only way to know what it produces is to execute it — which
// this app will not do while merely reading. Those lines are counted and
// reported as a gap, not guessed at.
//
// It does not read PATH assignments that are indented. An indented assignment
// is inside a function or a conditional and does not run at startup; treating
// it as if it did would be inventing a search path. They are counted too.

import Foundation

struct ShellPathModel {

    /// One folder added to the search path, with where the line that added it
    /// was. Provenance is kept for every entry because the tidying fix has to
    /// name the file it will rewrite, and because "which file did this" is the
    /// first question anyone asks about a surprising entry.
    struct Addition {
        let path: String
        let file: String
        let line: Int
        /// Whether the folder was named literally. False for the folders a
        /// package manager adds through its own `shellenv` call: those are not
        /// lines the reader wrote and are not lines this app will rewrite.
        let isLiteral: Bool
    }

    let homePath: String
    /// The profile files that exist, in the order a login shell reads them.
    private(set) var files: [String] = []
    /// Every folder added by any file, in the order it was added.
    private(set) var additions: [Addition] = []
    /// The folders a shell would actually search, in order, with repeats kept
    /// only once — at the position of the first mention, which is the position
    /// that decides what runs.
    private(set) var searchDirectories: [String] = []
    /// Whether any profile file asks the shell to remove repeats itself. zsh
    /// does this if you ask it to; without it, a repeated entry is a repeated
    /// entry, and this app's tidying has something to do.
    private(set) var zshUniquesPath = false
    private(set) var notes: [String] = []

    private var contentsByFile: [String: String] = [:]
    private var skippedIndented: [String] = []
    private var skippedCommands: [String] = []

    // MARK: - Reading

    /// The profile files a login shell reads, in order. `.bash_profile` is in
    /// the list because a Mac where someone once ran `chsh -s /bin/bash` still
    /// reads it, and a stale `.bash_profile` putting a folder ahead of everything
    /// is exactly the kind of thing that is invisible until it breaks something.
    static let profileNames = [".zshenv", ".zprofile", ".zshrc", ".zlogin", ".profile", ".bash_profile"]

    static func read(home: URL, brewPrefix: String?) -> ShellPathModel {
        var model = ShellPathModel(homePath: home.path)
        let fileManager = FileManager.default

        // The base: `/etc/paths` and the drop-ins beside it, which is what
        // `path_helper` assembles before any file in the home folder is read.
        var base: [String] = []
        let dropIns = (try? fileManager.contentsOfDirectory(atPath: "/etc/paths.d")) ?? []
        for source in ["/etc/paths"] + dropIns.sorted().map({ "/etc/paths.d/\($0)" }) {
            guard let text = try? String(contentsOfFile: source, encoding: .utf8) else { continue }
            base.append(contentsOf: text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") })
        }
        base = dedupe(base)

        var current = base
        for name in profileNames {
            let path = home.appendingPathComponent(name).path
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            model.files.append(path)
            model.contentsByFile[path] = text
            current = model.apply(text, file: path, to: current, brewPrefix: brewPrefix)
        }
        model.searchDirectories = dedupe(current)

        if !model.skippedIndented.isEmpty {
            model.notes.append("\(model.skippedIndented.count) PATH line\(model.skippedIndented.count == 1 ? "" : "s") indented inside a function or a conditional \(model.skippedIndented.count == 1 ? "was" : "were") left out of this reading, because indented lines do not run when a shell starts: \(model.skippedIndented.prefix(4).joined(separator: ", ")).")
        }
        if !model.skippedCommands.isEmpty {
            model.notes.append("\(model.skippedCommands.joined(separator: ", ")) sets PATH from a command's output. Housekeeping reads rather than runs, so whatever that command adds is missing from the path below.")
        }
        return model
    }

    /// One file's contribution, applied to the path it inherited.
    private mutating func apply(_ text: String, file: String, to inherited: [String], brewPrefix: String?) -> [String] {
        var current = inherited
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }

            if trimmed.contains("typeset -U path") || trimmed.contains("typeset -U PATH") {
                zshUniquesPath = true
            }

            // The package manager's own line. It prepends its folders, and it is
            // recognised rather than executed — the folders it would add are the
            // ones next to the `brew` that Homebrew installed.
            if let directories = Self.brewShellEnvDirectories(trimmed, brewPrefix: brewPrefix) {
                current = directories + current
                additions.append(contentsOf: directories.map {
                    Addition(path: $0, file: file, line: index + 1, isLiteral: false)
                })
                continue
            }

            guard let assignment = Self.pathAssignment(trimmed) else { continue }
            if assignment.rhs.contains("$(") || assignment.rhs.contains("`") {
                skippedCommands.append("\(((file as NSString).abbreviatingWithTildeInPath)):\(index + 1)")
                continue
            }
            if trimmed != line { skippedIndented.append("\((file as NSString).abbreviatingWithTildeInPath):\(index + 1)"); continue }

            var next: [String] = []
            for token in Self.split(assignment.rhs) {
                if Self.isPathSplice(token) {
                    next.append(contentsOf: current)
                } else {
                    let expanded = Self.expand(token, homePath: homePath)
                    guard !expanded.isEmpty else { continue }
                    next.append(expanded)
                    additions.append(Addition(path: expanded, file: file, line: index + 1, isLiteral: true))
                }
            }
            current = next
        }
        return current
    }

    // MARK: - Reading one line

    /// A line that assigns PATH, taken apart so the app can put it back together
    /// with different tokens in it. The quotes are kept, not removed: a rewrite
    /// that quietly drops the quoting from someone's profile file has changed
    /// more than it was asked to.
    struct PathAssignment {
        let prefix: String
        let rhs: String
        let suffix: String
    }

    static func pathAssignment(_ line: String) -> PathAssignment? {
        var rest = line
        var prefix = ""

        for leader in ["export PATH=", "export path=", "PATH=", "path="] {
            if rest.hasPrefix(leader) {
                prefix = leader
                rest = String(rest.dropFirst(leader.count))
                break
            }
        }
        guard !prefix.isEmpty, !rest.isEmpty else { return nil }

        if let first = rest.first, first == "\"" || first == "'" {
            let quote = String(first)
            let body = rest.dropFirst()
            guard let closing = body.lastIndex(of: Character(quote)) else { return nil }
            return PathAssignment(
                prefix: prefix + quote,
                rhs: String(body[body.startIndex..<closing]),
                suffix: String(body[closing...])
            )
        }
        // Unquoted, so a trailing comment has to be recognised by hand.
        if let comment = rest.range(of: " #") {
            return PathAssignment(prefix: prefix, rhs: String(rest[rest.startIndex..<comment.lowerBound]), suffix: String(rest[comment.lowerBound...]))
        }
        return PathAssignment(prefix: prefix, rhs: rest, suffix: "")
    }

    /// Splits a path value on its colons. No token this app writes ever contains
    /// a colon, and a folder with a colon in its name cannot be represented in
    /// PATH at all, so a plain split is the correct reading rather than a
    /// simplification.
    static func split(_ rhs: String) -> [String] {
        rhs.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    }

    static func isPathSplice(_ token: String) -> Bool {
        ["$PATH", "${PATH}", "$path", "${path}", "$Path"].contains(token)
    }

    /// `$HOME`, `${HOME}`, and a leading `~`, which is every way a profile file
    /// on this machine names the home folder.
    static func expand(_ token: String, homePath: String) -> String {
        var value = token
        for variable in ["$HOME", "${HOME}"] {
            value = value.replacingOccurrences(of: variable, with: homePath)
        }
        if value == "~" { value = homePath }
        if value.hasPrefix("~/") { value = homePath + value.dropFirst(1) }
        // `..` and a trailing slash are visual noise in a folder list and mean
        // nothing to a shell.
        value = URL(fileURLWithPath: value).standardized.path
        while value.count > 1 && value.hasSuffix("/") { value = String(value.dropLast()) }
        return value
    }

    /// `eval "$(/opt/homebrew/bin/brew shellenv)"` and its plainer cousins.
    /// The folders are derived from where that `brew` lives rather than by
    /// running it, so a reading stays a reading.
    static func brewShellEnvDirectories(_ line: String, brewPrefix: String?) -> [String]? {
        guard line.contains("shellenv") else { return nil }

        var prefix = brewPrefix
        if let match = try? NSRegularExpression(pattern: "(/[A-Za-z0-9_.+\\-@/]*/bin/brew)").firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ), let range = Range(match.range, in: line) {
            prefix = URL(fileURLWithPath: String(line[range])).deletingLastPathComponent().deletingLastPathComponent().path
        }
        guard let prefix, FileManager.default.fileExists(atPath: "\(prefix)/bin/brew") else { return nil }
        return ["\(prefix)/bin", "\(prefix)/sbin"]
    }

    /// Keeps the first mention of each folder and drops the rest. First, not
    /// last: the first mention is where a shell finds the folder, so dropping a
    /// later repeat cannot change which program runs.
    static func dedupe(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }
    }

    // MARK: - What the reading turns into

    /// Folders added more than once *by the same file*. Repeats spread across
    /// two files are left to the report, because which of the two should keep an
    /// entry depends on whether a shell is a login shell, and this app has no
    /// way to know how the reader opens a terminal.
    func repeatedWithinFile(_ file: String) -> [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for addition in additions where addition.file == file && addition.isLiteral {
            if counts[addition.path] == nil { order.append(addition.path) }
            counts[addition.path, default: 0] += 1
        }
        return order.filter { (counts[$0] ?? 0) > 1 }
    }

    /// Folders named by more than one file, for the report that has no fix.
    func repeatedAcrossFiles() -> [(String, [String])] {
        var byPath: [String: [String]] = [:]
        for addition in additions where addition.isLiteral {
            if !byPath[addition.path, default: []].contains(addition.file) {
                byPath[addition.path, default: []].append(addition.file)
            }
        }
        return byPath.filter { $0.value.count > 1 }
            .map { ($0.key, $0.value.sorted()) }
            .sorted { $0.0 < $1.0 }
    }

    func findings() -> [EnvironmentFinding] {
        var findings: [EnvironmentFinding] = []

        for file in files {
            let repeated = repeatedWithinFile(file)
            guard !repeated.isEmpty else { continue }
            let short = (file as NSString).abbreviatingWithTildeInPath
            findings.append(EnvironmentFinding(
                id: "pathfile:\(file)",
                category: .shellPath,
                severity: .untidy,
                title: "\(short) adds \(repeated.count == 1 ? "a folder" : "\(repeated.count) folders") more than once",
                summary: "The same folder is named twice in this file, which changes nothing about what runs — the first mention already wins — and makes the file harder to read and the search path harder to compare against another machine's.",
                evidence: repeated.map { "Repeated in \(short): \(($0 as NSString).abbreviatingWithTildeInPath)" }
                    + ["The file is read \(files.firstIndex(of: file).map { "\($0 + 1)\(ordinal($0 + 1))" } ?? "in order") of \(files.count)."],
                steps: [],
                fix: .rewriteShellConfig(path: file, newContents: correctedContents(of: file)),
                isSelected: true
            ))
        }

        for (path, files) in repeatedAcrossFiles() {
            let short = (path as NSString).abbreviatingWithTildeInPath
            findings.append(EnvironmentFinding(
                id: "pathcross:\(path)",
                category: .shellPath,
                severity: .untidy,
                title: "\(short) is added by \(files.count) different files",
                summary: "Two files both put this folder on the search path. Nothing is broken by it, and Housekeeping will not choose between them: which file should keep the entry depends on whether a shell is a login shell, and that is a question about how you open a terminal, not about the file.",
                evidence: files.map { "Added by \((($0 as NSString).abbreviatingWithTildeInPath))" },
                steps: [],
                fix: nil,
                isSelected: false
            ))
        }

        return findings
    }

    /// The file with later repeats of a folder removed, keeping the first
    /// mention of each so the order the shell searches in is bit-for-bit what it
    /// was. Every other line, including comments and blank lines, is copied
    /// through untouched.
    func correctedContents(of file: String) -> String {
        guard let text = contentsByFile[file] else { return "" }
        var seen = Set<String>()
        var output: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed == line,
                  let assignment = ShellPathModel.pathAssignment(trimmed),
                  !assignment.rhs.contains("$("), !assignment.rhs.contains("`") else {
                output.append(line)
                continue
            }

            var tokens: [String] = []
            for token in ShellPathModel.split(assignment.rhs) {
                if ShellPathModel.isPathSplice(token) { tokens.append(token); continue }
                let expanded = ShellPathModel.expand(token, homePath: homePath)
                guard !expanded.isEmpty else { continue }
                if seen.contains(expanded) { continue }
                seen.insert(expanded)
                tokens.append(token)
            }
            output.append(assignment.prefix + tokens.joined(separator: ":") + assignment.suffix)
        }
        return output.joined(separator: "\n")
    }

    /// The first line that puts a folder on the search path, so the fix that
    /// moves one folder later can name the file and the line it will touch.
    func lineIntroducing(_ directory: String) -> (file: String, line: Int)? {
        for addition in additions where addition.path == directory && addition.isLiteral {
            return (addition.file, addition.line)
        }
        return nil
    }

    /// A file whose own text mentions a path. Used for the runtime group, where
    /// the question is not what a file adds to PATH but whether it refers to the
    /// runtime at all — a wrapper function calling an absolute path counts, and
    /// fails the same way a broken symlink does.
    func filesMentioning(_ text: String) -> [String] {
        files.filter { contentsByFile[$0]?.contains(text) ?? false }
    }

    /// One folder moved to the end of the search path, in whichever line names
    /// it. Used for the case where two package managers both provide a command:
    /// the one that should lose is the one that goes last.
    func demoting(_ directory: String, in file: String) -> String {
        guard let text = contentsByFile[file] else { return "" }
        let stem = (directory as NSString).deletingLastPathComponent  // "/opt/local" for "/opt/local/bin"
        var output: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let assignment = ShellPathModel.pathAssignment(trimmed),
                  ShellPathModel.split(assignment.rhs).contains(where: { $0.hasPrefix(stem) || $0.contains("/opt/local") }) else {
                output.append(line)
                continue
            }

            let tokens = ShellPathModel.split(assignment.rhs)
            let moving = tokens.filter { $0.contains("/opt/local") }
            var staying = tokens.filter { !$0.contains("/opt/local") }
            // Without a splice there is nothing for it to move behind, so the
            // inherited path is put in front of both.
            if !staying.contains(where: ShellPathModel.isPathSplice) {
                staying.insert("$PATH", at: 0)
            }
            output.append(assignment.prefix + (staying + moving).joined(separator: ":") + assignment.suffix)
        }
        return output.joined(separator: "\n")
    }

    private func ordinal(_ value: Int) -> String {
        switch value % 100 {
        case 11, 12, 13: return "th"
        default: break
        }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
