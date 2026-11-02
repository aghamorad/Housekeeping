import Foundation
import SwiftUI

// MARK: - DNS Category

public enum DNSCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "All"
    case fast = "Fast & Privacy"
    case adblock = "Ad & Threat Blocking"
    case sanctionBypass = "Sanction Bypass"
    case gaming = "Gaming"
    case custom = "Custom"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "globe"
        case .fast: return "bolt.shield.fill"
        case .adblock: return "hand.raised.shield.fill"
        case .sanctionBypass: return "network.badge.shield.half.filled"
        case .gaming: return "gamecontroller.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - DNS Preset Model

public struct DNSPreset: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let category: DNSCategory
    public let primaryIP: String
    public let secondaryIP: String
    public let tag: String
    public let description: String
    public let isDHCP: Bool

    public init(
        id: String,
        name: String,
        category: DNSCategory,
        primaryIP: String,
        secondaryIP: String = "",
        tag: String,
        description: String,
        isDHCP: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primaryIP = primaryIP
        self.secondaryIP = secondaryIP
        self.tag = tag
        self.description = description
        self.isDHCP = isDHCP
    }

    /// Whether this preset represents automatic DHCP / router default.
    public static let automatic = DNSPreset(
        id: "dhcp-auto",
        name: "Automatic (DHCP)",
        category: .fast,
        primaryIP: "Router Default",
        secondaryIP: "DHCP",
        tag: "DEFAULT",
        description: "Restores default DNS assigned by your local Wi-Fi router or ISP DHCP.",
        isDHCP: true
    )

    /// Canonical list of built-in DNS providers including global Anycast and Iranian sanction bypass.
    public static let builtInPresets: [DNSPreset] = [
        automatic,

        // Global Fast & Privacy
        DNSPreset(
            id: "cloudflare-main",
            name: "Cloudflare (1.1.1.1)",
            category: .fast,
            primaryIP: "1.1.1.1",
            secondaryIP: "1.0.0.1",
            tag: "FASTEST",
            description: "Ultra-fast global Anycast network with strict zero-logging privacy."
        ),
        DNSPreset(
            id: "google-dns",
            name: "Google Public DNS",
            category: .fast,
            primaryIP: "8.8.8.8",
            secondaryIP: "8.8.4.4",
            tag: "RELIABLE",
            description: "Google's worldwide Anycast DNS infrastructure with high availability."
        ),
        DNSPreset(
            id: "quad9-privacy",
            name: "Quad9 DNS",
            category: .fast,
            primaryIP: "9.9.9.9",
            secondaryIP: "149.112.112.112",
            tag: "SWISS PRIVACY",
            description: "Swiss non-profit foundation. Blocks malicious domains with no telemetry."
        ),
        DNSPreset(
            id: "opendns-home",
            name: "OpenDNS Home",
            category: .fast,
            primaryIP: "208.67.222.222",
            secondaryIP: "208.67.220.220",
            tag: "CISCO",
            description: "Cisco Anycast network with built-in phishing and botnet defense."
        ),

        // Ad & Threat Blocking
        DNSPreset(
            id: "adguard-main",
            name: "AdGuard DNS",
            category: .adblock,
            primaryIP: "94.140.14.14",
            secondaryIP: "94.140.15.15",
            tag: "AD BLOCKING",
            description: "Blocks web banner ads, tracking scripts, coin miners, and malicious redirects."
        ),
        DNSPreset(
            id: "cloudflare-security",
            name: "Cloudflare Security",
            category: .adblock,
            primaryIP: "1.1.1.2",
            secondaryIP: "1.0.0.2",
            tag: "MALWARE BLOCK",
            description: "Automated threat protection that blocks known malware and phishing."
        ),

        // Sanction & 403 Developer Bypass (Iran)
        DNSPreset(
            id: "shecan",
            name: "Shecan (شکن)",
            category: .sanctionBypass,
            primaryIP: "178.22.122.100",
            secondaryIP: "185.51.200.2",
            tag: "403 BYPASS",
            description: "Bypasses international sanctions on Docker, Gradle, Adobe, Oracle, Canva, and Google Dev."
        ),
        DNSPreset(
            id: "online403",
            name: "403.online (۴۰۳)",
            category: .sanctionBypass,
            primaryIP: "10.202.10.202",
            secondaryIP: "10.202.10.102",
            tag: "DEV BYPASS",
            description: "Developer-focused sanction bypass for GitHub, npm, PyPI, OpenAI, Anthropic, and AWS."
        ),
        DNSPreset(
            id: "begzar",
            name: "Begzar (بگذر)",
            category: .sanctionBypass,
            primaryIP: "185.55.226.26",
            secondaryIP: "185.55.225.25",
            tag: "SANCTION BYPASS",
            description: "Fast free anti-sanction DNS service for Iranian developers and web services."
        ),

        // Gaming
        DNSPreset(
            id: "electro",
            name: "Electro (الکترو)",
            category: .gaming,
            primaryIP: "78.157.42.100",
            secondaryIP: "78.157.42.101",
            tag: "GAMING & STEAM",
            description: "Optimized for gaming traffic, Steam downloads, EA, Ubisoft, and Discord connectivity."
        ),
        DNSPreset(
            id: "radar-game",
            name: "Radar Game (رادار بازی)",
            category: .gaming,
            primaryIP: "10.202.10.10",
            secondaryIP: "10.202.10.11",
            tag: "LOW PING",
            description: "Low-latency gaming CDN routing and packet jitter reduction."
        )
    ]
}

// MARK: - Network Hardware Interface

public struct NetworkHardwareInterface: Identifiable, Hashable, Sendable {
    public let id: String
    public let userDefinedName: String
    public let hardwarePort: String
    public let device: String
    public let isPrimary: Bool
    public let configuredDNS: [String]

    public init(
        id: String,
        userDefinedName: String,
        hardwarePort: String,
        device: String,
        isPrimary: Bool,
        configuredDNS: [String]
    ) {
        self.id = id
        self.userDefinedName = userDefinedName
        self.hardwarePort = hardwarePort
        self.device = device
        self.isPrimary = isPrimary
        self.configuredDNS = configuredDNS
    }

    /// Display string e.g. "Wi-Fi (en0) · Primary"
    public var displayTitle: String {
        if isPrimary {
            return "\(userDefinedName) · Active Default"
        } else {
            return userDefinedName
        }
    }
}
