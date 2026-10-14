import Foundation

/// A measurement taken with no tunnel up, for comparison against the routes.
struct BaselineSample: Codable, Sendable {
    var pingMs: Double?
    var jitterMs: Double?
    var packetLoss: Double?
    var fetchSeconds: Double?
    var fetchSucceeded: Bool = false
    var testedAt: Date = Date()
}

/// Drives a provider through a list of routes, one at a time.
///
/// Sequential by necessity: a VPN client holds one tunnel, so two connects
/// cannot overlap without the second tearing down the first. Everything that
/// varies between providers lives behind `VPNProvider`; what is left here is
/// the timing, the polling and the ordering.
@MainActor
final class RouteEngine: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var phase: RoutePhase = .idle
    @Published private(set) var currentTarget: RouteTarget?
    @Published private(set) var results: [RouteResult] = []
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var activity: String = ""
    @Published private(set) var baseline: BaselineSample?
    @Published private(set) var startedAt: Date?
    @Published var errorMessage: String?

    /// Called once when a run ends, after the app has been returned to its
    /// resting state. The flag is `true` when the run reached the end and
    /// `false` when the user stopped it part-way.
    var onFinish: ((Bool) -> Void)?

    private var task: Task<Void, Never>?

    /// How often the tunnel state is re-read while waiting for it to settle.
    private let pollInterval: Double = 0.25

    // MARK: - Public control

    func start(
        provider: any VPNProvider,
        targets: [RouteTarget],
        options: RouteOptions,
        probeHost: String,
        probeURL: String
    ) {
        guard !isRunning, !targets.isEmpty else { return }

        results = []
        completedCount = 0
        totalCount = targets.count
        errorMessage = nil
        startedAt = Date()
        isRunning = true

        let order = options.randomizeOrder ? targets.shuffled() : targets

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(provider: provider, targets: order,
                           options: options, probeHost: probeHost, probeURL: probeURL)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        phase = .idle
        activity = "Stopped"
    }

    /// Measure the network with no tunnel up, so every route has a reference.
    func measureBaseline(probeHost: String, probeURL: String, options: RouteOptions) {
        guard !isRunning else { return }
        isRunning = true
        phase = .measuring
        activity = "Measuring this connection with no tunnel…"

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.phase = .idle; self.activity = "" }

            let ping = await RouteProbes.ping(host: probeHost, count: options.pingCount,
                                              timeout: options.connectTimeout)
            var sample = BaselineSample(
                pingMs: ping?.avgMs, jitterMs: ping?.stddevMs, packetLoss: ping?.loss
            )
            if options.runFetchProbe {
                let fetch = await RouteProbes.fetch(url: probeURL, timeout: 15)
                sample.fetchSeconds = fetch?.seconds
                sample.fetchSucceeded = fetch?.succeeded ?? false
            }
            if !Task.isCancelled { self.baseline = sample }
        }
    }

    func clearResults() {
        guard !isRunning else { return }
        results = []
        completedCount = 0
        totalCount = 0
        currentTarget = nil
    }

    // MARK: - The run

    private func run(
        provider: any VPNProvider,
        targets: [RouteTarget],
        options: RouteOptions,
        probeHost: String,
        probeURL: String
    ) async {
        defer {
            let completed = !Task.isCancelled
            isRunning = false
            phase = .idle
            currentTarget = nil
            onFinish?(completed)
        }

        // Start from a known state; a tunnel left up by an earlier run would
        // make the first connect a no-op and its timing meaningless.
        await provider.disconnect()
        _ = await waitForSettled(provider, target: .disconnected,
                                 timeout: 12, options: options)

        for (index, target) in targets.enumerated() {
            if Task.isCancelled { break }

            currentTarget = target
            activity = "Route \(index + 1) of \(targets.count)"
            phase = .connecting

            var result = RouteResult(target: target)
            let failure = await sweep(provider: provider, target: target,
                                      options: options, probeHost: probeHost,
                                      probeURL: probeURL, into: &result)

            if Task.isCancelled { break }
            result.failureReason = failure
            results.append(result)
            completedCount = index + 1

            phase = .cooling
            if options.cooldownSeconds > 0, index < targets.count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(options.cooldownSeconds * 1_000_000_000))
            }
        }

        // Never leave the machine on a route the user did not pick.
        phase = .disconnecting
        await provider.disconnect()
        _ = await waitForSettled(provider, target: .disconnected, timeout: 12, options: options)
        activity = Task.isCancelled ? "Stopped" : "Finished"
    }

    /// Returns a failure description, or nil when the route came up.
    private func sweep(
        provider: any VPNProvider,
        target: RouteTarget,
        options: RouteOptions,
        probeHost: String,
        probeURL: String,
        into result: inout RouteResult
    ) async -> String? {

        do {
            try await provider.prepare(target)
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        if Task.isCancelled { return "Cancelled" }

        let started = Date()
        do {
            try await provider.beginConnect(target)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            result.connectSeconds = nil
            return message
        }

        let connected = await waitForSettled(
            provider, target: .connected, timeout: options.connectTimeout, options: options
        )
        if !connected {
            let state = await provider.tunnelState()
            result.connectSeconds = nil
            return "Did not connect within \(Int(options.connectTimeout))s (state: \(state.rawValue))"
        }

        result.connectSeconds = Date().timeIntervalSince(started)
        if Task.isCancelled { return "Cancelled" }

        // Give the interface a moment to take routes and DNS before probing,
        // or the first packets race the tunnel and look like packet loss.
        if options.settleSeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(options.settleSeconds * 1_000_000_000))
        }
        if Task.isCancelled { return "Cancelled" }

        phase = .measuring
        if let ping = await RouteProbes.ping(host: probeHost, count: options.pingCount,
                                             timeout: 12) {
            result.pingMs = ping.received > 0 ? ping.avgMs : nil
            result.jitterMs = ping.stddevMs
            result.packetLoss = ping.loss
        }
        if Task.isCancelled { return "Cancelled" }

        if options.runFetchProbe {
            let fetch = await RouteProbes.fetch(url: probeURL, timeout: 20)
            result.fetchSeconds = fetch?.seconds
            result.fetchSucceeded = fetch?.succeeded ?? false
            result.exitIP = fetch?.exitIP
            result.exitCountry = fetch?.exitCountry
            if !result.fetchSucceeded, result.pingMs == nil {
                phase = .disconnecting
                await provider.disconnect()
                _ = await waitForSettled(provider, target: .disconnected,
                                         timeout: 12, options: options)
                return "Tunnel came up but carried no traffic"
            }
        } else {
            // Without the fetch probe, ping is the only evidence available.
            result.fetchSucceeded = result.pingMs != nil && (result.packetLoss ?? 1) < 1.0
        }

        phase = .disconnecting
        await provider.disconnect()
        _ = await waitForSettled(provider, target: .disconnected, timeout: 12, options: options)
        return nil
    }

    // MARK: - Waiting

    /// Polls until the tunnel reports the state we want, or the deadline passes.
    private func waitForSettled(
        _ provider: any VPNProvider,
        target: TunnelState,
        timeout: Double,
        options: RouteOptions
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            let state = await provider.tunnelState()
            if state == target { return true }
            // A route that has fallen back to Disconnected will never reach
            // Connected, so stop burning the deadline. Confirmed one poll
            // later, because providers report Disconnected for a beat before
            // they flip to Connecting.
            if target == .connected, state == .disconnected,
               await confirmStillDisconnected(provider) {
                return false
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return false
    }

    /// A single extra look, one poll later, to be sure the state really is
    /// settled rather than mid-transition.
    private func confirmStillDisconnected(_ provider: any VPNProvider) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 2 * 1_000_000_000))
        return await provider.tunnelState() == .disconnected
    }
}
