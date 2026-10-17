// Housekeeping — Spoofing the iPhone's location
//
// The engine here is Telesm's, carried over unchanged in behaviour: one call to
// `pymobiledevice3` sets a simulated GPS position, another clears it. Nothing is
// installed on the phone and nothing on it is modified — `--userspace` builds the
// developer tunnel inside the helper process, so the app itself never needs root.
//
// The only thing Housekeeping adds is the wrapper: `ProcessRunner`, because this
// app already runs programs and needs a deadline on one that can wait for a
// phone that is not there.

import Foundation
import Darwin

/// One place the phone can be told it is standing.
struct PhoneSpot: Identifiable, Hashable {
    let id: String
    let city: String
    let detail: String
    let latitude: Double
    let longitude: Double

    static let newYork = PhoneSpot(id: "nyc", city: "New York City", detail: "Times Square",
                                   latitude: 40.7580, longitude: -73.9855)
    static let london = PhoneSpot(id: "uk", city: "London", detail: "United Kingdom",
                                  latitude: 51.5074, longitude: -0.1278)
    static let oxford = PhoneSpot(id: "oxford", city: "St Antony's College", detail: "Oxford, UK",
                                  latitude: 51.76389, longitude: -1.2625)

    static let all: [PhoneSpot] = [.newYork, .london, .oxford]
}

struct PhoneDevice: Identifiable, Hashable {
    let udid: String
    let name: String
    let isUSB: Bool

    var id: String { udid }
}

/// What one call to the helper produced, in the shape the screen needs: whether
/// it worked, and one line worth showing. The raw log is not a reading a reader
/// can act on, and a last line of ninety words is not either.
struct PhoneOutcome {
    let ok: Bool
    let message: String
}

/// The helper's output, read on a background queue by the pipe handler and read
/// back while the app waits for the line that means the place is set.
private final class PhoneOutput {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// A pseudo-terminal for the helper's output.
///
/// `pymobiledevice3` announces a successful `set` with a line drawn through
/// `rich`, and `rich` renders its status only when the stream is a terminal. Given
/// a pipe it prints nothing at all — the place is set, the phone is reporting it,
/// and the app waits for a sentence that cannot arrive until it times out and
/// kills the session it had just started. A real pty is what makes the helper
/// behave as it does in a shell, and it does so without a wrapper process between
/// the app and the session it later has to end.
private enum PhoneTerminal {
    static func make() -> (master: Int32, slave: Int32)? {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return nil }
        return (master, slave)
    }
}

enum PhoneTool {
    // `simulate-location set` never exits: it holds the DVT session open for as
    // long as the phone should keep the fake position, and it is that session —
    // not a setting stored on the phone — that the phone reports. So it is kept
    // as a child process rather than awaited. Ending that process is what ends
    // the simulation.
    private static let sessionLock = NSLock()
    private static var held: (process: Process, output: FileHandle, spot: PhoneSpot, device: PhoneDevice)?

    /// The place the phone is currently reporting, if a session is being held.
    /// Read when the screen opens so closing and reopening it does not forget a
    /// location that is still in effect.
    static var activeSpot: PhoneSpot? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard let held, held.process.isRunning else { return nil }
        return held.spot
    }

    /// Ends whatever session is holding a fake location. Called by Real GPS and
    /// when Housekeeping quits — a child process outlives the app that started it.
    static func endSession() {
        sessionLock.lock()
        let current = held
        held = nil
        sessionLock.unlock()

        guard let current else { return }
        current.output.readabilityHandler = nil
        try? current.output.close()
        guard current.process.isRunning else { return }
        current.process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while current.process.isRunning && Date() < deadline { usleep(50_000) }
        if current.process.isRunning { kill(current.process.processIdentifier, SIGKILL) }
    }

    /// The helper is a pipx or Homebrew install, and a windowed app launched
    /// from the Finder inherits no shell profile, so the fixed locations are
    /// tried before `PATH`. `NSHomeDirectory()` rather than a literal path keeps
    /// this working for any account.
    static func executable(fileManager: FileManager = .default) -> String? {
        var candidates = [
            "\(NSHomeDirectory())/.local/bin/pymobiledevice3",
            "/opt/homebrew/bin/pymobiledevice3",
            "/usr/local/bin/pymobiledevice3"
        ]
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += searchPath.split(separator: ":").map { "\($0)/pymobiledevice3" }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    static let installHint = "pipx install pymobiledevice3"

    /// `usbmux list` prints a JSON array after a line of its own. Everything
    /// before the first bracket is human-readable preamble, so the array is
    /// taken by its brackets rather than by trusting the whole output to parse.
    static func devices(runner: ProcessRunner) async -> [PhoneDevice] {
        guard let executable = executable() else { return [] }
        guard let result = try? await runner.run(
            executable: executable,
            arguments: ["usbmux", "list"],
            timeout: 30
        ) else { return [] }

        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        guard
            let start = output.firstIndex(of: "["),
            let end = output.lastIndex(of: "]"),
            start < end,
            let data = String(output[start...end]).data(using: .utf8),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        let listed = rows.compactMap { row -> PhoneDevice? in
            guard let udid = (row["Identifier"] as? String) ?? (row["UniqueDeviceID"] as? String) else {
                return nil
            }
            let connection = (row["ConnectionType"] as? String) ?? ""
            return PhoneDevice(
                udid: udid,
                name: (row["DeviceName"] as? String) ?? "iPhone",
                isUSB: connection.localizedCaseInsensitiveContains("usb")
            )
        }

        // A phone plugged in and also reachable over Wi-Fi is listed twice — two
        // rows for one device, which reads as two phones. It is one phone, so it
        // gets one row, and the USB one wins: that is the connection the helper
        // sets a location over without the pairing prompt getting involved.
        var byPhone: [String: PhoneDevice] = [:]
        for device in listed {
            if let kept = byPhone[device.udid], kept.isUSB || !device.isUSB { continue }
            byPhone[device.udid] = device
        }
        return byPhone.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func set(_ spot: PhoneSpot, on device: PhoneDevice) async -> PhoneOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: hold(spot, on: device))
            }
        }
    }

    /// Starts the helper and waits only until it reports that the coordinates
    /// have been accepted, then keeps the process — and therefore the session —
    /// alive. The first call builds the tunnel and takes about forty to fifty
    /// seconds; replacing the place rebuilds it, because the old session has to
    /// end first for the new position to be the one the phone reports.
    private static func hold(_ spot: PhoneSpot, on device: PhoneDevice) -> PhoneOutcome {
        endSession()
        guard let executable = executable() else {
            return PhoneOutcome(ok: false, message: "pymobiledevice3 is not installed. In Terminal, run: \(installHint)")
        }

        var arguments = ["developer", "dvt", "simulate-location", "set", "--udid", device.udid]
        arguments += ["--userspace", "--",
                      String(format: "%.4f", spot.latitude),
                      String(format: "%.4f", spot.longitude)]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment()

        guard let terminal = PhoneTerminal.make() else {
            return PhoneOutcome(ok: false, message: "Could not open a terminal for pymobiledevice3.")
        }
        let tty = FileHandle(fileDescriptor: terminal.slave, closeOnDealloc: false)
        process.standardInput = tty
        process.standardOutput = tty
        process.standardError = tty
        let master = FileHandle(fileDescriptor: terminal.master, closeOnDealloc: true)

        let collected = PhoneOutput()
        master.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collected.append(chunk)
        }

        do {
            try process.run()
        } catch {
            master.readabilityHandler = nil
            try? master.close()
            return PhoneOutcome(ok: false, message: "Could not start pymobiledevice3. \(error.localizedDescription)")
        }
        // The child has its own copy; this one only keeps the parent attached to a
        // terminal it does not read from.
        close(terminal.slave)

        // The helper prints this line after `set` has returned, so it is the
        // point at which the phone has acknowledged the coordinates.
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline {
            if collected.text.contains("Press Ctrl+C") {
                sessionLock.lock()
                held = (process, master, spot, device)
                sessionLock.unlock()
                return PhoneOutcome(ok: true, message: "\(spot.city) is set. The iPhone reports it until Real GPS is pressed or the phone is unplugged.")
            }
            if !process.isRunning {
                master.readabilityHandler = nil
                try? master.close()
                return PhoneOutcome(ok: false, message: lastLine(of: collected.text,
                                                                 status: process.terminationStatus))
            }
            usleep(120_000)
        }

        process.terminate()
        master.readabilityHandler = nil
        try? master.close()
        return PhoneOutcome(ok: false,
                            message: "No answer after two and a half minutes. Is the iPhone plugged in, unlocked, and trusted by this Mac?")
    }

    static func clear(on device: PhoneDevice, runner: ProcessRunner) async -> PhoneOutcome {
        // Ending the held session is what restores the real GPS. The clear
        // command is still run, because it is the explicit request and it also
        // covers a location left behind by an earlier run of the helper.
        endSession()
        let arguments = ["developer", "dvt", "simulate-location", "clear",
                         "--udid", device.udid, "--userspace"]
        let outcome = await run(arguments, runner: runner)
        return outcome.ok
            ? PhoneOutcome(ok: true, message: "Cleared. The iPhone is back on its real GPS.")
            : outcome
    }

    private static func run(_ arguments: [String], runner: ProcessRunner) async -> PhoneOutcome {
        guard let executable = executable() else {
            return PhoneOutcome(ok: false, message: "pymobiledevice3 is not installed. In Terminal, run: \(installHint)")
        }

        // The first `--userspace` call builds a RemoteServiceDiscovery tunnel and
        // can sit for a while before it answers; later calls reuse it and return
        // quickly. Two minutes is the deadline the Telesm app found reliable.
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: executable,
                arguments: arguments,
                environment: environment(),
                timeout: 120
            )
        } catch {
            return PhoneOutcome(ok: false, message: "Could not start pymobiledevice3. \(error.localizedDescription)")
        }

        if result.timedOut {
            return PhoneOutcome(
                ok: false,
                message: "No answer after two minutes. Is the iPhone plugged in, unlocked, and trusted by this Mac?"
            )
        }

        if result.succeeded {
            return PhoneOutcome(ok: true, message: "")
        }

        return PhoneOutcome(ok: false, message: readable(result))
    }

    /// pipx installs the console script with a shebang into its own virtualenv,
    /// but Homebrew's Python and a manually installed helper both look at `PATH`
    /// for their imports, so the two user-level bin folders are stated rather
    /// than inherited from a Finder launch that has almost none.
    private static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let fixed = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (fixed + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private static func lastLine(of output: String, status: Int32) -> String {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else {
            return "pymobiledevice3 exited with code \(status) and said nothing."
        }
        return last.count > 160 ? String(last.prefix(160)) + "…" : last
    }

    /// One line of the helper's own last complaint, capped so a traceback cannot
    /// become the status line.
    private static func readable(_ result: ProcessRunner.Result) -> String {
        let output = result.stderr.isEmpty ? result.stdout : result.stderr
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else {
            return "pymobiledevice3 exited with code \(result.status) and said nothing."
        }
        return last.count > 160 ? String(last.prefix(160)) + "…" : last
    }
}
