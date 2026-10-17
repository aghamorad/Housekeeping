// Housekeeping — Spoof Location
//
// The sheet is written the way the rest of the app is: it says what it is about
// to do, it says what the reader has to do first, and it says how to get back.
// A location spoofer is the one job in Housekeeping that depends on something
// outside the Mac — a phone on the end of a cable — so the instructions are part
// of the screen rather than a tooltip. Nothing here acts until a place is picked,
// and the last thing on the screen is the way back to real GPS.

import SwiftUI

@MainActor
final class PhoneModel: ObservableObject {
    @Published var devices: [PhoneDevice] = []
    @Published var selected: PhoneDevice?
    // A session outlives this screen, so reopening it picks the place back up
    // rather than claiming the phone is on real GPS when it is not.
    @Published var current: PhoneSpot? = PhoneTool.activeSpot
    @Published var busy = false
    @Published var status = ""
    @Published var isError = false
    @Published var isRefreshing = false

    /// `nil` when the helper is missing. The screen uses this to show the install
    /// line instead of a button that would only fail.
    var helperPath: String? { PhoneTool.executable() }

    private let runner = ProcessRunner()

    func refresh() async {
        guard helperPath != nil else {
            status = "pymobiledevice3 is not installed on this Mac."
            isError = true
            return
        }
        isRefreshing = true
        let found = await PhoneTool.devices(runner: runner)
        isRefreshing = false
        devices = found

        // Unplugging the phone ends the session without anyone pressing
        // anything, so the screen has to notice and stop claiming a location.
        if PhoneTool.activeSpot == nil { current = nil }

        if let selected, found.contains(selected) {
            self.selected = selected
        } else {
            selected = found.first { $0.isUSB } ?? found.first
        }

        if found.isEmpty {
            status = "No iPhone found. Plug it in with a USB cable, unlock it, and tap Trust if the Mac asks."
            isError = false
        } else if !busy {
            status = current.map { "The iPhone is now in \($0.city)." } ?? "Ready."
            isError = false
        }
    }

    func apply(_ spot: PhoneSpot) async {
        guard let device = selected else {
            await refresh()
            return
        }
        busy = true
        isError = false
        status = "Setting \(spot.city)… the first press can take up to a minute."
        let outcome = await PhoneTool.set(spot, on: device)
        busy = false
        if outcome.ok {
            current = spot
            status = outcome.message
            isError = false
        } else {
            status = outcome.message
            isError = true
        }
    }

    func reset() async {
        guard let device = selected else {
            await refresh()
            return
        }
        busy = true
        isError = false
        status = "Clearing the fake location…"
        let outcome = await PhoneTool.clear(on: device, runner: runner)
        busy = false
        if outcome.ok {
            current = nil
            status = outcome.message
            isError = false
        } else {
            status = outcome.message
            isError = true
        }
    }
}

struct PhoneView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @StateObject private var model = PhoneModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    instructions
                    deviceRow
                    places
                    statusRow
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 660)
        .background(style.windowBackground)
        .preferredColorScheme(style.isRetro ? .light : .dark)
        .interactiveDismissDisabled(model.busy)
        .task { await model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spoof Location")
                    .font(style.titleFont)
                    .foregroundColor(style.text)
                Text("Tell the iPhone it is standing somewhere else, without changing the phone.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - What the reader has to do

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHAT TO DO")
                    .font(style.labelFont)
                    .foregroundColor(style.secondaryText)
                Spacer()
                Text(nextStep)
                    .font(style.smallFont)
                    .foregroundColor(style.accent)
            }

            step(
                1,
                title: "Plug in the iPhone",
                done: model.selected != nil,
                active: model.selected == nil,
                detail: model.selected == nil
                    ? "Use a USB cable, unlock the phone, tap Trust if the Mac asks, and enter the passcode on the phone if it asks for one. Wireless phones are not used here."
                    : "Found. Leave it plugged in and unlocked while a place is being set."
            )
            step(
                2,
                title: "Pick a place",
                done: model.current != nil,
                active: model.selected != nil && model.current == nil,
                detail: model.current == nil
                    ? "The first press takes up to a minute, because a connection to the phone has to be built. Leave the phone unlocked until the place is confirmed."
                    : "The phone is reporting the place you chose. Picking another replaces it, and rebuilds the connection."
            )
            step(
                3,
                title: "Put it back when you are done",
                done: false,
                active: model.current != nil,
                detail: "Press Real GPS below. The fake location stays while Housekeeping is open, even if you close this screen. Unplugging or restarting the phone also ends it, and so does quitting Housekeeping."
            )

            Divider().opacity(0.5)

            Text("Nothing is installed on the phone, nothing is jailbroken, and no app data is changed. Every app that asks the phone where it is — Maps, Weather, games, anything that records where you go — will be given the place you choose, so choose with that in mind.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.groupingBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The one line that tells the reader what the app is waiting for, so the
    /// checklist never has to be read in full to know the next move.
    private var nextStep: String {
        if model.helperPath == nil { return "Install the helper first" }
        if model.selected == nil { return "Waiting for the phone" }
        if model.current != nil { return "Done — put it back below" }
        return "Ready — choose a place"
    }

    private func step(_ number: Int, title: String, done: Bool, active: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(style.positive)
                } else {
                    Text("\(number)")
                        .font(style.smallFont.bold())
                        .foregroundColor(active ? style.windowBackground : style.secondaryText)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(active ? style.accent : style.rowSelection))
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(style.bodyFont.bold())
                    .foregroundColor(active ? style.text : style.text.opacity(0.75))
                Text(detail)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The phone

    @ViewBuilder
    private var deviceRow: some View {
        if let helper = model.helperPath {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.selected == nil ? style.secondaryText.opacity(0.5) : style.positive)
                    .frame(width: 9, height: 9)
                Text(model.selected.map { "\($0.name) · \($0.udid.prefix(8))…\($0.isUSB ? " · USB" : " · wireless")" }
                     ?? "No iPhone detected")
                    .font(style.pathFont)
                    .foregroundColor(style.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                ThemeButton(title: "Check Again", systemImage: "arrow.clockwise",
                            isEnabled: !model.busy && !model.isRefreshing,
                            help: "Look for a connected iPhone again. Nothing is changed on it.") {
                    Task { await model.refresh() }
                }
            }
            .helpIfPresent(helper)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("pymobiledevice3 is needed to talk to the phone, and this Mac does not have it.")
                    .font(style.bodyFont)
                    .foregroundColor(style.caution)
                HStack(spacing: 8) {
                    Text(PhoneTool.installHint)
                        .font(style.pathFont)
                        .foregroundColor(style.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(style.groupingBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text("in Terminal, then reopen this screen.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style.caution.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Places

    private var places: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLACES")
                .font(style.labelFont)
                .foregroundColor(style.secondaryText)

            ForEach(PhoneSpot.all) { spot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(spot.city)
                            .font(style.bodyFont.bold())
                            .foregroundColor(style.text)
                        Text("\(spot.detail) · \(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))")
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                    }
                    Spacer()
                    if model.current == spot {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(style.positive)
                    }
                    if model.busy {
                        EmptyView()
                    } else {
                        ThemeButton(
                            title: model.current == spot ? "Set Again" : "Go Here",
                            isPrimary: model.current != spot,
                            isEnabled: model.selected != nil,
                            help: model.selected == nil
                                ? "Plug an iPhone in first."
                                : "Set the iPhone's GPS to \(spot.city). Nothing on the phone is changed."
                        ) {
                            Task { await model.apply(spot) }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(model.current == spot ? style.rowSelection : style.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                ThemeButton(title: "Real GPS", systemImage: "location.fill",
                            isEnabled: !model.busy && model.selected != nil,
                            help: "Clear the fake location and let the iPhone use its own GPS again.") {
                    Task { await model.reset() }
                }
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Status and closing

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: model.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundColor(model.isError ? style.caution : style.secondaryText)
            }
            Text(model.status)
                .font(style.smallFont)
                .foregroundColor(model.isError ? style.caution : style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let current = model.current {
                Text("Fake location active: \(current.city)")
                    .font(style.smallFont)
                    .foregroundColor(style.caution)
            } else {
                Text("Real GPS")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Spacer()
            ThemeButton(title: "Done", isPrimary: true,
                        help: "Close this screen. A fake location, if one is set, stays until you press Real GPS, unplug the phone, or quit Housekeeping.") {
                appState.showPhone = false
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
