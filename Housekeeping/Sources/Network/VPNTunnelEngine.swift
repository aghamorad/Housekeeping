// Housekeeping — VPN Tunnels & Interface Watchdog Engine
//
// Discovers installed VPN connection profiles, active BSD virtual tunnel
// interfaces (utun), running background VPN engines/daemons, and evaluates
// routing and DNS conflicts. Provides safe disconnect and removal controls.

import Foundation
import AppKit

// MARK: - Connection Status

public enum VPNConnectionStatus: String, CaseIterable, Identifiable, Sendable {
    case connected = "Connected"
    case connecting = "Connecting"
    case disconnected = "Disconnected"
    case disabled = "Disabled"
    case unknown = "Unknown"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .connected: return "checkmark.shield.fill"
        case .connecting: return "arrow.triangle.2.circlepath.circle.fill"
        case .disconnected: return "shield.slash"
        case .disabled: return "slash.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Configured VPN Service

public struct VPNTunnelService: Identifiable, Equatable, Sendable {
    public let id: String // UUID
    public let name: String
    public let subtype: String
    public let status: VPNConnectionStatus
    public let isEnabled: Bool
    public let assignedIP: String?
    public let interface: String?

    public var displayProtocol: String {
        let lower = subtype.lowercased()
        if lower.contains("wireguard") { return "WireGuard" }
        if lower.contains("lightway") { return "Lightway" }
        if lower.contains("openvpn") { return "OpenVPN" }
        if lower.contains("ipsec") || lower.contains("ikev2") { return "IKEv2 / IPSec" }
        if lower.contains("shadowrocket") { return "Shadowrocket Proxy" }
        if lower.contains("nthlink") { return "nthLink Tunnel" }
        if let last = subtype.components(separatedBy: ".").last, !last.isEmpty {
            return last.capitalized
        }
        return "Packet Tunnel"
    }
}

// MARK: - Virtual Interface

public enum VirtualInterfaceKind: String, CaseIterable, Identifiable, Sendable {
    case activeVPN = "Active Routing Tunnel"
    case appleSystem = "macOS System Infrastructure"
    case idleTunnel = "Idle Virtual Device"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .activeVPN: return "bolt.shield.fill"
        case .appleSystem: return "apple.logo"
        case .idleTunnel: return "network"
        }
    }
}

public struct VirtualInterface: Identifiable, Equatable, Sendable {
    public let id: String // e.g. "utun4"
    public let name: String
    public let isUp: Bool
    public let mtu: Int
    public let ipv4: String?
    public let destinationIPv4: String?
    public let ipv6: String?
    public let isDefaultRoute: Bool
    public let kind: VirtualInterfaceKind
    public let owningProcess: String?
}

// MARK: - Running VPN Process

public struct RunningVPNProcess: Identifiable, Equatable, Sendable {
    public let id: Int // pid
    public let pid: pid_t
    public let name: String
    public let displayName: String
    public let executablePath: String
    public let user: String
    public let cpuPercent: Double
    public let memoryMB: Double
    public let isRoot: Bool
}

// MARK: - Routing & Diagnostic Summary

public struct VPNDiagnosticSummary: Equatable, Sendable {
    public let totalInstalledServices: Int
    public let totalActiveTunnels: Int
    public let totalVirtualInterfaces: Int
    public let totalRunningProcesses: Int
    public let activeVPNInterface: String?
    public let defaultPhysicalInterface: String?
    public let primaryDNS: [String]
    public let hasRoutingConflict: Bool
    public let conflictWarning: String?

    public static let empty = VPNDiagnosticSummary(
        totalInstalledServices: 0,
        totalActiveTunnels: 0,
        totalVirtualInterfaces: 0,
        totalRunningProcesses: 0,
        activeVPNInterface: nil,
        defaultPhysicalInterface: nil,
        primaryDNS: [],
        hasRoutingConflict: false,
        conflictWarning: nil
    )
}

// MARK: - VPN Tunnel Engine

public actor VPNTunnelEngine {
    public static let shared = VPNTunnelEngine()

    private let runner = ProcessRunner()

    public init() {}

    // MARK: - Full Scan

    public func scan() async -> (
        services: [VPNTunnelService],
        interfaces: [VirtualInterface],
        processes: [RunningVPNProcess],
        summary: VPNDiagnosticSummary
    ) {
        async let servicesTask = scanServices()
        async let routesTask = scanRoutes()
        async let ifacesTask = scanInterfaces()
        async let procsTask = scanProcesses()
        async let dnsTask = scanDNS()

        let (services, (defaultNetif, vpnNetif), ifacesRaw, procs, dns) = await (
            servicesTask,
            routesTask,
            ifacesTask,
            procsTask,
            dnsTask
        )

        // Classify interfaces based on active routes
        let interfaces: [VirtualInterface] = ifacesRaw.map { raw in
            let isActive = (raw.name == vpnNetif) || (raw.ipv4 != nil && raw.destinationIPv4 != nil)
            let isDefault = (raw.name == vpnNetif)
            let isAppleSystem: Bool
            if raw.name == "utun0" || raw.name == "utun1" || raw.name == "utun2" || raw.name == "utun3" ||
                raw.name == "utun5" || raw.name == "utun6" || raw.name == "utun7" || raw.name == "utun8" ||
                raw.name == "utun9" || raw.name == "utun10" {
                // If it only has link-local IPv6 and no IPv4, it is Apple's identityservicesd/rapportd
                isAppleSystem = (raw.ipv4 == nil)
            } else {
                isAppleSystem = false
            }

            let kind: VirtualInterfaceKind
            if isDefault || isActive {
                kind = .activeVPN
            } else if isAppleSystem {
                kind = .appleSystem
            } else {
                kind = .idleTunnel
            }

            return VirtualInterface(
                id: raw.name,
                name: raw.name,
                isUp: raw.isUp,
                mtu: raw.mtu,
                ipv4: raw.ipv4,
                destinationIPv4: raw.destinationIPv4,
                ipv6: raw.ipv6,
                isDefaultRoute: isDefault,
                kind: kind,
                owningProcess: isAppleSystem ? "macOS (AirDrop / iCloud)" : nil
            )
        }.sorted { lhs, rhs in
            // Active first, then idle, then Apple system
            if lhs.isDefaultRoute != rhs.isDefaultRoute { return lhs.isDefaultRoute }
            if lhs.kind != rhs.kind {
                if lhs.kind == .activeVPN { return true }
                if rhs.kind == .activeVPN { return false }
                if lhs.kind == .idleTunnel { return true }
                if rhs.kind == .idleTunnel { return false }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let activeCount = interfaces.filter { $0.kind == .activeVPN }.count
        let connectedServices = services.filter { $0.status == .connected }.count

        var conflictWarning: String? = nil
        var hasConflict = false

        if activeCount > 1 {
            hasConflict = true
            conflictWarning = "Multiple virtual tunnel devices (\(activeCount)) are actively routing traffic. This can cause severe packet loss and DNS loop stalls."
        } else if vpnNetif != nil && defaultNetif != nil && procs.isEmpty && connectedServices == 0 {
            hasConflict = true
            conflictWarning = "A tunnel interface (\(vpnNetif!)) is holding the default route, but no active VPN client process was found. Stale routes may be blackholing network requests."
        // A client, its daemon and its MCP server are parts of one VPN.
        // Process count alone is not evidence of a routing conflict.
        }

        let summary = VPNDiagnosticSummary(
            totalInstalledServices: services.count,
            totalActiveTunnels: activeCount,
            totalVirtualInterfaces: interfaces.count,
            totalRunningProcesses: procs.count,
            activeVPNInterface: vpnNetif,
            defaultPhysicalInterface: defaultNetif,
            primaryDNS: dns,
            hasRoutingConflict: hasConflict,
            conflictWarning: conflictWarning
        )

        return (services, interfaces, procs, summary)
    }

    // MARK: - Subsystem Scanners

    private func scanServices() async -> [VPNTunnelService] {
        guard let res = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "list"],
            timeout: 5
        ), res.succeeded else {
            return []
        }

        var found: [VPNTunnelService] = []
        let lines = res.stdout.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("VPN (") || trimmed.contains("IPSec") || trimmed.contains("PPP") else { continue }

            let isEnabled = trimmed.hasPrefix("*")

            // Status inside parentheses e.g. (Disconnected), (Connected), (Connecting)
            let status: VPNConnectionStatus
            if trimmed.contains("(Connected)") {
                status = .connected
            } else if trimmed.contains("(Connecting)") {
                status = .connecting
            } else if trimmed.contains("(Disconnected)") {
                status = .disconnected
            } else {
                status = .unknown
            }

            // Extract UUID
            var uuid = ""
            if let uuidRange = trimmed.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", options: .regularExpression) {
                uuid = String(trimmed[uuidRange])
            }

            // Extract Name (between quotes)
            var name = ""
            if let startQuote = trimmed.firstIndex(of: "\""),
               let endQuote = trimmed[trimmed.index(after: startQuote)...].firstIndex(of: "\"") {
                name = String(trimmed[trimmed.index(after: startQuote)..<endQuote])
            }

            // Extract SubType inside VPN (...)
            var subtype = ""
            if let vpnStart = trimmed.range(of: "VPN (")?.upperBound,
               let vpnEnd = trimmed[vpnStart...].firstIndex(of: ")") {
                subtype = String(trimmed[vpnStart..<vpnEnd])
            }

            guard !name.isEmpty || !uuid.isEmpty else { continue }

            let service = VPNTunnelService(
                id: uuid.isEmpty ? UUID().uuidString : uuid,
                name: name.isEmpty ? "Unnamed VPN (\(uuid.prefix(8)))" : name,
                subtype: subtype,
                status: isEnabled ? status : .disabled,
                isEnabled: isEnabled,
                assignedIP: nil,
                interface: nil
            )
            found.append(service)
        }

        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func scanRoutes() async -> (defaultNetif: String?, vpnNetif: String?) {
        guard let res = try? await runner.run(
            executable: "/usr/sbin/netstat",
            arguments: ["-rn", "-f", "inet"],
            timeout: 5
        ), res.succeeded else {
            return (nil, nil)
        }

        var defNetif: String? = nil
        var vpnNetif: String? = nil

        let lines = res.stdout.components(separatedBy: "\n")
        for line in lines {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4 else { continue }
            let dest = parts[0]
            let netif = parts.last ?? ""

            if dest == "default" {
                if netif.hasPrefix("utun") || netif.hasPrefix("tun") {
                    vpnNetif = netif
                } else if defNetif == nil {
                    defNetif = netif
                }
            } else if (dest == "0/1" || dest == "128.0/1") && (netif.hasPrefix("utun") || netif.hasPrefix("tun")) {
                vpnNetif = netif
            }
        }

        return (defNetif, vpnNetif)
    }

    private struct RawInterface {
        let name: String
        let isUp: Bool
        let mtu: Int
        let ipv4: String?
        let destinationIPv4: String?
        let ipv6: String?
    }

    private func scanInterfaces() async -> [RawInterface] {
        guard let res = try? await runner.run(
            executable: "/sbin/ifconfig",
            arguments: [],
            timeout: 5
        ), res.succeeded else {
            return []
        }

        var results: [RawInterface] = []
        var currentIface = ""
        var currentLines: [String] = []

        for line in res.stdout.components(separatedBy: "\n") {
            if line.range(of: "^[a-z0-9]+:", options: .regularExpression) != nil {
                if !currentIface.isEmpty {
                    if let raw = parseRawInterface(name: currentIface, lines: currentLines) {
                        results.append(raw)
                    }
                }
                currentIface = line.components(separatedBy: ":").first ?? ""
                currentLines = [line]
            } else if !currentIface.isEmpty {
                currentLines.append(line)
            }
        }
        if !currentIface.isEmpty, let raw = parseRawInterface(name: currentIface, lines: currentLines) {
            results.append(raw)
        }

        return results
    }

    private func parseRawInterface(name: String, lines: [String]) -> RawInterface? {
        guard name.hasPrefix("utun") || name.hasPrefix("tun") || name.hasPrefix("tap") || name.hasPrefix("ppp") else {
            return nil
        }

        let firstLine = lines.first ?? ""
        let isUp = firstLine.contains("UP")

        var mtu = 1500
        if let mtuRange = firstLine.range(of: "mtu [0-9]+", options: .regularExpression) {
            let mtuStr = firstLine[mtuRange].components(separatedBy: " ").last ?? "1500"
            mtu = Int(mtuStr) ?? 1500
        }

        var ipv4: String? = nil
        var destIPv4: String? = nil
        var ipv6: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 2 { ipv4 = parts[1] }
                if let arrowIdx = parts.firstIndex(of: "-->"), arrowIdx + 1 < parts.count {
                    destIPv4 = parts[arrowIdx + 1]
                }
            } else if trimmed.hasPrefix("inet6 ") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 2 {
                    let addr = parts[1]
                    // Skip link-local scope suffixes for clean display
                    ipv6 = addr.components(separatedBy: "%").first
                }
            }
        }

        return RawInterface(
            name: name,
            isUp: isUp,
            mtu: mtu,
            ipv4: ipv4,
            destinationIPv4: destIPv4,
            ipv6: ipv6
        )
    }

    private func scanProcesses() async -> [RunningVPNProcess] {
        guard let res = try? await runner.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid,user,%cpu,rss,comm"],
            timeout: 5
        ), res.succeeded else {
            return []
        }

        var found: [RunningVPNProcess] = []
        let lines = res.stdout.components(separatedBy: "\n")

        let vpnSignatures: [String: String] = [
            "expressvpn-lightway-rs": "ExpressVPN Lightway",
            "expressvpn-mcp": "ExpressVPN MCP",
            "shecan-updater": "Shecan Updater",
            "shecan-nextdns": "Shecan DNS Helper",
            "shecan-game": "Shecan Game Helper",
            "com.windscribe.helper.macos": "Windscribe Helper",
            "Windscribe": "Windscribe Client",
            "expressvpn-daemon": "ExpressVPN Daemon",
            "ExpressVPN": "ExpressVPN GUI",
            "AmneziaVPN-service": "AmneziaVPN Service",
            "AmneziaVPN": "AmneziaVPN Client",
            "amneziawg-go": "Amnezia WireGuard Engine",
            "wireguard-go": "WireGuard Go Tunnel",
            "wg": "WireGuard Quick",
            "tailscaled": "Tailscale Daemon",
            "Tailscale": "Tailscale Client",
            "warp-svc": "Cloudflare WARP Service",
            "Cloudflare WARP": "Cloudflare WARP Client",
            "Shadowrocket": "Shadowrocket Engine",
            "sing-box": "Sing-box Routing Engine",
            "clash": "Clash Tunnel Core",
            "xray": "Xray Core",
            "v2ray": "V2Ray Core",
            "openvpn": "OpenVPN Daemon",
            "vpnagentd": "Cisco AnyConnect Agent",
            "ciscod": "Cisco Secure Client",
            "surfsharkd": "Surfshark Daemon",
            "Surfshark": "Surfshark Client",
            "ProtonVPN": "ProtonVPN Client",
            "MullvadVPN": "Mullvad VPN Client",
            "FortiClient": "FortiClient Agent",
            "GlobalProtect": "Palo Alto GlobalProtect"
        ]

        for line in lines {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 5 else { continue }
            guard let pid = Int32(parts[0]) else { continue }
            let user = parts[1]
            let cpu = Double(parts[2]) ?? 0.0
            let rssKB = Double(parts[3]) ?? 0.0
            let path = parts.dropFirst(4).joined(separator: " ")
            let lower = path.lowercased()

            for (sig, friendly) in vpnSignatures.sorted(by: { $0.key.count > $1.key.count }) {
                if URL(fileURLWithPath: lower).lastPathComponent.contains(sig.lowercased()) {
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    found.append(RunningVPNProcess(
                        id: Int(pid),
                        pid: pid,
                        name: name,
                        displayName: friendly,
                        executablePath: path,
                        user: user,
                        cpuPercent: cpu,
                        memoryMB: rssKB / 1024.0,
                        isRoot: user == "root"
                    ))
                    break
                }
            }
        }

        return found.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private func scanDNS() async -> [String] {
        guard let res = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--dns"],
            timeout: 5
        ), res.succeeded else {
            return []
        }

        var servers: [String] = []
        var seen = Set<String>()
        let lines = res.stdout.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("nameserver[") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    let ip = parts[1].trimmingCharacters(in: .whitespaces)
                    if !ip.isEmpty && seen.insert(ip).inserted {
                        servers.append(ip)
                    }
                }
            }
        }

        return servers
    }

    // MARK: - Actions

    public func disconnect(service: VPNTunnelService) async throws {
        _ = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "stop", service.name],
            timeout: 5
        )
        _ = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "stop", service.id],
            timeout: 5
        )
    }

    public func connect(service: VPNTunnelService) async throws {
        _ = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "start", service.name],
            timeout: 5
        )
    }

    public func deleteService(service: VPNTunnelService) async throws {
        // Step 1: Disconnect and disable first
        _ = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "stop", service.name],
            timeout: 5
        )
        _ = try? await runner.run(
            executable: "/usr/sbin/scutil",
            arguments: ["--nc", "disablevpn", service.name],
            timeout: 5
        )

        // Step 2: Remove from macOS Network Preferences
        let directRes = try? await runner.run(
            executable: "/usr/sbin/networksetup",
            arguments: ["-removenetworkservice", service.name],
            timeout: 10
        )

        // Step 3: If direct remove did not succeed (e.g. requires administrator privileges on macOS),
        // execute through standard macOS AppleScript authorization dialog.
        if directRes?.succeeded != true {
            let escapedName = service.name.replacingOccurrences(of: "\"", with: "\\\"")
            let scriptSource = "do shell script \"/usr/sbin/networksetup -removenetworkservice \\\"\(escapedName)\\\"\" with administrator privileges"
            if let appleScript = NSAppleScript(source: scriptSource) {
                var errorDict: NSDictionary?
                appleScript.executeAndReturnError(&errorDict)
                if let errorDict {
                    let msg = errorDict[NSAppleScript.errorMessage] as? String ?? "Authorization failed"
                    throw NSError(domain: "VPNTunnelEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
                }
            }
        }
    }

    public func stopProcess(pid: pid_t) async throws {
        // Try gentle SIGTERM
        let res = kill(pid, SIGTERM)
        if res != 0 {
            // If failed (e.g. EPERM for root daemon), prompt via AppleScript
            let script = "do shell script \"kill -TERM \(pid)\" with administrator privileges"
            if let appleScript = NSAppleScript(source: script) {
                var errorDict: NSDictionary?
                appleScript.executeAndReturnError(&errorDict)
            }
        }
    }

    public func flushDNSAndResetRouting() async throws {
        _ = try? await runner.run(executable: "/usr/bin/dscacheutil", arguments: ["-flushcache"], timeout: 5)
        _ = try? await runner.run(executable: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], timeout: 5)
        _ = try? await runner.run(executable: "/usr/sbin/route", arguments: ["-n", "flush"], timeout: 5)
    }
}
