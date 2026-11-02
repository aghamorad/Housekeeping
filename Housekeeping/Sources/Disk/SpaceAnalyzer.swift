// Housekeeping — Space Analyzer & Storage Intelligence
//
// Fast, non-blocking disk capacity analyzer and category visualizer.
// Powers the Space Lens storage view with instant volume stats, category breakdowns,
// and large file discovery.

import Foundation
import AppKit

public struct StorageCategory: Identifiable, Sendable {
    public let id: String
    public let name: String
    public var size: Int64
    public let colorName: String
    public let icon: String
    public var isCalculating: Bool

    public init(
        id: String,
        name: String,
        size: Int64,
        colorName: String,
        icon: String,
        isCalculating: Bool = false
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.colorName = colorName
        self.icon = icon
        self.isCalculating = isCalculating
    }

    public var humanSize: String {
        if isCalculating && size == 0 {
            return "Measuring…"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public struct StorageItem: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    public let modifiedDate: Date?
    public let kind: String

    public var humanSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

@MainActor
public final class SpaceAnalyzer: ObservableObject {
    public static let shared = SpaceAnalyzer()

    @Published public private(set) var totalDiskBytes: Int64 = 0
    @Published public private(set) var freeDiskBytes: Int64 = 0
    @Published public private(set) var usedDiskBytes: Int64 = 0
    @Published public private(set) var isAnalyzing: Bool = false

    @Published public private(set) var categories: [StorageCategory] = []
    @Published public private(set) var largeFiles: [StorageItem] = []
    @Published public private(set) var currentFolderItems: [StorageItem] = []
    @Published public private(set) var currentFolderPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @Published public private(set) var navigationHistory: [String] = []
    @Published public private(set) var forwardHistory: [String] = []

    private let home = FileManager.default.homeDirectoryForCurrentUser

    public init() {
        refreshVolumeInfo()
        loadFolder(path: home.path)
        startCategoryAnalysis()
    }

    public var usedFraction: Double {
        guard totalDiskBytes > 0 else { return 0 }
        return Double(usedDiskBytes) / Double(totalDiskBytes)
    }

    public func refreshVolumeInfo() {
        do {
            let values = try home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let total = values.volumeTotalCapacity {
                totalDiskBytes = Int64(total)
            }
            if let avail = values.volumeAvailableCapacityForImportantUsage {
                freeDiskBytes = avail
            } else {
                let fsAttrs = try FileManager.default.attributesOfFileSystem(forPath: home.path)
                freeDiskBytes = (fsAttrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            }
            usedDiskBytes = max(0, totalDiskBytes - freeDiskBytes)
        } catch {
            totalDiskBytes = 500_000_000_000
            freeDiskBytes = 150_000_000_000
            usedDiskBytes = 350_000_000_000
        }
    }

    public func startCategoryAnalysis() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        let homeURL = self.home

        // Initialize categories with measuring state if empty or refresh requested
        if self.categories.isEmpty {
            self.categories = [
                StorageCategory(id: "apps", name: "Applications", size: 0, colorName: "blue", icon: "app.badge", isCalculating: true),
                StorageCategory(id: "dev", name: "Developer & Caches", size: 0, colorName: "purple", icon: "hammer.fill", isCalculating: true),
                StorageCategory(id: "media", name: "Media & Audio", size: 0, colorName: "pink", icon: "film.fill", isCalculating: true),
                StorageCategory(id: "downloads", name: "Downloads", size: 0, colorName: "orange", icon: "arrow.down.circle.fill", isCalculating: true),
                StorageCategory(id: "docs", name: "Documents", size: 0, colorName: "green", icon: "doc.fill", isCalculating: true),
                StorageCategory(id: "trash", name: "Trash", size: 0, colorName: "gray", icon: "trash.fill", isCalculating: true)
            ]
        } else {
            for i in self.categories.indices {
                self.categories[i].isCalculating = true
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            // Run all 6 categories in parallel
            async let appsTask = Self.duBytes(for: [
                "/Applications",
                "/Applications/Utilities",
                homeURL.appendingPathComponent("Applications").path
            ])

            async let downloadsTask = Self.duBytes(for: [
                homeURL.appendingPathComponent("Downloads").path
            ])

            async let trashTask = Self.duBytes(for: [
                homeURL.appendingPathComponent(".Trash").path
            ])

            async let mediaTask = Self.duBytes(for: [
                homeURL.appendingPathComponent("Movies").path,
                homeURL.appendingPathComponent("Music").path,
                homeURL.appendingPathComponent("Pictures").path
            ])

            async let devTask = Self.duBytes(for: [
                homeURL.appendingPathComponent("Library/Caches").path,
                homeURL.appendingPathComponent(".cache").path,
                homeURL.appendingPathComponent("Library/Developer/Xcode").path
            ])

            async let docsTask = Self.duBytes(for: [
                homeURL.appendingPathComponent("Documents").path,
                homeURL.appendingPathComponent("Desktop").path,
                homeURL.appendingPathComponent("C3PO").path
            ])

            async let largeFilesTask = Self.findLargeFiles(homeURL: homeURL)

            let (appsSize, downloadsSize, trashSize, mediaSize, devSize, docsSize, largeFiles) = await (
                appsTask, downloadsTask, trashTask, mediaTask, devTask, docsTask, largeFilesTask
            )

            let finalCategories: [StorageCategory] = [
                StorageCategory(id: "apps", name: "Applications", size: appsSize, colorName: "blue", icon: "app.badge", isCalculating: false),
                StorageCategory(id: "dev", name: "Developer & Caches", size: devSize, colorName: "purple", icon: "hammer.fill", isCalculating: false),
                StorageCategory(id: "media", name: "Media & Audio", size: mediaSize, colorName: "pink", icon: "film.fill", isCalculating: false),
                StorageCategory(id: "downloads", name: "Downloads", size: downloadsSize, colorName: "orange", icon: "arrow.down.circle.fill", isCalculating: false),
                StorageCategory(id: "docs", name: "Documents", size: docsSize, colorName: "green", icon: "doc.fill", isCalculating: false),
                StorageCategory(id: "trash", name: "Trash", size: trashSize, colorName: "gray", icon: "trash.fill", isCalculating: false)
            ]

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.categories = finalCategories
                self.largeFiles = largeFiles
                self.isAnalyzing = false
            }
        }
    }

    private nonisolated static func duBytes(for paths: [String]) async -> Int64 {
        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else { return 0 }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-sk"] + existingPaths
        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return 0 }
            var totalKB: Int64 = 0
            for line in output.components(separatedBy: "\n") {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                if let first = parts.first, let kb = Int64(first) {
                    totalKB += kb
                }
            }
            return totalKB * 1024
        } catch {
            return 0
        }
    }

    private nonisolated static func findLargeFiles(homeURL: URL) async -> [StorageItem] {
        // Fast Spotlight search for files > 200MB in home folder
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["kMDItemFSSize > 209715200", "-onlyin", homeURL.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var items: [StorageItem] = []

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                for path in lines.prefix(50) {
                    let url = URL(fileURLWithPath: path)
                    guard let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]),
                          vals.isDirectory != true,
                          let sz = vals.fileSize else { continue }

                    let ext = url.pathExtension.lowercased()
                    let kind: String
                    if ["dmg", "iso", "zip", "tar", "gz", "pkg"].contains(ext) {
                        kind = "Archive / Installer"
                    } else if ["mp4", "mkv", "mov", "avi", "m4v"].contains(ext) {
                        kind = "Video"
                    } else if ["mp3", "m4a", "m4b", "flac", "wav"].contains(ext) {
                        kind = "Audio"
                    } else {
                        kind = "File"
                    }

                    items.append(StorageItem(
                        url: url,
                        name: url.lastPathComponent,
                        size: Int64(sz),
                        isDirectory: false,
                        modifiedDate: vals.contentModificationDate,
                        kind: kind
                    ))
                }
            }
        } catch {}

        items.sort { $0.size > $1.size }
        return items
    }

    public func loadFolder(path: String) {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]) else { return }

        var items: [StorageItem] = []
        for item in contents {
            let vals = try? item.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey])
            let isDir = vals?.isDirectory == true && vals?.isPackage != true
            let size = Int64(vals?.fileSize ?? 0)

            items.append(StorageItem(
                url: item,
                name: item.lastPathComponent,
                size: size,
                isDirectory: isDir,
                modifiedDate: vals?.contentModificationDate,
                kind: isDir ? "Folder" : (vals?.isPackage == true ? "App / Package" : item.pathExtension.uppercased())
            ))
        }

        items.sort {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.size > $1.size
        }

        currentFolderPath = path
        currentFolderItems = items
    }

    public func navigateInto(_ item: StorageItem) {
        guard item.isDirectory else {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
            return
        }
        navigationHistory.append(currentFolderPath)
        forwardHistory.removeAll()
        loadFolder(path: item.url.path)
    }

    public func goBack() {
        guard let prev = navigationHistory.popLast() else { return }
        forwardHistory.append(currentFolderPath)
        loadFolder(path: prev)
    }

    public func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        navigationHistory.append(currentFolderPath)
        loadFolder(path: next)
    }

    public func goUp() {
        let parent = (currentFolderPath as NSString).deletingLastPathComponent
        guard parent != currentFolderPath, FileManager.default.fileExists(atPath: parent) else { return }
        navigationHistory.append(currentFolderPath)
        forwardHistory.removeAll()
        loadFolder(path: parent)
    }
}
