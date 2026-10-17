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
    let onAsk: () -> Void
    let onMediaDock: () -> Void
    let onBookbind: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void
    let onDisk: () -> Void
    let onExplain: (HousekeeperTopic) -> Void
    let onResize: (CGFloat) -> Void

    @State private var openRoom: Room?
    @State private var openProcess: ProcessLoad?
    @State private var pendingStop: StopKind?
    @State private var stopNote: String?
    @State private var stopNoteIsProblem = false

    private var snapshot: VitalsSnapshot { vitals.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hairline

            if let process = openProcess {
                processDetail(process)
            } else if let room = openRoom {
                roomDetail(room)
            } else {
                chips
                rooms
                busiest
            }

            hairline
            door
            credit
        }
        .frame(width: 352)
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
                roomButton(.processor, help: "What the processor is doing, what the number means, and who is using it.") {
                    cpuCard
                }
                roomButton(.memory, help: "What the memory reading counts, and what is holding it.") {
                    memoryCard
                }
                roomButton(.disk, help: "How full the startup volume is, what that means, and how to measure what is taking the room.") {
                    diskCard
                }
                roomButton(.network, help: "What the two traffic figures include.") {
                    networkCard
                }
                if let gpu = snapshot.gpu {
                    roomButton(.graphics, help: "How busy the graphics processor is.") {
                        gpuCard(gpu)
                    }
                }
                if let battery = snapshot.battery {
                    roomButton(.battery, help: "What the battery reading means right now.") {
                        batteryCard(battery)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
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
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.55))
                        .padding(8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        // A plain button still takes keyboard focus, and the panel opens already
        // key — the first button would arrive wearing a blue ring nobody put there.
        .focusable(false)
        .help(help)
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
            VStack(alignment: .leading, spacing: 2) {
                if snapshot.processes.isEmpty {
                    Text("watching…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.6))
                } else {
                    ForEach(snapshot.processes.prefix(3)) { process in
                        handRow(process, value: VitalsFormat.share(process.cpu))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 46, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func handRow(_ process: ProcessLoad, value: String) -> some View {
        Button {
            show(process)
        } label: {
            HStack(spacing: 6) {
                Text(process.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.45))
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Open \(process.name): what it is doing, what it is holding, and how to stop it.")
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
    }

    private func detailHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Button(action: leaveDetail) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                    Text("Back")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(HousekeepingInk.redLifted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer(minLength: 6)

            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(HousekeepingInk.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(HousekeepingInk.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
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
                    Text("\(snapshot.coreCount) cores · \(VitalsFormat.share(snapshot.cpu * Double(snapshot.coreCount))) of the whole chip")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
                Sparkline(values: snapshot.cpuHistory, color: HousekeepingInk.redLifted)
                    .frame(height: 30)

            case .memory:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    reading(String(format: "%.1f", Double(snapshot.memoryUsed) / 1_000_000_000))
                    Text("of \(VitalsFormat.gigabytes(snapshot.memoryTotal)) in use")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                    Spacer(minLength: 2)
                }
                Sparkline(values: snapshot.memoryHistory, color: HousekeepingInk.caution)
                    .frame(height: 30)

            case .disk:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    reading(VitalsFormat.percent(snapshot.diskFraction))
                    Text("\(VitalsFormat.gigabytes(snapshot.diskFree)) free of \(VitalsFormat.gigabytes(snapshot.diskTotal))")
                        .font(.system(size: 9, design: .monospaced))
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
                    .frame(height: 30)

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
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(HousekeepingInk.secondaryText)
                        Spacer(minLength: 2)
                    }
                    MeterBar(
                        fraction: Double(battery.percent) / 100,
                        color: battery.charging ? HousekeepingInk.positive : HousekeepingInk.caution
                    )
                } else {
                    Text("This Mac did not report a battery.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
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
            if !snapshot.processes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("BUSIEST HANDS")
                    ForEach(snapshot.processes.prefix(4)) { process in
                        detailHand(process, value: VitalsFormat.share(process.cpu))
                    }
                }
                .padding(.horizontal, 14)
            }

        case .memory:
            if !snapshot.memoryHogs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("BIGGEST HOLDERS")
                    ForEach(snapshot.memoryHogs.prefix(5)) { process in
                        detailHand(process, value: VitalsFormat.megabytes(process.memory))
                    }
                }
                .padding(.horizontal, 14)
            }

        case .network, .graphics, .battery:
            EmptyView()

        case .disk:
            detailButton("Measure My Folders", icon: "folder") {
                onClose()
                onDisk()
            }
            .padding(.horizontal, 14)
        }
    }

    private func detailHand(_ process: ProcessLoad, value: String) -> some View {
        Button {
            show(process)
        } label: {
            HStack(spacing: 6) {
                Text(process.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HousekeepingInk.secondaryText)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(HousekeepingInk.secondaryText.opacity(0.45))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HousekeepingInk.surfaceRaised.opacity(0.65))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
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

        return VStack(alignment: .leading, spacing: 9) {
            detailHeader("process \(process.id)")

            VStack(alignment: .leading, spacing: 6) {
                Text(process.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HousekeepingInk.text)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    reading(VitalsFormat.share(process.cpu))
                    Text("of one core")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                    Spacer(minLength: 2)
                    Text(VitalsFormat.megabytes(process.memory))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.text)
                        .monospacedDigit()
                    Text("held")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HousekeepingInk.secondaryText)
                }
            }
            .padding(.horizontal, 14)

            bodyText(running
                ? "A quit is a request: it can save, close and exit on its own terms. A force quit takes the memory away where it stands, and anything unsaved in it is lost. The name comes from the process itself — Housekeeping does not know what installed it or what it is partway through."
                : "This process is no longer running. It is kept here until you go back so the row does not vanish under your hand.")

            if let stopNote {
                Text(stopNote)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(stopNoteIsProblem ? HousekeepingInk.negative : HousekeepingInk.positive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }

            if running {
                if let pendingStop {
                    confirmation(pendingStop, process)
                } else {
                    HStack(spacing: 8) {
                        detailButton("Quit", icon: "xmark.circle", primary: true) {
                            stopNote = nil
                            pendingStop = .quit
                        }
                        detailButton("Force Quit", icon: "bolt.circle") {
                            stopNote = nil
                            pendingStop = .force
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            askButton(.process(process, totalMemory: snapshot.memoryTotal))
        }
        .padding(.bottom, 12)
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
        .padding(.horizontal, 14)
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(primary ? Color.white : HousekeepingInk.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
        .padding(.horizontal, 14)
        .help("Opens the housekeeper on this reading. It explains; Housekeeping decides.")
    }

    // MARK: - The door

    private var door: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                DoorButton(title: "Open", icon: "macwindow", action: leaving(onOpen))
                DoorButton(title: "Scan", icon: "magnifyingglass", action: leaving(onScan))
                DoorButton(title: "Ask", icon: "text.bubble", action: leaving(onAsk))
                DoorButton(title: "MediaDock", icon: "play.rectangle.fill", action: leaving(onMediaDock))
                DoorButton(title: "Bookbind", icon: "book.closed.fill", action: leaving(onBookbind))
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
