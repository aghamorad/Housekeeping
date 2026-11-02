// Housekeeping — Battery Health & Power Management Engine
//
// Native Darwin IOKit hardware interface and pmset assertion watcher.
// Reads Apple Silicon and Intel Smart Battery telemetry, cycle count degradation,
// power delivery metrics, and live sleep inhibitors with zero external dependencies.

import Foundation
import IOKit
import AppKit

@MainActor
public final class BatteryHealthEngine: ObservableObject {
    public static let shared = BatteryHealthEngine()

    @Published public private(set) var telemetry: BatteryTelemetry = .empty
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    private var refreshTimer: Timer?
    private var isRefreshing: Bool = false

    public init() {
        refresh()
    }

    public func startAutoRefresh(interval: TimeInterval = 6.0) {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        let tempCelsius = FanController.shared.batteryTemperature

        Task.detached(priority: .userInitiated) {
            let data = Self.readHardwareTelemetry(tempCelsius: tempCelsius)
            await MainActor.run {
                self.telemetry = data
                self.isLoading = false
                self.isRefreshing = false
            }
        }
    }

    // MARK: - Process and Setting Controls

    public func openSystemBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    public func terminateInhibitor(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        } else {
            kill(pid, SIGTERM)
        }
        // Refresh telemetry after brief delay to reflect cleared assertion
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.refresh()
        }
    }

    // MARK: - Hardware Reading Implementation

    private nonisolated static func readHardwareTelemetry(tempCelsius: Double?) -> BatteryTelemetry {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return BatteryTelemetry.empty
        }

        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return BatteryTelemetry.empty
        }

        // 1. Direct top-level registers
        let cycleCount = (dict["CycleCount"] as? Int) ?? 0
        let designCycleCount = (dict["DesignCycleCount9C"] as? Int) ?? (dict["DesignCycleCount"] as? Int) ?? 1000
        let voltageMv = (dict["Voltage"] as? Int) ?? (dict["AppleRawBatteryVoltage"] as? Int) ?? 0
        let amperageMa = (dict["Amperage"] as? Int) ?? 0
        let currentPercent = (dict["CurrentCapacity"] as? Int) ?? 0
        let isPluggedIn = (dict["ExternalConnected"] as? Bool) ?? false
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let deviceName = dict["DeviceName"] as? String
        let serialNumber = dict["Serial"] as? String

        // 2. BatteryData nested telemetry
        let batteryData = dict["BatteryData"] as? [String: Any]
        let fullChargeMah = (batteryData?["FullChargeCapacity"] as? Int) ?? (dict["AppleRawMaxCapacity"] as? Int) ?? 0
        let designMah = (batteryData?["DesignCapacity"] as? Int) ?? (dict["DesignCapacity"] as? Int) ?? 0
        let currentMah = (batteryData?["RemainingCapacity"] as? Int) ?? 0

        // 3. Charger & Adapter telemetry
        let adapterDetails = dict["AdapterDetails"] as? [String: Any]
        let adapterWatts = adapterDetails?["Watts"] as? Int
        let adapterDesc = adapterDetails?["Description"] as? String
        let adapterVoltage = adapterDetails?["AdapterVoltage"] as? Int
        let adapterCurrent = adapterDetails?["Current"] as? Int

        let chargerData = dict["ChargerData"] as? [String: Any]
        let notChargingReason = chargerData?["NotChargingReason"] as? Int ?? 0
        // Apple 80% limit / Optimized Charging sets NotChargingReason bit 24 (16777216)
        let isOptimizedHold = (notChargingReason == 16777216) || (isPluggedIn && !isCharging && currentPercent >= 75)

        // 4. Health calculation
        var rawHealthPercent = 100
        if designMah > 0 && fullChargeMah > 0 {
            rawHealthPercent = Int((Double(fullChargeMah) / Double(designMah) * 100.0).rounded())
        }

        // 5. Battery condition evaluation
        let condition: BatteryCondition
        if rawHealthPercent >= 80 && cycleCount < 1000 {
            condition = .normal
        } else if rawHealthPercent >= 70 {
            condition = .fair
        } else if rawHealthPercent >= 55 {
            condition = .serviceRecommended
        } else {
            condition = .replaceNow
        }

        // 6. Battery thermal sensor is passed in from MainActor

        // 7. Low Power Mode reading
        let lowPowerMode = readLowPowerModeState()

        // 8. Sleep inhibitors from pmset
        let inhibitors = readPmsetSleepInhibitors()

        return BatteryTelemetry(
            hasBattery: true,
            chargePercent: currentPercent,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isOptimizedHold: isOptimizedHold,
            healthPercent: rawHealthPercent,
            condition: condition,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            designCapacityMah: designMah,
            fullChargeCapacityMah: fullChargeMah,
            currentCapacityMah: currentMah,
            voltageMv: voltageMv,
            amperageMa: amperageMa,
            temperatureCelsius: tempCelsius,
            adapterWatts: adapterWatts,
            adapterDescription: adapterDesc,
            adapterVoltageMv: adapterVoltage,
            adapterCurrentMa: adapterCurrent,
            deviceName: deviceName,
            serialNumber: serialNumber,
            lowPowerMode: lowPowerMode,
            sleepInhibitors: inhibitors,
            timestamp: Date()
        )
    }

    private nonisolated static func readLowPowerModeState() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("lowpowermode         1") || output.contains("lowpowermode 1")
            }
        } catch {}
        return false
    }

    private nonisolated static func readPmsetSleepInhibitors() -> [SleepInhibitor] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        task.standardOutput = pipe
        var list: [SleepInhibitor] = []

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            // Match lines like: pid 42224(Google Chrome): [0x...] 00:53:44 NoIdleSleepAssertion named: "Playing audio"
            let regex = try NSRegularExpression(
                pattern: "pid\\s+(\\d+)\\((.+?)\\):\\s+\\[[^\\]]+\\]\\s+([0-9:]+)\\s+(\\w+)\\s+named:\\s+\"(.*?)\""
            )
            let nsOutput = output as NSString
            let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))

            for match in matches {
                guard match.numberOfRanges >= 6 else { continue }
                let pidStr = nsOutput.substring(with: match.range(at: 1))
                let name = nsOutput.substring(with: match.range(at: 2))
                let time = nsOutput.substring(with: match.range(at: 3))
                let assertionType = nsOutput.substring(with: match.range(at: 4))
                let details = nsOutput.substring(with: match.range(at: 5))

                let pid = Int32(pidStr) ?? 0
                let isSystem = name == "powerd" || name == "WindowServer" || name == "launchd"

                list.append(
                    SleepInhibitor(
                        pid: pid,
                        name: name,
                        assertionType: assertionType,
                        details: details,
                        timeActive: time,
                        isSystem: isSystem
                    )
                )
            }
        } catch {}

        // Sort so user-facing apps appear first, then longest active time
        return list.sorted { a, b in
            if a.isSystem != b.isSystem {
                return !a.isSystem && b.isSystem
            }
            return a.timeActive > b.timeActive
        }
    }
}
