// Housekeeping — VPN Tunnels & Interface Watchdog View
//
// Shows how many VPN tunnels and network services are installed and running.
// Displays active BSD utun interfaces, configured system VPN services, and
// running VPN background engines, with 1-click disconnect, delete, and DNS/route reset.

import SwiftUI
import AppKit

@MainActor
final class VPNTunnelsModel: ObservableObject {
    static let shared = VPNTunnelsModel()

    @Published private(set) var services: [VPNTunnelService] = []
    @Published private(set) var interfaces: [VirtualInterface] = []
    @Published private(set) var processes: [RunningVPNProcess] = []
    @Published private(set) var summary: VPNDiagnosticSummary = .empty
    @Published private(set) var isLoading: Bool = false
    @Published var selectedTab: VPNTunnelTab = .services
    @Published var pendingDeleteService: VPNTunnelService? = nil
    @Published var actionNotice: String? = nil

    public enum VPNTunnelTab: String, CaseIterable, Identifiable {
        case services = "Configured VPN Services"
        case interfaces = "Virtual Tunnels (utun)"
        case processes = "Running VPN Engines"
        case startup = "Startup & Background Items"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .services: return "lock.shield.fill"
            case .interfaces: return "network"
            case .processes: return "gearshape.2.fill"
            case .startup: return "power.circle"
            }
        }
    }

    init() {
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            let engine = VPNTunnelEngine.shared
            let (svcs, ifaces, procs, sum) = await engine.scan()

            await MainActor.run {
                self.services = svcs
                self.interfaces = ifaces
                self.processes = procs
                self.summary = sum
                self.isLoading = false
            }
        }
    }

    func disconnect(_ service: VPNTunnelService) {
        Task {
            try? await VPNTunnelEngine.shared.disconnect(service: service)
            actionNotice = "Disconnected \(service.name)"
            refresh()
        }
    }

    func connect(_ service: VPNTunnelService) {
        Task {
            try? await VPNTunnelEngine.shared.connect(service: service)
            actionNotice = "Connecting to \(service.name)…"
            refresh()
        }
    }

    func confirmDelete(_ service: VPNTunnelService) {
        pendingDeleteService = service
    }

    func executeDelete() {
        guard let service = pendingDeleteService else { return }
        Task {
            do {
                try await VPNTunnelEngine.shared.deleteService(service: service)
                actionNotice = "Successfully removed \(service.name) from macOS"
            } catch {
                actionNotice = "Could not delete \(service.name): \(error.localizedDescription)"
            }
            pendingDeleteService = nil
            refresh()
        }
    }

    func stopProcess(_ proc: RunningVPNProcess) {
        Task {
            try? await VPNTunnelEngine.shared.stopProcess(pid: proc.pid)
            actionNotice = "Stopped \(proc.displayName) (PID \(proc.pid))"
            refresh()
        }
    }

    func flushDNSAndReset() {
        Task {
            try? await VPNTunnelEngine.shared.flushDNSAndResetRouting()
            actionNotice = "DNS cache flushed & routing table reset"
            refresh()
        }
    }
}

// MARK: - View

struct VPNTunnelsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: VPNTunnelsModel = .shared
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                kpiBar

                if let notice = model.actionNotice {
                    actionNoticeBanner(notice)
                }

                if model.summary.hasRoutingConflict, let warning = model.summary.conflictWarning {
                    conflictBanner(warning)
                }

                tabBar

                switch model.selectedTab {
                case .services:
                    servicesSection
                case .interfaces:
                    interfacesSection
                case .processes:
                    processesSection
                case .startup:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Startup files and all other background activity now have their own Housekeeping page.")
                            .font(.system(size: 16))
                        Button("Open Background Activity") { appState.showBackgroundActivity = true }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .sheet(item: Binding(
            get: { model.pendingDeleteService.map { DeletionWrapper(service: $0) } },
            set: { _ in model.pendingDeleteService = nil }
        )) { wrapper in
            deleteConfirmationDialog(wrapper.service)
                .housekeepingSurface(style)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(style.accent)
                    Text("VPN Tunnels & Interfaces")
                        .font(style.isRetro ? style.titleFont : .system(size: 28, weight: .bold))
                }
                Text("Inspect configured VPN connections, active utun tunnel devices, and running background engines. Disconnect or delete stale profiles to prevent computer network confusion.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                ThemeButton(
                    title: "Flush DNS & Reset",
                    systemImage: "bolt.shield.fill"
                ) {
                    model.flushDNSAndReset()
                }
                .help("Flushes macOS DNS cache and resets routing table to recover from network stalls")

                ThemeButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    isEnabled: !model.isLoading
                ) {
                    model.refresh()
                }
            }
        }
    }

    // MARK: - KPI Bar

    private var kpiBar: some View {
        HStack(spacing: 14) {
            kpiCard(
                title: "Configured VPNs",
                value: "\(model.summary.totalInstalledServices)",
                detail: "\(model.services.filter { $0.isEnabled }.count) enabled in System Settings",
                icon: "lock.shield",
                color: style.accent
            )

            kpiCard(
                title: "Active Routing Tunnels",
                value: "\(model.summary.totalActiveTunnels)",
                detail: model.summary.activeVPNInterface.map { "\($0) routing default traffic" } ?? "Direct LAN (No VPN routing)",
                icon: "bolt.shield.fill",
                color: model.summary.totalActiveTunnels > 0 ? .green : .secondary
            )

            kpiCard(
                title: "Virtual Devices",
                value: "\(model.summary.totalVirtualInterfaces)",
                detail: "BSD utun / tun interfaces",
                icon: "network",
                color: .blue
            )

            kpiCard(
                title: "Running VPN Engines",
                value: "\(model.summary.totalRunningProcesses)",
                detail: "\(model.processes.map(\.displayName).prefix(2).joined(separator: ", "))",
                icon: "gearshape.2.fill",
                color: model.summary.totalRunningProcesses > 0 ? .orange : .secondary
            )
        }
    }

    private func kpiCard(title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(detail.isEmpty ? "None" : detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Notices

    private func actionNoticeBanner(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(msg)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button {
                model.actionNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
    }

    private func conflictBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Potential Network Conflict")
                    .font(.system(size: 13, weight: .bold))
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.flushDNSAndReset()
            } label: {
                Text("Reset Network Routes")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(VPNTunnelsModel.VPNTunnelTab.allCases) { tab in
                let isSelected = model.selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        if tab != .startup {
                            Text("(\(count(for: tab)))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(isSelected ? style.accent.opacity(0.18) : style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? style.accent : style.border, lineWidth: 1))
                    .foregroundStyle(isSelected ? style.accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func count(for tab: VPNTunnelsModel.VPNTunnelTab) -> Int {
        switch tab {
        case .services: return model.services.count
        case .interfaces: return model.interfaces.count
        case .processes: return model.processes.count
        case .startup: return 0
        }
    }

    // MARK: - Section 1: Configured VPN Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.services.isEmpty {
                emptySection(
                    icon: "lock.shield",
                    title: "No Configured VPN Services",
                    detail: "macOS System Settings currently has no VPN connection profiles saved."
                )
            } else {
                ForEach(model.services) { service in
                    serviceRow(service)
                }
            }
        }
    }

    private func serviceRow(_ service: VPNTunnelService) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(service.status == .connected ? Color.green.opacity(0.15) : style.accent.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: service.status.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(service.status == .connected ? .green : style.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(service.name)
                        .font(.system(size: 14, weight: .bold))
                    badgePill(
                        label: service.displayProtocol,
                        color: .blue
                    )
                    statusPill(service.status)
                }
                HStack(spacing: 10) {
                    Text(service.subtype)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("UUID: \(service.id.prefix(8))…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Row Action buttons
            HStack(spacing: 8) {
                if service.status == .connected {
                    Button {
                        model.disconnect(service)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("Disconnect")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect this active VPN tunnel")
                } else {
                    Button {
                        model.connect(service)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text("Connect")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(style.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Start connection on this VPN profile")
                }

                // Delete Button
                Button {
                    model.confirmDelete(service)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete VPN")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Permanently delete this VPN profile from macOS Network Settings")
            }
        }
        .padding(14)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
        .contextMenu {
            Button {
                HousekeeperTopic.ask(.vpnTunnelService(service))
            } label: {
                Label("Ask the Housekeeper About \(service.name)", systemImage: "sparkles")
            }

            Divider()

            if service.status == .connected {
                Button {
                    model.disconnect(service)
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    model.connect(service)
                } label: {
                    Label("Connect", systemImage: "play.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                model.confirmDelete(service)
            } label: {
                Label("Delete VPN Profile", systemImage: "trash")
            }
        }
    }

    // MARK: - Section 2: Virtual Interfaces (utun)

    private var interfacesSection: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(model.interfaces) { iface in
                interfaceRow(iface)
            }
        }
    }

    private func interfaceRow(_ iface: VirtualInterface) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iface.isDefaultRoute ? Color.green.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: iface.kind.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(iface.isDefaultRoute ? .green : (iface.kind == .appleSystem ? .blue : .secondary))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(iface.name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    if iface.isDefaultRoute {
                        badgePill(label: "Active Default Route (0.0.0.0/0)", color: .green)
                    } else if iface.kind == .appleSystem {
                        badgePill(label: "macOS System (AirDrop / iCloud)", color: .blue)
                    } else {
                        badgePill(label: "Idle Interface", color: .gray)
                    }
                    Text("MTU \(iface.mtu)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    if let ip = iface.ipv4 {
                        Text("IPv4: \(ip)\(iface.destinationIPv4.map { " → \($0)" } ?? "")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else if let ip6 = iface.ipv6 {
                        Text("IPv6: \(ip6)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("No IP assigned")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if iface.isDefaultRoute {
                Text("Routing Traffic")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else if iface.kind == .appleSystem {
                Text("System Protected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(iface.isDefaultRoute ? Color.green.opacity(0.4) : style.border, lineWidth: iface.isDefaultRoute ? 1.5 : 1)
        )
    }

    // MARK: - Section 3: Running Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.processes.isEmpty {
                emptySection(
                    icon: "checkmark.shield.fill",
                    title: "No Background VPN Engines Running",
                    detail: "No active third-party VPN daemons or routing loops are consuming system resources."
                )
            } else {
                ForEach(model.processes) { proc in
                    processRow(proc)
                }
            }
        }
    }

    private func processRow(_ proc: RunningVPNProcess) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(proc.displayName)
                        .font(.system(size: 14, weight: .bold))
                    Text("PID \(proc.pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    if proc.isRoot {
                        badgePill(label: "root daemon", color: .purple)
                    }
                }

                HStack(spacing: 10) {
                    Text(proc.executablePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%% CPU", proc.cpuPercent))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(proc.cpuPercent > 10 ? .orange : .primary)
                Text(String(format: "%.1f MB RAM", proc.memoryMB))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button {
                model.stopProcess(proc)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                    Text("Stop Engine")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Terminate this VPN background process")
        }
        .padding(14)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
        .contextMenu {
            Button {
                let knowledge = ProcessKnowledge.resolve(pid: proc.pid, name: proc.name)
                HousekeeperTopic.ask(.process(ProcessLoad(id: proc.pid, name: proc.name, cpu: proc.cpuPercent / 100.0, memory: UInt64(proc.memoryMB * 1024 * 1024)), totalMemory: ProcessInfo.processInfo.physicalMemory, knowledge: knowledge))
            } label: {
                Label("Ask the Housekeeper About \(proc.displayName)", systemImage: "sparkles")
            }

            Divider()

            Button(role: .destructive) {
                model.stopProcess(proc)
            } label: {
                Label("Stop Engine", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Badges & Helpers

    private func badgePill(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func statusPill(_ status: VPNConnectionStatus) -> some View {
        let color: Color = {
            switch status {
            case .connected: return .green
            case .connecting: return .orange
            case .disconnected: return .secondary
            case .disabled: return .secondary
            case .unknown: return .gray
            }
        }()

        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(status.rawValue)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
        .foregroundStyle(color)
    }

    private func emptySection(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Delete Confirmation Dialog

    private func deleteConfirmationDialog(_ service: VPNTunnelService) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete VPN Service?")
                        .font(.system(size: 18, weight: .bold))
                    Text("Permanently remove this connection profile from macOS.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("You are about to delete:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(style.accent)
                    Text(service.name)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    badgePill(label: service.displayProtocol, color: .blue)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                Text("This will remove '\(service.name)' from macOS System Settings (`networksetup` and `scutil --nc`). It will stop any routing table conflicts or DNS loop stalls caused by this profile.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                ThemeButton(title: "Cancel", systemImage: "xmark") {
                    model.pendingDeleteService = nil
                }
                Spacer()
                ThemeButton(
                    title: "Delete VPN Service",
                    systemImage: "trash.fill",
                    isPrimary: true
                ) {
                    model.executeDelete()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 280)
    }
}

private struct DeletionWrapper: Identifiable {
    var id: String { service.id }
    let service: VPNTunnelService
}
