import Foundation

struct PingSample: Sendable {
    var transmitted: Int
    var received: Int
    var avgMs: Double
    var stddevMs: Double
    var loss: Double
}

struct FetchSample: Sendable {
    var seconds: Double
    var bytes: Int
    var statusCode: Int
    var exitIP: String?
    var exitCountry: String?

    var succeeded: Bool { statusCode >= 200 && statusCode < 400 && bytes > 0 }
}

enum RouteProbes {

    /// Marks the boundary between the response body and curl's own report.
    private static let reportMarker = "\n---ROUTE---"

    // MARK: - Ping

    /// macOS ping. `-W` is the per-reply wait in milliseconds, `-t` is a
    /// ceiling on the whole command so a blackholed route cannot stall us.
    static func ping(host: String, count: Int, timeout: Double) async -> PingSample? {
        guard let pingPath = RouteProcess.which("/sbin/ping") ?? RouteProcess.which("ping") else {
            return nil
        }
        // -W is milliseconds on macOS and must leave room for `count` replies.
        let replyWait = max(200, Int(timeout * 1000 / Double(max(1, count))))
        let output: RouteProcessOutput
        do {
            output = try await RouteProcess.run(
                pingPath,
                ["-c", String(count), "-i", "0.3", "-W", String(replyWait),
                 "-t", String(Int(ceil(timeout))), host],
                timeout: timeout + 3
            )
        } catch {
            return nil
        }
        return parsePing(output.combined)
    }

    static func parsePing(_ text: String) -> PingSample? {
        var transmitted = 0
        var received = 0
        var loss = 1.0
        var avg = 0.0
        var stddev = 0.0
        var sawAnything = false

        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.contains("packets transmitted") {
                let nums = numbers(in: line)
                if nums.count >= 2 {
                    transmitted = Int(nums[0])
                    received = Int(nums[1])
                    sawAnything = true
                }
                if let pct = firstMatch(in: line, pattern: "([0-9.]+)% packet loss") {
                    loss = (Double(pct) ?? 100) / 100
                } else if let pct = firstMatch(in: line, pattern: "([0-9.]+)%") {
                    loss = (Double(pct) ?? 100) / 100
                }
            }

            if line.hasPrefix("round-trip") || line.hasPrefix("rtt") {
                if let tail = line.split(separator: "=").last {
                    let parts = tail.split(separator: "/").map {
                        Double($0.trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                    if parts.count >= 2 {
                        avg = parts[1]
                        if parts.count >= 4 { stddev = parts[3] }
                        sawAnything = true
                    }
                }
            }
        }

        guard sawAnything else { return nil }
        if transmitted > 0 {
            loss = Double(transmitted - received) / Double(transmitted)
        }
        // Every reply lost: no timing line, but still a usable sample.
        if received == 0 { avg = 0; stddev = 0 }
        return PingSample(
            transmitted: transmitted, received: received,
            avgMs: avg, stddevMs: stddev, loss: loss
        )
    }

    // MARK: - Fetch probe

    /// A real TLS round trip through whatever tunnel is currently up.
    ///
    /// Ping can succeed on a route that carries nothing — this is the probe
    /// that tells the two apart, so it is what decides a route's verdict.
    static func fetch(url: String, timeout: Double) async -> FetchSample? {
        guard let curl = RouteProcess.which("/usr/bin/curl") ?? RouteProcess.which("curl") else {
            return nil
        }
        let format = "\(reportMarker)%{time_total} %{size_download} %{http_code}"
        let output: RouteProcessOutput
        do {
            output = try await RouteProcess.run(
                curl,
                ["-sS", "--max-time", String(Int(ceil(timeout))),
                 "--connect-timeout", String(Int(ceil(min(timeout, 20)))),
                 "-L", "--compressed",
                 "-A", "Housekeeping/1.0",
                 "-w", format, url],
                timeout: timeout + 4
            )
        } catch {
            return nil
        }
        return parseFetch(output.stdout)
    }

    static func parseFetch(_ text: String) -> FetchSample? {
        guard let range = text.range(of: reportMarker, options: .backwards) else { return nil }
        let body = String(text[text.startIndex..<range.lowerBound])
        let report = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = report.split(separator: " ").map(String.init)
        guard fields.count >= 3 else { return nil }

        let seconds = Double(fields[0]) ?? 0
        let bytes = Int(Double(fields[1]) ?? 0)
        let code = Int(fields[2]) ?? 0

        // Cloudflare's trace endpoint reports the exit node in plain text.
        var exitIP: String?
        var exitCountry: String?
        for line in body.split(separator: "\n") {
            if line.hasPrefix("ip=") { exitIP = String(line.dropFirst(3)) }
            if line.hasPrefix("loc=") { exitCountry = String(line.dropFirst(4)) }
        }

        return FetchSample(
            seconds: seconds, bytes: bytes, statusCode: code,
            exitIP: exitIP, exitCountry: exitCountry
        )
    }

    // MARK: - Helpers

    private static func numbers(in line: String) -> [Double] {
        var found: [Double] = []
        var current = ""
        for ch in line {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else if !current.isEmpty {
                if let d = Double(current) { found.append(d) }
                current = ""
            }
        }
        if !current.isEmpty, let d = Double(current) { found.append(d) }
        return found
    }

    private static func firstMatch(in line: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
