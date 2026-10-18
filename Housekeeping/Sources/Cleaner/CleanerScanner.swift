// Housekeeping — Clean Up: reading the disk for things that can be rebuilt

import AppKit
import Foundation

/// The cleaner's own reader. It is deliberately separate from `Scanner`: the
/// sweep asks "what does this app own, and can I prove it is disposable?", while
/// this asks "is this a cache, a build product, or an installer?" — questions
/// whose answers are settled by where a thing is and what it is named, not by a
/// rule file. The move itself still goes through the same quarantine engine.
struct CleanerScanner {
    let home: URL
    let quarantine: URL
    let progress: @Sendable (String) -> Void

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, progress: @escaping @Sendable (String) -> Void = { _ in }) {
        self.progress = progress
        self.home = home.standardizedFileURL
        self.quarantine = CleanupEngine.quarantineURL(homeDirectory: home.standardizedFileURL)
    }

    // MARK: - The whole reading

    static func scanAll(progress: @escaping @Sendable (String) -> Void, partial: @Sendable (CleanerSnapshot, Set<CleanCategory>) -> Void = { _, _ in }) -> CleanerSnapshot {
        let scanner = CleanerScanner(progress: progress)
        let protection = ProtectionList()
        var completed: Set<CleanCategory> = []
        func publish(_ candidates: [CleanCandidate], category: CleanCategory) {
            completed.insert(category)
            partial(CleanerSnapshot(candidates: CleanCandidate.nonOverlapping(candidates).filter { !protection.isProtected($0.url) }, apps: [], trash: TrashSummary(), notes: []), completed)
        }
        progress("Looking through caches and logs…")
        var candidates = scanner.everydayJunk()
        publish(candidates, category: .everydayJunk)

        progress("Looking through developer caches…")
        candidates += scanner.developerCaches()

        progress("Looking through project folders for build leftovers…")
        candidates += scanner.projectArtifacts()
        publish(candidates, category: .developerLeftovers)

        progress("Looking for installers…")
        let installers = scanner.installers()
        candidates += installers
        publish(candidates, category: .installers)

        progress("Looking for large files…")
        var seen = Set(candidates.map(\.id))
        let large = scanner.largeFiles(excluding: seen)
        candidates += large
        seen.formUnion(large.map(\.id))
        publish(candidates, category: .largeFiles)

        progress("Listing your applications…")
        let apps = Uninstaller.installed(progress: progress).filter { !protection.isProtected($0.url) }.map { app in
            var copy = app
            copy.leftovers.removeAll { protection.isProtected($0.url) }
            return copy
        }
        completed.insert(.uninstall)
        partial(CleanerSnapshot(candidates: CleanCandidate.nonOverlapping(candidates).filter { !protection.isProtected($0.url) }, apps: apps, trash: TrashSummary(), notes: []), completed)

        progress("Counting the Trash…")
        let trash = TrashService.summary()

        // Anything already on the left-alone list is not offered again. The
        // list is read fresh from disk so a path protected a moment ago in a
        // context menu is honoured by the very next scan.
        if !protection.isEmpty {
            candidates.removeAll { protection.isProtected($0.url) }
        }

        return CleanerSnapshot(
            candidates: CleanCandidate.nonOverlapping(candidates).sorted { $0.size > $1.size },
            apps: apps,
            trash: trash,
            // macOS guards the Trash behind Full Disk Access. That is a
            // setting to change, not a passing condition, so say what it
            // actually is rather than guessing at a locked file.
            notes: trash.unreadable ? ["The Trash could not be read. macOS only lets an app see the Trash once you allow it under Full Disk Access in System Settings."] : []
        )
    }

    // MARK: - Everyday junk

    /// Caches, logs, saved window state and crash reports. Each is read one
    /// level deep, because the thing worth offering is the folder belonging to
    /// an app, not each file inside it.
    private func everydayJunk() -> [CleanCandidate] {
        struct Root {
            let relative: String
            let kind: String
            let leastSize: Int64
        }

        let roots = [
            Root(relative: "Library/Caches", kind: "A cache. The app makes it again when it needs it.", leastSize: 1_048_576),
            Root(relative: "Library/Logs", kind: "A log. It only records what already happened.", leastSize: 1_048_576),
            Root(relative: "Library/Saved Application State", kind: "Saved window positions. The app makes them again the next time it quits.", leastSize: 0),
            Root(relative: "Library/Application Support/CrashReporter", kind: "Crash reports. They only describe a crash that already happened.", leastSize: 0)
        ]

        var found: [CleanCandidate] = []
        for root in roots {
                if Task.isCancelled { break }
            let directory = home.appendingPathComponent(root.relative, isDirectory: true)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey],
                options: []
            )) ?? []

            for child in children {
                if Task.isCancelled { break }
                let name = child.lastPathComponent
                guard name != ".DS_Store", !name.hasPrefix(".") else { continue }
                let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values?.isSymbolicLink != true else { continue }
                guard !isInsideQuarantine(child) else { continue }
                if child.lastPathComponent == "Housekeeping" { continue }

                let size = measure(child)
                guard size >= root.leastSize else { continue }
                guard size > 0 else { continue }

                let display = Self.appName(forCacheName: name)
                found.append(CleanCandidate(
                    url: child,
                    size: size,
                    modified: Self.modified(child),
                    category: .everydayJunk,
                    name: display ?? name,
                    detail: display == nil ? root.kind : "\(name) — \(root.kind)"
                ))
            }
        }
        return found
    }

    // MARK: - Developer caches

    /// Download caches with a fixed, well-known location. Unlike a project
    /// folder, there is nothing here to prove: the path is the proof.
    private func developerCaches() -> [CleanCandidate] {
        let known: [(String, String)] = [
            (".npm/_cacache", "npm's download cache. `npm install` fills it again."),
            (".npm/_npx", "Packages run once with npx. They are downloaded again when needed."),
            (".yarn/cache", "Yarn's download cache."),
            ("Library/pnpm/store", "pnpm's download cache."),
            (".bun/install/cache", "Bun's download cache."),
            (".cache/pip", "pip's download cache."),
            (".cache/uv", "uv's download cache."),
            (".cargo/registry", "Rust crate sources downloaded by Cargo."),
            (".cargo/git", "Rust crates fetched from git by Cargo."),
            (".gradle/caches", "Gradle's download cache. The next build fetches what it needs."),
            (".m2/repository", "Java libraries downloaded by Maven."),
            (".cache/go-build", "Go's build cache."),
            ("go/pkg/mod/cache/download", "Go module downloads."),
            ("Library/Developer/Xcode/DerivedData", "Xcode's build products. The next build makes them again."),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Symbols for iOS versions Xcode has already read. They are copied off the device again when needed."),
            ("Library/Developer/CoreSimulator/Caches", "Simulator caches."),
            ("Library/Caches/CocoaPods", "CocoaPods' download cache."),
            ("Library/Caches/org.swift.swiftpm", "Swift Package Manager's download cache."),
            ("Library/Caches/Homebrew", "Homebrew's download cache. Installed programs are not affected.")
        ]

        var found: [CleanCandidate] = []
        for (relative, note) in known {
            let url = home.appendingPathComponent(relative, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard !isInsideQuarantine(url) else { continue }
            let size = measure(url)
            guard size > 0 else { continue }
            found.append(CleanCandidate(
                url: url,
                size: size,
                modified: Self.modified(url),
                category: .developerLeftovers,
                name: url.lastPathComponent,
                detail: note
            ))
        }
        return found
    }

    // MARK: - Project build leftovers

    /// Build folders inside the places projects actually live. A folder is only
    /// offered when the project beside it proves what it is: `.build` needs a
    /// `Package.swift`, `target` needs a `Cargo.toml`, a `build` folder needs a
    /// `package.json`. Without that proof it is just a folder that happens to be
    /// called "build", and it is left alone.
    private func projectArtifacts() -> [CleanCandidate] {
        let roots = [
            "Desktop", "Documents", "Downloads",
            "Claude", "Goose", "Projects", "Developer", "Code", "Hermes", "Gapcode"
        ]

        var found: [CleanCandidate] = []
        for relative in roots {
                if Task.isCancelled { break }
            let root = home.appendingPathComponent(relative, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            found += artifacts(under: root)
        }
        return found
    }

    private func artifacts(under root: URL) -> [CleanCandidate] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .contentModificationDateKey
        ]
        guard let walk = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [CleanCandidate] = []
        var budget = 60_000

        while let entry = walk.nextObject() as? URL {
            if Task.isCancelled { break }
            budget -= 1
            if budget <= 0 { break }

            let name = entry.lastPathComponent
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isSymbolicLink != true, values.isDirectory == true else { continue }
            guard !isInsideQuarantine(entry) else { walk.skipDescendants(); continue }

            if walk.level > 9 { walk.skipDescendants(); continue }

            // Never walk a repository, a library, or the Trash. The last two are
            // either not a project or are handled somewhere else entirely.
            if name == ".git" || name == "Library" || name == ".Trash" || name == "Housekeeping Quarantine" {
                walk.skipDescendants()
                continue
            }

            if let note = Self.artifactNote(name: name, at: entry) {
                let size = measure(entry)
                if size > 0 {
                    found.append(CleanCandidate(
                        url: entry,
                        size: size,
                        modified: Self.modified(entry),
                        category: .developerLeftovers,
                        name: name,
                        detail: note
                    ))
                }
                walk.skipDescendants()
                continue
            }

            // Folders that are never worth walking into, whether or not they
            // turn out to be a build product.
            if Self.prunedNames.contains(name) {
                walk.skipDescendants()
            }
        }
        return found
    }

    private static let prunedNames: Set<String> = [
        ".venv", "venv", ".tox", ".pytest_cache", ".mypy_cache",
        ".ruff_cache", ".gradle", ".dart_tool", "Pods", "DerivedData",
        ".build", "node_modules", "target", ".next", ".nuxt", ".svelte-kit",
        ".turbo", ".parcel-cache"
    ]

    /// The sentence to print for a build folder, or nil when this name is not
    /// proof of anything at this location.
    private static func artifactNote(name: String, at url: URL) -> String? {
        let parent = url.deletingLastPathComponent()

        func beside(_ file: String) -> Bool {
            FileManager.default.fileExists(atPath: parent.appendingPathComponent(file).path)
        }

        switch name {
        case "node_modules":
            return "Installed packages. The project's source is above it; `npm install` puts these back."
        case "__pycache__":
            return "Python bytecode. Python writes it again the next time the file is imported."
        case ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox":
            return "A tool's cache. It is written again the next time the tool runs."
        case ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache":
            return "A JavaScript build's cache. The next build makes it again."
        case ".dart_tool":
            return "Dart and Flutter's build cache. The next build makes it again."
        case ".build":
            return beside("Package.swift")
                ? "Swift build products. `swift build` makes them again."
                : nil
        case "target":
            return beside("Cargo.toml")
                ? "Rust build products. `cargo build` makes them again."
                : nil
        case "build", "dist", "out":
            return beside("package.json")
                ? "Build output. The project's source is above it; the build makes it again."
                : nil
        case ".venv", "venv":
            return beside("pyproject.toml") || beside("requirements.txt")
                || beside("setup.py") || beside("Pipfile")
                ? "A Python environment. The packages can be installed again from the project's requirements."
                : nil
        case "Pods":
            return beside("Podfile")
                ? "CocoaPods libraries. `pod install` puts them back."
                : nil
        case ".gradle":
            return beside("build.gradle") || beside("build.gradle.kts")
                ? "Gradle's project cache. The next build makes it again."
                : nil
        default:
            return nil
        }
    }

    // MARK: - Installers

    private func installers() -> [CleanCandidate] {
        let roots = [
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true)
        ]

        let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
        let archiveExtensions: Set<String> = ["zip", "rar", "7z"]

        var found: [CleanCandidate] = []
        for root in roots {
                if Task.isCancelled { break }
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let walk = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isPackageKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let entry = walk.nextObject() as? URL {
            if Task.isCancelled { break }
                if walk.level > 3 { walk.skipDescendants(); continue }
                let name = entry.lastPathComponent
                let ext = entry.pathExtension.lowercased()
                guard installerExtensions.contains(ext) || archiveExtensions.contains(ext) else { continue }

                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey])
                guard values?.isDirectory != true, values?.isSymbolicLink != true else { continue }
                guard !isInsideQuarantine(entry) else { continue }

                let size = measure(entry)
                // An ordinary zip has to be big to be worth a row; a disk image
                // or installer is always worth one, because that is what the
                // shelf is for.
                if archiveExtensions.contains(ext), size < 209_715_200 { continue }

                let isDiskImage = installerExtensions.contains(ext)
                found.append(CleanCandidate(
                    url: entry,
                    size: size,
                    modified: values?.contentModificationDate,
                    category: .installers,
                    name: name,
                    detail: isDiskImage
                        ? "An installer. The app it installed is already on your Mac; this copy only saves a download."
                        : "A large archive. Look at what is inside before moving it."
                ))
            }
        }
        return found
    }

    // MARK: - Large and old files

    private func largeFiles(excluding known: Set<String>) -> [CleanCandidate] {
        // Music is left out on purpose: reading inside it asks macOS for media-library
        // access, and the library is Apple Music's to manage — a cleaner has no business
        // offering its songs for quarantine.
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Pictures"]
        let now = Date()
        let yearAgo = now.addingTimeInterval(-365 * 24 * 60 * 60)

        var found: [CleanCandidate] = []
        for relative in roots {
                if Task.isCancelled { break }
            let root = home.appendingPathComponent(relative, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let walk = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isPackageKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            var budget = 120_000
            while let entry = walk.nextObject() as? URL {
            if Task.isCancelled { break }
                budget -= 1
                if budget <= 0 { break }
                guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]) else { continue }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                guard !isInsideQuarantine(entry) else { continue }
                guard !known.contains(entry.standardizedFileURL.path) else { continue }

                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                let modified = values.contentModificationDate
                let isBig = size >= 524_288_000
                let isOldAndMedium = size >= 209_715_200 && (modified.map { $0 < yearAgo } ?? false)
                guard isBig || isOldAndMedium else { continue }

                let age = modified.map { Self.ageNote($0) } ?? "an unknown age"
                found.append(CleanCandidate(
                    url: entry,
                    size: size,
                    modified: modified,
                    category: .largeFiles,
                    name: entry.lastPathComponent,
                    detail: isBig
                        ? "One of the biggest files on this Mac, last changed \(age)."
                        : "Not changed in \(age). It is only listed because it is old and fairly large."
                ))
            }
        }
        return found.sorted { $0.size > $1.size }.prefix(200).map { $0 }
    }

    // MARK: - Small helpers

    private func isInsideQuarantine(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let root = quarantine.path
        return path == root || path.hasPrefix(root + "/")
    }

    /// The application name behind a cache folder called `com.example.Thing`,
    /// when Launch Services knows one. Otherwise the folder keeps its own name,
    /// which is ugly but honest.
    private static func appName(forCacheName name: String) -> String? {
        guard name.contains(".") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) else { return nil }
        var display = FileManager.default.displayName(atPath: appURL.path)
        if display.hasSuffix(".app") { display.removeLast(4) }
        return display.isEmpty ? nil : display
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Allocated size, which is what the Finder shows and what freeing it
    /// actually returns to the disk. Symbolic links are never followed: a link
    /// is not the thing it points at, and counting it twice would overstate what
    /// can be freed.
    private func measure(_ url: URL) -> Int64 {
        progress("Measuring " + url.homeAbbreviatedPath)
        return Self.size(of: url, progress: progress)
    }

    static func size(of url: URL, progress: (@Sendable (String) -> Void)? = nil) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return 0 }

        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }

        guard let walk = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var files = 0
        var lastReport = Date()
        while let entry = walk.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let child = try? entry.resourceValues(forKeys: keys) else { continue }
            if child.isSymbolicLink == true {
                walk.skipDescendants()
                continue
            }
            guard child.isDirectory != true else { continue }
            total += Int64(child.totalFileAllocatedSize ?? child.fileAllocatedSize ?? child.fileSize ?? 0)
            files += 1
            if progress != nil, files % 512 == 0, Date().timeIntervalSince(lastReport) > 0.4 {
                progress?("Measuring \(url.homeAbbreviatedPath) · \(files.formatted()) files · \(total.humanReadable)")
                lastReport = Date()
            }
        }
        return total
    }

    private static func ageNote(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 60 { return "\(days) days ago" }
        if days < 730 { return "\(days / 30) months ago" }
        return "\(days / 365) years ago"
    }
}
