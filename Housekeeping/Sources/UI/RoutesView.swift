// Housekeeping — Testing routes
//
// The one screen here that changes the machine while it is open. A VPN client
// holds one tunnel at a time, so a route can only be tried alone: connect,
// measure, disconnect, next. That is why the connection drops and comes back
// for the length of a run, and why the screen says so before the reader presses
// the button rather than after.
//
// It is built once and shows two interfaces. Simple picks the settings and
// explains the result; Advanced exposes every control. Both drive the same
// engine through `RoutesModel`, so there is one behaviour with two ways in.

import SwiftUI

struct RoutesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @StateObject private var model = RoutesModel()

    @State private var sort: ResultSort = .best
    @State private var selectedResultID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let banner = model.banner {
                bannerBar(banner, tint: style.accent)
                Divider()
            }
            if let error = model.engine.errorMessage {
                bannerBar(error, tint: style.negative)
                Divider()
            }

            HStack(spacing: 0) {
                settingsColumn
                    .frame(width: 344)
                Divider()
                resultsColumn
                    .frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .frame(minWidth: 1040, maxWidth: 1040, minHeight: 680)
        .background(style.windowBackground)
        .preferredColorScheme(style.isRetro ? .light : .dark)
        // A run that is allowed to disappear closes nothing: the engine finishes
        // in the background and leaves the VPN disconnected, so nothing is left
        // hanging. What would be lost is the result — and the ability to stop it —
        // on the one screen where a keypress away from the window is easy to make
        // by accident. Escape closes the sheet once the run is over.
        .interactiveDismissDisabled(model.engine.isRunning)
        .task { await model.loadIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Routes")
                    .font(style.titleFont)
                    .foregroundColor(style.text)
                Text("Try the routes your client offers and find the one that actually carries traffic.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }

            Spacer()

            if model.engine.isRunning { runningChip }

            Picker("", selection: $model.uiMode) {
                ForEach(UIMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 172)
            .disabled(model.engine.isRunning)
            .help("Simple picks the settings and explains the result. Advanced exposes every control.")

            ThemeButton(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                isEnabled: !model.engine.isRunning && !model.isRefreshing,
                help: "Re-read the client's status and server list."
            ) {
                Task { await model.refreshAll() }
            }

            if model.providerKind == .windscribe {
                ThemeButton(
                    title: "Update List",
                    isEnabled: !model.engine.isRunning && !model.isRefreshing,
                    help: "Fetch a fresh server list from the client's public endpoint."
                ) {
                    model.refreshWindscribeLocations()
                }
            }

            ThemeButton(
                title: "Clear",
                isEnabled: !model.engine.results.isEmpty && !model.engine.isRunning,
                help: "Throw the measured results away. They can be taken again at any time."
            ) {
                model.engine.clearResults()
                selectedResultID = nil
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var runningChip: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
                .frame(width: 11, height: 11)
            Text("\(model.engine.completedCount)/\(model.engine.totalCount)")
                .font(style.smallFont)
                .foregroundColor(style.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(style.accent.opacity(0.14)))
        .overlay(Capsule().strokeBorder(style.accent.opacity(0.30), lineWidth: 0.5))
    }

    private func bannerBar(_ text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(tint)
            Text(text)
                .font(style.smallFont)
                .foregroundColor(style.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                model.banner = nil
                model.engine.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(style.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
    }

    // MARK: - The settings column

    private var settingsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.uiMode == .simple {
                    simpleSettings
                } else {
                    advancedSettings
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Simple settings

    @ViewBuilder
    private var simpleSettings: some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Find your best route")
                    .font(style.labelFont)
                    .foregroundColor(style.text)
                Text("No settings to understand. Pick where the traffic should come out, how hard to look, then run it.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        simpleStepOne
        simpleStepTwo
        simpleStepThree
    }

    private var simpleStepOne: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StepBadge(number: 1, title: "Where should your traffic come out?")
                Text(model.simpleCountries.isEmpty ? "none picked" : "\(model.simpleCountries.count) picked")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Text("Pick as many countries as you like. A country with more than one server is tried at more than one of them.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ThemeButton(title: "Nearby", help: "The countries closest to you.") {
                    pick(simpleNearby)
                }
                ThemeButton(title: "Popular", help: "The countries most often used.") {
                    pick(simplePopular)
                }
                ThemeButton(title: "Clear", isEnabled: !model.simpleCountries.isEmpty, help: "Choose none.") {
                    model.simpleCountries.removeAll()
                }
            }

            if !model.simpleCountries.isEmpty {
                Text(model.simpleCountries.sorted().joined(separator: ", "))
                    .font(style.smallFont)
                    .foregroundColor(style.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if countryChipItems.isEmpty {
                Text("No server list loaded yet.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            } else {
                FlowRow(spacing: 6, lineSpacing: 6) {
                    ForEach(countryChipItems) { item in
                        CountryChip(name: item.name, flag: item.flag, isSelected: model.simpleCountries.contains(item.name)) {
                            toggleSimpleCountry(item.name)
                        }
                    }
                }
            }
        }
    }

    private var simpleStepTwo: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepBadge(number: 2, title: "How hard should it look?")
            Picker("", selection: $model.simpleDepth) {
                ForEach(RouteDepth.allCases) { depth in
                    Text(depth.title).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.engine.isRunning)
            Text(model.simpleDepth.blurb)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var simpleStepThree: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepBadge(number: 3, title: "Run it")
            Text(targetCountWording)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            if !model.targets.isEmpty {
                Text(estimate(model.estimatedSeconds))
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            keepLogQuestion
            if model.engine.isRunning {
                ThemeButton(title: "Stop", isPrimary: true, help: "Stop the test and keep what has been tried so far.") {
                    model.stopTest()
                }
            } else {
                ThemeButton(
                    title: "Find My Best Route",
                    systemImage: "magnifyingglass",
                    isPrimary: true,
                    isEnabled: canRun,
                    help: runHelp
                ) {
                    model.startTest()
                }
            }
        }
    }

    // MARK: Advanced settings

    @ViewBuilder
    private var advancedSettings: some View {
        providerSection
        serversSection
        protocolsSection
        optionsSection
        advancedRunBar
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Client")
            Picker("", selection: $model.providerKind) {
                ForEach(ProviderKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.engine.isRunning)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.status.isDrivable ? style.positive : style.secondaryText.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(statusWording)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let advisory = model.status.advisory {
                Text(advisory)
                    .font(style.smallFont)
                    .foregroundColor(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Servers")
            Picker("", selection: $model.granularity) {
                ForEach(Granularity.allCases) { g in
                    Text(g.title).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.engine.isRunning)
            Text(model.granularity == .city
                 ? "One route per city, however many servers it holds."
                 : "One route per server, each tried on its own.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            searchField

            HStack(spacing: 6) {
                ThemeButton(title: "All Shown", isEnabled: !model.rows.isEmpty, help: "Select every server currently listed.") {
                    model.selectAllVisible()
                }
                ThemeButton(title: "By Country", isEnabled: !model.simpleCountries.isEmpty, help: "Select every server in the countries the simple view is pointed at.") {
                    for country in model.simpleCountries { model.select(country: country) }
                }
                ThemeButton(title: "None", isEnabled: !model.selectedKeys.isEmpty, help: "Select none.") {
                    model.clearSelection()
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.rows) { row in
                        LocationRowView(
                            row: row,
                            isSelected: model.selectedKeys.contains(row.id),
                            granularity: model.granularity
                        ) {
                            toggleKey(row.id)
                        }
                    }
                }
                .padding(4)
            }
            .frame(height: 200)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(style.groupingBackground))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(style.border, lineWidth: 0.5))

            Text("\(model.selectedKeys.count) selected")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
        }
    }

    private var protocolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Protocols")
            Text("Most clients choose a protocol for you and never say which. These are the ones this client accepts.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 5) {
                ForEach(model.protocols) { option in
                    ProtocolCard(
                        option: option,
                        isSelected: model.selectedProtocols.contains(option.id)
                    ) {
                        toggleProtocol(option.id)
                    }
                }
            }

            HStack(spacing: 6) {
                ThemeButton(title: "Common Ports", isEnabled: !model.commonPorts.isEmpty, help: "The ports most protocols share.") {
                    model.selectedPorts = Set(model.commonPorts)
                }
                ThemeButton(title: "All Ports", isEnabled: !model.availablePorts.isEmpty) {
                    model.selectedPorts = Set(model.availablePorts)
                }
                ThemeButton(title: "No Ports", isEnabled: !model.selectedPorts.isEmpty) {
                    model.selectedPorts.removeAll()
                }
            }

            if !model.availablePorts.isEmpty {
                Text("Ports")
                    .font(style.labelFont)
                    .foregroundColor(style.text)
                FlowRow(spacing: 6, lineSpacing: 6) {
                    ForEach(model.availablePorts, id: \.self) { port in
                        PortChip(
                            port: port,
                            isSelected: model.selectedPorts.contains(port),
                            isCommon: model.commonPorts.contains(port)
                        ) {
                            togglePort(port)
                        }
                    }
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Test Settings")

            checkboxRow(
                isChecked: model.options.runFetchProbe,
                title: "Load a real page after each connect",
                help: "After the tunnel is up, fetch a web page through it. This is what catches a route that connects but carries nothing."
            ) { model.options.runFetchProbe.toggle() }

            checkboxRow(
                isChecked: model.options.randomizeOrder,
                title: "Try the routes in a shuffled order",
                help: "Useful for a second pass, so a client that remembers the last server does not bias the result."
            ) { model.options.randomizeOrder.toggle() }

            stepperRow("Connect timeout", value: $model.options.connectTimeout, range: 10...120, step: 5) {
                "\(Int(model.options.connectTimeout))s"
            }
            stepperRow("Ping attempts", value: pingCountBinding, range: 1...20, step: 1) {
                "\(model.options.pingCount)"
            }
            stepperRow("Settle time", value: $model.options.settleSeconds, range: 0...5, step: 0.5) {
                String(format: "%.1fs", model.options.settleSeconds)
            }
            stepperRow("Cooldown", value: $model.options.cooldownSeconds, range: 0...5, step: 0.25) {
                String(format: "%.2fs", model.options.cooldownSeconds)
            }

            TextField("Ping host", text: $model.probeHost)
                .textFieldStyle(.roundedBorder)
                .font(style.smallFont)
                .disabled(model.engine.isRunning)
                .help("The host each route pings once it is up.")
            TextField("Test page URL", text: $model.probeURL)
                .textFieldStyle(.roundedBorder)
                .font(style.smallFont)
                .disabled(model.engine.isRunning)
                .help("The page fetched through each tunnel when the fetch probe is on.")

            ThemeButton(
                title: "Measure With No Tunnel",
                isEnabled: !model.engine.isRunning,
                help: "Take a reference reading of this connection with the tunnel down, to compare the routes against."
            ) {
                model.measureBaseline()
            }

            if let baseline = model.engine.baseline, let ping = baseline.pingMs {
                Text("This connection, tunnel down: \(Int(ping.rounded())) ms ping.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var advancedRunBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Run")
            Text("\(model.targets.count) route\(model.targets.count == 1 ? "" : "s")")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            if !model.targets.isEmpty {
                Text(estimate(model.estimatedSeconds))
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            keepLogQuestion
            if model.engine.isRunning {
                ThemeButton(title: "Stop", isPrimary: true, help: "Stop the test and keep what has been tried so far.") {
                    model.stopTest()
                }
            } else {
                ThemeButton(
                    title: "Run Test",
                    systemImage: "play.fill",
                    isPrimary: true,
                    isEnabled: canRun,
                    help: runHelp
                ) {
                    model.startTest()
                }
            }
        }
    }

    // MARK: - The results column

    @ViewBuilder
    private var resultsColumn: some View {
        if model.uiMode == .simple {
            simpleResults
        } else {
            advancedResults
        }
    }

    private var simpleResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.engine.isRunning {
                    inProgressCard
                } else if model.engine.results.isEmpty {
                    nothingYetCard
                } else if let best = bestResult {
                    winnerCard(best)
                } else {
                    allFailedCard
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inProgressCard: some View {
        ThemePanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trying route \(model.engine.completedCount + 1) of \(model.engine.totalCount)")
                    .font(style.labelFont)
                    .foregroundColor(style.text)
                Text("Leave the app open and let the connection come and go — that is the test working, not a fault.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(model.engine.completedCount), total: Double(max(model.engine.totalCount, 1)))
                Text(model.engine.activity)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nothingYetCard: some View {
        ThemePanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing tried yet")
                    .font(style.labelFont)
                    .foregroundColor(style.text)
                ExplainRow(icon: "1.circle", text: "Choose the countries where the traffic should come out.")
                ExplainRow(icon: "2.circle", text: "Choose how hard it should look — quick, thorough, or careful.")
                ExplainRow(icon: "3.circle", text: "Press the button. The connection will drop and come back while it works.")
                Text("Results appear here, best first, once the run is done.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func winnerCard(_ best: RouteResult) -> some View {
        ThemePanel(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(style.positive)
                    Text("Best route found")
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                    Spacer()
                    Text("\(model.reachableCount) of \(model.engine.results.count) worked")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }

                HStack(spacing: 8) {
                    if let flag = best.target.location.flag {
                        Text(flag).font(.system(size: 18))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routeHeadline(best))
                            .font(style.bodyFont)
                            .foregroundColor(style.text)
                        Text(best.target.routeLabel.uppercased())
                            .font(style.pathFont)
                            .foregroundColor(style.secondaryText)
                    }
                    Spacer()
                    VerdictPill(verdict: best.verdict, colour: verdictColour(best.verdict, style))
                }

                HStack(spacing: 18) {
                    StatTile(label: "Connect", value: seconds(best.connectSeconds))
                    StatTile(label: "Ping", value: milliseconds(best.pingMs), caption: baselineCaption)
                    StatTile(label: "Page", value: seconds(best.fetchSeconds))
                }

                Text(useLine(best))
                    .font(style.smallFont)
                    .foregroundColor(style.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var allFailedCard: some View {
        ThemePanel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not one route came back")
                    .font(style.labelFont)
                    .foregroundColor(style.text)
                Text("All \(model.engine.results.count) routes were tried and none of them carried traffic. Try the Thorough or Careful depth, or pick different countries.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var advancedResults: some View {
        if model.engine.results.isEmpty && !model.engine.isRunning {
            VStack(spacing: 8) {
                Spacer()
                Text("Nothing tested yet")
                    .font(style.bodyFont)
                    .foregroundColor(style.text)
                Text("Pick the servers, protocols and ports on the left, then run the test. Results land here, best first.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                summaryStrip
                if model.engine.isRunning {
                    Divider()
                    runningBar
                }
                Divider()
                sortBar
                Divider()
                resultsTable
                if let selected = selectedResult {
                    Divider()
                    detailBar(selected)
                }
            }
        }
    }

    private var summaryStrip: some View {
        HStack(alignment: .top, spacing: 18) {
            StatTile(label: "Tested", value: "\(model.engine.completedCount)/\(model.engine.totalCount)")
            StatTile(
                label: "Reachable",
                value: "\(model.reachableCount)",
                caption: model.engine.completedCount > 0
                    ? "\(Int((reachableFraction * 100).rounded()))% of tested"
                    : nil
            )
            StatTile(label: "Best route", value: bestResult.map(routeHeadline) ?? "—")
            StatTile(label: "Best ping", value: fastestPing.map { "\(Int($0.rounded())) ms" } ?? "—", caption: baselineCaption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var runningBar: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
            Text(model.engine.phase.title)
                .font(style.smallFont)
                .foregroundColor(style.text)
            if let target = model.engine.currentTarget {
                Text(target.displayLabel)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.engine.activity)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            ProgressView(value: Double(model.engine.completedCount), total: Double(max(model.engine.totalCount, 1)))
                .frame(width: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(style.accent.opacity(0.08))
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            Text(model.engine.results.count == 1 ? "1 route" : "\(model.engine.results.count) routes")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Spacer()
            Text("Order")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Picker("", selection: $sort) {
                ForEach(ResultSort.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var resultsTable: some View {
        Table(sortedResults, selection: $selectedResultID) {
            TableColumn("Location") { (r: RouteResult) in
                HStack(spacing: 6) {
                    if let flag = r.target.location.flag { Text(flag) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.target.location.city.isEmpty ? r.target.location.country : r.target.location.city)
                            .font(style.smallFont)
                            .foregroundColor(style.text)
                            .lineLimit(1)
                        Text(r.target.location.country)
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Route") { (r: RouteResult) in
                Text(r.target.routeLabel.lowercased())
                    .font(style.pathFont)
                    .foregroundColor(style.secondaryText)
            }
            .width(min: 64, ideal: 84)

            TableColumn("Connect") { (r: RouteResult) in metric(seconds(r.connectSeconds)) }
                .width(min: 60, ideal: 74)
            TableColumn("Ping") { (r: RouteResult) in metric(milliseconds(r.pingMs)) }
                .width(min: 52, ideal: 64)
            TableColumn("Loss") { (r: RouteResult) in metric(percent(r.packetLoss)) }
                .width(min: 46, ideal: 58)
            TableColumn("Page") { (r: RouteResult) in metric(seconds(r.fetchSeconds)) }
                .width(min: 50, ideal: 64)

            TableColumn("Verdict") { (r: RouteResult) in
                VerdictPill(verdict: r.verdict, colour: verdictColour(r.verdict, style))
            }
            .width(min: 72, ideal: 86)

            TableColumn("Note") { (r: RouteResult) in
                Text(r.failureReason ?? "")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func metric(_ value: String) -> some View {
        Text(value.isEmpty ? "—" : value)
            .font(style.smallFont)
            .foregroundColor(style.text)
    }

    private func detailBar(_ r: RouteResult) -> some View {
        HStack(alignment: .top, spacing: 18) {
            detail("Connect", seconds(r.connectSeconds))
            detail("Ping", milliseconds(r.pingMs))
            detail("Jitter", milliseconds(r.jitterMs))
            detail("Loss", percent(r.packetLoss))
            detail("Page", seconds(r.fetchSeconds))
            detail("Exit", exitText(r))
            Spacer()
            if let reason = r.failureReason {
                Text(reason)
                    .font(style.smallFont)
                    .foregroundColor(style.negative)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(style.groupingBackground)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Text(value.isEmpty ? "—" : value)
                .font(style.smallFont)
                .foregroundColor(style.text)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.status.isDrivable ? style.positive : style.secondaryText.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(footerStatus)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Spacer()
            AskHousekeeperButton(topic: model.housekeeperTopic, closing: { appState.showRoutes = false })
            ThemeButton(title: "Done", isPrimary: true, help: "Close this screen.") {
                appState.showRoutes = false
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pieces

    private var keepLogQuestion: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                ThemeCheckbox(isChecked: model.keepLog, help: "Append this run to a markdown file.") {
                    model.keepLog.toggle()
                }
                Text("Keep a written log of this run")
                    .font(style.smallFont)
                    .foregroundColor(style.text)
            }
            Text("Writes one file, appended to, at \(RoutePaths.logDirectoryDisplayPath)/route-log.md. Off by default; nothing else is written.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.keepLog {
                ThemeButton(title: "Show the Log Folder", help: "Open Finder at the folder the log lives in.") {
                    model.openLogFolder()
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(style.secondaryText)
            TextField("Search cities and countries", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(style.smallFont)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(style.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(style.groupingBackground))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(style.border, lineWidth: 0.5))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(style.labelFont)
            .foregroundColor(style.text)
    }

    private func checkboxRow(isChecked: Bool, title: String, help: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            ThemeCheckbox(isChecked: isChecked, help: help) { action() }
            Text(title)
                .font(style.smallFont)
                .foregroundColor(style.text)
            Spacer()
        }
        .help(help)
    }

    private func stepperRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping () -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Spacer()
            Text(display())
                .font(style.smallFont)
                .foregroundColor(style.text)
            Stepper(value: value, in: range, step: step) { EmptyView() }
                .labelsHidden()
                .disabled(model.engine.isRunning)
        }
    }

    // MARK: - Small helpers

    private var pingCountBinding: Binding<Double> {
        Binding(
            get: { Double(model.options.pingCount) },
            set: { model.options.pingCount = Int($0.rounded()) }
        )
    }

    private var countryChipItems: [CountryChoice] {
        model.countryChoices.map { CountryChoice(name: $0.name, flag: $0.flag) }
    }

    private var sortedResults: [RouteResult] { sort.apply(model.engine.results) }

    private var bestResult: RouteResult? {
        model.engine.results.filter { $0.verdict != .failed }.min { $0.score < $1.score }
    }

    private var fastestPing: Double? {
        model.engine.results.compactMap(\.pingMs).min()
    }

    private var reachableFraction: Double {
        guard model.engine.completedCount > 0 else { return 0 }
        return Double(model.reachableCount) / Double(model.engine.completedCount)
    }

    private var baselineCaption: String? {
        guard let ping = model.engine.baseline?.pingMs else { return nil }
        return "no tunnel \(Int(ping.rounded())) ms"
    }

    private var selectedResult: RouteResult? {
        guard let id = selectedResultID else { return nil }
        return model.engine.results.first { $0.id == id }
    }

    private var canRun: Bool { model.status.isDrivable && !model.targets.isEmpty }

    private var runHelp: String {
        if !model.status.isDrivable {
            return model.status.installed
                ? "Sign in to \(model.providerKind.displayName) first."
                : "Install the \(model.providerKind.displayName) client first."
        }
        if model.targets.isEmpty { return "Pick at least one location, protocol and port first." }
        return "Start the test. The connection will drop and come back for each route."
    }

    private var targetCountWording: String {
        model.targets.isEmpty
            ? "Nothing to try yet."
            : "\(model.targets.count) route\(model.targets.count == 1 ? "" : "s") to try"
    }

    private var statusWording: String {
        let name = model.providerKind.displayName
        if !model.status.installed { return "\(name) — not installed" }
        if !model.status.loggedIn { return "\(name) — signed out" }
        return model.status.detail.isEmpty ? "\(name) — ready" : "\(name) — \(model.status.detail)"
    }

    private var footerStatus: String {
        let name = model.providerKind.displayName
        let state = model.status.installed ? (model.status.loggedIn ? "ready" : "signed out") : "not installed"
        if model.engine.results.isEmpty { return "\(name): \(state)" }
        return "\(name): \(state) · \(model.reachableCount) of \(model.engine.results.count) routes carried traffic"
    }

    private func routeHeadline(_ r: RouteResult) -> String {
        var parts = [r.target.location.city, r.target.location.country].filter { !$0.isEmpty }
        if !r.target.location.node.isEmpty { parts.append(r.target.location.node) }
        return parts.joined(separator: ", ")
    }

    private func useLine(_ r: RouteResult) -> String {
        "To use it, open \(model.providerKind.displayName) and connect to \(r.target.location.city) over \(r.target.routeLabel.uppercased())."
    }

    private func exitText(_ r: RouteResult) -> String {
        [r.exitIP, r.exitCountry].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func pick(_ names: [String]) {
        let known = Set(model.countries)
        model.simpleCountries.formUnion(names.filter(known.contains))
    }

    private func toggleSimpleCountry(_ name: String) {
        if model.simpleCountries.contains(name) {
            model.simpleCountries.remove(name)
        } else {
            model.simpleCountries.insert(name)
        }
    }

    private func toggleKey(_ id: String) {
        if model.selectedKeys.contains(id) {
            model.selectedKeys.remove(id)
        } else {
            model.selectedKeys.insert(id)
        }
    }

    private func toggleProtocol(_ id: String) {
        if model.selectedProtocols.contains(id) {
            model.selectedProtocols.remove(id)
        } else {
            model.selectedProtocols.insert(id)
        }
    }

    private func togglePort(_ port: Int) {
        if model.selectedPorts.contains(port) {
            model.selectedPorts.remove(port)
        } else {
            model.selectedPorts.insert(port)
        }
    }

    private let simpleNearby = ["Turkey", "United Arab Emirates", "Armenia", "Georgia", "Qatar"]
    private let simplePopular = ["Germany", "Netherlands", "France", "United Kingdom", "United States", "Canada"]
}

// MARK: - Result ordering

private enum ResultSort: String, CaseIterable, Identifiable {
    case best
    case connect
    case ping
    case loss
    case fetch
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: return "Best"
        case .connect: return "Connect"
        case .ping: return "Ping"
        case .loss: return "Loss"
        case .fetch: return "Page"
        case .location: return "Location"
        }
    }

    func apply(_ results: [RouteResult]) -> [RouteResult] {
        switch self {
        case .best: return results.sorted { $0.score < $1.score }
        case .connect: return results.sorted { $0.connectSort < $1.connectSort }
        case .ping: return results.sorted { $0.pingSort < $1.pingSort }
        case .loss: return results.sorted { $0.lossSort < $1.lossSort }
        case .fetch: return results.sorted { $0.fetchSort < $1.fetchSort }
        case .location: return results.sorted { $0.locationSort < $1.locationSort }
        }
    }
}

/// A country as the simple view offers it — a name and, when the client gives a
/// code, a flag. Identifiable by name so `ForEach` can key on it.
private struct CountryChoice: Identifiable {
    let name: String
    let flag: String?
    var id: String { name }
}

// MARK: - Flow layout

/// Lays subviews out left to right, wrapping to a new line when the next one
/// would not fit. Hand-rolled because the native flow layout arrived after the
/// deployment target this app builds for.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? widest : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Small components

private struct StepBadge: View {
    @Environment(\.uiStyle) private var style
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 16, height: 16)
                .background(Circle().fill(style.accent.opacity(0.16)))
                .foregroundColor(style.accent)
            Text(title)
                .font(style.labelFont)
                .foregroundColor(style.text)
        }
    }
}

private struct CountryChip: View {
    @Environment(\.uiStyle) private var style
    let name: String
    let flag: String?
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                if let flag { Text(flag) }
                Text(name)
                    .font(style.smallFont)
                    .foregroundColor(style.text)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? style.rowSelection : style.groupingBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? style.accent : style.border, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Chosen. Press to remove \(name)." : "Add \(name).")
    }
}

private struct PortChip: View {
    @Environment(\.uiStyle) private var style
    let port: Int
    let isSelected: Bool
    let isCommon: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Text("\(port)")
                    .font(style.pathFont)
                    .foregroundColor(style.text)
                if isCommon {
                    Circle()
                        .fill(style.accent.opacity(isSelected ? 1 : 0.5))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? style.rowSelection : style.groupingBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? style.accent : style.border, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(isCommon ? "Port \(port) — shared by most protocols." : "Port \(port).")
    }
}

private struct ProtocolCard: View {
    @Environment(\.uiStyle) private var style
    let option: ProtocolOption
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? style.accent : style.secondaryText)
                    Text(option.title)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                    Spacer()
                }
                if !option.note.isEmpty {
                    Text(option.note)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? style.rowSelection : style.groupingBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? style.accent : style.border, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LocationRowView: View {
    @Environment(\.uiStyle) private var style
    let row: LocationRow
    let isSelected: Bool
    let granularity: Granularity
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? style.accent : style.secondaryText)
                if let flag = row.flag { Text(flag) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.representative.city.isEmpty ? row.representative.country : row.representative.city)
                        .font(style.smallFont)
                        .foregroundColor(style.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? style.rowSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts = [row.representative.country]
        if granularity == .city {
            if row.isMultiNode { parts.append("\(row.nodeCount) servers") }
        } else if !row.representative.node.isEmpty {
            parts.append(row.representative.node)
        }
        return parts.joined(separator: " · ")
    }
}

private struct VerdictPill: View {
    let verdict: RouteVerdict
    let colour: Color

    var body: some View {
        Text(verdict.title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.16)))
            .overlay(Capsule().strokeBorder(colour.opacity(0.35), lineWidth: 0.5))
            .foregroundColor(colour)
    }
}

private struct StatTile: View {
    @Environment(\.uiStyle) private var style
    let label: String
    let value: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Text(value)
                .font(style.bodyFont)
                .foregroundColor(style.text)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExplainRow: View {
    @Environment(\.uiStyle) private var style
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(style.accent)
                .frame(width: 16)
            Text(text)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Formatting

private func verdictColour(_ verdict: RouteVerdict, _ style: UIStyle) -> Color {
    switch verdict {
    case .excellent, .good: return style.positive
    case .usable: return style.accent
    case .poor: return style.caution
    case .failed: return style.negative
    }
}

private func seconds(_ value: Double?) -> String {
    value.map { String(format: "%.2f s", $0) } ?? ""
}

private func milliseconds(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded())) ms" } ?? ""
}

private func percent(_ value: Double?) -> String {
    value.map { String(format: "%.0f%%", $0 * 100) } ?? ""
}

private func estimate(_ total: Double) -> String {
    if total < 60 { return "≈ \(Int(total.rounded()))s" }
    return "≈ \(Int((total / 60).rounded())) min"
}
