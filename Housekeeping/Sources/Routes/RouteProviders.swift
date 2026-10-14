import Foundation

/// One VPN client, driven through its own CLI.
///
/// The route engine knows nothing about Windscribe or ExpressVPN beyond this
/// interface, so a third provider is a new conforming type plus one line in
/// `ProviderRegistry.all` — nothing in the engine or the UI changes.
protocol VPNProvider: Sendable {

    var kind: ProviderKind { get }
    var displayName: String { get }

    /// Is the client present, is the account signed in, what is the tunnel doing.
    func probeStatus() async -> ProviderStatus

    /// The server list this provider can be tested against.
    func loadLocations() async -> [VPNLocation]

    /// Protocols the client will actually accept, with whatever ports it
    /// reports for them. Empty `ports` means the provider has no port axis.
    func protocolOptions() async -> [ProtocolOption]

    /// Anything that must be set before a connect lands — ExpressVPN has to
    /// have its protocol chosen, Windscribe takes it inline.
    func prepare(_ target: RouteTarget) async throws

    /// Issue the connect. Must return promptly rather than block until the
    /// tunnel is up, so the engine can time the transition itself.
    func beginConnect(_ target: RouteTarget) async throws

    func disconnect() async
    func tunnelState() async -> TunnelState

    /// The address the world sees. Differs from the plain address when the
    /// tunnel is really carrying traffic.
    func publicIP() async -> String?
}

extension VPNProvider {
    func prepare(_ target: RouteTarget) async throws {}
    func publicIP() async -> String? { nil }
}

enum ProviderRegistry {
    static let all: [any VPNProvider] = [
        WindscribeProvider(),
        ExpressVPNProvider(),
    ]

    static func provider(for kind: ProviderKind) -> any VPNProvider {
        all.first { $0.kind == kind } ?? WindscribeProvider()
    }
}

// MARK: - Shared CLI output handling

enum CLIOutput {

    /// Windscribe writes a JSON log record per line ahead of the real payload.
    /// The payload is *also* embedded inside those records, escaped, so the
    /// cleanest way to read it is to drop the records and keep what is left.
    static func stripLogLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pull `Key: value` pairs out of a status block, case-insensitively.
    static func keyValuePairs(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty { out[key] = value }
        }
        return out
    }

    /// `"443, 587, 21"` → `[443, 587, 21]`
    static func parseIntList(_ text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}

// MARK: - Windscribe

struct WindscribeProvider: VPNProvider {

    let kind: ProviderKind = .windscribe
    let displayName = "Windscribe"

    /// Ports to offer if the client cannot be asked. Mirrors what
    /// `windscribe-cli ports <protocol>` returns on v2.24.12.
    private static let fallbackPorts: [String: [Int]] = [
        "wireguard": [443, 80, 53, 123, 1194, 65142],
        "ikev2": [500],
        "udp": [443, 80, 53, 123, 1194, 54783],
        "tcp": [443, 587, 21, 22, 80, 123, 143, 3306, 8080, 54783, 1194],
        "stealth": [443, 587, 21, 22, 80, 123, 143, 3306, 8080, 54783, 8443],
        "wstunnel": [443],
    ]

    private static let protocolOrder = ["wireguard", "ikev2", "udp", "tcp", "stealth", "wstunnel"]

    private static let protocolNotes: [String: String] = [
        "wireguard": "Fastest, and the least overhead of the protocols offered.",
        "ikev2": "Fixed on port 500, so the port cannot be changed.",
        "udp": "OpenVPN over UDP. Quick and light, but UDP is not always carried.",
        "tcp": "OpenVPN over TCP. Slower, but more widely carried than UDP.",
        "stealth": "A TCP-based protocol with extra encapsulation.",
        "wstunnel": "The tunnel carried inside a WebSocket, over port 443.",
    ]

    // MARK: - Locating the client

    static func cliPath() -> String? {
        let candidates = [
            "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli",
            "/Applications/Windscribe.app/Contents/Resources/windscribe-cli",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return RouteProcess.which("windscribe-cli")
    }

    private func requireCLI() throws -> String {
        guard let path = Self.cliPath() else {
            throw RouteProcessError.launchFailed(
                "windscribe-cli not found. Install the Windscribe client for macOS."
            )
        }
        return path
    }

    private func run(_ args: [String], timeout: Double = 20) async throws -> String {
        let output = try await RouteProcess.run(requireCLI(), args, timeout: timeout)
        if output.timedOut {
            throw RouteProcessError.timedOut(timeout)
        }
        return CLIOutput.stripLogLines(output.stdout + "\n" + output.stderr)
    }

    // MARK: - Status

    func probeStatus() async -> ProviderStatus {
        guard let path = Self.cliPath() else { return .unavailable }

        let text: String
        do {
            text = try await run(["status"], timeout: 20)
        } catch {
            return ProviderStatus(
                cliPath: path, installed: true, loggedIn: false,
                detail: "Client installed, but the app is not responding.",
                advisory: "Open the Windscribe app and sign in, then refresh."
            )
        }

        let fields = CLIOutput.keyValuePairs(text)
        let login = fields["login state"] ?? "Unknown"
        let connect = fields["connect state"] ?? "Unknown"
        let internet = fields["internet connectivity"] ?? ""
        let ip = fields["public ip"]

        return ProviderStatus(
            cliPath: path,
            installed: true,
            loggedIn: login.lowercased().contains("logged in"),
            detail: [connect, internet.isEmpty ? nil : internet]
                .compactMap { $0 }
                .joined(separator: " · "),
            tunnel: TunnelState.parse(connect),
            publicIP: ip
        )
    }

    func tunnelState() async -> TunnelState {
        guard let text = try? await run(["status"], timeout: 15) else { return .unknown }
        let fields = CLIOutput.keyValuePairs(text)
        return TunnelState.parse(fields["connect state"] ?? "")
    }

    func publicIP() async -> String? {
        guard let text = try? await run(["status"], timeout: 15) else { return nil }
        return CLIOutput.keyValuePairs(text)["public ip"]
    }

    // MARK: - Protocols

    func protocolOptions() async -> [ProtocolOption] {
        let available = Self.cliPath() != nil
        var options: [ProtocolOption] = []

        for proto in Self.protocolOrder {
            var ports = Self.fallbackPorts[proto] ?? []
            if available, let text = try? await run(["ports", proto], timeout: 15) {
                let live = CLIOutput.parseIntList(text)
                if !live.isEmpty { ports = live }
            }
            options.append(ProtocolOption(
                id: proto,
                title: Self.prettyName(proto),
                note: Self.protocolNotes[proto] ?? "",
                ports: ports
            ))
        }
        return options
    }

    private static func prettyName(_ proto: String) -> String {
        switch proto {
        case "wireguard": return "WireGuard"
        case "ikev2": return "IKEv2"
        case "udp": return "UDP"
        case "tcp": return "TCP"
        case "stealth": return "Stealth"
        case "wstunnel": return "WStunnel"
        default: return proto.capitalized
        }
    }

    // MARK: - Locations

    /// Windscribe's own `locations` command returns an empty payload, so the
    /// list comes from the bundled file — the same dataset the public status
    /// endpoint serves — with a user refresh layered over it.
    func loadLocations() async -> [VPNLocation] {
        let file = FileManager.default.fileExists(atPath: RoutePaths.cachedLocations.path)
            ? RoutePaths.cachedLocations
            : RoutePaths.bundledLocations
        guard let file else { return [] }
        return Self.parseLocations(at: file)
    }

    static func parseLocations(at url: URL) -> [VPNLocation] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataBlock = root["data"] as? [String: Any],
              let locations = dataBlock["locations"] as? [String: Any]
        else { return [] }

        var out: [VPNLocation] = []
        for (_, entry) in locations {
            guard let entry = entry as? [String: Any] else { continue }
            let country = (entry["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
            let continent = (entry["continent"] as? String) ?? ""
            let code = (entry["country_code"] as? String) ?? ""

            for pop in (entry["pops"] as? [[String: Any]]) ?? [] {
                // Status 1 is the only value the app itself treats as usable.
                if let status = pop["status"] as? Int, status != 1 { continue }
                let raw = (pop["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !raw.isEmpty else { continue }

                let city: String
                let node: String
                if let sep = raw.range(of: " - ") {
                    city = String(raw[raw.startIndex..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
                    node = String(raw[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    city = raw
                    node = ""
                }

                out.append(VPNLocation(
                    id: "\(code)|\(city)|\(node)",
                    city: city,
                    node: node,
                    country: country,
                    countryCode: code,
                    continent: continent,
                    isPremium: (pop["is_premium"] as? Int ?? 0) == 1
                ))
            }
        }

        return out.sorted {
            ($0.country, $0.city, $0.node) < ($1.country, $1.city, $1.node)
        }
    }

    /// Pull a fresh server list from Windscribe's public status endpoint.
    static func refreshLocations() async throws -> Int {
        guard let curl = RouteProcess.which("/usr/bin/curl") ?? RouteProcess.which("curl") else {
            throw RouteProcessError.launchFailed("curl is unavailable.")
        }
        let output = try await RouteProcess.run(
            curl,
            ["-sS", "--max-time", "30", "--compressed",
             "-A", "Housekeeping/1.0", "https://api.windscribe.com/WebsiteStatus"],
            timeout: 36
        )
        guard !output.timedOut else { throw RouteProcessError.timedOut(30) }

        // Validate before overwriting: a captive portal or a poisoned DNS
        // answer returns 200 with something that is not a location list.
        guard let data = output.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let block = root["data"] as? [String: Any],
              block["locations"] is [String: Any]
        else {
            throw RouteProcessError.launchFailed(
                "The endpoint did not return a server list — the response may have been redirected."
            )
        }

        try data.write(to: RoutePaths.cachedLocations, options: .atomic)
        return parseLocations(at: RoutePaths.cachedLocations).count
    }

    // MARK: - Connecting

    func beginConnect(_ target: RouteTarget) async throws {
        let route = target.port.map { "\(target.proto):\($0)" } ?? target.proto
        // -n returns as soon as the request is accepted, so the engine owns
        // the deadline and can time the transition itself.
        let text = try await run(["connect", "-n", target.identifier, route], timeout: 25)
        if let failure = Self.failureMessage(in: text) {
            throw RouteProcessError.launchFailed(failure)
        }
    }

    func disconnect() async {
        _ = try? await run(["disconnect"], timeout: 25)
    }

    /// Windscribe answers a rejected connect in prose rather than an exit
    /// code, so the text has to be inspected.
    static func failureMessage(in text: String) -> String? {
        let lowered = text.lowercased()
        let markers = [
            "unable to connect", "not logged in", "no such", "invalid",
            "does not exist", "failed to connect", "cannot connect",
        ]
        guard markers.contains(where: lowered.contains) else { return nil }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0.count < 200 }
    }
}

// MARK: - ExpressVPN

struct ExpressVPNProvider: VPNProvider {

    let kind: ProviderKind = .expressvpn
    let displayName = "ExpressVPN"

    /// `auto` is deliberately absent. It picks a protocol per network, which
    /// makes the protocol column meaningless in a run.
    private static let protocols: [(id: String, title: String, note: String)] = [
        ("lightwayudp", "Lightway UDP",
         "ExpressVPN's own protocol. Fastest of the five, and the one it uses by default."),
        ("lightwaytcp", "Lightway TCP",
         "Same protocol carried over TCP — slower, but usable where UDP is not."),
        ("openvpnudp", "OpenVPN UDP", "The long-standing standard. Quick, and widely recognised."),
        ("openvpntcp", "OpenVPN TCP",
         "Port 443 TCP. Often the most widely carried of the five."),
        ("wireguard", "WireGuard", "Lean and fast."),
    ]

    // MARK: - Locating the client

    static func cliPath() -> String? {
        if let found = RouteProcess.which("expressvpnctl") { return found }
        for path in ["/usr/local/bin/expressvpnctl", "/opt/homebrew/bin/expressvpnctl"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func requireCLI() throws -> String {
        guard let path = Self.cliPath() else {
            throw RouteProcessError.launchFailed(
                "expressvpnctl not found. Install the ExpressVPN client for macOS."
            )
        }
        return path
    }

    /// The CLI refuses to do anything unless the GUI client is running or
    /// background mode has been switched on, so it gets a longer leash.
    private func run(_ args: [String], timeout: Double = 30) async throws -> String {
        let output = try await RouteProcess.run(requireCLI(), args, timeout: timeout)
        if output.timedOut {
            throw RouteProcessError.timedOut(timeout)
        }
        let text = (output.stdout + "\n" + output.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if lowered.contains("gui client must be running")
            || lowered.contains("daemon is inactive")
            || lowered.contains("not running") {
            throw RouteProcessError.launchFailed(Self.daemonAdvisory)
        }
        return text
    }

    static let daemonAdvisory =
        "The ExpressVPN background service is not running. Open the ExpressVPN app, "
        + "or switch on background mode so the tunnel can be driven while the app is closed."

    // MARK: - Status

    func probeStatus() async -> ProviderStatus {
        guard let path = Self.cliPath() else { return .unavailable }

        let text: String
        do {
            text = try await run(["status"], timeout: 25)
        } catch {
            return ProviderStatus(
                cliPath: path, installed: true, loggedIn: false,
                detail: "Installed, but the background service is not answering.",
                advisory: Self.daemonAdvisory
            )
        }

        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let state = lines.first { !$0.isEmpty } ?? "Unknown"
        let fields = CLIOutput.keyValuePairs(text)
        let location = fields["location"]

        let protocolName = (try? await run(["get", "protocol"], timeout: 15)) ?? ""

        return ProviderStatus(
            cliPath: path,
            installed: true,
            // `status` does not report login, but a daemon that answers is a
            // daemon with an activated account behind it.
            loggedIn: true,
            detail: [state, location, protocolName.isEmpty ? nil : protocolName.lowercased()]
                .compactMap { $0 }
                .joined(separator: " · "),
            tunnel: TunnelState.parse(state),
            publicIP: (try? await run(["get", "vpnip"], timeout: 12)) ?? nil,
            advisory: nil
        )
    }

    func tunnelState() async -> TunnelState {
        guard let text = try? await run(["get", "connectionstate"], timeout: 15) else {
            return .unknown
        }
        return TunnelState.parse(text)
    }

    func publicIP() async -> String? {
        guard let text = try? await run(["get", "vpnip"], timeout: 15) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.lowercased() == "unknown" ? nil : value
    }

    // MARK: - Protocols

    func protocolOptions() async -> [ProtocolOption] {
        Self.protocols.map {
            ProtocolOption(id: $0.id, title: $0.title, note: $0.note, ports: [])
        }
    }

    // MARK: - Locations

    func loadLocations() async -> [VPNLocation] {
        guard let text = try? await run(["get", "regions"], timeout: 25) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.lowercased() != "smart" }
            .map { Self.describe(region: $0) }
            .sorted { ($0.country, $0.city, $0.node) < ($1.country, $1.city, $1.node) }
    }

    /// ExpressVPN names regions as slugs — `germany-frankfurt-1`, `uk-london`,
    /// `isle-of-man`. Splitting on the first hyphen would make the country of
    /// `isle-of-man` come out as "Isle", so the country is resolved by longest
    /// match against the ISO region names Foundation already knows.
    static func describe(region: String) -> VPNLocation {
        var slug = region.lowercased()
        var suffix = ""

        // A trailing number distinguishes two nodes in the same city.
        if let dash = slug.lastIndex(of: "-") {
            let tail = slug[slug.index(after: dash)...]
            if !tail.isEmpty, tail.allSatisfy({ $0.isNumber }) {
                suffix = String(tail)
                slug = String(slug[slug.startIndex..<dash])
            }
        }

        if let match = longestCountryMatch(in: slug) {
            let rest = slug.dropFirst(match.slug.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let city = prettyPlace(rest)
            return VPNLocation(
                id: region,
                city: city.isEmpty ? (suffix.isEmpty ? "" : "Node #\(suffix)")
                                   : (suffix.isEmpty ? city : "\(city) #\(suffix)"),
                node: "",
                country: match.name,
                countryCode: match.code,
                continent: "",
                isPremium: false
            )
        }

        // Unknown slug: fall back to reading it as country-then-city.
        let parts = slug.split(separator: "-").map(String.init)
        let country = prettyPlace(parts.first ?? slug)
        let city = prettyPlace(parts.dropFirst().joined(separator: " "))
        return VPNLocation(
            id: region, city: city, node: "",
            country: country, countryCode: "", continent: "", isPremium: false
        )
    }

    private struct CountryMatch {
        let slug: String
        let name: String
        let code: String
    }

    /// Built once from Foundation's own region table, so it covers countries
    /// ExpressVPN has not added yet and never needs maintaining by hand.
    private static let countryIndex: [CountryMatch] = {
        var out: [CountryMatch] = []
        let english = Locale(identifier: "en_US")

        // ExpressVPN's own spellings that Foundation disagrees with.
        let aliases: [String: String] = [
            "usa": "US",
            "uk": "GB",
            "south-korea": "KR",
            "russia": "RU",
            "vietnam": "VN",
            "taiwan": "TW",
            "moldova": "MD",
            "bolivia": "BO",
            "venezuela": "VE",
            "tanzania": "TZ",
            "syria": "SY",
            "laos": "LA",
            "brunei": "BN",
        ]

        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2,
                  let name = english.localizedString(forRegionCode: code),
                  !name.isEmpty
            else { continue }
            out.append(CountryMatch(slug: slugify(name), name: name, code: code))
        }
        for (slug, code) in aliases {
            let name = english.localizedString(forRegionCode: code) ?? slug
            // The alias keeps the provider's own word, so the list reads the
            // way ExpressVPN writes it.
            let display = slug == "usa" ? "United States"
                        : slug == "uk" ? "United Kingdom"
                        : name
            out.append(CountryMatch(slug: slug, name: display, code: code))
        }

        // Longest slug first, so `south-korea` wins over a `south` prefix.
        return out.sorted { $0.slug.count > $1.slug.count }
    }()

    private static func longestCountryMatch(in slug: String) -> CountryMatch? {
        for candidate in countryIndex {
            if slug == candidate.slug { return candidate }
            if slug.hasPrefix(candidate.slug + "-") { return candidate }
        }
        return nil
    }

    private static func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    private static func prettyPlace(_ slug: String) -> String {
        guard !slug.isEmpty else { return "" }
        let cleaned = slug.replacingOccurrences(of: "-", with: " ")
        return cleaned.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Connecting

    func prepare(_ target: RouteTarget) async throws {
        _ = try await run(["set", "protocol", target.proto], timeout: 20)
    }

    func beginConnect(_ target: RouteTarget) async throws {
        let text = try await run(["connect", target.identifier], timeout: 30)
        let lowered = text.lowercased()
        if lowered.contains("error") || lowered.contains("failed") {
            throw RouteProcessError.launchFailed(
                text.split(separator: "\n").first.map(String.init) ?? "Connect was refused."
            )
        }
    }

    func disconnect() async {
        _ = try? await run(["disconnect"], timeout: 25)
    }
}
