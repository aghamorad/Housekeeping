// Housekeeping — the house, measured
//
// The panel behind the octopus shows the machine as it is now, so every number
// here comes from a live reading rather than a stored file. Three of them are
// differences between two readings — processor time, network bytes, and the CPU
// time each process has spent — because a counter that only ever climbs says
// nothing on its own. Those deltas are why the readings are kept and subtracted
// rather than reported raw.
//
// Nothing here runs until the panel is opened. A menu bar app that measures once
// a second forever, with nobody looking, is the kind of thing this app exists to
// point at.

import Foundation
import Darwin
import IOKit
import IOKit.ps

struct ProcessLoad: Identifiable, Equatable {
    let id: pid_t
    let name: String
    /// Fraction of one core, so a busy process can read above 100%.
    let cpu: Double
    /// Physical memory the process is holding, the same figure Activity Monitor
    /// calls its memory. Read from the same rusage as the CPU time.
    let memory: UInt64
}

struct BatteryState: Equatable {
    let percent: Int
    let charging: Bool
    let onAC: Bool
    let minutesLeft: Int?
}

struct VitalsSnapshot: Equatable {
    var cpu: Double = 0
    var coreCount: Int = ProcessInfo.processInfo.processorCount
    var cpuHistory: [Double] = []

    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var memoryHistory: [Double] = []

    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var diskFree: UInt64 = 0

    var downPerSecond: Double = 0
    var upPerSecond: Double = 0
    var networkHistory: [Double] = []

    var gpu: Double?
    var battery: BatteryState?
    var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    /// The busiest hands. Kept to four because the panel names the first three.
    var processes: [ProcessLoad] = []
    /// The biggest holders of memory, which are rarely the busiest hands — a
    /// browser idles at no processor time while holding gigabytes.
    var memoryHogs: [ProcessLoad] = []

    var memoryFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }

    var diskFraction: Double {
        diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0
    }

    /// One number for the ring beside her name. It is a summary, not a verdict
    /// about the machine's health: disk above 80% is the only part that gets
    /// sharply worse, because that is the one thing the reader has to act on.
    var healthScore: Int {
        let processor = cpu * 30
        let memory = memoryFraction * 35
        let disk = max(0, diskFraction - 0.8) * 120
        return max(0, min(100, Int((100 - processor - memory - disk).rounded())))
    }

    var isMeasuring: Bool { memoryTotal == 0 }
}

@MainActor
final class SystemVitals: NSObject, ObservableObject {
    static let shared = SystemVitals()

    @Published private(set) var snapshot = VitalsSnapshot()

    let machineName: String
    let osVersion: String

    private var timer: Timer?
    private var previousCPU: (busy: Double, total: Double)?
    private var previousInterfaces: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var previousProcessTimes: [pid_t: (cpu: UInt64, memory: UInt64)] = [:]
    private var lastProcessSample = Date()
    private var quickProcessSample = false

    private var cpuHistory: [Double] = []
    private var memoryHistory: [Double] = []
    private var networkHistory: [Double] = []
    private static let historyLimit = 48

    private override init() {
        machineName = Self.readMachineName()
        osVersion = Self.readOSVersion()
        super.init()
    }

    // MARK: - Running

    func start() {
        guard timer == nil else { return }
        sample()

        // A process's CPU share is the difference between two readings, so the
        // first one is only a baseline. Without taking it here, that baseline
        // would be the first *scheduled* sample, and the panel would say
        // "watching…" for the first seconds it was open. Take it now, then let
        // the first tick a second later complete the pair.
        previousProcessTimes = readProcessUsage()
        lastProcessSample = Date()
        quickProcessSample = true

        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-reads now rather than up to 2.5 seconds from now. Used after the panel
    /// has stopped a process, so the list it is looking at does not keep naming it.
    /// The last process sample is backdated past the sampling threshold, which
    /// gives the CPU shares a real interval to divide by instead of a few
    /// milliseconds of noise.
    func refresh() {
        lastProcessSample = Date().addingTimeInterval(-0.6)
        sample()
    }

    /// Sends a stop signal to one process. Returns what went wrong, or nil.
    ///
    /// The normal signal is a request the process is free to answer on its own
    /// terms — save, close, exit. The force signal takes the memory away where it
    /// stands. Either way, the answer is Housekeeping's: a process it cannot signal
    /// is reported rather than retried harder.
    @discardableResult
    func stop(_ process: ProcessLoad, force: Bool) -> String? {
        guard process.id > 1, process.id != getpid() else {
            return "Housekeeping will not stop that process."
        }
        if kill(process.id, force ? SIGKILL : SIGTERM) != 0 {
            switch errno {
            case ESRCH:
                // It left between the last sample and the press.
                refresh()
                return nil
            case EPERM:
                return "macOS would not let Housekeeping stop \(process.name). It belongs to the system or to another user."
            default:
                return String(cString: strerror(errno))
            }
        }
        refresh()
        return nil
    }

    @objc private func tick() {
        sample()
    }

    // MARK: - Sampling

    private func sample() {
        let cpu = readCPU()
        let memory = readMemory()
        let disk = readDisk()
        let network = readNetwork()

        append(cpu, to: &cpuHistory)
        append(Double(memory.used) / Double(max(memory.total, 1)), to: &memoryHistory)
        append(min(1, (network.down + network.up) / (20 * 1024 * 1024)), to: &networkHistory)

        var next = VitalsSnapshot()
        next.cpu = cpu
        next.cpuHistory = cpuHistory
        next.memoryUsed = memory.used
        next.memoryTotal = memory.total
        next.memoryHistory = memoryHistory
        next.diskUsed = disk.used
        next.diskTotal = disk.total
        next.diskFree = disk.free
        next.downPerSecond = network.down
        next.upPerSecond = network.up
        next.networkHistory = networkHistory
        next.gpu = readGPU()
        next.battery = readBattery()
        next.uptime = ProcessInfo.processInfo.systemUptime
        let hands = readProcesses()
        next.processes = hands.busy
        next.memoryHogs = hands.holding
        snapshot = next
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    private func readCPU() -> Double {
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var ncpu: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count)
        guard result == KERN_SUCCESS, let info else { return snapshot.cpu }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(info))),
                vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var busy: Double = 0
        var idle: Double = 0
        var index = 0
        while index + Int(CPU_STATE_MAX) <= Int(count) {
            busy += Double(info[index + Int(CPU_STATE_USER)])
            busy += Double(info[index + Int(CPU_STATE_SYSTEM)])
            busy += Double(info[index + Int(CPU_STATE_NICE)])
            idle += Double(info[index + Int(CPU_STATE_IDLE)])
            index += Int(CPU_STATE_MAX)
        }

        let total = busy + idle
        defer { previousCPU = (busy, total) }
        guard let previous = previousCPU else { return 0 }
        let busyDelta = busy - previous.busy
        let totalDelta = total - previous.total
        guard totalDelta > 0 else { return snapshot.cpu }
        return min(1, max(0, busyDelta / totalDelta))
    }

    private func readMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }

        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    private func readDisk() -> (used: UInt64, total: UInt64, free: UInt64) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value,
              total > 0 else { return (0, 0, 0) }
        return (total > free ? total - free : 0, total, free)
    }

    private func readNetwork() -> (down: Double, up: Double) {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return (0, 0) }
        defer { freeifaddrs(interfaces) }

        var down: Double = 0
        var up: Double = 0
        var current: [String: (rx: UInt32, tx: UInt32)] = [:]
        var pointer = first

        while true {
            let entry = pointer.pointee
            if entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let raw = entry.ifa_data {
                let name = String(cString: entry.ifa_name)
                if !name.hasPrefix("lo") {
                    let stats = raw.assumingMemoryBound(to: if_data.self).pointee
                    let rx = stats.ifi_ibytes
                    let tx = stats.ifi_obytes
                    current[name] = (rx, tx)
                    if let previous = previousInterfaces[name] {
                        // The counters are 32-bit and wrap; wrapping subtraction is
                        // the difference, not a negative number.
                        down += Double(rx &- previous.rx)
                        up += Double(tx &- previous.tx)
                    }
                }
            }
            guard let next = entry.ifa_next else { break }
            pointer = next
        }

        previousInterfaces = current
        return (down, up)
    }

    private func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
               let utilization = statistics["Device Utilization %"] as? NSNumber {
                IOObjectRelease(service)
                return min(1, max(0, utilization.doubleValue / 100))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private func readBattery() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }

            let minutes = (description[kIOPSTimeToEmptyKey] as? Int) ?? -1
            return BatteryState(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                charging: (description[kIOPSIsChargingKey] as? Bool) ?? false,
                onAC: (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                minutesLeft: minutes > 0 ? minutes : nil
            )
        }
        return nil
    }

    /// CPU time and memory for every process, from one rusage each. The two
    /// readings are collected together because the second is free: `phys_footprint`
    /// is already in the structure that supplies the CPU time.
    private func readProcessUsage() -> [pid_t: (cpu: UInt64, memory: UInt64)] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.size + 32)
        let filled = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return [:] }

        var usageByPID: [pid_t: (cpu: UInt64, memory: UInt64)] = [:]
        let count = Int(filled) / MemoryLayout<pid_t>.size

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0, pid != getpid() else { continue }

            var usage = rusage_info_v4()
            let read = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
                }
            }
            guard read == 0 else { continue }

            // phys_footprint is the figure Activity Monitor calls memory: it is
            // what the process has charged against the machine, not what it has
            // merely reserved.
            usageByPID[pid] = (
                usage.ri_user_time &+ usage.ri_system_time,
                usage.ri_phys_footprint
            )
        }

        return usageByPID
    }

    private func readProcesses() -> (busy: [ProcessLoad], holding: [ProcessLoad]) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastProcessSample)
        // Every tick would mean reading a rusage for every process on the machine
        // once a second. Nothing in this panel moves that fast. The one exception
        // is the tick right after the panel opens, which finishes the pair the
        // baseline left half-done.
        guard elapsed >= (quickProcessSample ? 0.4 : 2.5) else {
            return (snapshot.processes, snapshot.memoryHogs)
        }
        lastProcessSample = now
        quickProcessSample = false

        let usages = readProcessUsage()
        var loads: [ProcessLoad] = []

        for (pid, usage) in usages {
            // The first reading of a process only establishes a baseline. Its
            // memory is real, though, so it still counts for the holders list.
            let share: Double
            if let previous = previousProcessTimes[pid] {
                let seconds = Double(usage.cpu &- previous.cpu) / 1_000_000_000
                share = seconds / elapsed
            } else {
                share = 0
            }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            let named = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = named > 0 ? String(cString: nameBuffer) : "pid \(pid)"
            loads.append(ProcessLoad(id: pid, name: name, cpu: share, memory: usage.memory))
        }

        previousProcessTimes = usages

        // A floor only to keep sleepers out. At 1% an idle Mac reports nobody at
        // all, and the panel says "watching…" while the machine is plainly doing
        // something — the three busiest hands are worth naming even when the
        // busiest is only using a tenth of a core.
        let busy = loads
            .filter { $0.cpu > 0.001 }
            .sorted { $0.cpu > $1.cpu }
        let holding = loads
            .filter { $0.memory > 8 * 1_048_576 }
            .sorted { $0.memory > $1.memory }

        return (Array(busy.prefix(4)), Array(holding.prefix(6)))
    }

    // MARK: - Machine

    private static func readMachineName() -> String {
        if let brand = sysctlString("machdep.cpu.brand_string"), !brand.isEmpty {
            if brand.contains("Intel") { return "Intel" }
            return brand.replacingOccurrences(of: "Apple ", with: "")
        }
        if let model = sysctlString("hw.model"), !model.isEmpty { return model }
        return "Mac"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func readOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }
}

// MARK: - Wording

enum VitalsFormat {
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Per-process CPU is a fraction of one core, and the busiest hand on an idle
    /// Mac is usually well under one percent — rounding to whole numbers would
    /// report a column of zeros. Tenths until the number is big enough to speak
    /// for itself.
    static func share(_ value: Double) -> String {
        let percent = value * 100
        if percent < 9.95 { return String(format: "%.1f%%", percent) }
        return "\(Int(percent.rounded()))%"
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        return gigabytes >= 100 ? String(format: "%.0f GB", gigabytes) : String(format: "%.1f GB", gigabytes)
    }

    /// For a process, where whole gigabytes would round most of the list to zero.
    static func megabytes(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1024 { return String(format: "%.1f GB", megabytes / 1024) }
        return "\(Int(megabytes.rounded())) MB"
    }

    static func rate(_ bytes: Double) -> String {
        if bytes < 1024 { return "0 KB/s" }
        if bytes < 1_048_576 { return String(format: "%.0f KB/s", bytes / 1024) }
        return String(format: "%.1f MB/s", bytes / 1_048_576)
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    static func minutes(_ value: Int?) -> String? {
        guard let value, value > 0 else { return nil }
        return "\(value / 60)h \(String(format: "%02d", value % 60))m"
    }
}
