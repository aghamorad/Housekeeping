import SwiftUI
import AppKit

struct UninstallActivityView: View {
    let session: UninstallSession
    let done: () -> Void
    let reviewQuarantine: () -> Void
    @Environment(\.uiStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedApps: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                stages
                ThemePanel {
                    VStack(spacing: 20) {
                        UninstallTransferView(session: session)
                            .frame(height: 156)
                            .accessibilityHidden(true)
                        Text(session.headline)
                            .font(.system(size: 26, weight: .bold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        explanation
                        if session.isFinished {
                            HStack(spacing: 30) {
                                metric("Apps removed", value: "\(session.removedApps)")
                                metric("Related items removed", value: "\(session.removedRelated)")
                                metric("In Quarantine", value: session.movedSize.sizeDescription)
                            }
                            .padding(.vertical, 8)
                            Text("Space is freed when you permanently delete these items from Quarantine.")
                                .font(.system(size: 13)).foregroundStyle(style.secondaryText)
                                .multilineTextAlignment(.center)
                        } else {
                            VStack(spacing: 9) {
                                ProgressView(value: Double(session.event.completed), total: Double(max(1, session.total)))
                                    .tint(style.accent)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: session.event.completed)
                                HStack {
                                    Text("\(session.event.completed) of \(session.total) items checked")
                                    Spacer()
                                    Text("\(session.removedCount) moved")
                                }
                                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                                .foregroundStyle(style.secondaryText)
                            }.frame(maxWidth: 480)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(session.isFinished ? "Removal report" : "Apps & related files")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        if session.failedCount > 0 {
                            Text("\(session.failedCount) left in place")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(style.caution)
                        }
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(session.apps) { app in activityRow(app) }
                    }
                }
                if session.isFinished {
                    HStack {
                        ThemeButton(title: "Back to Apps", systemImage: "arrow.left", action: done)
                        Spacer()
                        if session.removedCount > 0 {
                            ThemeButton(title: "Review Quarantine / Restore", systemImage: "archivebox",
                                        isPrimary: true, action: reviewQuarantine)
                        }
                    }
                } else {
                    Label("You can use other Housekeeping tools while removal continues.", systemImage: "info.circle")
                        .font(.system(size: 13)).foregroundStyle(style.secondaryText)
                }
            }
            .padding(32)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(style.text)
        .housekeepingSurface(style)
        .onAppear { expandFailures() }
        .onChange(of: session.failedCount) { _ in expandFailures() }
    }

    private func expandFailures() {
        for app in session.apps where ([app.id] + app.leftovers.map(\.id)).contains(where: { session.outcomes[$0] == false }) {
            expandedApps.insert(app.id)
        }
    }

    private var stages: some View {
        HStack(spacing: 12) {
            stage("Review", number: 1, complete: true, active: false)
            Rectangle().fill(style.border).frame(maxWidth: 60, maxHeight: 2)
            stage("Uninstall", number: 2, complete: session.isFinished && !session.needsAttention, active: !session.isFinished)
            Rectangle().fill(style.border).frame(maxWidth: 60, maxHeight: 2)
            stage("Summary", number: 3, complete: false, active: session.isFinished)
        }.padding(.vertical, 4)
    }

    private func stage(_ title: String, number: Int, complete: Bool, active: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(complete || active ? style.accent : style.groupingBackground)
                if complete { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(active ? .white : style.secondaryText) }
            }.frame(width: 28, height: 28)
            Text(title).font(.system(size: 14, weight: active ? .bold : .medium))
        }
    }

    @ViewBuilder private var explanation: some View {
        if let interruption = session.interruption {
            Text(interruption).font(.system(size: 14)).foregroundStyle(style.negative).textSelection(.enabled)
            Text("Some work may already have completed. Review Quarantine before trying again.")
                .font(.system(size: 14)).foregroundStyle(style.secondaryText)
        } else if session.isFinished {
            Text(session.needsAttention
                 ? "Removed items are recoverable. Expand an app below to see which items were left in place and why."
                 : "The apps and their included related files are now in Quarantine. You can restore them together if you change your mind.")
                .font(.system(size: 15)).multilineTextAlignment(.center)
        } else if session.event.phase == .permission {
            Label("Approve the macOS administrator prompt to continue. Canceling leaves this app and its related files in place.", systemImage: "lock.shield")
                .font(.system(size: 14)).multilineTextAlignment(.center)
        } else if let path = session.event.path {
            VStack(spacing: 5) {
                Text(session.event.phase == .recording ? "Recording the outcome" : "Moving to Quarantine")
                    .font(.system(size: 14, weight: .medium))
                Text(URL(fileURLWithPath: path).homeAbbreviatedPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(style.secondaryText).lineLimit(2).textSelection(.enabled)
            }
        } else {
            Text("Apps move first, followed by the related files you included. Recovery details are saved after every item.")
                .font(.system(size: 14)).multilineTextAlignment(.center)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(title).font(.system(size: 13)).foregroundStyle(style.secondaryText)
        }
    }

    private func activityRow(_ app: InstalledApp) -> some View {
        let paths = [app.id] + app.leftovers.map(\.id)
        let completed = paths.filter { session.outcomes[$0] != nil }.count
        let failed = paths.contains { session.outcomes[$0] == false }
        let active = !session.isFinished && paths.contains(session.event.path ?? "")
        let expanded = expandedApps.contains(app.id)
        return ThemePanel {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        if expanded { expandedApps.remove(app.id) } else { expandedApps.insert(app.id) }
                    }
                } label: {
                    HStack(spacing: 14) {
                        if let icon = session.icons[app.id] {
                            Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                                .opacity(session.outcomes[app.id] == true ? 0.55 : 1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.system(size: 15, weight: .semibold))
                            Text("\(completed) of \(paths.count) items checked · \(app.leftovers.count) related")
                                .font(.system(size: 13)).foregroundStyle(style.secondaryText)
                        }
                        Spacer()
                        if failed {
                            Label("Needs attention", systemImage: "exclamationmark.circle.fill").foregroundStyle(style.caution)
                        } else if completed == paths.count {
                            Label("Removed", systemImage: "checkmark.circle.fill").foregroundStyle(style.positive)
                        } else if active {
                            ProgressView().controlSize(.small)
                            Text(session.event.phase == .permission ? "Permission needed" : "Removing…")
                        } else { Text(session.isFinished ? "Not finished" : "Waiting").foregroundStyle(style.secondaryText) }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .contentShape(Rectangle()).frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(app.name), \(completed) of \(paths.count) items checked. \(expanded ? "Hide" : "Show") details")
                if expanded {
                    Divider()
                    itemRow(path: app.id, name: "Application bundle", size: app.size)
                    ForEach(app.leftovers) { item in
                        itemRow(path: item.id, name: item.name, size: item.size)
                    }
                }
            }.padding(16)
        }
    }

    private func itemRow(path: String, name: String, size: Int64) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.outcomes[path] == true ? "checkmark.circle.fill"
                  : session.outcomes[path] == false ? "exclamationmark.circle.fill" : "circle")
                .foregroundStyle(session.outcomes[path] == true ? style.positive
                                 : session.outcomes[path] == false ? style.caution : style.secondaryText)
                .frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(name).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(size.sizeDescription).font(.system(size: 13)).foregroundStyle(style.secondaryText)
                }
                Text(URL(fileURLWithPath: path).homeAbbreviatedPath)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(style.secondaryText)
                    .textSelection(.enabled)
                if let message = session.messages[path] {
                    Text(message).font(.system(size: 13)).foregroundStyle(style.negative).textSelection(.enabled)
                }
                if session.isFinished && session.outcomes[path] == false {
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                }
            }
        }.padding(.vertical, 5)
    }
}

/// A visible-only transfer animation. It stops when permission is requested,
/// the window loses focus, Reduce Motion is enabled, or removal finishes.
private struct UninstallTransferView: View {
    let session: UninstallSession
    @Environment(\.uiStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var appActive = NSApp.isActive
    @State private var onScreen = false
    @State private var appeared = false

    private var moving: Bool {
        !session.isFinished && (session.event.phase == .moving || session.event.phase == .recording)
    }

    var body: some View {
        let animated = moving && !reduceMotion && appActive && scenePhase == .active && onScreen && appeared
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            let phase = animated ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 : 0.5
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(style.accent.opacity(0.08)).frame(width: 116, height: 116)
                    if let app = session.activeApp, let icon = session.icons[app.id] {
                        Image(nsImage: icon).resizable().frame(width: 76, height: 76)
                            .scaleEffect(session.isFinished ? 0.82 : 1)
                            .opacity(session.isFinished ? 0.55 : 1)
                    }
                }
                ZStack {
                    Rectangle().fill(style.border).frame(height: 2)
                    if !session.isFinished && session.event.phase != .permission {
                        ForEach(0..<3) { index in
                            let position = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                            Image(systemName: "doc.fill")
                                .font(.system(size: 20)).foregroundStyle(style.accent)
                                .offset(x: (position - 0.5) * 130, y: -8 * sin(position * .pi))
                                .opacity(animated ? sin(position * .pi) : 0.5)
                        }
                    }
                }.frame(width: 150)
                ZStack {
                    Circle().stroke(style.border, lineWidth: 5)
                    Circle().trim(from: 0, to: CGFloat(session.event.completed) / CGFloat(max(1, session.total)))
                        .stroke(style.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: session.isFinished ? (session.needsAttention ? "exclamationmark" : "checkmark")
                          : session.event.phase == .permission ? "lock.shield" : "archivebox")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(session.isFinished && session.needsAttention ? style.caution : style.accent)
                        .id(session.isFinished)
                        .transition(.scale.combined(with: .opacity))
                }.frame(width: 108, height: 108)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: session.isFinished)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: session.event.completed)
        .tracksOnScreen($onScreen)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
    }
}
