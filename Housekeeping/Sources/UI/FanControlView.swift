// Housekeeping — Fan & Thermal Control Interface
//
// Clean, spacious hardware monitor and cooling controller for Apple Silicon and Intel Macs.
// Provides live temperature sensors, fan RPM readouts, preset modes, and custom speeds.

import SwiftUI
import AppKit

struct FanControlView: View {
    @ObservedObject var controller: FanController = .shared
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                thermalOverviewGrid
                coolingModeSection
                fansSection
                safetyNotice
            }
            .padding(32)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .onAppear {
            controller.refresh()
            controller.startMonitoring()
        }
        .onDisappear {
            controller.stopMonitoring()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            if let vacuumMascot = HousekeeperMascot.loadVacuuming() {
                Image(nsImage: vacuumMascot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "fan.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accent)
                    Text("Fans & Thermals")
                        .font(style.isRetro ? style.titleFont : .system(size: 28, weight: .bold))
                }
                Text("Monitor hardware temperatures and regulate Mac cooling fan speeds in real time.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                ThemeButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    help: "Query SMC and hardware thermal sensors immediately"
                ) {
                    controller.refresh()
                }
                ThemeButton(
                    title: "Restore Auto",
                    systemImage: "arrow.counterclockwise",
                    isPrimary: controller.activePreset != .systemAuto,
                    help: "Hand fan control back to macOS system thermal management"
                ) {
                    controller.resetToAuto()
                }
            }
        }
    }

    // MARK: - Thermal Overview Grid

    private var thermalOverviewGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hardware Temperatures")
                .font(.system(size: 16, weight: .semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                tempTile(
                    title: "CPU Temperature",
                    temp: controller.cpuTemperature,
                    icon: "cpu",
                    defaultUnit: "°C"
                )
                tempTile(
                    title: "GPU Temperature",
                    temp: controller.gpuTemperature,
                    icon: "display",
                    defaultUnit: "°C"
                )
                tempTile(
                    title: "Battery",
                    temp: controller.batteryTemperature,
                    icon: "battery.100.bolt",
                    defaultUnit: "°C"
                )
                tempTile(
                    title: "System Average",
                    temp: controller.averageTemperature,
                    icon: "thermometer.medium",
                    defaultUnit: "°C"
                )
            }
        }
    }

    private func tempTile(title: String, temp: Double?, icon: String, defaultUnit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tempColor(temp))
                Spacer()
                Text(tempBadgeText(temp))
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tempColor(temp).opacity(0.12), in: Capsule())
                    .foregroundStyle(tempColor(temp))
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if let temp {
                Text("\(Int(temp.rounded())) \(defaultUnit)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            } else {
                Text("Measuring…")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    private func tempColor(_ temp: Double?) -> Color {
        guard let temp else { return .secondary }
        if temp < 55 { return .green }
        if temp < 75 { return .orange }
        return .red
    }

    private func tempBadgeText(_ temp: Double?) -> String {
        guard let temp else { return "ACTIVE" }
        if temp < 55 { return "COOL" }
        if temp < 75 { return "WARM" }
        return "HOT"
    }

    // MARK: - Cooling Mode Presets

    private var coolingModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cooling Profile")
                    .font(.system(size: 16, weight: .semibold))
                Text("Select how aggressively your Mac's fans should cool the hardware.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach(FanPreset.allCases) { preset in
                    presetCard(preset)
                }
            }

            if controller.activePreset == .custom {
                customSliderCard
            }
        }
    }

    private func presetCard(_ preset: FanPreset) -> some View {
        let isSelected = controller.activePreset == preset
        return Button {
            controller.applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: preset.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? style.accent : .secondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(style.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? style.text : style.text.opacity(0.85))
                    Text(preset.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(isSelected ? style.accent.opacity(0.08) : style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? style.accent : style.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var customSliderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Target RPM:")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Int(controller.customTargetRPM)) RPM")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(style.accent)
                Spacer()
                Text("Slide to set desired RPM across all active fans")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            let minBound = controller.fans.map(\.minRPM).min() ?? 1200
            let maxBound = controller.fans.map(\.maxRPM).max() ?? 5000

            Slider(
                value: $controller.customTargetRPM,
                in: minBound...maxBound,
                step: 100
            ) {
                Text("Target RPM")
            } onEditingChanged: { editing in
                if !editing {
                    controller.applyCustomRPM(Int(controller.customTargetRPM))
                }
            }
            .tint(style.accent)

            HStack {
                Text("\(Int(minBound)) RPM (Min)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(maxBound)) RPM (Max)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Fans Detail Section

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Active Fans")
                .font(.system(size: 16, weight: .semibold))

            if !controller.hasFans || controller.fans.isEmpty {
                HStack(spacing: 16) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passive Silent Cooling Architecture")
                            .font(.system(size: 14, weight: .bold))
                        Text("This Mac operates silently without mechanical fans. Thermal sensors monitor component heat above.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
            } else {
                VStack(spacing: 12) {
                    ForEach(controller.fans) { fan in
                        fanRow(fan)
                    }
                }
            }
        }
    }

    private func fanRow(_ fan: FanInfo) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(style.border, lineWidth: 6)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(fan.percentage))
                        .stroke(
                            fan.percentage > 0.8 ? Color.red : (fan.percentage > 0.5 ? Color.orange : style.accent),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                    Image(systemName: "fan.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(style.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(fan.name)
                            .font(.system(size: 15, weight: .bold))
                        Text(fan.isManual ? "MANUAL" : "AUTO")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((fan.isManual ? Color.orange : Color.green).opacity(0.12), in: Capsule())
                            .foregroundStyle(fan.isManual ? Color.orange : Color.green)
                    }
                    Text("Range: \(Int(fan.minRPM)) – \(Int(fan.maxRPM)) RPM")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(fan.currentRPM.rounded())) RPM")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(Int(fan.percentage * 100))% Capacity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressBar(
                fraction: fan.percentage,
                caption: nil,
                detail: nil,
                height: 6
            )
        }
        .padding(18)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Safety Notice

    private var safetyNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 20))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Safety Guard Active")
                    .font(.system(size: 12, weight: .bold))
                Text("Housekeeping always bounds fan speeds within factory hardware limits and automatically returns control to macOS when the application closes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.2), lineWidth: 1))
    }
}
