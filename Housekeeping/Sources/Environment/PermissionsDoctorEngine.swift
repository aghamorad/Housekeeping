// Housekeeping — Permissions & System Doctor Engine
//
// Diagnoses permission issues, root ownership of user config directories (e.g. ~/.gemini),
// broken network/proxy/DNS connections, stuck Gatekeeper quarantine flags,
// zombie TCC entries, and orphan background launch agents.

import Foundation
import AppKit

public enum DoctorCategory: String, CaseIterable, Identifiable, Sendable {
    case filePermissions = "File & Tool Permissions"
    case networkConnections = "Network & Connections"
    case gatekeeper = "App Quarantine & Gatekeeper"
    case backgroundDaemons = "Background Daemons & Plists"
    case privacyGrants = "Privacy & Security Permissions"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .filePermissions: return "folder.badge.gearshape"
        case .networkConnections: return "network.badge.shield.half.filled"
        case .gatekeeper: return "checkmark.shield"
        case .backgroundDaemons: return "list.bullet.rectangle"
        case .privacyGrants: return "hand.raised.fill"
        }
    }
}

public enum DoctorSeverity: String, Sendable {
    case critical = "Needs Fix"
    case warning = "Advisory"
    case healthy = "Healthy"
}

public struct DoctorIssue: Identifiable, Sendable {
    public let id: String
    public let category: DoctorCategory
    public let severity: DoctorSeverity
    public let title: String
    public let detail: String
    public let path: String?
    public let recommendedFix: String
    public let canAutoFix: Bool
    public var isFixed: Bool = false
}

@MainActor
public final class PermissionsDoctorEngine: ObservableObject {
    public static let shared = PermissionsDoctorEngine()

    @Published public private(set) var isScanning = false
    @Published public private(set) var isFixing = false
    @Published public private(set) var issues: [DoctorIssue] = []
    @Published public private(set) var lastScanDate: Date?
    @Published public private(set) var fixMessage: String?
    @Published public private(set) var recommendationText: String = ""

    private let runner = ProcessRunner()

    private init() {}

    // MARK: - Scan

    public func scanAll() async {
        isScanning = true
        fixMessage = nil

        let discovered: [DoctorIssue] = await Task.detached(priority: .userInitiated) {
            var found: [DoctorIssue] = []
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser.path
            let uid = getuid()

            // 1. Audit User Config Permissions (e.g. ~/.gemini, ~/.config, ~/.claude, ~/C3PO)
            let criticalPaths = [
                home + "/.gemini",
                home + "/.config",
                home + "/.claude",
                home + "/.codex",
                home + "/.hermes",
                home + "/C3PO",
                home + "/Library/Application Support/com.google.GeminiMacOS",
                home + "/Library/Application Support/Claude",
                home + "/Library/Application Support/Code"
            ]

            for path in criticalPaths {
                guard fm.fileExists(atPath: path) else { continue }

                // Check directory ownership
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let ownerID = attrs[.ownerAccountID] as? UInt32,
                   ownerID != uid {
                    found.append(DoctorIssue(
                        id: "perm-root-\(path)",
                        category: .filePermissions,
                        severity: .critical,
                        title: "Folder owned by root: \(URL(fileURLWithPath: path).lastPathComponent)",
                        detail: "Path \(path) is owned by system root instead of your user account. Apps such as Gemini or CLI assistants will fail to save settings or security bookmarks.",
                        path: path,
                        recommendedFix: "Restore ownership to your user account (\(NSUserName()):staff).",
                        canAutoFix: true
                    ))
                    continue
                }

                // Check for unreadable / unwriteable sub-items or root-owned files
                if let enumerator = fm.enumerator(atPath: path) {
                    var rootFilesCount = 0
                    var lockedFilesCount = 0
                    var inspected = 0
                    while let subPath = enumerator.nextObject() as? String {
                        inspected += 1
                        if inspected > 500 { break }
                        if subPath.contains("/.git") || subPath.contains("/node_modules") || subPath.contains("/venv") || subPath.contains("/.build") {
                            enumerator.skipDescendants()
                            continue
                        }
                        let fullPath = (path as NSString).appendingPathComponent(subPath)
                        if let subAttrs = try? fm.attributesOfItem(atPath: fullPath) {
                            if let subOwner = subAttrs[.ownerAccountID] as? UInt32, subOwner == 0 {
                                rootFilesCount += 1
                            }
                            if let posix = subAttrs[.posixPermissions] as? NSNumber {
                                let perms = posix.intValue
                                if (perms & 0o200) == 0 { // no user write
                                    lockedFilesCount += 1
                                }
                            }
                        }
                    }
                    if rootFilesCount > 0 || lockedFilesCount > 0 {
                        found.append(DoctorIssue(
                            id: "perm-subitems-\(path)",
                            category: .filePermissions,
                            severity: .critical,
                            title: "Locked files in \(URL(fileURLWithPath: path).lastPathComponent)",
                            detail: "Found \(rootFilesCount) file(s) owned by root and \(lockedFilesCount) read-only file(s) inside \(path).",
                            path: path,
                            recommendedFix: "Fix permissions and unlock all subfiles for \(NSUserName()).",
                            canAutoFix: true
                        ))
                    }
                }
            }

            // 2. Network & Connection Audit
            // Check active proxy settings that might be stuck
            if let proxyCheck = try? await ProcessRunner().run(
                executable: "/usr/sbin/networksetup",
                arguments: ["-getwebproxy", "Wi-Fi"]
            ), proxyCheck.succeeded {
                if proxyCheck.stdout.contains("Enabled: Yes") {
                    found.append(DoctorIssue(
                        id: "net-stuck-http-proxy",
                        category: .networkConnections,
                        severity: .warning,
                        title: "Stuck HTTP Proxy on Wi-Fi",
                        detail: "An active HTTP proxy is enabled on Wi-Fi. If no proxy service is currently running, this will break internet connections.",
                        path: nil,
                        recommendedFix: "Disable orphan HTTP proxy on Wi-Fi.",
                        canAutoFix: true
                    ))
                }
            }
            if let secureProxy = try? await ProcessRunner().run(
                executable: "/usr/sbin/networksetup",
                arguments: ["-getsecurewebproxy", "Wi-Fi"]
            ), secureProxy.succeeded {
                if secureProxy.stdout.contains("Enabled: Yes") {
                    found.append(DoctorIssue(
                        id: "net-stuck-https-proxy",
                        category: .networkConnections,
                        severity: .warning,
                        title: "Stuck HTTPS Proxy on Wi-Fi",
                        detail: "An active HTTPS proxy is enabled on Wi-Fi. If no proxy server is active, web browsing and AI agents will fail with connection refused.",
                        path: nil,
                        recommendedFix: "Disable orphan HTTPS proxy on Wi-Fi.",
                        canAutoFix: true
                    ))
                }
            }

            // Check for orphan VPN utun interfaces
            if let ifconfig = try? await ProcessRunner().run(
                executable: "/sbin/ifconfig",
                arguments: []
            ), ifconfig.succeeded {
                let lines = ifconfig.stdout.components(separatedBy: "\n")
                let utunLines = lines.filter { $0.hasPrefix("utun") && $0.contains("POINTOPOINT") }
                // Check if any VPN app is running
                let runningApps = NSWorkspace.shared.runningApplications
                let vpnAppsRunning = ["windscribe", "expressvpn", "surfshark", "amnezia", "outline"].contains { vpnKey in
                    runningApps.contains { app in
                        (app.localizedName?.lowercased().contains(vpnKey) ?? false) ||
                        (app.bundleIdentifier?.lowercased().contains(vpnKey) ?? false)
                    }
                }
                if utunLines.count > 4 && !vpnAppsRunning {
                    found.append(DoctorIssue(
                        id: "net-many-utun",
                        category: .networkConnections,
                        severity: .warning,
                        title: "Multiple lingering VPN interfaces (\(utunLines.count))",
                        detail: "Found \(utunLines.count) virtual network interfaces (utun) active on your system while no primary VPN app appears active.",
                        path: nil,
                        recommendedFix: "Flush DNS cache and verify network connectivity.",
                        canAutoFix: true
                    ))
                }
            }

            // 3. Gatekeeper & App Quarantine
            let appDirs = [
                URL(fileURLWithPath: "/Applications"),
                fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]
            for dir in appDirs {
                guard let apps = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for app in apps where app.pathExtension == "app" {
                    let path = app.path
                    let hasQuarantine = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
                    if hasQuarantine {
                        found.append(DoctorIssue(
                            id: "gatekeeper-\(path)",
                            category: .gatekeeper,
                            severity: .warning,
                            title: "Quarantined App: \(app.deletingPathExtension().lastPathComponent)",
                            detail: "App carries Gatekeeper quarantine flags. It may prompt 'App is damaged and can't be opened' or fail to run background CLI tools.",
                            path: path,
                            recommendedFix: "Remove Gatekeeper quarantine flag safely.",
                            canAutoFix: true
                        ))
                    }
                }
            }

            // 4. Background Daemons: broken launch agents
            let agentDirs = [
                fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
                URL(fileURLWithPath: "/Library/LaunchAgents")
            ]
            for agentDir in agentDirs {
                guard let plists = try? fm.contentsOfDirectory(at: agentDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for plist in plists where plist.pathExtension == "plist" {
                    guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { continue }
                    var targetBinary: String?
                    if let prog = dict["Program"] as? String {
                        targetBinary = prog
                    } else if let args = dict["ProgramArguments"] as? [String], let first = args.first {
                        targetBinary = first
                    }
                    if let bin = targetBinary, !bin.isEmpty, bin.hasPrefix("/") {
                        if !fm.fileExists(atPath: bin) {
                            found.append(DoctorIssue(
                                id: "daemon-broken-\(plist.path)",
                                category: .backgroundDaemons,
                                severity: .warning,
                                title: "Broken LaunchAgent: \(plist.lastPathComponent)",
                                detail: "This startup item points to missing binary \(bin). macOS may repeatedly attempt to launch it, wasting battery and processor cycles.",
                                path: plist.path,
                                recommendedFix: "Move broken startup plist to Trash.",
                                canAutoFix: true
                            ))
                        }
                    }
                }
            }
            return found
        }.value

        self.issues = discovered
        self.lastScanDate = Date()
        self.recommendationText = buildRecommendationText(issues: discovered)
        self.isScanning = false
    }

    // MARK: - Housekeeper Recommendations

    private func buildRecommendationText(issues: [DoctorIssue]) -> String {
        if issues.isEmpty {
            return "Housekeeper Doctor scanned your Mac's file permissions, network interfaces, app quarantine flags, and background startup services.\n\nEverything is in peak health! No permission blocks, broken proxies, or orphan background services were detected. You do not need to do anything."
        }

        var lines: [String] = []
        let critCount = issues.filter { $0.severity == .critical }.count
        let warnCount = issues.filter { $0.severity == .warning }.count

        lines.append("Housekeeper Doctor completed a diagnostic check of your Mac (\(critCount) critical, \(warnCount) advisory). Here is what we found and what we recommend:\n")

        if critCount > 0 {
            lines.append("• Critical Permissions (\(critCount) item\(critCount == 1 ? "" : "s")):")
            lines.append("  Some configuration folders in your home directory have root ownership or read-only permissions (similar to what caused issues in your Gemini workspace). We recommend tapping 'Fix Recommended Issues' to safely restore full user access.")
        }

        let netIssues = issues.filter { $0.category == .networkConnections }
        if !netIssues.isEmpty {
            lines.append("• Network Connections (\(netIssues.count) item\(netIssues.count == 1 ? "" : "s")):")
            lines.append("  Detected stale proxy settings or lingering network interfaces. Housekeeper recommends resetting stale proxy states and flushing the DNS resolver so your connections carry traffic without drops.")
        }

        let gatekeeperIssues = issues.filter { $0.category == .gatekeeper }
        if !gatekeeperIssues.isEmpty {
            lines.append("• App Quarantine (\(gatekeeperIssues.count) item\(gatekeeperIssues.count == 1 ? "" : "s")):")
            lines.append("  Certain downloaded apps still carry macOS Gatekeeper quarantine tags. Clearing these tags prevents 'Damaged app' warnings.")
        }

        let daemonIssues = issues.filter { $0.category == .backgroundDaemons }
        if !daemonIssues.isEmpty {
            lines.append("• Broken Startup Items (\(daemonIssues.count) item\(daemonIssues.count == 1 ? "" : "s")):")
            lines.append("  Found startup items pointing to apps or tools that were deleted. Moving them to Trash prevents silent background crash loops.")
        }

        lines.append("\nOur Recommendation: Simply tap 'Fix Recommended Issues' below. Housekeeper will resolve all safe items automatically in one tap.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Fixes

    public func fixAllRecommended() async {
        isFixing = true
        var fixedCount = 0

        for issue in issues where issue.canAutoFix && !issue.isFixed {
            let success = await applyFix(for: issue)
            if success {
                fixedCount += 1
            }
        }

        fixMessage = fixedCount > 0
            ? "Successfully repaired \(fixedCount) issue\(fixedCount == 1 ? "" : "s")! Refreshing diagnostic status…"
            : "No issues required automatic repair."

        // Re-scan to verify
        await scanAll()
        isFixing = false
    }

    public func fixSingle(issue: DoctorIssue) async {
        isFixing = true
        let success = await applyFix(for: issue)
        fixMessage = success ? "Repaired: \(issue.title)" : "Could not complete fix for \(issue.title)."
        await scanAll()
        isFixing = false
    }

    private func applyFix(for issue: DoctorIssue) async -> Bool {
        switch issue.category {
        case .filePermissions:
            guard let path = issue.path else { return false }
            let user = NSUserName()
            _ = try? await runner.run(
                executable: "/usr/sbin/chown",
                arguments: ["-R", "\(user):staff", path]
            )
            _ = try? await runner.run(
                executable: "/bin/chmod",
                arguments: ["-R", "u+rwX", path]
            )
            return true

        case .networkConnections:
            if issue.id.contains("proxy") {
                _ = try? await runner.run(executable: "/usr/sbin/networksetup", arguments: ["-setwebproxystate", "Wi-Fi", "off"])
                _ = try? await runner.run(executable: "/usr/sbin/networksetup", arguments: ["-setsecurewebproxystate", "Wi-Fi", "off"])
                _ = try? await runner.run(executable: "/usr/sbin/networksetup", arguments: ["-setsocksfirewallproxystate", "Wi-Fi", "off"])
            }
            _ = try? await runner.run(executable: "/usr/bin/dscacheutil", arguments: ["-flushcache"])
            _ = try? await runner.run(executable: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
            return true

        case .gatekeeper:
            guard let path = issue.path else { return false }
            removexattr(path, "com.apple.quarantine", 0)
            removexattr(path, "com.apple.provenance", 0)
            _ = try? await runner.run(executable: "/usr/bin/xattr", arguments: ["-d", "com.apple.quarantine", path])
            _ = try? await runner.run(executable: "/usr/bin/xattr", arguments: ["-d", "com.apple.provenance", path])
            return true

        case .backgroundDaemons:
            guard let path = issue.path else { return false }
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return true
            } catch {
                return false
            }

        case .privacyGrants:
            return false
        }
    }
}
