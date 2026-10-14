import Foundation

// MARK: - Where things live

enum RoutePaths {

    /// ~/Library/Application Support/Housekeeping
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("Housekeeping", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A location list the user has refreshed, layered over the bundled one.
    static var cachedLocations: URL {
        supportDirectory.appendingPathComponent("locations.json")
    }

    /// The copy shipped inside the .app, used when no refresh has been run.
    static var bundledLocations: URL? {
        Bundle.main.url(forResource: "locations", withExtension: "json")
    }

    /// ~/Documents/Housekeeping — kept out of Application Support on purpose,
    /// so the log is somewhere the user would actually think to look for it.
    static var logDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Housekeeping", isDirectory: true)
    }

    /// One markdown file, appended to. Not one file per run: the point is to
    /// be able to read a month of results in one place.
    static var logFile: URL {
        logDirectory.appendingPathComponent("route-log.md")
    }

    static var logDirectoryDisplayPath: String {
        (logDirectory.path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - The written record

/// The written record of a run: what worked, what did not, and where.
///
/// Everything lands in one markdown file that is appended to rather than
/// replaced, so each run adds a dated section and the earlier ones stay
/// readable. The file is for the user — the app only ever adds to it.
enum RouteLog {

    /// Adds `run` as a new section and returns the file it was written to.
    @discardableResult
    static func append(_ run: RouteRun) throws -> URL {
        let url = RoutePaths.logFile
        try FileManager.default.createDirectory(
            at: RoutePaths.logDirectory,
            withIntermediateDirectories: true
        )

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var text = existing.isEmpty ? preamble : existing
        if !text.hasSuffix("\n") { text += "\n" }
        text += section(for: run)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static let preamble = """
    # Housekeeping route log

    One section per run, oldest first. Each section gives the date and time,
    the provider, and every route that was tried — country, city, and the
    protocol and port it was reached over. The routes that carried traffic come
    first, best first; the ones that did not are listed under them with the
    reason.

    This file is yours. Read it, keep it, delete it — the app only ever adds.

    ---

    """

    static func section(for run: RouteRun) -> String {
        let worked = run.results
            .filter { $0.verdict != .failed }
            .sorted { $0.score < $1.score }
        let failed = run.results
            .filter { $0.verdict == .failed }
            .sorted {
                ($0.target.location.country, $0.target.location.city)
                    < ($1.target.location.country, $1.target.location.city)
            }

        var out = "## \(stamp(run.startedAt)) — \(run.provider.displayName)\n\n"

        if let best = worked.first {
            out += "**Best route:** \(describe(best))\n\n"
            out += "**\(worked.count) of \(run.results.count)** routes carried traffic.\n\n"
        } else if run.results.isEmpty {
            out += "**No routes were tested.**\n\n"
        } else {
            out += "**Nothing carried traffic.** All \(run.results.count) routes were tried "
            out += "and none of them passed data.\n\n"
        }

        if let baseline = run.baseline, let ping = baseline.pingMs {
            out += "With the tunnel off, ping was \(Int(ping.rounded())) ms"
            if let seconds = baseline.fetchSeconds {
                out += " and a test page came back in \(String(format: "%.2f", seconds)) s"
            }
            out += ".\n\n"
        }

        if !worked.isEmpty {
            out += "### Worked\n\n"
            out += "| Time | Country | City | Node | Route | Connect | Ping | Jitter | Loss | Fetch | Exit |\n"
            out += "|---|---|---|---|---|---|---|---|---|---|---|\n"
            for r in worked {
                let l = r.target.location
                out += "| \(clock(r.testedAt)) | \(cell(l.country)) | \(cell(l.city)) "
                out += "| \(cell(l.node)) | `\(r.target.routeLabel)` "
                out += "| \(seconds(r.connectSeconds)) | \(ms(r.pingMs)) | \(ms(r.jitterMs)) "
                out += "| \(percent(r.packetLoss)) | \(seconds(r.fetchSeconds)) "
                out += "| \(cell(exit(r))) |\n"
            }
            out += "\n"
        }

        if !failed.isEmpty {
            out += "### Did not work\n\n"
            out += "| Time | Country | City | Node | Route | Why |\n"
            out += "|---|---|---|---|---|---|\n"
            for r in failed {
                let l = r.target.location
                out += "| \(clock(r.testedAt)) | \(cell(l.country)) | \(cell(l.city)) "
                out += "| \(cell(l.node)) | `\(r.target.routeLabel)` "
                out += "| \(cell(r.failureReason ?? "connected but carried no traffic")) |\n"
            }
            out += "\n"
        }

        return out
    }

    // MARK: - Pieces

    private static func describe(_ r: RouteResult) -> String {
        let l = r.target.location
        var parts = [l.city, l.country].filter { !$0.isEmpty }
        if !l.node.isEmpty { parts.append(l.node) }
        var line = "\(parts.joined(separator: ", ")) — `\(r.target.routeLabel)`"
        if let ping = r.pingMs { line += ", ping \(Int(ping.rounded())) ms" }
        if let fetch = r.fetchSeconds { line += ", page in \(String(format: "%.2f", fetch)) s" }
        return line
    }

    private static func exit(_ r: RouteResult) -> String {
        guard let ip = r.exitIP else { return "" }
        guard let country = r.exitCountry, !country.isEmpty else { return ip }
        return "\(ip) · \(country)"
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }
    private static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? ""
    }

    private static func ms(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) ms" } ?? ""
    }

    private static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) } ?? ""
    }

    /// A markdown table cell cannot contain a raw pipe or newline.
    private static func cell(_ value: String) -> String {
        let flat = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "/")
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? "—" : flat
    }
}
