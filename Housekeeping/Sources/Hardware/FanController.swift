// Housekeeping — Fan and Thermal Hardware Control
//
// Native Apple SMC and IOHID interface for Apple Silicon (M1/M2/M3/M4/M5) and Intel Macs.
// Provides live fan RPM readouts, mode control (Auto / Presets / Manual), and thermal sensors.

import Foundation
import IOKit
import AppKit

// MARK: - SMC Data Types and Constants

private enum SMCDataType: String {
    case UI8 = "ui8 "
    case UI16 = "ui16"
    case UI32 = "ui32"
    case SP78 = "sp78"
    case FLT = "flt "
    case FPE2 = "fpe2"
}

private enum SMCKeys: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

public enum FanMode: Int, Codable, Sendable {
    case automatic = 0
    case forced = 1
    case auto3 = 3

    public var isAutomatic: Bool {
        self == .automatic || self == .auto3
    }
}

public enum FanPreset: String, CaseIterable, Identifiable {
    case systemAuto = "System Auto"
    case quiet = "Quiet"
    case balanced = "Balanced"
    case maximum = "Full Blast"
    case custom = "Custom"

    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .systemAuto: return "gearshape.2"
        case .quiet: return "leaf"
        case .balanced: return "wind"
        case .maximum: return "tornado"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    public var description: String {
        switch self {
        case .systemAuto: return "macOS manages fan speed based on thermal demand"
        case .quiet: return "Runs at minimum baseline RPM for silent operation"
        case .balanced: return "Elevated 50% RPM for sustained heavy workloads"
        case .maximum: return "100% maximum RPM for rapid thermal cooling"
        case .custom: return "Manually adjust target RPM slider"
        }
    }
}

private struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)
    
    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    
    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

fileprivate struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
    init(_ key: String) { self.key = key }
}

private extension FourCharCode {
    init(fromString str: String) {
        self = str.utf8.reduce(0) { sum, character in sum << 8 | UInt32(character) }
    }
    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 8  & 0xff)!) +
               String(describing: UnicodeScalar(self       & 0xff)!)
    }
}

private extension Float {
    init?(_ bytes: [UInt8]) {
        self = bytes.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Self.self) }
    }
    var bytes: [UInt8] { withUnsafeBytes(of: self, Array.init) }
}

// MARK: - SMC Driver Client

final class SMCClient: @unchecked Sendable {
    static let shared = SMCClient()
    private var conn: io_connect_t = 0
    private let lock = NSLock()
    private var keyInfoCache: [UInt32: SMCKeyData_t.keyInfo_t] = [:]
    private var fanModeKeyIsLower: Bool?

    init() {
        open()
    }

    deinit {
        close()
    }

    private func open() {
        lock.lock()
        defer { lock.unlock() }
        guard conn == 0 else { return }
        var iterator: io_iterator_t = 0
        let matching: CFMutableDictionary = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else { return }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }
        _ = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
        keyInfoCache.removeAll()
    }

    private func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        if conn == 0 { open() }
        guard conn != 0 else { return kIOReturnNotOpen }
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }

    fileprivate func read(_ value: UnsafeMutablePointer<SMCVal_t>) -> kern_return_t {
        guard value.pointee.key.count == 4, value.pointee.key.utf8.count == 4 else { return kIOReturnBadArgument }
        lock.lock()
        defer { lock.unlock() }

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = FourCharCode(fromString: value.pointee.key)

        let keyInfo: SMCKeyData_t.keyInfo_t
        if let cached = keyInfoCache[input.key] {
            keyInfo = cached
        } else {
            input.data8 = SMCKeys.readKeyInfo.rawValue
            let r = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
            guard r == kIOReturnSuccess && output.result == 0 else { return r != kIOReturnSuccess ? r : kIOReturnNotFound }
            keyInfo = output.keyInfo
            if keyInfo.dataSize > 0 && keyInfo.dataType != 0 {
                keyInfoCache[input.key] = keyInfo
            }
        }

        value.pointee.dataSize = UInt32(keyInfo.dataSize)
        value.pointee.dataType = keyInfo.dataType.toString()
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = SMCKeys.readBytes.rawValue

        let r = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        guard r == kIOReturnSuccess && output.result == 0 else { return r != kIOReturnSuccess ? r : kIOReturnError }

        let mirror = Mirror(reflecting: output.bytes)
        var bytes: [UInt8] = []
        for (i, child) in mirror.children.enumerated() {
            if i >= Int(keyInfo.dataSize) { break }
            if let b = child.value as? UInt8 { bytes.append(b) }
        }
        for (i, b) in bytes.enumerated() where i < value.pointee.bytes.count {
            value.pointee.bytes[i] = b
        }
        return kIOReturnSuccess
    }

    fileprivate func write(_ value: SMCVal_t) -> kern_return_t {
        guard value.key.count == 4, value.key.utf8.count == 4 else { return kIOReturnBadArgument }
        lock.lock()
        defer { lock.unlock() }

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = FourCharCode(fromString: value.key)
        input.data8 = SMCKeys.writeBytes.rawValue
        input.keyInfo.dataSize = IOByteCount32(value.dataSize)
        input.bytes = (value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3], value.bytes[4], value.bytes[5],
                       value.bytes[6], value.bytes[7], value.bytes[8], value.bytes[9], value.bytes[10], value.bytes[11],
                       value.bytes[12], value.bytes[13], value.bytes[14], value.bytes[15], value.bytes[16], value.bytes[17],
                       value.bytes[18], value.bytes[19], value.bytes[20], value.bytes[21], value.bytes[22], value.bytes[23],
                       value.bytes[24], value.bytes[25], value.bytes[26], value.bytes[27], value.bytes[28], value.bytes[29],
                       value.bytes[30], value.bytes[31])

        let result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess && output.result == 0 else { return kIOReturnError }
        return kIOReturnSuccess
    }

    func getValue(_ key: String) -> Double? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0 else { return nil }
        switch val.dataType {
        case SMCDataType.UI8.rawValue:
            return Double(val.bytes[0])
        case SMCDataType.UI16.rawValue:
            return Double(UInt16(val.bytes[0]) << 8 | UInt16(val.bytes[1]))
        case SMCDataType.UI32.rawValue:
            return Double(UInt32(val.bytes[0]) << 24 | UInt32(val.bytes[1]) << 16 | UInt32(val.bytes[2]) << 8 | UInt32(val.bytes[3]))
        case SMCDataType.FLT.rawValue:
            return Float(val.bytes).map { Double($0) }
        case SMCDataType.FPE2.rawValue:
            return Double((Int(val.bytes[0]) << 6) + (Int(val.bytes[1]) >> 2))
        case SMCDataType.SP78.rawValue:
            return Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1])) / 256.0
        default:
            return nil
        }
    }

    func fanModeKey(_ id: Int) -> String {
        #if arch(arm64)
        if fanModeKeyIsLower == nil {
            var probe = SMCVal_t("F0md")
            fanModeKeyIsLower = read(&probe) == kIOReturnSuccess && probe.dataSize > 0
        }
        return (fanModeKeyIsLower == true) ? "F\(id)md" : "F\(id)Md"
        #else
        return "F\(id)Md"
        #endif
    }

    func setFanMode(_ id: Int, mode: FanMode) -> Bool {
        #if arch(arm64)
        let modeKey = fanModeKey(id)
        if mode == .forced {
            _ = unlockFanControl(fanId: id)
            var modeVal = SMCVal_t(modeKey)
            _ = read(&modeVal)
            modeVal.bytes[0] = 1
            return write(modeVal) == kIOReturnSuccess
        } else {
            // Restore auto
            var modeVal = SMCVal_t(modeKey)
            if read(&modeVal) == kIOReturnSuccess && modeVal.bytes[0] != 0 {
                modeVal.bytes[0] = 0
                _ = write(modeVal)
            }
            var targetValue = SMCVal_t("F\(id)Tg")
            if read(&targetValue) == kIOReturnSuccess {
                let zeroBytes = Float(0).bytes
                targetValue.bytes[0] = zeroBytes[0]
                targetValue.bytes[1] = zeroBytes[1]
                targetValue.bytes[2] = zeroBytes[2]
                targetValue.bytes[3] = zeroBytes[3]
                _ = write(targetValue)
            }
            var ftstVal = SMCVal_t("Ftst")
            if read(&ftstVal) == kIOReturnSuccess && ftstVal.dataSize > 0 {
                ftstVal.bytes[0] = 0
                _ = write(ftstVal)
            }
            return true
        }
        #else
        // Intel
        var value = SMCVal_t("FS! ")
        if read(&value) == kIOReturnSuccess {
            let fansMode = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            let fanBit = UInt16(1) << id
            let newMode = mode.isAutomatic ? fansMode & ~fanBit : fansMode | fanBit
            value.bytes[0] = UInt8(newMode >> 8)
            value.bytes[1] = UInt8(newMode & 0xff)
            _ = write(value)
        }
        return true
        #endif
    }

    func setFanSpeed(_ id: Int, speed: Int) -> Bool {
        guard speed >= 0 else { return false }
        #if arch(arm64)
        _ = setFanMode(id, mode: .forced)
        #endif

        var value = SMCVal_t("F\(id)Tg")
        guard read(&value) == kIOReturnSuccess else { return false }

        if value.dataType == SMCDataType.FLT.rawValue {
            let bytes = Float(speed).bytes
            for i in 0..<4 { value.bytes[i] = bytes[i] }
        } else if value.dataType == SMCDataType.FPE2.rawValue {
            let clamped = min(speed, 16383)
            value.bytes[0] = UInt8(clamped >> 6)
            value.bytes[1] = UInt8((clamped << 2) ^ ((clamped >> 6) << 8))
        } else {
            return false
        }
        return write(value) == kIOReturnSuccess
    }

    #if arch(arm64)
    private func unlockFanControl(fanId: Int) -> Bool {
        let modeKey = fanModeKey(fanId)
        var modeVal = SMCVal_t(modeKey)
        if read(&modeVal) == kIOReturnSuccess {
            modeVal.bytes[0] = 1
            if write(modeVal) == kIOReturnSuccess { return true }
        }
        var ftstVal = SMCVal_t("Ftst")
        if read(&ftstVal) == kIOReturnSuccess && ftstVal.dataSize > 0 {
            ftstVal.bytes[0] = 1
            _ = write(ftstVal)
            usleep(100_000)
            _ = read(&modeVal)
            modeVal.bytes[0] = 1
            _ = write(modeVal)
            return true
        }
        return false
    }
    #endif
}

// MARK: - Thermal Sensor Reader (IOHID & SMC)

final class ThermalReader {
    static let shared = ThermalReader()

    private typealias IOHIDEventSystemClientCreateFunc = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias IOHIDEventSystemClientSetMatchingFunc = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias IOHIDEventSystemClientCopyServicesFunc = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias IOHIDServiceClientCopyPropertyFunc = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias IOHIDServiceClientCopyEventFunc = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias IOHIDEventGetFloatValueFunc = @convention(c) (AnyObject, Int32) -> Double

    private var hidClientCreate: IOHIDEventSystemClientCreateFunc?
    private var hidSetMatching: IOHIDEventSystemClientSetMatchingFunc?
    private var hidCopyServices: IOHIDEventSystemClientCopyServicesFunc?
    private var hidCopyProperty: IOHIDServiceClientCopyPropertyFunc?
    private var hidCopyEvent: IOHIDServiceClientCopyEventFunc?
    private var hidGetFloatValue: IOHIDEventGetFloatValueFunc?

    private var hidClient: AnyObject?
    private var hidServices: [AnyObject] = []
    private var hasResolvedHID = false

    init() {
        resolveHIDFunctions()
    }

    private func resolveHIDFunctions() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        if let s = dlsym(handle, "IOHIDEventSystemClientCreate") {
            hidClientCreate = unsafeBitCast(s, to: IOHIDEventSystemClientCreateFunc.self)
        }
        if let s = dlsym(handle, "IOHIDEventSystemClientSetMatching") {
            hidSetMatching = unsafeBitCast(s, to: IOHIDEventSystemClientSetMatchingFunc.self)
        }
        if let s = dlsym(handle, "IOHIDEventSystemClientCopyServices") {
            hidCopyServices = unsafeBitCast(s, to: IOHIDEventSystemClientCopyServicesFunc.self)
        }
        if let s = dlsym(handle, "IOHIDServiceClientCopyProperty") {
            hidCopyProperty = unsafeBitCast(s, to: IOHIDServiceClientCopyPropertyFunc.self)
        }
        if let s = dlsym(handle, "IOHIDServiceClientCopyEvent") {
            hidCopyEvent = unsafeBitCast(s, to: IOHIDServiceClientCopyEventFunc.self)
        }
        if let s = dlsym(handle, "IOHIDEventGetFloatValue") {
            hidGetFloatValue = unsafeBitCast(s, to: IOHIDEventGetFloatValueFunc.self)
        }
    }

    func readTemps() -> (cpu: Double?, gpu: Double?, battery: Double?, average: Double?) {
        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        var batteryTemp: Double?

        // 1. Try IOHID on Apple Silicon
        if let clientCreate = hidClientCreate, let setMatching = hidSetMatching,
           let copyServices = hidCopyServices, let copyEvent = hidCopyEvent,
           let getFloat = hidGetFloatValue, let copyProp = hidCopyProperty {
            if hidClient == nil {
                if let unmanaged = clientCreate(kCFAllocatorDefault) {
                    let client = unmanaged.takeRetainedValue()
                    let match: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
                    setMatching(client, match as CFDictionary)
                    hidClient = client
                }
            }
            if let client = hidClient {
                if hidServices.isEmpty {
                    if let servicesUnmanaged = copyServices(client) {
                        hidServices = servicesUnmanaged.takeRetainedValue() as [AnyObject]
                    }
                }
                for s in hidServices {
                    let name = (copyProp(s, "Product" as CFString)?.takeRetainedValue() as? String)?.lowercased() ?? ""
                    if let evUnmanaged = copyEvent(s, 15, 0, 0) {
                        let ev = evUnmanaged.takeRetainedValue()
                        let val = getFloat(ev, 15 << 16)
                        if val > 15 && val < 115 {
                            if name.contains("battery") {
                                batteryTemp = val
                            } else if name.contains("gpu") {
                                gpuTemps.append(val)
                            } else {
                                cpuTemps.append(val)
                            }
                        }
                    }
                }
            }
        }

        // 2. SMC fallback for Intel or missing sensors
        let smc = SMCClient.shared
        if cpuTemps.isEmpty {
            for key in ["TC0P", "TC0D", "TC0E", "TC0F", "Tp09", "Tp0T"] {
                if let t = smc.getValue(key), t > 15 && t < 115 {
                    cpuTemps.append(t)
                }
            }
        }
        if gpuTemps.isEmpty {
            for key in ["TG0P", "TG0D", "TG0E"] {
                if let t = smc.getValue(key), t > 15 && t < 115 {
                    gpuTemps.append(t)
                }
            }
        }
        if batteryTemp == nil {
            if let t = smc.getValue("TB0T"), t > 10 && t < 80 {
                batteryTemp = t
            }
        }

        let cpuAvg = cpuTemps.isEmpty ? nil : (cpuTemps.reduce(0, +) / Double(cpuTemps.count))
        let gpuAvg = gpuTemps.isEmpty ? nil : (gpuTemps.reduce(0, +) / Double(gpuTemps.count))
        let allTemps = cpuTemps + gpuTemps
        let overallAvg = allTemps.isEmpty ? nil : (allTemps.reduce(0, +) / Double(allTemps.count))

        return (cpuAvg, gpuAvg, batteryTemp, overallAvg)
    }
}

// MARK: - Fan Information Model

public struct FanInfo: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public var currentRPM: Double
    public var targetRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var isManual: Bool

    public var percentage: Double {
        guard maxRPM > minRPM else { return 0 }
        return max(0, min(1, (currentRPM - minRPM) / (maxRPM - minRPM)))
    }
}

// MARK: - Fan & Thermal Controller Observable State

@MainActor
public final class FanController: ObservableObject {
    public static let shared = FanController()

    @Published public private(set) var fans: [FanInfo] = []
    @Published public private(set) var hasFans: Bool = true
    @Published public private(set) var isSupported: Bool = true
    @Published public private(set) var activePreset: FanPreset = .systemAuto

    @Published public private(set) var cpuTemperature: Double?
    @Published public private(set) var gpuTemperature: Double?
    @Published public private(set) var batteryTemperature: Double?
    @Published public private(set) var averageTemperature: Double?

    @Published public var customTargetRPM: Double = 2500

    private var monitorTimer: Timer?
    private let smc = SMCClient.shared
    private let thermal = ThermalReader.shared

    public init() {
        refresh()
        startMonitoring()
        // Ensure safety: restore Auto when application terminates
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetToAuto()
            }
        }
    }

    public func startMonitoring() {
        guard monitorTimer == nil else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    public func refresh() {
        Task.detached(priority: .userInitiated) { [smc, thermal] in
            let temps = thermal.readTemps()
            var detectedFans: [FanInfo] = []
            let fanCountVal = smc.getValue("FNum")
            let count = fanCountVal.map { Int($0) } ?? 0

            for i in 0..<count {
                let actual = smc.getValue("F\(i)Ac") ?? 0
                let minRPM = smc.getValue("F\(i)Mn") ?? 1200
                let maxRPM = smc.getValue("F\(i)Mx") ?? 5000
                let target = smc.getValue("F\(i)Tg") ?? actual
                let modeVal = smc.getValue("F\(i)md") ?? smc.getValue("F\(i)Md") ?? 0
                let isManual = (modeVal != 0)

                let fanName = count == 1 ? "System Fan" : (i == 0 ? "Left Fan (CPU)" : "Right Fan (GPU)")
                detectedFans.append(FanInfo(
                    id: i,
                    name: fanName,
                    currentRPM: actual,
                    targetRPM: target,
                    minRPM: minRPM,
                    maxRPM: maxRPM,
                    isManual: isManual
                ))
            }
            let finalFans = detectedFans

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cpuTemperature = temps.cpu
                self.gpuTemperature = temps.gpu
                self.batteryTemperature = temps.battery
                self.averageTemperature = temps.average
                self.fans = finalFans
                self.hasFans = (count > 0)
                if let firstFan = finalFans.first, firstFan.isManual {
                    if self.activePreset == .systemAuto {
                        self.activePreset = .custom
                    }
                }
            }
        }
    }

    public func applyPreset(_ preset: FanPreset) {
        activePreset = preset
        switch preset {
        case .systemAuto:
            resetToAuto()
        case .quiet:
            for fan in fans {
                _ = smc.setFanSpeed(fan.id, speed: Int(fan.minRPM))
            }
            refresh()
        case .balanced:
            for fan in fans {
                let mid = Int(fan.minRPM + (fan.maxRPM - fan.minRPM) * 0.5)
                _ = smc.setFanSpeed(fan.id, speed: mid)
            }
            refresh()
        case .maximum:
            for fan in fans {
                _ = smc.setFanSpeed(fan.id, speed: Int(fan.maxRPM))
            }
            refresh()
        case .custom:
            applyCustomRPM(Int(customTargetRPM))
        }
    }

    public func applyCustomRPM(_ rpm: Int) {
        activePreset = .custom
        for fan in fans {
            let clamped = max(Int(fan.minRPM), min(Int(fan.maxRPM), rpm))
            _ = smc.setFanSpeed(fan.id, speed: clamped)
        }
        refresh()
    }

    public func resetToAuto() {
        activePreset = .systemAuto
        for fan in fans {
            _ = smc.setFanMode(fan.id, mode: .automatic)
        }
        refresh()
    }
}
