// Housekeeping — the panel behind the octopus
//
// This is the app's own answer to a live menu bar panel, so the words are the
// app's: rooms rather than devices, hands rather than processes, a door rather than
// a menu. The house reads Tidy, Busy or Crowded, and the octopus in the corner
// works harder as the processor does, so her body is a reading too.
//
// Everything is redrawn from one published snapshot. Nothing here starts work of
// its own except the twelve-frames-a-second clock that makes her breathe.

import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var vitals: SystemVitals
    @ObservedObject var loginItem: LoginItem

    let onOpen: () -> Void
    let onScan: () -> Void
    let onAsk: () -> Void
    let onExtras: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void

    private var snapshot: VitalsSnapshot { vitals.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hairline
            chips
            rooms
            busiest
            hairline
            door
            credit
        }
        .frame(width: 352)
        .background(HousekeepingInk.surface)
    }

    // MARK: - Who is on duty

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
                OctopusMark(
                    time: context.date.timeIntervalSinceReferenceDate,
                    color: HousekeepingInk.redLifted,
                    effort: effort,
                    rendering: .fullColour
                )
                .frame(width: 46, height: 46)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("HOUSEKEEPING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(HousekeepingInk.secondaryText)

                if snapshot.isMeasuring {
                    Text("Measuring the house…")
                        .font(RetroTypography.titleFont)
                        .foregroundStyle(HousekeepingInk.text)
                } else {
                    HStack(spacing: 6) {
                        Text(verdict)
                            .font(RetroTypography.titleFont)
                            .foregroundStyle(scoreColor)
                        Text("· \(snapshot.healthScore)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(HousekeepingInk.secondaryText)
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 4)
            scoreRing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// The octopus works harder when the machine does: at rest she is barely
    /// breathing, at full load she is visibly pushing.
    private var effort: Double {
        min(1, max(0, (snapshot.cpu - 0.15) / 0.55))
    }

    private var verdict: String {
        switch snapshot.healthScore {
        case 82...: return "Tidy"
        case 60..<82: return "Busy"
        default: return "Crowded"
        }
    }

    private var scoreColor: Color {
        switch snapshot.healthScore {
        case 82...: return HousekeepingInk.positive
        case 60..<82: return HousekeepingInk.caution
        default: return HousekeepingInk.negative
        }
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(HousekeepingInk.hairline, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(snapshot.healthScore) / 100)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(snapshot.healthScore)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(HousekeepingInk.text)
                .monospacedDigit()
        }
        .frame(width: 38, height: 38)
        .help("One reading of the whole house: processor, memory and disk together.")
    }

    // MARK: - The machine, in a line

    private var chips: some View {
        HStack(spacing: 6) {
            chip(vitals.machineName)
            chip(VitalsFormat.gigabytes(ProcessInfo.processInfo.physicalMemory))
            chip(vitals.osVersion)
            chip("up \(VitalsFormat.uptime(snapshot.uptime))")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(HousekeepingInk.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(HousekeepingInk.surfaceRaised))
            .overlay(Capsule().stroke(HousekeepingInk.hairline, lineWidth: 1))
    }

    // MARK: - The rooms

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("THE ROOMS")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                cpuCard
                memoryCard
                diskCard
                networkCard
                if let gpu = snapshot.gpu {
                    gpuCard(gpu)
                }
                if let battery = snapshot.battery {
                    batteryCard(battery)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var cpuCard: some View {
        VitalsCard(title: "PROCESSOR") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                reading(VitalsFormat.percent(snapshot.cpu))
                Spacer(minLength: 2)
                Text("\(snapshot.coreCount) cores")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
            }
            Sparkline(values: snapshot.cpuHistory, color: HousekeepingInk.redLifted)
                .frame(height: 22)
        }
    }

    private var memoryCard: some View {
        VitalsCard(title: "MEMORY") {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // The unit is in the "of", so the reading is just the number: at
                // this width "11.3 GB of 16.0 GB" cannot fit and gets cut off.
                reading(String(format: "%.1f", Double(snapshot.memoryUsed) / 1_000_000_000))
                Text("of \(VitalsFormat.gigabytes(snapshot.memoryTotal))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                Spacer(minLength: 2)
            }
            Sparkline(values: snapshot.memoryHistory, color: HousekeepingInk.caution)
                .frame(height: 22)
        }
    }

    private var diskCard: some View {
        VitalsCard(title: "DISK") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                reading(VitalsFormat.percent(snapshot.diskFraction))
                Spacer(minLength: 2)
                Text("\(VitalsFormat.gigabytes(snapshot.diskFree)) free")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .lineLimit(1)
            }
            MeterBar(fraction: snapshot.diskFraction, color: diskColor)
            Spacer(minLength: 0)
        }
    }

    private var diskColor: Color {
        switch snapshot.diskFraction {
        case ..<0.8: return HousekeepingInk.positive
        case ..<0.92: return HousekeepingInk.caution
        default: return HousekeepingInk.negative
        }
    }

    private var networkCard: some View {
        VitalsCard(title: "NETWORK") {
            HStack(spacing: 8) {
                Label(VitalsFormat.rate(snapshot.downPerSecond), systemImage: "arrow.down")
                Label(VitalsFormat.rate(snapshot.upPerSecond), systemImage: "arrow.up")
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(HousekeepingInk.text)
            .lineLimit(1)

            Sparkline(values: snapshot.networkHistory, color: HousekeepingInk.positive)
                .frame(height: 22)
        }
    }

    private func gpuCard(_ value: Double) -> some View {
        VitalsCard(title: "GRAPHICS") {
            HStack(alignment: .firstTextBaseline) {
                reading(VitalsFormat.percent(value))
                Spacer(minLength: 2)
            }
            MeterBar(fraction: value, color: HousekeepingInk.redLifted)
            Spacer(minLength: 0)
        }
    }

    private func batteryCard(_ battery: BatteryState) -> some View {
        VitalsCard(title: "BATTERY") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                reading("\(battery.percent)%")
                Spacer(minLength: 2)
                Text(batteryNote(battery))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .lineLimit(1)
            }
            MeterBar(
                fraction: Double(battery.percent) / 100,
                color: battery.charging ? HousekeepingInk.positive : HousekeepingInk.caution
            )
            Spacer(minLength: 0)
        }
    }

    private func batteryNote(_ battery: BatteryState) -> String {
        if battery.charging { return "charging" }
        if battery.onAC { return "on power" }
        if let left = VitalsFormat.minutes(battery.minutesLeft) { return "\(left) left" }
        return "on battery"
    }

    // MARK: - Busiest hands

    private var busiest: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("BUSIEST HANDS")

            // Three rows either way: the panel is a fixed-height popover, and a
            // section that appears a few seconds after opening would be clipped.
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.processes.isEmpty {
                    Text("watching…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.6))
                } else {
                    ForEach(snapshot.processes.prefix(3)) { process in
                        HStack(spacing: 6) {
                            Text(process.name)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(HousekeepingInk.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(VitalsFormat.share(process.cpu))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(HousekeepingInk.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 46, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - The door

    private var door: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                DoorButton(title: "Open", icon: "macwindow", action: leaving(onOpen))
                DoorButton(title: "Scan", icon: "magnifyingglass", action: leaving(onScan))
                DoorButton(title: "Ask", icon: "text.bubble", action: leaving(onAsk))
                DoorButton(title: "Extras", icon: "square.grid.2x2", action: leaving(onExtras))
            }

            HStack(spacing: 8) {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HousekeepingInk.secondaryText)
                // Same reason as the door buttons: the panel opens key, and the
                // switch would arrive with a blue ring around it.
                .focusable(false)

                Spacer(minLength: 4)

                Button("Quit") { onQuit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .focusable(false)
                    .help("Quit Housekeeping. The octopus leaves the menu bar.")
            }

            if loginItem.needsApproval {
                HStack(spacing: 4) {
                    Text("macOS is waiting for you to allow it.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.caution)
                    Button("Allow…") { loginItem.openSystemSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.redLifted)
                        .focusable(false)
                    Spacer(minLength: 0)
                }
            }

            if let problem = loginItem.problem {
                Text(problem)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.negative)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// The popover closes before the window opens, so the click does not leave a
    /// panel hanging over whatever was just brought forward.
    private func leaving(_ action: @escaping () -> Void) -> () -> Void {
        return {
            onClose()
            action()
        }
    }

    // MARK: - Small parts

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.85))
    }

    private func reading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .semibold, design: .monospaced))
            .foregroundStyle(HousekeepingInk.text)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var hairline: some View {
        Rectangle()
            .fill(HousekeepingInk.hairline)
            .frame(height: 1)
    }

    private var credit: some View {
        Text("Made by Morad · Housekeeping \(version)")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

// MARK: - Cards

struct VitalsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(HousekeepingInk.secondaryText)
            content
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(HousekeepingInk.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(HousekeepingInk.hairline, lineWidth: 1)
        )
    }
}

struct DoorButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(HousekeepingInk.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(HousekeepingInk.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(HousekeepingInk.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        // A plain button still takes keyboard focus, and the panel opens already
        // key — the first button would arrive wearing a blue ring nobody put there.
        .focusable(false)
    }
}

// MARK: - Drawings

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.16), color.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                } else {
                    Rectangle()
                        .fill(color.opacity(0.14))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let slots = max(values.count, 2)
        let step = size.width / CGFloat(slots - 1)
        let usable = max(size.height - 3, 1)
        return values.enumerated().map { index, value in
            let level = min(1, max(0, value))
            return CGPoint(
                x: CGFloat(index) * step,
                y: 1.5 + usable * (1 - CGFloat(level))
            )
        }
    }
}

struct MeterBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HousekeepingInk.redShaded.opacity(0.9))
                Capsule()
                    .fill(color)
                    .frame(width: max(3, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 6)
    }
}
