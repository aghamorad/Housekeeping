import Foundation

// MARK: - Providers

enum ProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case windscribe
    case expressvpn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .windscribe: return "Windscribe"
        case .expressvpn: return "ExpressVPN"
        }
    }

    var supportsPorts: Bool {
        switch self {
        case .windscribe: return true
        case .expressvpn: return false
        }
    }
}

// MARK: - Locations

struct VPNLocation: Identifiable, Hashable, Codable, Sendable {
    /// Unique among the provider's locations, but not necessarily what the
    /// CLI wants to be handed — that is `connectID`.
    let id: String
    let city: String
    /// Datacenter / node nickname, when the provider distinguishes one.
    let node: String
    let country: String
    let countryCode: String
    let continent: String
    let isPremium: Bool

    var label: String {
        node.isEmpty ? city : "\(city) — \(node)"
    }

    /// What to pass the provider's CLI to pin *this* machine.
    var connectID: String { node.isEmpty ? city : node }

    /// What to pass to get any machine in this city.
    var cityConnectID: String { city }

    /// Two-letter code for a flag, when the provider supplies one.
    var flag: String? {
        guard countryCode.count == 2 else { return nil }
        let base: UInt32 = 0x1F1E6
        var scalars = String.UnicodeScalarView()
        for ch in countryCode.uppercased().unicodeScalars {
            guard let s = UnicodeScalar(base + ch.value - 65) else { return nil }
            scalars.append(s)
        }
        return String(scalars)
    }
}

// MARK: - Routes

struct RouteTarget: Identifiable, Hashable, Codable, Sendable {
    let provider: ProviderKind
    let location: VPNLocation
    /// The exact string handed to the provider CLI — a nickname when the
    /// run is pinned per datacenter, a city or region otherwise.
    let identifier: String
    let proto: String
    /// Nil for providers with no port axis (ExpressVPN).
    let port: Int?

    var id: String {
        let portPart = port.map { ":\($0)" } ?? ""
        return "\(provider.rawValue)|\(identifier)|\(proto)\(portPart)"
    }

    var routeLabel: String {
        port.map { "\(proto):\($0)" } ?? proto
    }

    var displayLabel: String {
        "\(location.city)\(location.node.isEmpty ? "" : " (\(location.node))") · \(routeLabel.uppercased())"
    }
}

// MARK: - Protocol descriptions

struct ProtocolOption: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let note: String
    /// Ports the provider itself reports as available for this protocol.
    let ports: [Int]
}

// MARK: - Measurements

enum RouteVerdict: String, Codable, Sendable {
    case excellent
    case good
    case usable
    case poor
    case failed

    var title: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .usable: return "Usable"
        case .poor: return "Poor"
        case .failed: return "Failed"
        }
    }
}

struct RouteResult: Identifiable, Hashable, Codable, Sendable {
    var id: String { target.id }
    let target: RouteTarget
    /// Seconds from issuing connect to the tunnel reporting Connected.
    var connectSeconds: Double?
    /// Round-trip time to the first probe host, milliseconds.
    var pingMs: Double?
    /// Jitter across the ping sample, milliseconds.
    var jitterMs: Double?
    /// Packet loss across the ping sample, 0...1.
    var packetLoss: Double?
    /// Seconds for a real TLS fetch through the tunnel.
    var fetchSeconds: Double?
    /// Whether the fetch actually returned data.
    var fetchSucceeded: Bool = false
    /// Where the traffic actually left from, as the fetch probe saw it. Nil
    /// when the probe never completed.
    var exitIP: String?
    var exitCountry: String?
    /// First line of whatever the provider said on failure.
    var failureReason: String?
    var testedAt: Date = Date()

    var verdict: RouteVerdict {
        if failureReason != nil || !fetchSucceeded { return .failed }
        guard let ping = pingMs else { return .failed }
        let loss = packetLoss ?? 0
        if loss > 0.5 { return .failed }
        if loss > 0 && ping > 400 { return .poor }
        if ping < 80 && loss == 0 { return .excellent }
        if ping < 180 && loss == 0 { return .good }
        if ping < 400 { return .usable }
        return .poor
    }

    /// Lower is better. Failed routes sort to the bottom.
    var score: Double {
        guard verdict != .failed else { return .greatestFiniteMagnitude }
        let connect = connectSeconds ?? 30
        let ping = pingMs ?? 900
        let loss = packetLoss ?? 1
        let fetch = fetchSeconds ?? 9
        return connect * 1.0 + ping * 0.5 + loss * 400 + fetch * 30
    }

    // MARK: - Ordering

    // Non-optional shadows, so a column can be ordered without every value
    // being unwrapped. A missing measurement sinks to the bottom rather than
    // sorting as if it were zero.

    var connectSort: Double { connectSeconds ?? .greatestFiniteMagnitude }
    var pingSort: Double { pingMs ?? .greatestFiniteMagnitude }
    var lossSort: Double { packetLoss ?? .greatestFiniteMagnitude }
    var fetchSort: Double { fetchSeconds ?? .greatestFiniteMagnitude }
    var locationSort: String {
        "\(target.location.country)|\(target.location.city)|\(target.location.node)"
    }

    var verdictRank: Int {
        switch verdict {
        case .excellent: return 0
        case .good: return 1
        case .usable: return 2
        case .poor: return 3
        case .failed: return 4
        }
    }
}

// MARK: - Provider runtime status

/// Provider CLIs each name their states differently; everything inside this
/// module speaks this one vocabulary.
enum TunnelState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case unknown

    var isSettled: Bool { self == .connected || self == .disconnected }

    static func parse(_ raw: String) -> TunnelState {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return .unknown }
        if s.contains("disconnect") && !s.contains("ing") { return .disconnected }
        if s.contains("reconnect") || s.contains("connecting") || s == "interrupted" {
            return .connecting
        }
        if s.contains("disconnect") { return .disconnecting }
        if s.contains("connected") { return .connected }
        if s.contains("disconnected") { return .disconnected }
        return .unknown
    }
}

struct ProviderStatus: Sendable {
    var cliPath: String?
    var installed: Bool
    var loggedIn: Bool
    /// Everything else worth showing in the UI.
    var detail: String
    var tunnel: TunnelState = .unknown
    var publicIP: String?
    /// Provider-specific warnings the user has to act on (e.g. ExpressVPN's
    /// daemon not running). Shown prominently, never auto-fixed.
    var advisory: String?

    var isDrivable: Bool { installed && loggedIn }

    static let unavailable = ProviderStatus(
        cliPath: nil, installed: false, loggedIn: false,
        detail: "Client not found"
    )
}

// MARK: - Run configuration

struct RouteOptions: Codable, Sendable {
    var connectTimeout: Double = 45
    var pingCount: Int = 4
    var runFetchProbe: Bool = true
    var settleSeconds: Double = 1.0
    /// Sleep between routes, so a provider's daemon can fully let go of the
    /// previous tunnel before the next connect lands.
    var cooldownSeconds: Double = 0.75
    var randomizeOrder: Bool = false
}

enum RoutePhase: Equatable, Sendable {
    case idle
    case connecting
    case measuring
    case disconnecting
    case cooling

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .measuring: return "Measuring"
        case .disconnecting: return "Disconnecting"
        case .cooling: return "Cooldown"
        }
    }
}

// MARK: - A completed pass

struct RouteRun: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var provider: ProviderKind
    var baseline: BaselineSample?
    var results: [RouteResult]

    var best: RouteResult? {
        results.filter { $0.verdict != .failed }.min { $0.score < $1.score }
    }
}

// MARK: - Interface choices

/// How finely the server list is broken up. A city usually has several
/// datacenters behind it, and they do not fail together — testing each one
/// separately is often what finds the route that works best.
enum Granularity: String, CaseIterable, Identifiable {
    case city
    case datacenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .city: return "One per city"
        case .datacenter: return "Every datacenter"
        }
    }
}

/// Which of the two interfaces is on screen. Simple is for someone who has
/// never had a reason to think about protocols or ports; it drives the same
/// engine, on settings chosen for them.
enum UIMode: String, CaseIterable, Identifiable {
    case simple
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        }
    }
}

/// How much work the simple interface is allowed to do on the user's behalf.
/// Each one is a real preset over granularity, protocols, ports and probes.
enum RouteDepth: String, CaseIterable, Identifiable {
    case quick
    case thorough
    case careful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick"
        case .thorough: return "Thorough"
        case .careful: return "Careful"
        }
    }

    var blurb: String {
        switch self {
        case .quick:
            return "One server per city, over the settings almost everything accepts. "
                + "Minutes rather than an hour."
        case .thorough:
            return "Every datacenter in the countries below, over both TCP and UDP. "
                + "This is what finds the routes the quick pass misses."
        case .careful:
            return "Everything Thorough does, plus a real page load through each tunnel. "
                + "Slower, and it is the one that catches a route which connects but carries nothing."
        }
    }
}

/// One selectable line in the server list. In city mode this stands for every
/// datacenter in that city; in datacenter mode for a single machine.
struct LocationRow: Identifiable, Hashable {
    let id: String
    let representative: VPNLocation
    let members: [VPNLocation]

    var nodeCount: Int { members.count }
    var isMultiNode: Bool { members.count > 1 }
    var country: String { representative.country }
    var flag: String? { representative.flag }
}
