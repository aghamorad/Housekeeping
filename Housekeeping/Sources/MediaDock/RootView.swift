import AppKit
import SwiftUI

struct RootView: View {
    /// The way out. MediaDock 9 is a sheet inside Housekeeping, and a screen that
    /// fills the window must still carry its own way back — there is no sheet
    /// chrome above it to offer one.
    let onBack: () -> Void

    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 178)
            Rectangle().fill(skin.darkEdge).frame(width: 1)
            VStack(spacing: 0) {
                TitleBar(onBack: onBack)
                Rectangle().fill(skin.darkEdge).frame(height: 1)
                Group {
                    switch model.section {
                    case .download: DownloadView()
                    case .setup: SetupView()
                    case .cookies: CookiesView()
                    case .troubleshooting: TroubleshootingView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(skin.darkEdge).frame(height: 1)
                ActivityConsole()
                    .frame(height: 224)
            }
        }
        .background(skin.desktop)
        .foregroundStyle(skin.ink)
        .sheet(isPresented: $model.showCommandReview) {
            CommandReviewSheet()
                .environmentObject(model)
        }
        .alert("MediaDock 9", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task { model.refreshDependencies() }
    }
}

private struct Sidebar: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // A glyph rather than `applicationIconImage`: this screen runs
                // inside Housekeeping now, and that call would draw the house's
                // icon over a dock that is not it.
                Group {
                    if skin.isRetro {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(skin.ink)
                            .frame(width: 64, height: 64)
                            .background(skin.paper)
                            .overlay(Rectangle().stroke(skin.darkEdge, lineWidth: 1))
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(HousekeepingInk.redLifted)
                            .frame(width: 56, height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(HousekeepingInk.red.opacity(0.20))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(skin.darkEdge, lineWidth: 1)
                            )
                    }
                }
                Text("MEDIADOCK 9")
                    .font(skin.font(13, weight: .black))
                    .tracking(0.8)
            }
            .padding(.top, 18)
            .padding(.bottom, 20)

            ForEach(AppSection.allCases) { section in
                Button {
                    model.section = section
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.symbol)
                            .frame(width: 15)
                        Text(section.rawValue)
                        Spacer()
                        if model.section == section {
                            Rectangle().fill(skin.ink).frame(width: 5, height: 5)
                        }
                    }
                    .font(skin.font(12, weight: model.section == section ? .bold : .regular))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .background(model.section == section ? skin.selection : Color.clear)
                }
                .buttonStyle(.plain)
                .foregroundStyle(skin.ink)
                Rectangle().fill(skin.midEdge.opacity(0.55)).frame(height: 1)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    StatusLight(color: model.runner.isRunning ? skin.cyan : skin.green)
                    Text(model.runner.isRunning ? "WORKING" : "READY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                Text("Commands stay visible.\nNothing installs silently.")
                    .font(skin.font(10))
                    .foregroundStyle(skin.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(skin.chrome)
    }
}

private struct TitleBar: View {
    let onBack: () -> Void

    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Housekeeping")
                        .font(skin.font(11, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(skin.chrome)
                .overlay(
                    Rectangle().stroke(skin.midEdge, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(skin.ink)
            .help("Close MediaDock 9 and go back to Housekeeping.")
            .accessibilityLabel("Back to Housekeeping")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.section.rawValue)
                    .font(skin.font(16, weight: .bold))
                Text(subtitle)
                    .font(skin.font(10))
                    .foregroundStyle(skin.ink.opacity(0.66))
            }
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("CHECKING TOOLS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(skin.paper)
    }

    private var subtitle: String {
        switch model.section {
        case .download: return "One link in; a visible command out."
        case .setup: return "Detect, install, and update the tools MediaDock orchestrates."
        case .cookies: return "Account access stays in your browser or in a file you choose."
        case .troubleshooting: return "Start with versions, then isolate account and network failures."
        }
    }
}

private struct ActivityConsole: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatusLight(color: lightColor)
                Text(model.runner.currentItem)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                if model.runner.isRunning {
                    Button("Stop") { model.runner.stop() }
                        .buttonStyle(MediaDockButtonStyle())
                }
                Button("Copy command") { model.copy(model.runner.activeCommand) }
                    .buttonStyle(MediaDockButtonStyle())
                Button("Export log") { model.exportLog() }
                    .buttonStyle(MediaDockButtonStyle())
                Button("Clear") { model.runner.clear() }
                    .buttonStyle(MediaDockButtonStyle())
                    .disabled(model.runner.isRunning)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(skin.chrome)

            if let progress = model.runner.progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(skin.field)
                        Rectangle().fill(skin.cyan).frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 4)
            } else {
                Rectangle().fill(skin.midEdge).frame(height: 1)
            }

            LogScroller(entries: model.runner.entries)
        }
        .background(skin.console)
    }

    private var lightColor: Color {
        if model.runner.isRunning { return skin.cyan }
        if let code = model.runner.lastExitCode, code != 0 { return skin.red }
        return skin.green
    }
}

private struct LogScroller: View {
    @Environment(\.mediaDockSkin) private var skin
    let entries: [LogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if entries.isEmpty {
                        Text("Activity log is empty. Commands and tool output will appear here.")
                            .foregroundStyle(skin.ink.opacity(0.5))
                    }
                    ForEach(entries) { entry in
                        Text(entry.text)
                            .foregroundStyle(color(for: entry.kind))
                            .textSelection(.enabled)
                            .id(entry.id)
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .onChange(of: entries.count) { _ in
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: LogKind) -> Color {
        switch kind {
        case .command: return skin.cyan
        case .success: return skin.green
        case .error: return skin.red
        case .info: return skin.amber
        case .output: return skin.ink.opacity(0.86)
        }
    }
}

private struct CommandReviewSheet: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.reviewTitle)
                .font(skin.font(18, weight: .bold))
            Text("These commands can install or update software. Nothing runs until you confirm below.")
                .font(skin.font(12))

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.pendingCommands) { command in
                        RetroPanel(title: command.name) {
                            Text(command.displayCommand)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .insetBorder()
                            Text(command.explanation)
                                .font(skin.font(11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    model.pendingCommands = []
                    model.showCommandReview = false
                }
                .buttonStyle(MediaDockButtonStyle())
                Spacer()
                Button("Run shown commands") { model.runReviewedCommands() }
                    .buttonStyle(MediaDockButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 680, height: 520)
        .background(skin.paper)
    }
}
