import AppKit
import Combine
import Foundation
import SwiftUI

/// The state behind the Routes screen.
///
/// Routes tries every server, protocol and port a VPN client offers, one at a
/// time, and measures how well each one carries traffic. This holds everything
/// that screen needs: which client, which places, which protocols and ports,
/// the settings a run uses, and the two interfaces that drive it. The run
/// itself lives in `RouteEngine`; this only decides what to hand it.
///
/// Nothing here touches disk except the written log, and that only when the
/// reader asks for it.
@MainActor
final class RoutesModel: ObservableObject {

    // MARK: - Provider

    @Published var providerKind: ProviderKind = .windscribe {
        didSet {
            guard providerKind != oldValue else { return }
            resetForProviderChange()
        }
    }
    @Published private(set) var status: ProviderStatus = .unavailable
    @Published private(set) var isRefreshing = false

    // MARK: - Where the traffic can come out

    @Published private(set) var locations: [VPNLocation] = []
    @Published var selectedKeys: Set<String> = []
    @Published var searchText: String = ""
    @Published var granularity: Granularity = .city {
        didSet {
            guard granularity != oldValue else { return }
            // Selection keys are not comparable across granularities.
            selectedKeys.removeAll()
        }
    }

    // MARK: - Protocols and ports

    @Published private(set) var protocols: [ProtocolOption] = []
    @Published var selectedProtocols: Set<String> = ["tcp"]
    @Published var selectedPorts: Set<Int> = [443]

    // MARK: - How the test is run

    @Published var options = RouteOptions()
    @Published var probeHost: String = "1.1.1.1"
    @Published var probeURL: String = "https://www.cloudflare.com/cdn-cgi/trace"

    // MARK: - Messaging

    @Published var banner: String?

    // MARK: - Which interface is on screen

    /// Simple chooses the settings for the reader; Advanced exposes every
    /// control. Held for the length of the screen only — it is not remembered
    /// between visits, so the screen always opens on the plain one.
    @Published var uiMode: UIMode = .simple {
        didSet {
            guard uiMode != oldValue else { return }
            prepareSimpleMode()
        }
    }

    /// The countries the simple interface is pointed at, by display name.
    @Published var simpleCountries: Set<String> = [] {
        didSet {
            guard simpleCountries != oldValue else { return }
            applySimpleCountries()
        }
    }

    @Published var simpleDepth: RouteDepth = .quick {
        didSet {
            guard simpleDepth != oldValue else { return }
            applySimplePreset()
        }
    }

    // MARK: - The written log

    static let keepLogDefaultsKey = "housekeeping.routes.keepLog"

    /// Whether a run should leave a markdown record of itself behind. Off by
    /// default: it writes a file outside the app, so it is the reader's call.
    @Published var keepLog: Bool =
        UserDefaults.standard.bool(forKey: keepLogDefaultsKey) {
        didSet {
            guard keepLog != oldValue else { return }
            UserDefaults.standard.set(keepLog, forKey: Self.keepLogDefaultsKey)
        }
    }

    /// A spread of nearby and well-connected countries, used only until the
    /// reader picks for themselves.
    static let starterCountries = [
        "Turkey", "United Arab Emirates", "Armenia", "Georgia",
        "Germany", "Netherlands", "France", "Qatar",
    ]

    let engine = RouteEngine()

    private var provider: any VPNProvider { ProviderRegistry.provider(for: providerKind) }
    private var hasLoaded = false

    /// The engine is a second object, and the screen reads its progress on every
    /// frame. Nothing forwards an engine change to this model by default, so a
    /// run would advance without the screen redrawing. Re-emitting here is what
    /// keeps `engine.isRunning`, the counts and the results live.
    private var engineSink: AnyCancellable?

    init() {
        engineSink = engine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Lifecycle

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refreshAll()
    }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let active = provider
        status = await active.probeStatus()
        locations = await active.loadLocations()
        protocols = await active.protocolOptions()

        // Drop selections that this client does not offer.
        let validProtocols = Set(protocols.map(\.id))
        selectedProtocols.formIntersection(validProtocols)
        if selectedProtocols.isEmpty, let first = protocols.first {
            selectedProtocols = [first.id]
        }
        selectedPorts.formIntersection(Set(availablePorts))

        if locations.isEmpty, status.installed {
            banner = "No server list came back from \(active.displayName)."
        } else if !status.installed {
            banner = status.detail
        }

        // A simple-mode preset applied before the protocol list arrived would
        // have pinned ports nothing offers, so it is re-derived here.
        prepareSimpleMode()
    }

    // MARK: - The simple interface

    /// Everything the simple interface needs in place: somewhere to look, and
    /// settings that match the depth it is set to.
    func prepareSimpleMode() {
        guard uiMode == .simple else { return }

        if simpleCountries.isEmpty {
            let known = Set(countries)
            simpleCountries.formUnion(Self.starterCountries.filter(known.contains))
            // Nothing off the starter list is on offer; take a few rather than
            // leaving the reader facing a dead button.
            if simpleCountries.isEmpty { simpleCountries.formUnion(countries.prefix(4)) }
        }

        applySimplePreset()
    }

    /// Turns the three simple choices into the engine's real settings.
    func applySimplePreset() {
        let depth = simpleDepth
        granularity = depth == .quick ? .city : .datacenter

        let supported = Set(protocols.map(\.id))
        var wanted: Set<String>
        switch depth {
        case .quick: wanted = ["tcp"]
        case .thorough: wanted = ["tcp", "udp"]
        case .careful: wanted = supported
        }
        wanted.formIntersection(supported)
        selectedProtocols = wanted.isEmpty ? supported : wanted

        // Derived from the protocol choice above, so it is read after it.
        if availablePorts.isEmpty {
            // Client with no port axis: one route per protocol.
            selectedPorts = []
        } else {
            let preferred: Set<Int>
            switch depth {
            case .quick: preferred = [443]
            case .thorough: preferred = [443, 80, 1194]
            case .careful: preferred = Set(commonPorts)
            }
            let pinned = preferred.intersection(Set(availablePorts))
            selectedPorts = pinned.isEmpty ? Set(availablePorts) : pinned
        }

        switch depth {
        case .quick:
            options.runFetchProbe = false
            options.pingCount = 3
            options.settleSeconds = 0
        case .thorough:
            options.runFetchProbe = true
            options.pingCount = 4
            options.settleSeconds = 0.5
        case .careful:
            options.runFetchProbe = true
            options.pingCount = 8
            options.settleSeconds = 1.5
        }
        options.randomizeOrder = false

        applySimpleCountries()
    }

    /// Re-applies the simple picks. Selection keys are not comparable across
    /// granularities, so this runs again after any change to either.
    func applySimpleCountries() {
        searchText = ""
        selectedKeys.removeAll()
        let known = Set(countries)
        for country in simpleCountries.sorted() where known.contains(country) {
            select(country: country)
        }
    }

    /// Countries the client offers, each with a flag where it has a code.
    var countryChoices: [(name: String, flag: String?)] {
        var flags: [String: String] = [:]
        for loc in locations {
            if flags[loc.country] == nil, let flag = loc.flag { flags[loc.country] = flag }
        }
        return countries.map { (name: $0, flag: flags[$0]) }
    }

    private func resetForProviderChange() {
        selectedKeys.removeAll()
        selectedProtocols = []
        selectedPorts = []
        locations = []
        protocols = []
        status = .unavailable
        banner = nil
        engine.clearResults()
        Task { await refreshAll() }
    }

    // MARK: - Locations

    /// Every location the client can be tried against, grouped and filtered.
    var rows: [LocationRow] { groupedRows(matching: searchText) }

    /// Pure, so it can be called from a view body without touching published
    /// state. A getter that wrote to `searchText` to see the unfiltered list
    /// would re-invalidate the view on every read and never settle.
    private func groupedRows(matching query: String) -> [LocationRow] {
        let grouped: [LocationRow]

        switch granularity {
        case .city:
            var byCity: [String: [VPNLocation]] = [:]
            for loc in locations {
                byCity["\(loc.countryCode)|\(loc.city)", default: []].append(loc)
            }
            grouped = byCity.map { key, members in
                LocationRow(id: key, representative: members[0], members: members)
            }
        case .datacenter:
            grouped = locations.map {
                LocationRow(id: $0.id, representative: $0, members: [$0])
            }
        }

        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? grouped : grouped.filter {
            $0.representative.city.lowercased().contains(needle)
                || $0.representative.country.lowercased().contains(needle)
                || $0.representative.node.lowercased().contains(needle)
                || $0.members.contains { $0.node.lowercased().contains(needle) }
        }

        return filtered.sorted {
            ($0.representative.country, $0.representative.city)
                < ($1.representative.country, $1.representative.city)
        }
    }

    var countries: [String] {
        Array(Set(locations.map(\.country))).sorted()
    }

    func selectAllVisible() {
        selectedKeys.formUnion(rows.map(\.id))
    }

    func select(country: String) {
        let keys = rows.filter { $0.country == country }.map(\.id)
        selectedKeys.formUnion(keys)
    }

    func clearSelection() { selectedKeys.removeAll() }

    var selectedRows: [LocationRow] {
        let index = Dictionary(uniqueKeysWithValues: rowsForSelection.map { ($0.id, $0) })
        return selectedKeys.compactMap { index[$0] }
    }

    /// Built from the unfiltered list so that narrowing the search box does
    /// not silently drop locations that are already selected.
    private var rowsForSelection: [LocationRow] { groupedRows(matching: "") }

    // MARK: - Ports

    /// Ports offered by at least one selected protocol.
    var availablePorts: [Int] {
        let ports = protocols
            .filter { selectedProtocols.contains($0.id) }
            .flatMap(\.ports)
        return Array(Set(ports)).sorted()
    }

    /// Ports that appear in most protocols — the ones worth trying first.
    var commonPorts: [Int] {
        let counts = protocols
            .filter { selectedProtocols.contains($0.id) }
            .flatMap(\.ports)
            .reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        return counts.filter { $0.value >= 3 }.keys.sorted()
    }

    // MARK: - The list of routes to try

    var targets: [RouteTarget] {
        let rows = selectedRows
        guard !rows.isEmpty, !selectedProtocols.isEmpty else { return [] }
        let active = provider
        var out: [RouteTarget] = []
        var seen = Set<String>()

        for row in rows {
            let pins: [(VPNLocation, String)] = granularity == .city
                ? [(row.representative, row.representative.cityConnectID)]
                : row.members.map { ($0, $0.connectID) }

            for (location, identifier) in pins {
                for proto in protocols where selectedProtocols.contains(proto.id) {
                    if proto.ports.isEmpty {
                        // Client with no port axis.
                        append(&out, &seen, RouteTarget(
                            provider: active.kind, location: location,
                            identifier: identifier, proto: proto.id, port: nil
                        ))
                    } else {
                        for port in proto.ports where selectedPorts.contains(port) {
                            append(&out, &seen, RouteTarget(
                                provider: active.kind, location: location,
                                identifier: identifier, proto: proto.id, port: port
                            ))
                        }
                    }
                }
            }
        }
        return out
    }

    private func append(_ out: inout [RouteTarget], _ seen: inout Set<String>, _ target: RouteTarget) {
        guard !seen.contains(target.id) else { return }
        seen.insert(target.id)
        out.append(target)
    }

    /// Rough wall-clock estimate: connect plus probes plus teardown per route.
    var estimatedSeconds: Double {
        let perRoute = min(options.connectTimeout, 14)
            + options.settleSeconds
            + Double(options.pingCount) * 0.5
            + (options.runFetchProbe ? 2.5 : 0)
            + options.cooldownSeconds
            + 1.0
        return Double(targets.count) * perRoute
    }

    /// How many of the tested routes carried traffic.
    var reachableCount: Int {
        engine.results.filter { $0.verdict != .failed }.count
    }

    // MARK: - Running

    func startTest() {
        let list = targets
        guard !list.isEmpty else {
            banner = "Pick at least one location, protocol and port first."
            return
        }
        banner = nil
        engine.onFinish = { [weak self] completed in
            self?.testDidFinish(completed: completed)
        }
        engine.start(
            provider: provider, targets: list, options: options,
            probeHost: probeHost, probeURL: probeURL
        )
    }

    /// Everything the log needs is already in the engine; this only decides
    /// whether to write it.
    private func testDidFinish(completed: Bool) {
        guard keepLog else { return }
        let run = currentRun()
        guard !run.results.isEmpty else { return }
        do {
            let url = try RouteLog.append(run)
            banner = completed
                ? "Run logged to \(RoutePaths.logDirectoryDisplayPath)/\(url.lastPathComponent)"
                : "Logged the \(run.results.count) routes tested before you stopped."
        } catch {
            banner = "The run finished, but its log could not be written: \(error.localizedDescription)"
        }
    }

    func openLogFolder() {
        try? FileManager.default.createDirectory(
            at: RoutePaths.logDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RoutePaths.logDirectory)
    }

    func stopTest() { engine.stop() }

    func measureBaseline() {
        engine.measureBaseline(probeHost: probeHost, probeURL: probeURL, options: options)
    }

    // MARK: - Refreshing the server list

    func refreshWindscribeLocations() {
        guard providerKind == .windscribe else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let count = try await WindscribeProvider.refreshLocations()
                locations = await WindscribeProvider().loadLocations()
                banner = "Server list refreshed: \(count) datacenters."
            } catch {
                banner = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    // MARK: - The run so far

    func currentRun() -> RouteRun {
        RouteRun(
            startedAt: engine.startedAt ?? Date(),
            provider: providerKind,
            baseline: engine.baseline,
            results: engine.results
        )
    }

    // MARK: - What the housekeeper is asked about

    /// The subject this screen hands the housekeeper, built from the run on
    /// screen so the facts follow what the reader is looking at.
    var housekeeperTopic: HousekeeperTopic {
        HousekeeperTopic.routes(
            provider: providerKind.displayName,
            running: engine.isRunning,
            tested: engine.completedCount,
            total: engine.totalCount,
            reachable: reachableCount
        )
    }
}
