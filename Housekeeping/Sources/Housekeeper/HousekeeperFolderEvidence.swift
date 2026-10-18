import Foundation

/// Resolves the folder a question names against the app's full held inventory
/// and known locations. Reads only metadata and a bounded set of child names;
/// never reads file contents, runs a command, or changes the filesystem.
enum HousekeeperFolderEvidence {
    struct Location: Sendable {
        let path: String
        var purpose: String? = nil
        var owner: String? = nil
        var source: String? = nil
        var bytes: Int64? = nil
        var measuredAt: Date? = nil
        var isPartial: Bool = false
    }
    struct Request: Sendable {
        var focusedPath: String?
        let locations: [Location]
        let home: String
    }
    struct Report: Sendable {
        let context: String
        let focusedPath: String?
        var clarification: String? = nil
    }

    static func inspect(question: String, request: Request, fileManager: FileManager = .default) -> Report? {
        let query = question.lowercased()
        let words = Set(query.split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "." }.map(String.init))
        let paths = explicitPaths(in: question, home: request.home)
        let named = request.locations.filter { location in
            let name = URL(fileURLWithPath: location.path).lastPathComponent.lowercased()
            return name.count > 1 && query.range(of: "(?<![\\w])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\w])", options: .regularExpression) != nil
        }
        let aboutFolder = !paths.isEmpty || !named.isEmpty || ["folder", "directory", "cache"].contains(where: words.contains)
            || (request.focusedPath != nil && (["this", "that", "it", "inside", "wheels", "archives", "packages", "python"].contains(where: words.contains) || query.contains("what about")))
        guard aboutFolder else { return nil }

        var locations: [String: Location] = [:]
        for location in request.locations {
            let path = URL(fileURLWithPath: location.path).standardizedFileURL.path
            var merged = locations[path] ?? location
            if let purpose = location.purpose { merged.purpose = purpose; merged.owner = location.owner; merged.source = location.source }
            if let bytes = location.bytes { merged.bytes = bytes; merged.measuredAt = location.measuredAt; merged.isPartial = location.isPartial }
            locations[path] = merged
        }
        var targets = paths
        var resolutionNote: String?
        if paths.isEmpty {
            let focused = request.focusedPath
            if let focused, (named.isEmpty || named.contains { $0.path == focused }) {
                targets = [focused]
            } else {
                targets = Array(Set(named.map(\.path))).sorted()
            }
        } else if paths.count == 1, paths[0].split(separator: "/").count == 1,
                  !fileManager.fileExists(atPath: paths[0]) {
            // A displayed '/uv' may be a shorthand, but never silently pretend
            // the literal root path exists. Name matching is explicitly labelled.
            let basename = URL(fileURLWithPath: paths[0]).lastPathComponent
            let matches = locations.keys.filter { URL(fileURLWithPath: $0).lastPathComponent == basename }
            if let focused = request.focusedPath, matches.contains(focused) {
                resolutionNote = "The literal short path \(paths[0]) could not be found. It matches the name of the currently discussed folder \(focused). Explain that real folder using its full path; do not claim the root path exists."
                targets = [focused]
            } else if !matches.isEmpty {
                resolutionNote = "The literal path \(paths[0]) could not be found. These are folders with the same name in known locations, offered as alternatives rather than an exact-path match."
                targets = matches.sorted()
            }
        }
        guard !targets.isEmpty else {
            return Report(context: "FOLDER QUESTION: No path or unique matching folder was supplied. Ask for the full path or have the user open the folder and choose Explain this folder. You may explain a tool's general purpose without claiming a folder on this Mac was identified.", focusedPath: nil)
        }
        let totalTargets = targets.count
        targets = Array(targets.prefix(2))
        var lines = ["FOLDER EVIDENCE FOR THE LATEST QUESTION (read now; takes priority over general scan status):"]
        if let resolutionNote { lines.append(resolutionNote) }
        if totalTargets > targets.count { lines.append("Showing only two of \(totalTargets) matching paths. The folder is ambiguous until the user chooses a full path.") }
        if targets.count > 1 { lines.append("Several paths are discussed below. Keep their identities distinct; do not combine their sizes or purposes.") }
        var existing: [String] = []
        for path in targets {
            lines.append("Path: \(path)")
            guard let attributes = try? fileManager.attributesOfItem(atPath: path), let type = attributes[.type] as? FileAttributeType else {
                lines.append("This exact path could not be inspected. It may be missing or inaccessible; do not claim it exists.")
                continue
            }
            if type == .typeSymbolicLink {
                lines.append("Symbolic link. Destination: \((try? fileManager.destinationOfSymbolicLink(atPath: path)) ?? "unreadable"). Target contents were not inspected.")
                continue
            }
            guard type == .typeDirectory else { lines.append("This is a file, not a directory. Its contents were not read."); continue }
            existing.append(path)
            let identity = locations.values.filter { entry in
                entry.purpose != nil && (path == entry.path || path.hasPrefix(entry.path + "/"))
            }.max { $0.path.count < $1.path.count }
            if let identity {
                lines.append("Identified by Housekeeping's location rules: \(identity.owner ?? "known tool"). \(identity.purpose!)")
                if let source = identity.source { lines.append("Documentation: \(source)") }
            } else {
                lines.append("Purpose is not established by a known location rule. Use observed names as clues, not proof of ownership or disposability.")
            }
            // Exact known cache/data roots, not an arbitrary directory named uv.
            let uvCache = URL(fileURLWithPath: request.home).appendingPathComponent(".cache/uv").path
            let uvData = URL(fileURLWithPath: request.home).appendingPathComponent(".local/share/uv").path
            if path == uvCache || path.hasPrefix(uvCache + "/") {
                lines.append("PURPOSE: uv is Astral's Python package and project manager. This location is its shared package cache, reused across Python projects. It holds downloaded packages, wheels, extracted archives, build outputs and interpreter metadata so installs can reuse work. It is not the project's source code.")
                if query.contains("wheel") {
                    lines.append("WHEELS: A Python wheel (.whl) is a built, installable package distribution; it may contain pure Python code or compiled extensions. uv keeps wheel-related cache data in versioned buckets such as wheels-v6 or wheels-v7. The suffix describes uv's internal cache format, not Python's version. No package contents were read here.")
                }
                lines.append("CAUTION: Removing cache data may require downloads/rebuilds and can affect offline work. Use uv's own cache-management commands for cleanup; do not manually edit an active cache. Unusual symlink-linked environments can depend on cache data. This is an explanation, not a cleanup approval.")
                lines.append("Source: https://docs.astral.sh/uv/concepts/cache/")
            } else if path == uvData || path.hasPrefix(uvData + "/") {
                lines.append("PURPOSE: uv's persistent local data, distinct from its cache. It can contain uv-managed Python installations and tool environments. Removing it can break interpreters, tools or dependent projects; do not describe it as disposable package cache.")
                lines.append("Source: https://docs.astral.sh/uv/reference/storage/")
            }
            if let measured = locations[path], let bytes = measured.bytes {
                lines.append("Recorded size: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)); partial: \(measured.isPartial). Measured: \(measured.measuredAt?.formatted() ?? "date not recorded"). This is not a fresh size measurement or guaranteed recoverable space.")
            } else { lines.append("No measured folder size available. No recursive measurement was run for this question.") }
            do {
                guard let children = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]) else {
                    lines.append("Child names could not be read."); continue
                }
                var names: [String] = []
                for case let child as URL in children {
                    if Task.isCancelled { break }
                    names.append(String(child.lastPathComponent.prefix(80)))
                    if names.count >= 16 { break }
                }
                lines.append("Observed immediate child names (sample of at most 16; file contents not read): " + (names.isEmpty ? "none returned" : names.joined(separator: ", ")))
            }
        }
        lines.append("Answer what the folder is and why it exists using this evidence. Do not substitute a generic scan report or ask for a path already shown above. If purpose remains unknown, state that and explain which observed clues are useful.")
        var clarification: String?
        if existing.count > 1 && (paths.isEmpty || resolutionNote != nil), !["compare", "difference", "both"].contains(where: query.contains) {
            let choices = existing.map { path in
                let purpose = locations[path]?.purpose ?? "Purpose is not established."
                return "\(path)\n\(purpose)"
            }
            clarification = "I found more than one matching folder. These are different locations:\n\n" + choices.joined(separator: "\n\n") + "\n\nWhich folder do you mean? You can open it in Disk Browser and choose Explain this folder."
        }
        return Report(context: lines.joined(separator: "\n"), focusedPath: existing.count == 1 ? existing[0] : nil, clarification: clarification)
    }

    static func explicitPaths(in question: String, home: String) -> [String] {
        // Quoted paths may contain spaces; unquoted paths stop at prose punctuation.
        let pattern = #"[\"`']((?:~|/)[^\"`'\n]+)[\"`']|(?<![\w:/])((?:~/|/)[^\s\"`'<>?,;!]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(question.startIndex..., in: question)
        var paths: [String] = []
        for match in regex.matches(in: question, range: range).prefix(4) {
            let capture = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard let found = Range(capture, in: question) else { continue }
            var path = String(question[found]).trimmingCharacters(in: CharacterSet(charactersIn: ".:()"))
            if path.hasPrefix("~/") { path = home + String(path.dropFirst()) }
            guard path.hasPrefix("/"), !path.hasPrefix("//") else { continue }
            path = URL(fileURLWithPath: path).standardizedFileURL.path
            if !paths.contains(path) { paths.append(path) }
        }
        return paths
    }
}
