import SwiftUI
import AppKit

/// The starting point keeps measurements separate from actions. Every number
/// comes from the filesystem or a completed scan, and every tile opens a tool.
struct OverviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @ObservedObject private var vitals = SystemVitals.shared
    @State private var mascotHovered = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroBanner

                if let zombie = vitals.snapshot.zombieCandidates.first {
                    zombieAlertBanner(zombie)
                }

                if let inhibitor = vitals.snapshot.sleepInhibitor {
                    sleepInhibitorBanner(inhibitor)
                }

                OverviewStorageCard(scan: { appState.startScan() }, browse: { appState.showDiskBrowser = true })

                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily Maintenance").font(.system(size: 17, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        OverviewActionCard(title: "Clean Up", icon: "sparkles", color: style.accent,
                                           detail: "Review caches, AI model files, installers, and app data.", actionLabel: "Clean files") {
                            appState.showClean = true
                        }
                        OverviewActionCard(title: "Update Apps", icon: "arrow.triangle.2.circlepath", color: style.accent,
                                           detail: "3 simple channels: Mac Apps, Homebrew, and Unknown origins.", actionLabel: "Check updates") {
                            appState.showUpdateList = true
                        }
                        OverviewActionCard(title: "App Uninstaller", icon: "xmark.app", color: style.accent,
                                           detail: "Cleanly remove apps and their hidden support files.", actionLabel: "Uninstall apps") {
                            appState.showUninstaller = true
                        }
                        OverviewActionCard(title: "Cooling & Fans", icon: "fan.fill", color: style.accent,
                                           detail: "Real-time temperature sensors and fan speed controls.", actionLabel: "Control fans") {
                            appState.showFanControl = true
                        }
                        OverviewActionCard(title: "Battery Health", icon: "battery.100.bolt", color: style.accent,
                                           detail: "Hardware wear, cycle count, and sleep drain inhibitors.", actionLabel: "Manage power") {
                            appState.showBatteryHealth = true
                        }
                    }
                }

                OverviewActivity(model: appState.cleaner) { appState.showClean = true }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Studios & Utilities").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("MediaDock 9, Bookbind, Space Lens, and Tools").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        HStack(spacing: 14) {
                            utility("MediaDock 9", detail: "YouTube, Spotify & Apple Music", icon: "play.rectangle.fill") { appState.showMediaDock = true }
                            utility("Bookbind", detail: "Audiobook creator & tagger", icon: "book.closed.fill") { appState.showBookbind = true }
                            utility("DNS Switcher", detail: "Fast DNS & 403 bypass", icon: "globe.badge.chevron.backward") { appState.showDNSSwitcher = true }
                        }
                        HStack(spacing: 14) {
                            utility("Space Lens", detail: "Visual category disk map", icon: "internaldrive") { appState.showDiskBrowser = true }
                            utility("Local Models", detail: "Manage MLX Apple Silicon models", icon: "brain") { appState.showLocalModels = true }
                            utility("VPN Tunnels", detail: "Installed & active tunnels", icon: "lock.shield") { appState.showVPNTunnels = true }
                        }
                        HStack(spacing: 14) {
                            utility("Terminal Health", detail: "Check shell installations", icon: "terminal") { appState.showSetupCheck = true }
                            utility("Battery Health", detail: "Cycles, health & wear", icon: "battery.100.bolt") { appState.showBatteryHealth = true }
                            utility("App Doctor", detail: "Fix Gatekeeper & damaged apps", icon: "bandage.fill") { appState.showAppRepair = true }
                        }
                    }
                }

                if let results = appState.scanResults {
                    Button {
                        appState.showOverview = false
                        appState.flowStep = .review
                    } label: {
                        HStack {
                            Label("Return to scan results", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Text("\(results.foundItems.count) items · \(results.summary.totalSize.sizeDescription)")
                            Image(systemName: "arrow.right")
                        }.font(.system(size: 13)).padding(14)
                    }.buttonStyle(.plain)
                        .background(style.groupingBackground, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background { HousekeepingBackdrop(style: style) }
    }

    private var heroBanner: some View {
        HStack(spacing: 18) {
            if let mascotImage = HousekeeperMascot.loadMascot() ?? loadBenignMonsterMascot() {
                Image(nsImage: mascotImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .scaleEffect(mascotHovered ? 1.06 : 1.0)
                    .onHover { mascotHovered = $0 }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: mascotHovered)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(style.accent.opacity(0.12)).frame(width: 56, height: 56)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26))
                        .foregroundStyle(style.accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Housekeeper")
                    .font(style.isRetro ? style.titleFont : .system(size: 26, weight: .bold))
                    .tracking(-0.5)
                Text("Everything is running cool, fast, and clutter-free. Made by Morad.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(Host.current().localizedName ?? "This Mac", systemImage: "desktopcomputer")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(style.border, lineWidth: 1))
    }

    private func zombieAlertBanner(_ process: ProcessLoad) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.red.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Runaway Task Detected: \(process.name)")
                    .font(.system(size: 15, weight: .bold))
                Text("Consuming \(Int(process.cpu * 100))% CPU continuously. It appears trapped in an infinite loop.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                SystemVitals.terminate(pid: process.id, force: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Stop Task Now")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
    }

    private func sleepInhibitorBanner(_ process: ProcessLoad) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Mac Sleep Prevented")
                    .font(.system(size: 15, weight: .bold))
                Text("The '\(process.name)' command is forbidding your Mac from sleeping automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                SystemVitals.terminate(pid: process.id, force: false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                    Text("Allow Sleep")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private func loadBenignMonsterMascot() -> NSImage? {
        let preferred = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/housekeeper_octopus_maid.png")
        if FileManager.default.fileExists(atPath: preferred.path), let img = NSImage(contentsOf: preferred) {
            return img
        }
        let bundlePath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BenignMonster/mascot.png")
        if FileManager.default.fileExists(atPath: bundlePath.path), let img = NSImage(contentsOf: bundlePath) {
            return img
        }
        let devPath = URL(fileURLWithPath: "/Users/Morad/C3PO/Housekeeping/Housekeeping/Resources/BenignMonster/housekeeper_octopus_maid.png")
        if FileManager.default.fileExists(atPath: devPath.path), let img = NSImage(contentsOf: devPath) {
            return img
        }
        let fallback = URL(fileURLWithPath: "/Users/Morad/Desktop/BMP/afaedd61-c32a-4a0b-a308-26727bf2fc0a.png")
        if FileManager.default.fileExists(atPath: fallback.path), let img = NSImage(contentsOf: fallback) {
            return img
        }
        return nil
    }

    private func utility(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(style.accent)
                    .frame(width: 36, height: 36)
                    .background(style.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(16).contentShape(Rectangle())
        }.buttonStyle(HousekeepingPressableStyle(pressedScale: 0.97))
            .housekeepingCard(cornerRadius: 12)
            .hoverHighlight(cornerRadius: 12, hovered: style.accent.opacity(0.04))
            .accessibilityLabel(title)
    }
}

private struct OverviewStorageCard: View {
    let scan: () -> Void
    let browse: () -> Void
    @Environment(\.uiStyle) private var style
    @State private var reading: VolumeReading?

    private struct VolumeReading: Sendable {
        let name: String
        let total: Int64
        let available: Int64
        var used: Int64 { max(0, total - available) }
        var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(reading?.name ?? "Mac storage", systemImage: "internaldrive")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    if let reading {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(reading.available.humanReadable).font(.system(size: style.isRetro ? 36 : 44, weight: style.isRetro ? .regular : .light)).tracking(style.isRetro ? -0.5 : -1.5).monospacedDigit()
                            Text("available").font(.system(size: 15)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Reading storage…").font(.system(size: 28, weight: .semibold))
                    }
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 9) {
                    ThemeButton(title: "Scan My Mac", systemImage: "magnifyingglass", isPrimary: true, action: scan)
                    Button(action: browse) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Browse storage")
                        }
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain).foregroundStyle(style.accent)
                }
            }
            VStack(spacing: 10) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.065))
                        Capsule().fill(LinearGradient(colors: [style.accentShaded, style.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geometry.size.width * (reading?.fraction ?? 0)))
                            .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.16)).frame(height: 1) }
                    }
                }.frame(height: 8)
                HStack {
                    if let reading {
                        Text("\(reading.used.humanReadable) used")
                        Spacer()
                        Text("\(reading.total.humanReadable) total")
                    } else { Text("The next step only reads your files.") }
                }.font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(28)
        .housekeepingCard(cornerRadius: 18, prominent: true)
        .task {
            reading = await Task.detached(priority: .utility) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                guard let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey]),
                      let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil as VolumeReading? }
                return VolumeReading(name: values.volumeName ?? "Mac storage", total: Int64(total), available: Int64(available))
            }.value
        }
    }
}

private struct OverviewActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let detail: String
    let actionLabel: String
    let action: () -> Void
    @Environment(\.uiStyle) private var style
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(color)
                        .frame(width: 44, height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: style.isRetro ? 1 : 13, style: .continuous)
                                .fill(LinearGradient(colors: [color.opacity(0.14), color.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay(RoundedRectangle(cornerRadius: style.isRetro ? 1 : 13, style: .continuous).strokeBorder(color.opacity(0.12), lineWidth: 0.75))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? style.accent : .secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).frame(minHeight: 34, alignment: .top)
                }
                HStack(spacing: 6) {
                    Text(actionLabel)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium))
                        .offset(x: hovering && !reduceMotion && !style.isRetro ? 3 : 0)
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(style.accent)
                    .padding(.top, 5)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .housekeepingCard(cornerRadius: 16, highlighted: hovering)
            .offset(y: hovering && !reduceMotion && !style.isRetro ? -2 : 0)
        }
        .buttonStyle(HousekeepingPressableStyle(pressedScale: 0.98))
        .onHover { hovering = $0 }
        .animation(reduceMotion || style.isRetro ? nil : .easeOut(duration: 0.14), value: hovering)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

private struct OverviewActivity: View {
    @Environment(\.uiStyle) private var style
    @ObservedObject var model: CleanerModel
    let open: () -> Void

    var body: some View {
        if model.phase != .idle {
            Button(action: open) {
                HStack(spacing: 12) {
                    if model.phase == .scanning { ProgressView().controlSize(.small) }
                    else { Image(systemName: "list.bullet.rectangle").foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.phase == .scanning ? "Clean Up is scanning" : "Your Clean Up results")
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.phase == .scanning ? model.progressLine : "\(model.candidates.count) items · \(model.cleanerTotal.sizeDescription)\(model.wasStopped ? " · Partial scan" : "")")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .background(style.rowSelection, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct SidebarNavigationRow: View {
    @Environment(\.uiStyle) private var style
    let title: String
    let icon: String
    let selected: Bool
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? style.accent : .secondary).frame(width: 20)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? style.rowSelection : (hovering ? style.groupingBackground.opacity(0.65) : .clear))
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.035), .clear], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style.accent.opacity(0.13), lineWidth: 0.75))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HousekeepingPressableStyle(pressedScale: 0.97))
        .disabled(!enabled).opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
