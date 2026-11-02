import Foundation
import Combine
import SwiftUI

// MARK: - DNS Engine

@MainActor
public final class DNSEngine: ObservableObject {
    public static let shared = DNSEngine()

    @Published public private(set) var interfaces: [NetworkHardwareInterface] = []
    @Published public var selectedInterfaceID: String = "primary" // "primary", specific service name, or "all"
    @Published public private(set) var activeSystemDNS: [String] = []
    @Published public private(set) var customPresets: [DNSPreset] = []
    @Published public private(set) var latencies: [String: Double] = [:] // preset.id -> latency ms (-1 for timeout)
    @Published public private(set) var isTestingPing: [String: Bool] = [:]
    @Published public private(set) var isWorking: Bool = false
    @Published public var statusNotice: String?

    private let customPresetsKey = "housekeeping.custom_dns_presets"

    public init() {
        loadCustomPresets()
        refresh()
    }

    // MARK: - Discovery & State

    public func refresh() {
        Task {
            await reloadNetworkState()
        }
    }

    private func reloadNetworkState() async {
        let (discoveredInterfaces, systemDNS) = await Task.detached(priority: .userInitiated) {
            let defDevice = self.queryDefaultRouteDevice()
            let hwPorts = self.queryHardwarePorts()
            let services = self.queryNetworkServices()

            var list: [NetworkHardwareInterface] = []
            for service in services {
                // Ignore virtual VPN services in hardware interface list
                if service.lowercased().contains("surfshark") ||
                   service.lowercased().contains("shadowrocket") ||
                   service.lowercased().contains("nthlink") ||
                   service.lowercased().contains("wireguard") {
                    continue
                }

                let dev = hwPorts[service] ?? ""
                let isPrimary = (dev == defDevice && !dev.isEmpty) || (defDevice.isEmpty && service == "Wi-Fi")
                let currentDNS = self.queryConfiguredDNS(for: service)

                list.append(NetworkHardwareInterface(
                    id: service,
                    userDefinedName: service,
                    hardwarePort: service,
                    device: dev,
                    isPrimary: isPrimary,
                    configuredDNS: currentDNS
                ))
            }

            // Fallback if list is empty
            if list.isEmpty {
                list.append(NetworkHardwareInterface(
                    id: "Wi-Fi",
                    userDefinedName: "Wi-Fi",
                    hardwarePort: "Wi-Fi",
                    device: "en0",
                    isPrimary: true,
                    configuredDNS: self.queryConfiguredDNS(for: "Wi-Fi")
                ))
            }

            let activeResolvers = self.queryActiveResolvers()
            return (list, activeResolvers)
        }.value

        self.interfaces = discoveredInterfaces
        self.activeSystemDNS = systemDNS

        // Ensure selectedInterfaceID is valid
        if selectedInterfaceID != "primary" && selectedInterfaceID != "all" {
            if !discoveredInterfaces.contains(where: { $0.id == selectedInterfaceID }) {
                selectedInterfaceID = "primary"
            }
        }
    }

    public var effectiveTargetInterfaceName: String? {
        if selectedInterfaceID == "primary" {
            return interfaces.first(where: { $0.isPrimary })?.id ?? interfaces.first?.id
        } else if selectedInterfaceID == "all" {
            return nil // represents all
        } else {
            return selectedInterfaceID
        }
    }

    public func isPresetActive(_ preset: DNSPreset) -> Bool {
        guard let target = effectiveTargetInterfaceName,
              let iface = interfaces.first(where: { $0.id == target }) else {
            return false
        }

        if preset.isDHCP {
            return iface.configuredDNS.isEmpty
        }

        if iface.configuredDNS.isEmpty {
            return false
        }

        let primaryMatch = iface.configuredDNS.contains(preset.primaryIP)
        if !preset.secondaryIP.isEmpty {
            return primaryMatch && iface.configuredDNS.contains(preset.secondaryIP)
        }
        return primaryMatch
    }

    // MARK: - DNS Application & Cache Flushing

    public func apply(preset: DNSPreset) {
        guard !isWorking else { return }
        isWorking = true
        statusNotice = "Applying \(preset.name)…"

        Task {
            let targetInterfaces: [String]
            if self.selectedInterfaceID == "all" {
                targetInterfaces = self.interfaces.map { $0.id }
            } else if let target = self.effectiveTargetInterfaceName {
                targetInterfaces = [target]
            } else {
                targetInterfaces = ["Wi-Fi"]
            }

            let isDHCP = preset.isDHCP
            let primary = preset.primaryIP
            let secondary = preset.secondaryIP

            let success = await Task.detached(priority: .userInitiated) {
                var ok = true
                for iface in targetInterfaces {
                    let res: Int32
                    if isDHCP {
                        res = self.runTool("/usr/sbin/networksetup", ["-setdnsservers", iface, "empty"])
                    } else if secondary.isEmpty {
                        res = self.runTool("/usr/sbin/networksetup", ["-setdnsservers", iface, primary])
                    } else {
                        res = self.runTool("/usr/sbin/networksetup", ["-setdnsservers", iface, primary, secondary])
                    }
                    if res != 0 { ok = false }
                }
                // Flush macOS DNS cache
                self.flushResolverCache()
                return ok
            }.value

            await self.reloadNetworkState()
            self.isWorking = false
            if success {
                self.statusNotice = "✓ Successfully switched to \(preset.name)"
            } else {
                self.statusNotice = "⚠️ Some network interfaces could not be updated."
            }

            // Auto-clear notice after 4 seconds
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.statusNotice?.contains(preset.name) == true {
                self.statusNotice = nil
            }
        }
    }

    public func restoreAutomaticDHCP() {
        apply(preset: DNSPreset.automatic)
    }

    public func flushDNSCache() {
        guard !isWorking else { return }
        isWorking = true
        statusNotice = "Flushing macOS DNS resolver cache…"

        Task {
            await Task.detached(priority: .userInitiated) {
                self.flushResolverCache()
            }.value

            await self.reloadNetworkState()
            self.isWorking = false
            self.statusNotice = "✓ DNS resolver cache cleared and refreshed"

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.statusNotice?.contains("resolver cache") == true {
                self.statusNotice = nil
            }
        }
    }

    // MARK: - Latency Testing

    public func testLatency(for preset: DNSPreset) {
        guard !preset.isDHCP, !preset.primaryIP.isEmpty else { return }
        isTestingPing[preset.id] = true

        Task {
            let ms = await Task.detached(priority: .utility) {
                return self.measurePing(ip: preset.primaryIP)
            }.value

            self.latencies[preset.id] = ms
            self.isTestingPing[preset.id] = false
        }
    }

    public func testAllLatencies() {
        let all = DNSPreset.builtInPresets + customPresets
        for preset in all where !preset.isDHCP {
            testLatency(for: preset)
        }
    }

    // MARK: - Custom Presets Management

    public func addCustomPreset(name: String, primary: String, secondary: String, tag: String = "CUSTOM") {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecondary = secondary.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty, !cleanPrimary.isEmpty else { return }

        let preset = DNSPreset(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: cleanName,
            category: .custom,
            primaryIP: cleanPrimary,
            secondaryIP: cleanSecondary,
            tag: tag.isEmpty ? "CUSTOM" : tag.uppercased(),
            description: "Custom user-configured DNS server."
        )

        customPresets.append(preset)
        saveCustomPresets()
    }

    public func removeCustomPreset(id: String) {
        customPresets.removeAll(where: { $0.id == id })
        saveCustomPresets()
    }

    private func loadCustomPresets() {
        guard let data = UserDefaults.standard.data(forKey: customPresetsKey),
              let list = try? JSONDecoder().decode([DNSPreset].self, from: data) else {
            return
        }
        self.customPresets = list
    }

    private func saveCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: customPresetsKey)
        }
    }

    // MARK: - Low-Level CLI Helpers (Non-isolated)

    nonisolated private func queryDefaultRouteDevice() -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/sbin/route")
        p.arguments = ["get", "default"]
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
            for line in out.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    return trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        } catch {}
        return ""
    }

    nonisolated private func queryHardwarePorts() -> [String: String] {
        var map: [String: String] = [:]
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-listallhardwareports"]
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)

            var currentPort = ""
            for line in out.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Hardware Port:") {
                    currentPort = trimmed.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("Device:") && !currentPort.isEmpty {
                    let dev = trimmed.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                    map[currentPort] = dev
                    currentPort = ""
                }
            }
        } catch {}
        return map
    }

    nonisolated private func queryNetworkServices() -> [String] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-listallnetworkservices"]
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
            return out.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
        } catch {}
        return []
    }

    nonisolated private func queryConfiguredDNS(for service: String) -> [String] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-getdnsservers", service]
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
            if out.contains("There aren't any DNS Servers") {
                return []
            }
            return out.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.contains(".") }
        } catch {}
        return []
    }

    nonisolated private func queryActiveResolvers() -> [String] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--dns"]
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
            var servers: [String] = []
            for line in out.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("nameserver[") {
                    let parts = trimmed.split(separator: ":")
                    if parts.count >= 2 {
                        let ip = parts[1].trimmingCharacters(in: .whitespaces)
                        if !servers.contains(ip) && ip.contains(".") {
                            servers.append(ip)
                        }
                    }
                }
            }
            return servers
        } catch {}
        return []
    }

    nonisolated private func flushResolverCache() {
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        p1.arguments = ["-flushcache"]
        try? p1.run()
        p1.waitUntilExit()

        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p2.arguments = ["-HUP", "mDNSResponder"]
        try? p2.run()
        p2.waitUntilExit()
    }

    nonisolated private func measurePing(ip: String) -> Double {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/sbin/ping")
        p.arguments = ["-c", "1", "-W", "1000", ip]
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return -1 }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
            // Parse: time=12.34 ms
            if let range = out.range(of: "time=") {
                let sub = out[range.upperBound...]
                let parts = sub.split(separator: " ")
                if let numStr = parts.first, let ms = Double(numStr) {
                    return ms
                }
            }
        } catch {}
        return -1
    }

    nonisolated private func runTool(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }
}
