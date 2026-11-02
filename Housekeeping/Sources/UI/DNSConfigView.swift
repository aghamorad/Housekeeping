import SwiftUI
import AppKit

struct DNSConfigView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var engine = DNSEngine.shared
    @Environment(\.uiStyle) private var style

    @State private var selectedCategory: DNSCategory = .all
    @State private var showingCustomSheet = false

    // Custom preset inputs
    @State private var customName = ""
    @State private var customPrimary = ""
    @State private var customSecondary = ""
    @State private var customTag = "CUSTOM"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let notice = engine.statusNotice {
                        statusBanner(notice)
                    }

                    activeStatusCard
                    interfaceSelectorCard
                    categoryFilterBar
                    presetsGrid

                    if selectedCategory == .custom || selectedCategory == .all {
                        customDNSCreationCard
                    }

                    educationalNotes
                }
                .padding(28)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background { HousekeepingBackdrop(style: style) }
        .onAppear {
            engine.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ThemeButton(title: "Back", systemImage: "chevron.left",
                        help: "Go back to Housekeeping.") {
                appState.showDNSSwitcher = false
            }

            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(style.accent.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(style.accentLifted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("DNS Easy Switcher")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)
                Text("Switch DNS servers in 1-click · Bypass 403 developer sanctions · Block ads & trackers")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }

            Spacer()

            ThemeButton(title: "Flush DNS Cache", systemImage: "bolt.horizontal.fill",
                        help: "Clears local macOS DNS cache and restarts mDNSResponder.") {
                engine.flushDNSCache()
            }

            ThemeButton(title: "Test Latencies", systemImage: "timer", isPrimary: true,
                        help: "Measures ping round-trip latency to all DNS providers.") {
                engine.testAllLatencies()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Status Notice Banner

    private func statusBanner(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: text.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(text.contains("✓") ? .green : style.accent)
                .font(.system(size: 16))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style.text)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(style.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.accent.opacity(0.28), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Active Status Card

    private var activeStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.green.opacity(0.4), lineWidth: 3))
                    Text("ACTIVE SYSTEM DNS RESOLVER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(style.secondaryText)
                }
                Spacer()

                Button {
                    engine.restoreAutomaticDHCP()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Automatic (DHCP)")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentPresetName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(style.text)

                    HStack(spacing: 8) {
                        if engine.activeSystemDNS.isEmpty {
                            Text("Using router default DNS via DHCP")
                                .font(.system(size: 12))
                                .foregroundStyle(style.secondaryText)
                        } else {
                            Text("Active IP: \(engine.activeSystemDNS.joined(separator: " · "))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(style.secondaryText)
                        }
                    }
                }

                Spacer()

                if let iface = engine.interfaces.first(where: { $0.id == engine.effectiveTargetInterfaceName }) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Target Network Service")
                            .font(.system(size: 11))
                            .foregroundStyle(style.secondaryText)
                        Text(iface.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(style.accentLifted)
                    }
                }
            }
        }
        .padding(20)
        .housekeepingCard(cornerRadius: 14, prominent: true)
    }

    private var currentPresetName: String {
        let all = DNSPreset.builtInPresets + engine.customPresets
        for preset in all {
            if engine.isPresetActive(preset) {
                return preset.name
            }
        }
        if let target = engine.effectiveTargetInterfaceName,
           let iface = engine.interfaces.first(where: { $0.id == target }) {
            if iface.configuredDNS.isEmpty {
                return "Automatic (DHCP · Router Default)"
            } else {
                return "Custom DNS (\(iface.configuredDNS.joined(separator: ", ")))"
            }
        }
        return "Automatic (DHCP)"
    }

    // MARK: - Interface Selector

    private var interfaceSelectorCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 15))
                .foregroundStyle(style.accent)
            Text("Apply DNS To:")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style.secondaryText)

            Picker("", selection: $engine.selectedInterfaceID) {
                Text("Primary Active Interface").tag("primary")
                Divider()
                ForEach(engine.interfaces) { iface in
                    Text(iface.displayTitle).tag(iface.id)
                }
                Divider()
                Text("All Physical Interfaces (Wi-Fi & Ethernet)").tag("all")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)

            Spacer()

            Text("\(engine.interfaces.count) network services detected")
                .font(.system(size: 12))
                .foregroundStyle(style.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DNSCategory.allCases) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 12))
                            Text(cat.rawValue)
                                .font(.system(size: 13, weight: selectedCategory == cat ? .semibold : .regular))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if selectedCategory == cat {
                                Capsule().fill(style.accent)
                            } else {
                                Capsule().fill(style.rowBackground)
                            }
                        }
                        .overlay {
                            if selectedCategory != cat {
                                Capsule().stroke(style.border, lineWidth: 1)
                            }
                        }
                        .foregroundStyle(selectedCategory == cat ? Color.white : style.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Presets Grid

    private var filteredPresets: [DNSPreset] {
        let all = DNSPreset.builtInPresets + engine.customPresets
        switch selectedCategory {
        case .all:
            return all
        case .fast, .adblock, .sanctionBypass, .gaming:
            return all.filter { $0.category == selectedCategory }
        case .custom:
            return engine.customPresets
        }
    }

    private var presetsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
            ForEach(filteredPresets) { preset in
                presetCard(preset)
            }
        }
    }

    private func presetCard(_ preset: DNSPreset) -> some View {
        let isActive = engine.isPresetActive(preset)
        let latency = engine.latencies[preset.id]
        let isPinging = engine.isTestingPing[preset.id] ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(style.text)

                    HStack(spacing: 6) {
                        Text(preset.tag)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tagColor(preset.tag).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(tagColor(preset.tag))

                        Text(preset.category.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(style.secondaryText)
                    }
                }

                Spacer()

                if isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Active")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if preset.isDHCP {
                    Text("Configured by DHCP router")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(style.secondaryText)
                } else {
                    Text("Primary: \(preset.primaryIP)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(style.text)
                    if !preset.secondaryIP.isEmpty {
                        Text("Secondary: \(preset.secondaryIP)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(style.secondaryText)
                    }
                }
            }

            Text(preset.description)
                .font(.system(size: 12))
                .foregroundStyle(style.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)

            Divider()

            HStack {
                // Latency Indicator
                if preset.isDHCP {
                    Text("Local gateway")
                        .font(.system(size: 11))
                        .foregroundStyle(style.secondaryText)
                } else if isPinging {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Pinging…")
                            .font(.system(size: 11))
                            .foregroundStyle(style.secondaryText)
                    }
                } else if let ms = latency {
                    if ms > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(ms < 100 ? Color.green : (ms < 250 ? Color.orange : Color.red))
                                .frame(width: 7, height: 7)
                            Text("\(Int(ms)) ms")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(ms < 100 ? Color.green : (ms < 250 ? Color.orange : Color.red))
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("Timeout")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Button {
                        engine.testLatency(for: preset)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text("Ping")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(style.accent)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Apply button
                if isActive {
                    Text("In Use")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Button {
                        engine.apply(preset: preset)
                    } label: {
                        HStack(spacing: 5) {
                            Text(preset.isDHCP ? "Reset to DHCP" : "Switch DNS")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(style.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                // Delete custom preset button
                if preset.category == .custom {
                    Button {
                        engine.removeCustomPreset(id: preset.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("Delete custom preset")
                }
            }
        }
        .padding(16)
        .housekeepingCard(cornerRadius: 12, highlighted: isActive)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "FASTEST", "DEFAULT": return .green
        case "MALWARE BLOCK", "AD BLOCKING": return .purple
        case "403 BYPASS", "DEV BYPASS", "SANCTION BYPASS": return .orange
        case "GAMING & STEAM", "LOW PING": return .blue
        case "SWISS PRIVACY", "CISCO": return .teal
        default: return style.accent
        }
    }

    // MARK: - Custom DNS Creation

    private var customDNSCreationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Custom DNS Preset", systemImage: "plus.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style.text)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preset Name").font(.system(size: 11)).foregroundStyle(style.secondaryText)
                    TextField("e.g. Work DNS, Local Pi-hole", text: $customName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Primary DNS IP").font(.system(size: 11)).foregroundStyle(style.secondaryText)
                    TextField("1.1.1.1 or 192.168.1.5", text: $customPrimary)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Secondary DNS IP (Optional)").font(.system(size: 11)).foregroundStyle(style.secondaryText)
                    TextField("1.0.0.1", text: $customSecondary)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tag").font(.system(size: 11)).foregroundStyle(style.secondaryText)
                    TextField("CUSTOM", text: $customTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Action").font(.system(size: 11)).foregroundStyle(.clear)
                    Button {
                        engine.addCustomPreset(
                            name: customName,
                            primary: customPrimary,
                            secondary: customSecondary,
                            tag: customTag
                        )
                        customName = ""
                        customPrimary = ""
                        customSecondary = ""
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("Add Preset")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(style.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              customPrimary.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(18)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Educational Notes

    private var educationalNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How DNS Switching Works on macOS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.secondaryText)

            Text("• **Instant Application**: Changes take effect immediately via `/usr/sbin/networksetup -setdnsservers` without requiring system reboot.\n• **Sanction & 403 Bypass**: Presets like Shecan, 403.online, and Electro resolve international CDN IP addresses directly, unlocking developer platforms (Docker Hub, Gradle, PyPI, OpenAI, Anthropic, Adobe, Oracle, Canva) restricted by geo-blocking.\n• **Zero Background Daemons**: Housekeeper modifies macOS native network service properties directly and does not run persistent background proxy daemons or battery-draining VPN taps.\n• **Cache Flushing**: Whenever DNS is switched, Housekeeper automatically flushes the Darwin directory services cache (`dscacheutil -flushcache`) and sends a `-HUP` signal to `mDNSResponder` so open browser tabs resolve the new addresses instantly.")
                .font(.system(size: 12))
                .foregroundStyle(style.secondaryText)
                .lineSpacing(4)
        }
        .padding(18)
        .background(style.rowBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
