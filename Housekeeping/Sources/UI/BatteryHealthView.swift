// Housekeeping — Battery Health & Power Management View
//
// Native telemetry dashboard displaying Apple Silicon & Intel battery hardware health,
// cycle degradation, power delivery wattage, and live sleep inhibitor analysis.

import SwiftUI
import AppKit

struct BatteryHealthView: View {
    @Environment(\.uiStyle) private var style
    @EnvironmentObject private var appState: AppState
    @StateObject private var engine = BatteryHealthEngine.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                headerBar

                if !engine.telemetry.hasBattery {
                    noBatteryCard
                } else {
                    heroMetricsGrid
                    hardwareDetailsShelf
                    sleepInhibitorsSection
                    batteryCareGuideSection
                }
            }
            .padding(24)
            .frame(maxWidth: 960)
        }
        .background { HousekeepingBackdrop(style: style) }
        .onAppear {
            engine.startAutoRefresh(interval: 5.0)
        }
        .onDisappear {
            engine.stopAutoRefresh()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "battery.100.bolt")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accent)
                    Text("Battery Health & Power")
                        .font(.system(size: 22, weight: .bold))
                }
                Text("Live hardware telemetry, cycle count, degradation, and sleep inhibitor drain analysis.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                ThemeButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    help: "Query IOKit and pmset registers immediately"
                ) {
                    engine.refresh()
                }

                ThemeButton(
                    title: "macOS Settings ↗",
                    systemImage: "gearshape",
                    help: "Open Apple System Settings for Battery & Low Power Mode"
                ) {
                    engine.openSystemBatterySettings()
                }

                ThemeButton(
                    title: "Ask Housekeeper",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    isPrimary: true,
                    help: "Discuss battery condition and battery life tips with the local AI Housekeeper"
                ) {
                    appState.housekeeperTopic = .batteryHealth(engine.telemetry)
                    appState.showHousekeeper = true
                }
            }
        }
    }

    // MARK: - Desktop Mac Fallback

    private var noBatteryCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 36))
                .foregroundStyle(style.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Desktop Mac — Continuous AC Power")
                    .font(.system(size: 15, weight: .bold))
                Text("This Mac does not have an internal battery. It operates on continuous AC mains power with no battery degradation.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Hero Metrics Grid (3 Cards)

    private var heroMetricsGrid: some View {
        let t = engine.telemetry

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
            // Card 1: Live Charge & State
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("CURRENT CHARGE", systemImage: t.isCharging ? "bolt.fill" : (t.isPluggedIn ? "powerplug.fill" : "battery.75"))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(style.accent)
                    Spacer()
                    if t.isOptimizedHold {
                        Text("OPTIMIZED HOLD")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.blue)
                    } else if t.isCharging {
                        Text("CHARGING")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.green)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(t.chargePercent)%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(t.isPluggedIn ? (t.isCharging ? "charging on AC" : "on AC power (bypass)") : "discharging on battery")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(style.border)
                            .frame(height: 8)
                        Capsule()
                            .fill(t.chargePercent > 20 ? Color.green : Color.orange)
                            .frame(width: geo.size.width * CGFloat(max(0, min(100, t.chargePercent))) / 100.0, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Voltage: \(String(format: "%.2f V", t.voltageVolts))")
                    Spacer()
                    Text(t.amperageMa == 0 ? "0 mA (Bypass)" : "\(t.amperageMa) mA")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))

            // Card 2: Maximum Health & Capacity
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("BATTERY HEALTH", systemImage: "heart.fill")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.condition.color)
                    Spacer()
                    Text(t.condition.title.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(t.condition.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(t.condition.color)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(t.healthPercent)%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(t.condition.color)
                    Text("of original capacity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Capacity comparison bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(style.border)
                            .frame(height: 8)
                        Capsule()
                            .fill(t.condition.color)
                            .frame(width: geo.size.width * CGFloat(max(0, min(100, t.healthPercent))) / 100.0, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Max: \(t.fullChargeCapacityMah) mAh")
                    Spacer()
                    Text("Factory: \(t.designCapacityMah) mAh")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))

            // Card 3: Cycle Count & Lifespan
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("CYCLE LIFESPAN", systemImage: "repeat.circle.fill")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(style.accent)
                    Spacer()
                    Text("\(t.cyclesRemaining) CYCLES LEFT")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(style.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(style.accent)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(t.cycleCount)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("/ \(t.designCycleCount) rated cycles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Cycle Life Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(style.border)
                            .frame(height: 8)
                        Capsule()
                            .fill(t.cycleFraction > 0.8 ? Color.red : (t.cycleFraction > 0.6 ? Color.orange : style.accent))
                            .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, t.cycleFraction))), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(String(format: "%.1f%% consumed", t.cycleFraction * 100.0))
                    Spacer()
                    Text("Apple 1,000 rating")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
        }
    }

    // MARK: - Hardware Telemetry Shelf

    private var hardwareDetailsShelf: some View {
        let t = engine.telemetry

        return VStack(alignment: .leading, spacing: 14) {
            Text("Hardware Registers & Power Delivery")
                .font(.system(size: 15, weight: .bold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                specTile(
                    title: "AC Charger",
                    value: t.adapterWatts != nil ? "\(t.adapterWatts!)W USB-PD" : "None (Battery)",
                    subvalue: t.adapterDescription ?? (t.isPluggedIn ? "Connected" : "Disconnected"),
                    icon: "bolt.fill"
                )
                specTile(
                    title: "Adapter Voltage & Current",
                    value: t.adapterVoltageMv != nil ? String(format: "%.1f V @ %.2f A", Double(t.adapterVoltageMv!) / 1000.0, Double(t.adapterCurrentMa ?? 0) / 1000.0) : "N/A",
                    subvalue: t.isOptimizedHold ? "Holding at 80% limit" : "Direct supply",
                    icon: "waveform.path.ecg"
                )
                specTile(
                    title: "Battery Cell Temperature",
                    value: t.temperatureCelsius != nil ? String(format: "%.1f °C", t.temperatureCelsius!) : "Measuring…",
                    subvalue: (t.temperatureCelsius ?? 30.0) < 35.0 ? "Cool & Optimal" : "Warm",
                    icon: "thermometer.medium"
                )
                specTile(
                    title: "Battery Controller IC",
                    value: t.deviceName ?? "Apple Smart Battery",
                    subvalue: "Serial: \(t.serialNumber ?? "N/A")",
                    icon: "memorychip"
                )
                specTile(
                    title: "Capacity Loss",
                    value: "-\(t.capacityLossMah) mAh",
                    subvalue: String(format: "%.1f%% normal chemical wear", Double(t.capacityLossMah) / Double(max(1, t.designCapacityMah)) * 100.0),
                    icon: "chart.line.downtrend.xyaxis"
                )
                specTile(
                    title: "Low Power Mode",
                    value: t.lowPowerMode ? "Enabled" : "Disabled",
                    subvalue: t.lowPowerMode ? "Throttles background work" : "Full performance active",
                    icon: "leaf.fill"
                )
            }
        }
        .padding(20)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    private func specTile(title: String, value: String, subvalue: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(style.accent)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Text(subvalue)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.groupingBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sleep Inhibitors Section

    private var sleepInhibitorsSection: some View {
        let inhibitors = engine.telemetry.sleepInhibitors

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Active Sleep Inhibitors")
                            .font(.system(size: 15, weight: .bold))
                        Text("\(inhibitors.count)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(inhibitors.isEmpty ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(inhibitors.isEmpty ? Color.green : Color.orange)
                    }
                    Text("Processes currently preventing your Mac from entering deep sleep when the display is off or lid is closed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if inhibitors.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.green)
                    Text("No sleep inhibitors active. Your Mac will sleep peacefully when idle.")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(14)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(inhibitors) { item in
                        inhibitorRow(item)
                    }
                }
            }
        }
        .padding(20)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    private func inhibitorRow(_ item: SleepInhibitor) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: item.isSystem ? "gearshape.2.fill" : "app.fill")
                .font(.system(size: 18))
                .foregroundStyle(item.isSystem ? Color.secondary : style.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                    Text("PID \(item.pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if item.isSystem {
                        Text("SYSTEM")
                            .font(.system(size: 8, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(item.humanAssertionType): \"\(item.details)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("Active \(item.timeActive)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            if !item.isSystem {
                Button {
                    engine.terminateInhibitor(pid: item.pid)
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Ask \(item.name) to quit so your Mac can sleep")
            }
        }
        .padding(10)
        .background(style.groupingBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Battery Longevity & Care Guide

    private var batteryCareGuideSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(style.accent)
                Text("Housekeeper's Rules for Battery Longevity")
                    .font(.system(size: 15, weight: .bold))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                guideCard(
                    number: "1",
                    title: "The 80% Limit",
                    body: "Lithium cells age fastest at extreme states of charge. Keeping macOS Optimized Charging active holds the charge around 80% during long desk sessions."
                )
                guideCard(
                    number: "2",
                    title: "Heat Degrades Cells",
                    body: "Elevated temperature oxidizes lithium-ion electrolytes 4x faster than charge cycles. Avoid resting your Mac on soft bedding where intake vents choke."
                )
                guideCard(
                    number: "3",
                    title: "AC Pass-Through",
                    body: "When connected to a 40W+ USB-PD charger, modern MacBooks bypass the battery entirely and draw power directly from mains, preserving cell cycles."
                )
                guideCard(
                    number: "4",
                    title: "Storage Charge",
                    body: "If leaving your MacBook in a drawer or bag for weeks, power it off at roughly 50% charge. Never store a lithium-ion battery completely flat (0%)."
                )
            }
        }
        .padding(20)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    private func guideCard(number: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(style.accent)
                    .frame(width: 18, height: 18)
                    .background(style.accent.opacity(0.15), in: Circle())
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.groupingBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
