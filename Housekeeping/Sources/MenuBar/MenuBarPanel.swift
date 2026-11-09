// Housekeeping — the panel behind the octopus
//
// This is the app's own answer to a live menu bar panel, so the words are the
// app's: rooms rather than devices, hands rather than processes, a door rather than
// a menu. The house reads Tidy, Busy or Crowded, and the octopus in the corner
// works harder as the processor does, so her body is a reading too.
//
// Everything is redrawn from one published snapshot. Nothing here starts work of
// its own except the twelve-frames-a-second clock that makes her breathe.
//
// The panel is also the smallest screen the app has, and a number that fits in it
// cannot also explain itself. So every room and every hand opens a page here:
// the reading, what it means, what is behind it, and a way to ask the housekeeper
// for more. A process page can stop the process, because the reader who has
// opened a row by name is the one entitled to act on it.

import Darwin
import SwiftUI

private enum Room: String, Identifiable {
    case processor
    case memory
    case disk
    case network
    case graphics
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processor: return "The processor"
        case .memory: return "Memory"
        case .disk: return "The disk"
        case .network: return "The network"
        case .graphics: return "Graphics"
        case .battery: return "The battery"
        }
    }
}

private enum StopKind {
    case quit
    case force
}

struct MenuBarPanel: View {
    @ObservedObject var vitals: SystemVitals
    @ObservedObject var loginItem: LoginItem

    let onOpen: () -> Void
    let onScan: () -> Void
    let onFans: () -> Void
    let onUpdates: () -> Void
    let onAsk: () -> Void
    let onMediaDock: () -> Void
    let onBookbind: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void
    let onDisk: () -> Void
    var onBatteryHealth: (() -> Void)? = nil
    let onExplain: (HousekeeperTopic) -> Void
    let onResize: (CGFloat) -> Void

    private enum ConsumerTab: String, CaseIterable {
        case ram = "Memory"
        case cpu = "Processor"
    }

    @State private var openRoom: Room?
    @State private var openProcess: ProcessLoad?
    @State private var pendingStop: StopKind?
    @State private var stopNote: String?
    @State private var stopNoteIsProblem = false
    @State private var selectedConsumerTab: ConsumerTab = .ram
    @State private var isTopConsumersExpanded: Bool = false
    @State private var isMemoryExpanded: Bool = false
    @State private var isProcessorExpanded: Bool = false
    @State private var showAdvancedSensors: Bool = false

    private var snapshot: VitalsSnapshot { vitals.snapshot }

    /// The header's octopus, drawn the same way whether it is moving or still.
    private func panelMark(at time: Double) -> some View {
        OctopusMark(
            time: time,
            color: HousekeepingInk.redLifted,
            effort: effort,
            rendering: .fullColour
        )
        .frame(width: 46, height: 46)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hairline

            if let process = openProcess {
                processDetail(process)
            } else if let room = openRoom {
                roomDetail(room)
            } else {
                deviceSummary
                rooms
                topResourceConsumers
            }

            hairline
            door
            credit
        }
        .frame(width: 392)
        .background(HousekeepingInk.surface)
        // The popover is sized once, from the view it was built with. A detail
        // page is taller than the overview, so the page reports its own height
        // and the status item resizes the popover to it.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PanelHeightKey.self) { height in
            onResize(height)
        }
        .onReceive(NotificationCenter.default.publisher(for: .housekeepingPanelClosed)) { _ in
            pendingStop = nil
            stopNote = nil
            openProcess = nil
            openRoom = nil
        }
    }

    // MARK: - Who is on duty

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // Still, on purpose. Every animated frame inside a popover makes AppKit
            // re-solve the whole panel's Auto Layout, and measured on this Mac that
            // is about 1.4% of a core per frame: twelve frames a second of a
            // forty-six point drawing cost a fifth of a core, more than the rest of
            // the app put together. The mark in the menu bar still breathes, and so
            // does the one in the window; this one is the price the panel is not
            // going to pay.
            if let mascot = HousekeeperMascot.loadMascot() {
                Image(nsImage: mascot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
            } else {
                panelMark(at: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("HOUSEKEEPING")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.85))

                if snapshot.isMeasuring {
                    Text("Measuring the house…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HousekeepingInk.text)
                } else {
                    Text(verdictTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(scoreColor)

                    Text(verdictSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
            scoreRing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// The octopus works harder when the machine does: at rest she is barely
    /// breathing, at full load she is visibly pushing.
    private var effort: Double {
        min(1, max(0, (snapshot.cpu - 0.15) / 0.55))
    }

    private var verdictTitle: String {
        if let alert = vitals.healthAlert {
            switch alert {
            case .sustainedCPU: return "Sustained High CPU"
            case .seriousThermal: return "High Thermal Pressure"
            case .criticalThermal: return "Critical Thermal Pressure"
            }
        }
        switch snapshot.healthScore {
        case 80...: return "Mac is Healthy"
        case 60..<80: return "Mac is Busy"
        default: return "Needs Attention"
        }
    }

    private var verdictSubtitle: String {
        if let alert = vitals.healthAlert {
            switch alert {
            case .sustainedCPU: return "CPU above 90% repeatedly. Check processes."
            case .seriousThermal: return "macOS reports serious thermal pressure."
            case .criticalThermal: return "Reduce heavy work and check cooling."
            }
        }
        switch snapshot.healthScore {
        case 80...: return "Everything is running smoothly"
        case 60..<80: return "A few apps are working hard"
        default: return "Memory or disk is getting crowded"
        }
    }

    private var scoreColor: Color {
        if let alert = vitals.healthAlert {
            return alert.isCritical ? HousekeepingInk.negative : HousekeepingInk.caution
        }
        switch snapshot.healthScore {
        case 80...: return HousekeepingInk.positive
        case 60..<80: return HousekeepingInk.caution
        default: return HousekeepingInk.negative
        }
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(HousekeepingInk.hairline, lineWidth: 3)
            Circle()
                .trim(from: 0, to: vitals.healthAlert == nil ? CGFloat(snapshot.healthScore) / 100 : 1)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if vitals.healthAlert != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(scoreColor)
            } else {
                Text("\(snapshot.healthScore)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.text)
                    .monospacedDigit()
            }
        }
        .frame(width: 40, height: 40)
        .help(vitals.healthAlert?.explanation ?? "One reading of the whole house: processor, memory and disk together.")
    }

    // MARK: - The machine, in a line

    private var deviceSummary: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 11))
                    .foregroundStyle(HousekeepingInk.secondaryText)

                Text(specsText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let temp = snapshot.cpuTemperature {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 10))
                    Text("\(Int(temp.rounded()))°C")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(temp > 75 ? HousekeepingInk.negative : HousekeepingInk.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(HousekeepingInk.surfaceRaised, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var specsText: String {
        var parts: [String] = []
        if !vitals.machineName.isEmpty {
            parts.append(vitals.machineName)
        }
        parts.append(VitalsFormat.gigabytes(ProcessInfo.processInfo.physicalMemory) + " RAM")
        if !vitals.osVersion.isEmpty {
            parts.append(vitals.osVersion)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - The rooms

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("THE ROOMS")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                roomButton(.processor, help: "What the processor is doing, what the number means, and who is using it.") {
                    cpuCard
                }
                roomButton(.memory, help: "What the memory reading counts, and what is holding it.") {
                    memoryCard
                }
                roomButton(.disk, help: "How full the startup volume is, what that means, and how to measure what is taking the room.") {
                    diskCard
                }
                if let battery = snapshot.battery {
                    roomButton(.battery, help: "What the battery reading means right now.") {
                        batteryCard(battery)
                    }
                } else {
                    roomButton(.processor, help: "Thermal state and cooling.") {
                        coolingCard
                    }
                }
            }

            // Advanced Sensors Disclosure (Network & GPU)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showAdvancedSensors.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(showAdvancedSensors ? "Hide Network & Graphics" : "Show Network & Graphics")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Image(systemName: showAdvancedSensors ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.8))
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if showAdvancedSensors {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    roomButton(.network, help: "What the two traffic figures include.") {
                        networkCard
                    }
                    if let gpu = snapshot.gpu {
                        roomButton(.graphics, help: "How busy the graphics processor is.") {
                            gpuCard(gpu)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func roomButton<Card: View>(
        _ room: Room,
        help: String,
        @ViewBuilder card: () -> Card
    ) -> some View {
        Button {
            show(room)
        } label: {
            card()
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.55))
                        .padding(8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        // A plain button still takes keyboard focus, and the panel opens already
        // key — the first button would arrive wearing a blue ring nobody put there.
        .focusable(false)
        .help(help)
        .contextMenu {
            Button {
                onClose()
                onExplain(topic(for: room))
            } label: {
                Label("Ask the Housekeeper About \(room.title)", systemImage: "sparkles")
            }
            Button {
                show(room)
            } label: {
                Label("Open \(room.title) Room", systemImage: "macwindow")
            }
        }
    }

    private var cpuCard: some View {
        VitalsCard(title: "PROCESSOR") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                reading(VitalsFormat.percent(snapshot.cpu))
                Spacer(minLength: 2)
                Text("\(snapshot.coreCount) cores")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
            }
            MeterBar(
                fraction: min(1.0, max(0.0, snapshot.cpu)),
                color: snapshot.cpu < 0.6 ? HousekeepingInk.positive : (snapshot.cpu < 0.85 ? HousekeepingInk.caution : HousekeepingInk.redLifted)
            )
            Spacer(minLength: 0)
        }
    }

    private var memoryCard: some View {
        VitalsCard(title: "MEMORY") {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                reading(String(format: "%.1f", Double(snapshot.memoryUsed) / 1_000_000_000))
                Text("of \(VitalsFormat.gigabytes(snapshot.memoryTotal))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                Spacer(minLength: 2)

                Button {
                    _ = vitals.freeRAM()
                } label: {
                    Text("Free")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.positive)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(HousekeepingInk.positive.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Free RAM by flushing memory caches and compacting pages")
            }
            MeterBar(
                fraction: Double(snapshot.memoryUsed) / Double(max(snapshot.memoryTotal, 1)),
                color: memoryColor
            )
            Spacer(minLength: 0)
        }
    }

    private var memoryColor: Color {
        let fraction = Double(snapshot.memoryUsed) / Double(max(snapshot.memoryTotal, 1))
        switch fraction {
        case ..<0.75: return HousekeepingInk.positive
        case ..<0.90: return HousekeepingInk.caution
        default: return HousekeepingInk.negative
        }
    }

    private var coolingCard: some View {
        VitalsCard(title: "COOLING") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let temp = snapshot.cpuTemperature {
                    reading("\(Int(temp.rounded()))°C")
                } else {
                    reading("Normal")
                }
                Spacer(minLength: 2)
                if let fan = snapshot.fanRPM, fan > 0 {
                    Text("\(Int(fan.rounded())) RPM")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
            }
            MeterBar(
                fraction: Double(snapshot.cpuTemperature ?? 40) / 100.0,
                color: (snapshot.cpuTemperature ?? 40) > 75 ? HousekeepingInk.negative : HousekeepingInk.positive
            )
            Spacer(minLength: 0)
        }
    }

    private var diskCard: some View {
        VitalsCard(title: "DISK") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                reading(VitalsFormat.percent(snapshot.diskFraction))
                Spacer(minLength: 2)
                Text("\(VitalsFormat.gigabytes(snapshot.diskFree)) free")
                    .font(.system(size: 10.5, design: .monospaced))
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
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(HousekeepingInk.text)
            .lineLimit(1)

            Sparkline(values: snapshot.networkHistory, color: HousekeepingInk.positive)
                .frame(height: 24)
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
                    .font(.system(size: 10.5, design: .monospaced))
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

    // MARK: - Top Resource Consumers

    private var topResourceConsumers: some View {
        let processes = selectedConsumerTab == .cpu ? snapshot.processes : snapshot.memoryHogs

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                sectionLabel(selectedConsumerTab == .cpu ? "APPS USING PROCESSOR" : "APPS USING MEMORY")
                Spacer()

                if !processes.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isTopConsumersExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(isTopConsumersExpanded ? "Compact" : "Expand (\(processes.count))")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            Image(systemName: isTopConsumersExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(HousekeepingInk.redLifted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(HousekeepingInk.redLifted.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(isTopConsumersExpanded ? "Show compact list" : "Expand to view all active processes")
                }

                HStack(spacing: 4) {
                    ForEach(ConsumerTab.allCases, id: \.self) { tab in
                        Button {
                            selectedConsumerTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: selectedConsumerTab == tab ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(selectedConsumerTab == tab ? HousekeepingInk.text : HousekeepingInk.secondaryText.opacity(0.75))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    selectedConsumerTab == tab
                                        ? RoundedRectangle(cornerRadius: 5).fill(HousekeepingInk.surfaceRaised)
                                        : RoundedRectangle(cornerRadius: 5).fill(Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }

            if processes.isEmpty {
                Text("watching…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(processes) { process in
                            consumerRow(
                                process,
                                value: selectedConsumerTab == .cpu
                                    ? VitalsFormat.share(process.cpu)
                                    : VitalsFormat.megabytes(process.memory),
                                isCPU: selectedConsumerTab == .cpu
                            )
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(height: isTopConsumersExpanded ? 280 : 138)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func consumerRow(_ process: ProcessLoad, value: String, isCPU: Bool) -> some View {
        let knowledge = ProcessKnowledge.resolve(pid: process.id, name: process.name)

        return HStack(spacing: 10) {
            ProcessIconView(pid: process.id, name: process.name, isCPU: isCPU, size: 24)

            Button {
                show(process)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(knowledge.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(HousekeepingInk.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(knowledge.category)
                        .font(.system(size: 10))
                        .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.85))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("View details for \(knowledge.displayName)")

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(HousekeepingInk.secondaryText)
                .monospacedDigit()

            // 1-Click Quit button
            Button {
                performStop(.quit, process)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(HousekeepingInk.negative.opacity(0.75))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Quit \(knowledge.displayName)")

            Button {
                show(process)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.4))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HousekeepingInk.surfaceRaised.opacity(0.65))
        )
        .contextMenu {
            Button {
                onClose()
                onExplain(.process(process, totalMemory: snapshot.memoryTotal, knowledge: knowledge))
            } label: {
                Label("Ask the Housekeeper", systemImage: "sparkles")
            }

            Divider()

            Button {
                show(process)
            } label: {
                Label("Inspect Details", systemImage: "info.circle")
            }

            if isRunning(process) {
                Divider()
                Button {
                    performStop(.quit, process)
                } label: {
                    Label("Quit \(knowledge.displayName)", systemImage: "xmark.circle")
                }
                Button {
                    performStop(.force, process)
                } label: {
                    Label("Force Quit", systemImage: "bolt.circle")
                }
            }
        }
    }

    // MARK: - Opening and closing a page

    private func show(_ room: Room) {
        stopNote = nil
        pendingStop = nil
        openProcess = nil
        openRoom = room
    }

    private func show(_ process: ProcessLoad) {
        stopNote = nil
        pendingStop = nil
        openRoom = nil
        openProcess = process
    }

    private func leaveDetail() {
        pendingStop = nil
        stopNote = nil
        openProcess = nil
        openRoom = nil
        isMemoryExpanded = false
        isProcessorExpanded = false
    }

    private func detailHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Button(action: leaveDetail) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Back")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(HousekeepingInk.redLifted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer(minLength: 6)

            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(HousekeepingInk.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(HousekeepingInk.secondaryText)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    // MARK: - A room's page

    private func roomDetail(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            detailHeader(room.title)
            roomReading(room)
            bodyText(roomExplanation(room))
            roomList(room)
            askButton(topic(for: room))
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func roomReading(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch room {
            case .processor:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    reading(VitalsFormat.percent(snapshot.cpu))
                    Spacer(minLength: 2)
                    Text("\(snapshot.coreCount) cores · \(VitalsFormat.share(snapshot.cpu * Double(snapshot.coreCount))) of chip")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
                Sparkline(values: snapshot.cpuHistory, color: HousekeepingInk.redLifted)
                    .frame(height: 32)

            case .memory:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    reading(String(format: "%.1f", Double(snapshot.memoryUsed) / 1_000_000_000))
                    Text("of \(VitalsFormat.gigabytes(snapshot.memoryTotal)) in use")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                    Spacer(minLength: 2)
                }
                Sparkline(values: snapshot.memoryHistory, color: HousekeepingInk.caution)
                    .frame(height: 32)

            case .disk:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    reading(VitalsFormat.percent(snapshot.diskFraction))
                    Text("\(VitalsFormat.gigabytes(snapshot.diskFree)) free of \(VitalsFormat.gigabytes(snapshot.diskTotal))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                    Spacer(minLength: 2)
                }
                MeterBar(fraction: snapshot.diskFraction, color: diskColor)

            case .network:
                HStack(spacing: 12) {
                    Label(VitalsFormat.rate(snapshot.downPerSecond), systemImage: "arrow.down")
                    Label(VitalsFormat.rate(snapshot.upPerSecond), systemImage: "arrow.up")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(HousekeepingInk.text)
                Sparkline(values: snapshot.networkHistory, color: HousekeepingInk.positive)
                    .frame(height: 32)

            case .graphics:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let gpu = snapshot.gpu {
                        reading(VitalsFormat.percent(gpu))
                        Spacer(minLength: 2)
                    } else {
                        Text("Not reported")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HousekeepingInk.secondaryText)
                        Spacer(minLength: 2)
                    }
                }
                MeterBar(fraction: snapshot.gpu ?? 0, color: HousekeepingInk.redLifted)

            case .battery:
                if let battery = snapshot.battery {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        reading("\(battery.percent)%")
                        Text(batteryNote(battery))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(HousekeepingInk.secondaryText)
                        Spacer(minLength: 2)
                    }
                    MeterBar(
                        fraction: Double(battery.percent) / 100,
                        color: battery.charging ? HousekeepingInk.positive : HousekeepingInk.caution
                    )
                } else {
                    Text("This Mac did not report a battery.")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func roomExplanation(_ room: Room) -> String {
        switch room {
        case .processor:
            return "This is the share of the whole processor that was busy in the last second, added up across every core. Short spikes are ordinary. A figure that stays high while nothing visible is running is the case worth looking at — open a hand below to see what it is doing."
        case .memory:
            return "This counts memory apps are actively using, memory the system cannot page out, and memory it has compressed in RAM. macOS keeps memory busy on purpose, so a high reading is not a fault by itself; the honest test is memory pressure, which this panel does not read. The holders below are what is taking the room."
        case .disk:
            return "The volume macOS started from. macOS wants roughly a tenth free; below about 5%, caches, updates and the sleep image start failing. The panel can say how full it is, but not what is taking the room — measuring folders is the disk browser's job."
        case .network:
            return "Every app's traffic added together, measured between two readings a second apart. It says how much is moving, not who is moving it. While a VPN tunnel is up, the same bytes can be counted twice: once on the tunnel, once on the interface carrying it."
        case .graphics:
            return "How busy the graphics processor is, as its driver reports it. Video, games and image or video work move it; a figure that stays high with nothing open is worth looking at. Housekeeping has no per-app breakdown of the graphics processor."
        case .battery:
            return "The charge left, and what macOS estimates for the time remaining at the current draw. Percent is charge, not health — a worn battery can read 100% and still empty quickly."
        }
    }

    @ViewBuilder
    private func roomList(_ room: Room) -> some View {
        switch room {
        case .processor:
            VStack(alignment: .leading, spacing: 10) {
                if !snapshot.processes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            sectionLabel("BUSIEST HANDS (\(snapshot.processes.count))")
                            Spacer()
                            if snapshot.processes.count > 4 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isProcessorExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(isProcessorExpanded ? "Compact" : "Expand All (\(snapshot.processes.count))")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        Image(systemName: isProcessorExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 8.5, weight: .bold))
                                    }
                                    .foregroundStyle(HousekeepingInk.redLifted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(HousekeepingInk.redLifted.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }

                        let procHeight: CGFloat = isProcessorExpanded ? 280 : min(CGFloat(max(snapshot.processes.count, 1)) * 44, 140)
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 5) {
                                ForEach(snapshot.processes) { process in
                                    detailHand(process, value: VitalsFormat.share(process.cpu))
                                }
                            }
                            .padding(.trailing, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(height: procHeight)
                    }
                }
                detailButton("Cooling & Fan Controls", icon: "fan.fill") {
                    onClose()
                    onFans()
                }
            }
            .padding(.horizontal, 16)

        case .memory:
            VStack(alignment: .leading, spacing: 10) {
                detailButton("Free RAM Now", icon: "memorychip", primary: true) {
                    _ = vitals.freeRAM()
                }

                if !snapshot.memoryHogs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            sectionLabel("BIGGEST HOLDERS (\(snapshot.memoryHogs.count))")
                            Spacer()
                            if snapshot.memoryHogs.count > 4 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isMemoryExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(isMemoryExpanded ? "Compact" : "Expand All (\(snapshot.memoryHogs.count))")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        Image(systemName: isMemoryExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 8.5, weight: .bold))
                                    }
                                    .foregroundStyle(HousekeepingInk.redLifted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(HousekeepingInk.redLifted.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }

                        let memHeight: CGFloat = isMemoryExpanded ? 300 : min(CGFloat(max(snapshot.memoryHogs.count, 1)) * 44, 150)
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 5) {
                                ForEach(snapshot.memoryHogs) { process in
                                    detailHand(process, value: VitalsFormat.megabytes(process.memory))
                                }
                            }
                            .padding(.trailing, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(height: memHeight)
                    }
                }
            }
            .padding(.horizontal, 16)

        case .battery:
            VStack(alignment: .leading, spacing: 10) {
                if let onBatteryHealth {
                    detailButton("Battery Health Management", icon: "battery.100.bolt", primary: true) {
                        onClose()
                        onBatteryHealth()
                    }
                }
                if !snapshot.processes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("ENERGY CONSUMERS (\(snapshot.processes.count))")
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 5) {
                                ForEach(snapshot.processes) { process in
                                    detailHand(process, value: VitalsFormat.share(process.cpu))
                                }
                            }
                            .padding(.trailing, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 180)
                    }
                }
            }
            .padding(.horizontal, 16)

        case .network, .graphics:
            EmptyView()

        case .disk:
            VStack(alignment: .leading, spacing: 10) {
                detailButton("Explore with Space Lens", icon: "internaldrive", primary: true) {
                    onClose()
                    onDisk()
                }
                detailButton("Scan for Clutter", icon: "sparkles") {
                    onClose()
                    onScan()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func detailHand(_ process: ProcessLoad, value: String) -> some View {
        let knowledge = ProcessKnowledge.resolve(pid: process.id, name: process.name)

        return HStack(spacing: 10) {
            ProcessIconView(pid: process.id, name: process.name, size: 22)

            Button {
                show(process)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(knowledge.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HousekeepingInk.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(knowledge.category)
                        .font(.system(size: 9.5))
                        .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.85))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(HousekeepingInk.secondaryText)
                .monospacedDigit()

            Button {
                performStop(.quit, process)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13.5))
                    .foregroundStyle(HousekeepingInk.negative.opacity(0.8))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Quit \(knowledge.displayName)")

            Button {
                show(process)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.45))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(HousekeepingInk.surfaceRaised.opacity(0.65))
        )
        .contextMenu {
            Button {
                onClose()
                onExplain(.process(process, totalMemory: snapshot.memoryTotal, knowledge: knowledge))
            } label: {
                Label("Ask the Housekeeper", systemImage: "sparkles")
            }

            Divider()

            Button {
                show(process)
            } label: {
                Label("Inspect Details", systemImage: "info.circle")
            }

            if isRunning(process) {
                Divider()
                Button {
                    performStop(.quit, process)
                } label: {
                    Label("Quit \(knowledge.displayName)", systemImage: "xmark.circle")
                }
                Button {
                    performStop(.force, process)
                } label: {
                    Label("Force Quit", systemImage: "bolt.circle")
                }
            }
        }
    }

    private func topic(for room: Room) -> HousekeeperTopic {
        switch room {
        case .processor: return .processor(snapshot)
        case .memory: return .memory(snapshot)
        case .disk: return .disk(snapshot)
        case .network: return .network(snapshot)
        case .graphics: return .graphics(snapshot)
        case .battery:
            guard let battery = snapshot.battery else { return .battery(BatteryState(percent: 0, charging: false, onAC: false, minutesLeft: nil)) }
            return .battery(battery)
        }
    }

    // MARK: - A process's page

    private func processDetail(_ stored: ProcessLoad) -> some View {
        // The stored row is the one that was pressed; the snapshot may have a
        // fresher figure for the same process.
        let process = snapshot.processes.first { $0.id == stored.id }
            ?? snapshot.memoryHogs.first { $0.id == stored.id }
            ?? stored
        let running = isRunning(process)
        let knowledge = ProcessKnowledge.resolve(pid: process.id, name: process.name)

        return VStack(alignment: .leading, spacing: 9) {
            detailHeader("process \(process.id)")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProcessIconView(pid: process.id, name: process.name, size: 22)
                    Text(knowledge.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HousekeepingInk.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(knowledge.category)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule().fill(HousekeepingInk.surfaceRaised)
                        )
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }

                if knowledge.displayName != process.name {
                    Text(process.name)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }

                HStack(spacing: 12) {
                    reading(VitalsFormat.share(process.cpu))
                    Text("of one core")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                    Spacer(minLength: 2)
                    Text(VitalsFormat.megabytes(process.memory))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.text)
                        .monospacedDigit()
                    Text("held")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
            }
            .padding(.horizontal, 16)

            // Housekeeping Knowledge Card
            VStack(alignment: .leading, spacing: 6) {
                if let parent = knowledge.parentApp {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(HousekeepingInk.redLifted)
                        Text("Connected to:")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(HousekeepingInk.secondaryText)
                        Text(parent)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(HousekeepingInk.text)
                        if let ppid = knowledge.parentPid {
                            Text("(PID \(ppid))")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.8))
                        }
                    }
                }

                if let work = knowledge.workingOn {
                    HStack(spacing: 5) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(HousekeepingInk.redLifted)
                        Text("Active workload:")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(HousekeepingInk.secondaryText)
                        Text(work)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HousekeepingInk.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Text(knowledge.summary)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HousekeepingInk.text.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 5) {
                    Circle()
                        .fill(safetyColor(knowledge.safetyLevel))
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    Text(knowledge.safetyAdvice)
                        .font(.system(size: 9))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HousekeepingInk.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(HousekeepingInk.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 16)

            bodyText(running
                ? "A quit is a request: it can save, close and exit on its own terms. A force quit takes the memory away where it stands, and anything unsaved in it is lost."
                : "This process is no longer running. It is kept here until you go back so the row does not vanish under your hand.")

            if let stopNote {
                Text(stopNote)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(stopNoteIsProblem ? HousekeepingInk.negative : HousekeepingInk.positive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if running {
                if let pendingStop {
                    confirmation(pendingStop, process)
                } else {
                    HStack(spacing: 8) {
                        if knowledge.safetyLevel == .systemProtected {
                            Text("System Protected Process")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(HousekeepingInk.caution)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        } else {
                            detailButton("Quit", icon: "xmark.circle", primary: true) {
                                stopNote = nil
                                pendingStop = .quit
                            }
                            detailButton("Force Quit", icon: "bolt.circle") {
                                stopNote = nil
                                pendingStop = .force
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            askButton(.process(process, totalMemory: snapshot.memoryTotal, knowledge: knowledge))
        }
        .padding(.bottom, 12)
    }

    private func safetyColor(_ level: ProcessSafetyLevel) -> Color {
        switch level {
        case .safeToQuit: return HousekeepingInk.positive
        case .caution: return HousekeepingInk.caution
        case .systemProtected: return HousekeepingInk.negative
        }
    }

    private func confirmation(_ kind: StopKind, _ process: ProcessLoad) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(kind == .quit
                 ? "Ask \(process.name) to quit?"
                 : "Force \(process.name) to quit?")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HousekeepingInk.text)
                .lineLimit(2)

            Text(kind == .quit
                 ? "It will be asked to save and close. A process that cannot close on its own may stay open."
                 : "It will not be asked to save. Anything unsaved in it is lost.")
                .font(.system(size: 9.5))
                .foregroundStyle(HousekeepingInk.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                detailButton("Cancel", icon: "arrow.uturn.backward") {
                    pendingStop = nil
                }
                detailButton(kind == .quit ? "Quit" : "Force Quit",
                             icon: kind == .quit ? "xmark.circle" : "bolt.circle",
                             primary: true) {
                    performStop(kind, process)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func performStop(_ kind: StopKind, _ process: ProcessLoad) {
        if let error = vitals.stop(process, force: kind == .force) {
            stopNote = error
            stopNoteIsProblem = true
        } else {
            stopNote = kind == .force
                ? "Force quit sent to \(process.name)."
                : "Quit sent to \(process.name)."
            stopNoteIsProblem = false
        }
        pendingStop = nil
    }

    private func isRunning(_ process: ProcessLoad) -> Bool {
        process.id > 0 && kill(process.id, 0) == 0
    }

    // MARK: - Buttons inside a page

    private func detailButton(
        _ title: String,
        icon: String,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(primary ? Color.white : HousekeepingInk.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary ? HousekeepingInk.red : HousekeepingInk.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(primary ? HousekeepingInk.redLifted : HousekeepingInk.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func askButton(_ topic: HousekeeperTopic) -> some View {
        detailButton("Ask the Housekeeper", icon: "bubble.left.and.text.bubble.right") {
            onClose()
            onExplain(topic)
        }
        .padding(.horizontal, 16)
        .help("Opens the housekeeper on this reading. It explains; Housekeeping decides.")
    }

    // MARK: - The door

    private var door: some View {
        VStack(spacing: 8) {
            if let note = vitals.ramPurgeMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(HousekeepingInk.positive)
                    Text(note)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.text)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HousekeepingInk.positive.opacity(0.12))
                )
            }

            HStack(spacing: 8) {
                DoorButton(title: "Free RAM", icon: "memorychip", action: { _ = vitals.freeRAM() })
                DoorButton(title: "Clean Clutter", icon: "sparkles", action: leaving(onScan))
                DoorButton(title: "Cooling", icon: "fan.fill", action: leaving(onFans))
                DoorButton(title: "Open App", icon: "macwindow", action: leaving(onOpen))
            }

            HStack(spacing: 8) {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HousekeepingInk.secondaryText)
                // Same reason as the door buttons: the panel opens key, and the
                // switch would arrive with a blue ring around it.
                .focusable(false)

                Spacer(minLength: 4)

                Button {
                    leaving(onUpdates)()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("Updates")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(HousekeepingInk.secondaryText)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Check for Housekeeping updates")

                Text("·")
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.4))

                Button("Quit") { onQuit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .focusable(false)
                    .help("Quit Housekeeping. The octopus leaves the menu bar.")
            }

            if loginItem.needsApproval {
                HStack(spacing: 4) {
                    Text("macOS is waiting for you to allow it.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.caution)
                    Button("Allow…") { loginItem.openSystemSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.redLifted)
                        .focusable(false)
                    Spacer(minLength: 0)
                }
            }

            if let problem = loginItem.problem {
                Text(problem)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.negative)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
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
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.85))
    }

    private func reading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 21, weight: .bold, design: .monospaced))
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
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.24.1"
    }
}

// MARK: - Height reporting

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(HousekeepingInk.secondaryText)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HousekeepingInk.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(HousekeepingInk.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HousekeepingInk.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(HousekeepingInk.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

// MARK: - Process Icon Resolution

public final class ProcessIconProvider {
    public static let shared = ProcessIconProvider()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 300
    }

    public func icon(for pid: pid_t, name: String) -> NSImage? {
        let key = "\(pid):\(name)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // 0. Explicit special cases for system components
        if name.contains("Safari") || name.contains("WebKit") {
            let icon = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
            cache.setObject(icon, forKey: key)
            return icon
        }
        if name == "Finder" {
            let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
            cache.setObject(icon, forKey: key)
            return icon
        }
        if name.contains("WebKit") || name.contains("Safari") {
            if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                let icon = NSWorkspace.shared.icon(forFile: safariURL.path)
                cache.setObject(icon, forKey: key)
                return icon
            }
        }

        // 1. NSRunningApplication lookup by PID
        if pid > 0, let runningApp = NSRunningApplication(processIdentifier: pid), let icon = runningApp.icon {
            cache.setObject(icon, forKey: key)
            return icon
        }

        // 2. Binary path inspection via proc_pidpath
        let execPath = ProcessKnowledge.path(for: pid)
        if !execPath.isEmpty {
            if let appRange = execPath.range(of: ".app") {
                let bundlePath = String(execPath[..<appRange.upperBound])
                let icon = NSWorkspace.shared.icon(forFile: bundlePath)
                cache.setObject(icon, forKey: key)
                return icon
            }
        }

        // 3. Match against running applications localizedName or bundleIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: {
            guard let loc = $0.localizedName else { return false }
            return loc.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                   name.localizedCaseInsensitiveContains(loc) ||
                   loc.localizedCaseInsensitiveContains(name)
        }), let icon = app.icon {
            cache.setObject(icon, forKey: key)
            return icon
        }

        // 4. Clean name for Electron/Chromium helpers or secondary processes
        var cleanName = name
        for suffix in [" (Renderer)", " (GPU)", " (Plugin)", " Helper", " Web Content", " Networking"] {
            cleanName = cleanName.replacingOccurrences(of: suffix, with: "")
        }

        if let app = runningApps.first(where: {
            guard let loc = $0.localizedName else { return false }
            return loc.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }), let icon = app.icon {
            cache.setObject(icon, forKey: key)
            return icon
        }

        // 5. Look for an app on disk in common application folders
        for baseDir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", "/System/Library/CoreServices"] {
            let candidate = "\(baseDir)/\(cleanName).app"
            if FileManager.default.fileExists(atPath: candidate) {
                let icon = NSWorkspace.shared.icon(forFile: candidate)
                cache.setObject(icon, forKey: key)
                return icon
            }
        }

        // 6. Check if NSWorkspace knows an app URL for this name or bundle identifier
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cleanName) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            cache.setObject(icon, forKey: key)
            return icon
        }

        return nil
    }
}

struct ProcessIconView: View {
    let pid: pid_t
    let name: String
    var isCPU: Bool = false
    var size: CGFloat = 18

    var body: some View {
        if let image = ProcessIconProvider.shared.icon(for: pid, name: name) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            let knowledge = ProcessKnowledge.resolve(pid: pid, name: name)
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(HousekeepingInk.surfaceRaised)
                Image(systemName: knowledge.icon.isEmpty ? (isCPU ? "cpu" : "memorychip") : knowledge.icon)
                    .font(.system(size: size * 0.58, weight: .semibold))
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.85))
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(HousekeepingInk.hairline, lineWidth: 0.5)
            )
        }
    }
}
