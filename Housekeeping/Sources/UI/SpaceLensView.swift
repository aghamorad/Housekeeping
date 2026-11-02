// Housekeeping — Space Lens & Visual Storage Explorer
//
// Modern, intuitive disk visualizer and storage manager.
// Replaces cramped, confusing scans with instant volume overview, category breakdown,
// large-file discovery, and fluid folder exploration.

import SwiftUI
import AppKit

struct SpaceLensView: View {
    @ObservedObject var analyzer: SpaceAnalyzer = .shared
    @Environment(\.uiStyle) private var style

    @State private var activeTab: Tab = .categories
    @State private var searchFilter: String = ""

    private enum Tab: String, CaseIterable, Identifiable {
        case categories = "Storage Lens"
        case largeFiles = "Big & Old Files"
        case explorer = "Folder Explorer"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .categories: return "circle.grid.cross"
            case .largeFiles: return "doc.zipper"
            case .explorer: return "folder.badge.gearshape"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                diskCapacityHero
                tabPicker

                switch activeTab {
                case .categories:
                    categoriesSection
                case .largeFiles:
                    largeFilesSection
                case .explorer:
                    folderExplorerSection
                }
            }
            .padding(32)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .onAppear {
            analyzer.refreshVolumeInfo()
            if analyzer.categories.isEmpty {
                analyzer.startCategoryAnalysis()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accent)
                    Text("Space Lens & Storage")
                        .font(style.isRetro ? style.titleFont : .system(size: 28, weight: .bold))
                }
                Text("Instant visual breakdown of your Mac's storage, large files, and heaviest folders.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ThemeButton(
                title: "Analyze Again",
                systemImage: "arrow.clockwise",
                isEnabled: !analyzer.isAnalyzing,
                help: "Recalculate volume capacity and categorize space"
            ) {
                analyzer.refreshVolumeInfo()
                analyzer.startCategoryAnalysis()
            }
        }
    }

    // MARK: - Disk Hero Bar

    private var diskCapacityHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macintosh HD")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(humanSize(analyzer.usedDiskBytes)) used of \(humanSize(analyzer.totalDiskBytes))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(humanSize(analyzer.freeDiskBytes)) Free")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }

            // Visual Segmented Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 16)

                    HStack(spacing: 2) {
                        let usedWidth = geo.size.width * CGFloat(analyzer.usedFraction)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [style.accent, style.accent.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, usedWidth), height: 16)
                    }
                }
            }
            .frame(height: 16)

            HStack {
                Label("Used (\(Int(analyzer.usedFraction * 100))%)", systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(style.accent)
                Spacer()
                Label("Available (\(Int((1 - analyzer.usedFraction) * 100))%)", systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Tab Switcher

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                let isSelected = activeTab == tab
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isSelected ? style.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(isSelected ? style.accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage by Category")
                .font(.system(size: 16, weight: .semibold))

            if analyzer.isAnalyzing && analyzer.categories.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Measuring storage categories…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(analyzer.categories) { cat in
                        categoryCard(cat)
                    }
                }
            }
        }
    }

    private func categoryCard(_ cat: StorageCategory) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(catColor(cat.colorName).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: cat.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(catColor(cat.colorName))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(cat.name)
                    .font(.system(size: 14, weight: .bold))
                Text(cat.humanSize)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                quickJumpToCategory(cat.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    private func catColor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "green": return .green
        default: return .gray
        }
    }

    private func quickJumpToCategory(_ id: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        activeTab = .explorer
        switch id {
        case "downloads":
            analyzer.loadFolder(path: home.appendingPathComponent("Downloads").path)
        case "dev":
            analyzer.loadFolder(path: home.appendingPathComponent("Library/Caches").path)
        case "media":
            analyzer.loadFolder(path: home.appendingPathComponent("Movies").path)
        case "apps":
            analyzer.loadFolder(path: "/Applications")
        default:
            analyzer.loadFolder(path: home.path)
        }
    }

    // MARK: - Large Files Section

    private var largeFilesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Large & Forgotten Files")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Files over 200 MB in your user folders that may be ready for archival or removal.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(analyzer.largeFiles.count) items found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if analyzer.largeFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("No excessively large loose files detected.")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 1) {
                    ForEach(analyzer.largeFiles) { item in
                        storageItemRow(item)
                    }
                }
                .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
            }
        }
    }

    // MARK: - Folder Explorer Section

    private var folderExplorerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Navigation Breadcrumbs & Controls
            HStack(spacing: 8) {
                ThemeButton(
                    title: "Back",
                    systemImage: "chevron.left",
                    isEnabled: !analyzer.navigationHistory.isEmpty
                ) {
                    analyzer.goBack()
                }

                ThemeButton(
                    title: "Forward",
                    systemImage: "chevron.right",
                    isEnabled: !analyzer.forwardHistory.isEmpty
                ) {
                    analyzer.goForward()
                }

                ThemeButton(
                    title: "Up",
                    systemImage: "arrow.up",
                    isEnabled: analyzer.currentFolderPath != "/"
                ) {
                    analyzer.goUp()
                }

                Text(analyzer.currentFolderPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)

                Spacer()

                ThemeButton(
                    title: "Finder",
                    systemImage: "macwindow"
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: analyzer.currentFolderPath)])
                }
            }

            // Quick Location Chips
            HStack(spacing: 8) {
                locationChip("Home", path: FileManager.default.homeDirectoryForCurrentUser.path)
                locationChip("Downloads", path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
                locationChip("Applications", path: "/Applications")
                locationChip("Caches", path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches").path)
                locationChip("C3PO", path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("C3PO").path)
            }

            // Items List
            if analyzer.currentFolderItems.isEmpty {
                Text("Folder is empty.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                VStack(spacing: 1) {
                    ForEach(analyzer.currentFolderItems) { item in
                        storageItemRow(item)
                    }
                }
                .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
            }
        }
    }

    private func locationChip(_ title: String, path: String) -> some View {
        Button {
            analyzer.loadFolder(path: path)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(analyzer.currentFolderPath == path ? style.accent.opacity(0.12) : Color.secondary.opacity(0.1), in: Capsule())
                .foregroundStyle(analyzer.currentFolderPath == path ? style.accent : .primary)
        }
        .buttonStyle(.plain)
    }

    private func storageItemRow(_ item: StorageItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.name))
                .font(.system(size: 16))
                .foregroundStyle(item.isDirectory ? style.accent : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.kind)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.size > 0 {
                Text(item.humanSize)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                if item.isDirectory {
                    Button {
                        analyzer.navigateInto(item)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(style.accent)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("Open folder")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory {
                analyzer.navigateInto(item)
            }
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ["dmg", "iso", "zip", "tar", "gz", "pkg"].contains(ext) { return "doc.zipper" }
        if ["mp4", "mkv", "mov"].contains(ext) { return "film" }
        if ["mp3", "m4a", "flac"].contains(ext) { return "music.note" }
        if ["pdf", "doc", "docx", "txt", "md"].contains(ext) { return "doc.text" }
        return "doc"
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
