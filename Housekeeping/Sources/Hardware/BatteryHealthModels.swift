// Housekeeping — Battery Health Models
//
// Typed telemetry representations for Apple Silicon and Intel Smart Battery hardware,
// power adapters, cycle life, degradation, and macOS sleep inhibitor assertions.

import Foundation
import SwiftUI

public enum BatteryCondition: String, Codable, Sendable {
    case normal = "Normal"
    case fair = "Fair"
    case serviceRecommended = "Service Recommended"
    case replaceNow = "Replace Now"

    public var title: String { rawValue }

    public var color: Color {
        switch self {
        case .normal: return Color(red: 0.2, green: 0.78, blue: 0.35) // Vibrant Emerald
        case .fair: return Color(red: 0.95, green: 0.65, blue: 0.15) // Amber
        case .serviceRecommended, .replaceNow: return Color(red: 0.92, green: 0.28, blue: 0.25) // Ruby
        }
    }

    public var description: String {
        switch self {
        case .normal:
            return "Your battery is operating within normal manufacturer specifications and retains healthy capacity."
        case .fair:
            return "Your battery shows noticeable chemical aging but continues to operate safely for portable use."
        case .serviceRecommended:
            return "Battery capacity has dropped below 80% or cycle count has exceeded Apple's design limit. Service is recommended."
        case .replaceNow:
            return "Cell degradation is severe. Runtime is significantly limited, and battery replacement is strongly advised."
        }
    }
}

public struct SleepInhibitor: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let pid: pid_t
    public let name: String
    public let assertionType: String
    public let details: String
    public let timeActive: String
    public let isSystem: Bool

    public init(
        id: UUID = UUID(),
        pid: pid_t,
        name: String,
        assertionType: String,
        details: String,
        timeActive: String,
        isSystem: Bool
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.assertionType = assertionType
        self.details = details
        self.timeActive = timeActive
        self.isSystem = isSystem
    }

    public var humanAssertionType: String {
        switch assertionType {
        case "PreventUserIdleSystemSleep":
            return "Preventing Idle System Sleep"
        case "PreventUserIdleDisplaySleep":
            return "Preventing Display Sleep"
        case "NoIdleSleepAssertion":
            return "Preventing App Idle Sleep"
        case "ExternalMedia":
            return "External Drive Mounted"
        case "UserIsActive":
            return "Active Keyboard / Trackpad Input"
        case "BackgroundTask":
            return "Background Processing Task"
        default:
            return assertionType
        }
    }
}

public struct BatteryTelemetry: Sendable, Equatable {
    public let hasBattery: Bool
    public let chargePercent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let isOptimizedHold: Bool
    public let healthPercent: Int
    public let condition: BatteryCondition
    public let cycleCount: Int
    public let designCycleCount: Int
    public let designCapacityMah: Int
    public let fullChargeCapacityMah: Int
    public let currentCapacityMah: Int
    public let voltageMv: Int
    public let amperageMa: Int
    public let temperatureCelsius: Double?
    public let adapterWatts: Int?
    public let adapterDescription: String?
    public let adapterVoltageMv: Int?
    public let adapterCurrentMa: Int?
    public let deviceName: String?
    public let serialNumber: String?
    public let lowPowerMode: Bool
    public let sleepInhibitors: [SleepInhibitor]
    public let timestamp: Date

    public init(
        hasBattery: Bool = true,
        chargePercent: Int = 0,
        isCharging: Bool = false,
        isPluggedIn: Bool = false,
        isOptimizedHold: Bool = false,
        healthPercent: Int = 100,
        condition: BatteryCondition = .normal,
        cycleCount: Int = 0,
        designCycleCount: Int = 1000,
        designCapacityMah: Int = 0,
        fullChargeCapacityMah: Int = 0,
        currentCapacityMah: Int = 0,
        voltageMv: Int = 0,
        amperageMa: Int = 0,
        temperatureCelsius: Double? = nil,
        adapterWatts: Int? = nil,
        adapterDescription: String? = nil,
        adapterVoltageMv: Int? = nil,
        adapterCurrentMa: Int? = nil,
        deviceName: String? = nil,
        serialNumber: String? = nil,
        lowPowerMode: Bool = false,
        sleepInhibitors: [SleepInhibitor] = [],
        timestamp: Date = Date()
    ) {
        self.hasBattery = hasBattery
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isOptimizedHold = isOptimizedHold
        self.healthPercent = healthPercent
        self.condition = condition
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.designCapacityMah = designCapacityMah
        self.fullChargeCapacityMah = fullChargeCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.voltageMv = voltageMv
        self.amperageMa = amperageMa
        self.temperatureCelsius = temperatureCelsius
        self.adapterWatts = adapterWatts
        self.adapterDescription = adapterDescription
        self.adapterVoltageMv = adapterVoltageMv
        self.adapterCurrentMa = adapterCurrentMa
        self.deviceName = deviceName
        self.serialNumber = serialNumber
        self.lowPowerMode = lowPowerMode
        self.sleepInhibitors = sleepInhibitors
        self.timestamp = timestamp
    }

    public var cycleFraction: Double {
        guard designCycleCount > 0 else { return 0 }
        return min(1.0, max(0.0, Double(cycleCount) / Double(designCycleCount)))
    }

    public var cyclesRemaining: Int {
        return max(0, designCycleCount - cycleCount)
    }

    public var capacityLossMah: Int {
        guard designCapacityMah > 0, fullChargeCapacityMah > 0 else { return 0 }
        return max(0, designCapacityMah - fullChargeCapacityMah)
    }

    public var voltageVolts: Double {
        return Double(voltageMv) / 1000.0
    }

    public var powerWatts: Double {
        let v = Double(voltageMv) / 1000.0
        let a = Double(abs(amperageMa)) / 1000.0
        return v * a
    }

    public static let empty = BatteryTelemetry(hasBattery: false)
}
