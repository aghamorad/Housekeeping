// Housekeeping — Browsing the measured disk
//
// The screen. One measurement happens at the top, everything after it is
// navigation, and navigation is free in every direction. There is a Back button
// and a keyboard shortcut for it because the whole point of measuring once is
// that going back should cost nothing and should therefore be offered as plainly
// as going in.

import AppKit
import SwiftUI

struct DiskBrowserView: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DiskBrowserModel()

    @State private var rootChoice: DiskBrowserModel.RootChoice = .home
    @State private var showLimits = false
    @State private var showBiggest = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            breadcrumbBar
            Divider()
            body_
            Divider()
            footer
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(style.windowBackground)
        .background(keyboardShortcuts)
    }

    /// Hidden controls that exist only to carry shortcuts. Command-[ is Back and
    /// Command-Up is Up, which is what Finder uses, so the two keys a reader
    /// already reaches for do what they already expect.
    private var keyboardShortcuts: some View {
        Group {
            Button("Back") { model.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Up") { model.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Measure") { scan(rootChoice.url) }
                .keyboardShortcut("r", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browsing the disk")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)
                Text(model.measurementDescription ?? "Measure once, then move around freely — in and back out again.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }

            Spacer()

            if model.isScanning {
                ThemeButton(title: "Stop", systemImage: "stop.circle", help: "Stop measuring and keep what has been measured so far.") {
                    model.stopScan()
                }
            } else {
                Picker("", selection: $rootChoice) {
                    ForEach(DiskBrowserModel.RootChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                .help("Which part of the disk to measure. The measurement is taken once and everything after it is navigation.")

                ThemeButton(title: "Choose…", help: "Measure a folder of your own choosing.") {
                    chooseFolder()
                }

                ThemeButton(
                    title: model.snapshot == nil ? "Measure" : "Measure Again",
                    systemImage: "gauge.with.dots.needle.bottom.50percent",
                    isPrimary: true,
                    help: "Read the disk once, from here down, and hold the result so that moving between folders costs nothing."
                ) {
                    scan(rootChoice.url)
                }
            }

            if model.snapshot != nil, !model.isScanning {
                ThemeButton(title: "Forget", help: "Throw the held measurement away. It can be taken again at any time, so nothing is lost by this.") {
                    model.forgetSnapshot()
                }
            }

            ThemeButton(title: "Done", help: "Close the disk browser.") {
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Where you are, and the way back

    private var breadcrumbBar: some View {
        HStack(spacing: 8) {
            ThemeButton(
                title: "Back",
                systemImage: "chevron.backward",
                isEnabled: model.canGoBack,
                help: "Go back to the folder you were looking at before this one (⌘[)."
            ) {
                model.goBack()
            }

            ThemeButton(
                title: "Up",
                systemImage: "arrow.up",
                isEnabled: model.canGoUp,
                help: "Go to the folder that contains this one (⌘↑)."
            ) {
                model.goUp()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, step in
                        if index > 0 {
                            Text("▸")
                                .font(style.smallFont)
                                .foregroundStyle(style.secondaryText)
                        }
                        Button {
                            model.open(step.path)
                        } label: {
                            Text(step.name)
                                .font(style.bodyFont)
                                .foregroundStyle(step.path == model.currentPath ? style.text : style.accent)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help(step.path)
                    }
                }
            }

            Spacer(minLength: 8)

            if let node = model.currentNode {
                ThemeButton(title: "Show in Finder", help: "Open this folder in the Finder, to do something about what you have found here.") {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - The list

    @ViewBuilder
    private var body_: some View {
        if model.isScanning {
            measuring
        } else if model.rootNode == nil {
            emptyState
        } else {
            listing
        }
    }

    private var measuring: some View {
        VStack(spacing: 14) {
            Spacer()
            if let progress = model.progress {
                ProgressView()
                Text("\(progress.filesScanned.formatted()) files so far · \(progress.bytesScanned.humanReadable)")
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                Text(progress.currentFolderName)
                    .font(style.pathFont)
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
                Text("Reading for \(progress.elapsedDescription). Folders are measured once, here, so that opening and closing them afterwards is instant.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            } else {
                ProgressView()
                Text("Starting…")
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Nothing measured yet")
                .font(style.titleFont)
                .foregroundStyle(style.text)
            Text("Press Measure and Housekeeping will read the disk from the top down, once. Everything after that — opening a folder, coming back out, going up — is answered from what it already read.")
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listing: some View {
        VStack(spacing: 0) {
            if showBiggest { biggestPanel }

            ScrollView {
                LazyVStack(spacing: 0) {
                    let children = model.visibleChildren
                    if children.isEmpty {
                        nothingButFilesHere
                    }
                    ForEach(children) { node in
                        row(node)
                        Divider().opacity(0.35)
                    }
                    if let node = model.currentNode, node.hiddenChildCount > 0 {
                        hiddenRow(node)
                    }
                }
            }
        }
    }

    private func row(_ node: DiskNode) -> some View {
        let share = model.shareOfParent(node)
        return Button {
            model.open(node.path)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(node.isUnmeasured ? style.secondaryText : style.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(node.displayName)
                            .font(style.bodyFont)
                            .foregroundStyle(style.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if node.isPartial {
                            Text("at least")
                                .font(style.smallFont)
                                .foregroundStyle(style.caution)
                                .help("Something in here could not be read, so this is a floor and the real figure is larger.")
                        }
                    }
                    Text(node.url.homeAbbreviatedPath)
                        .font(style.pathFont)
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                proportionBar(share)

                Text(node.size.sizeDescription)
                    .font(style.labelFont)
                    .monospacedDigit()
                    .foregroundStyle(style.text)
                    .frame(width: 86, alignment: .trailing)

                Text(share > 0 ? "\(Int((share * 100).rounded()))%" : "—")
                    .font(style.smallFont)
                    .monospacedDigit()
                    .foregroundStyle(style.secondaryText)
                    .frame(width: 44, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(node.path)\n\(model.summary(for: node))")
    }

    /// A folder's own contents, minus the subfolders big enough to have a row of
    /// their own. Without this line the sizes above it would not add up to the
    /// folder's size, and the arithmetic on screen would look broken when it is
    /// only summarised.
    private func hiddenRow(_ node: DiskNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13))
                .foregroundStyle(style.secondaryText)
                .frame(width: 18)
            Text("\(node.hiddenChildCount.formatted()) smaller folders, each under \(node.size > 0 ? (node.hiddenSize / Int64(max(node.hiddenChildCount, 1))).humanReadable : "the reporting floor")")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(node.hiddenSize.sizeDescription)
                .font(style.labelFont)
                .monospacedDigit()
                .foregroundStyle(style.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var nothingButFilesHere: some View {
        VStack(spacing: 6) {
            Text("Nothing to open inside this folder")
                .font(style.bodyFont)
                .foregroundStyle(style.text)
            Text("Whatever it holds is files, or folders too small to list separately. Press Back to return to where you came from, or Up for the folder above.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func proportionBar(_ fraction: Double) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(style.border.opacity(0.35))
            RoundedRectangle(cornerRadius: 2)
                .fill(style.accent.opacity(0.75))
                .frame(width: max(2, 90 * fraction))
        }
        .frame(width: 90, height: 6)
        .help("This folder's share of the one that contains it.")
    }

    // MARK: - The biggest folders anywhere

    private var biggestPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The largest folders anywhere below the measurement")
                .font(style.labelFont)
                .foregroundStyle(style.text)
            ForEach(model.biggestFolders()) { node in
                HStack(spacing: 10) {
                    Text(node.url.homeAbbreviatedPath)
                        .font(style.pathFont)
                        .foregroundStyle(style.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 10)
                    Text(node.size.sizeDescription)
                        .font(style.labelFont)
                        .monospacedDigit()
                        .foregroundStyle(style.secondaryText)
                    Button("Go") { model.open(node.path) }
                        .buttonStyle(.plain)
                        .font(style.smallFont)
                        .foregroundStyle(style.accent)
                        .help("Open this folder in the browser.")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.groupingBackground)
    }

    // MARK: - What is on screen, in words

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let node = model.currentNode {
                    Text(node.displayName)
                        .font(style.labelFont)
                        .foregroundStyle(style.text)
                    Text(node.size.sizeDescription)
                        .font(style.labelFont)
                        .monospacedDigit()
                        .foregroundStyle(style.text)
                    Text(model.summary(for: node))
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                }

                Spacer()

                ThemeButton(title: showBiggest ? "Hide the biggest folders" : "Where did it all go?", help: "List the largest folders anywhere below the measurement, without having to click into anything.") {
                    showBiggest.toggle()
                }

                if !model.limits.isEmpty {
                    ThemeButton(title: "What was left out", help: "The folders this measurement deliberately did not count, and why.") {
                        showLimits.toggle()
                    }
                }
            }

            if let note = model.note {
                Text(note)
                    .font(style.smallFont)
                    .foregroundStyle(style.caution)
            }

            if showLimits {
                ForEach(model.limits, id: \.self) { limit in
                    Text("• \(limit)")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Doing it

    private func scan(_ url: URL) {
        model.scan(root: url)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Choose the folder to measure from. Everything below it is measured; nothing above it is read."
        panel.prompt = "Measure"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url)
    }
}
