// Housekeeping — what earlier readings and repairs found
//
// The screen itself only ever shows the current state. That is the right thing
// for deciding what to do now, and the wrong thing for answering the question
// that comes later: "this was fine last week, what changed?"
//
// A record is one line per event — a reading, a repair run, a verification —
// with the sentence a person would say and the rows that made it up. It lives
// in the app's own support folder, is capped so it cannot grow without bound,
// and holds no file contents: only names, counts and messages that are already
// on screen.

import Foundation

struct EnvironmentHistoryEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case scan
        case repair
        case verification

        var label: String {
            switch self {
            case .scan: return "Check"
            case .repair: return "Repair"
            case .verification: return "Verification"
            }
        }
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let summary: String
    let detail: [String]

    init(id: UUID = UUID(), date: Date = Date(), kind: Kind, summary: String, detail: [String]) {
        self.id = id
        self.date = date
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }
}

/// The store. Not a singleton: the app owns one, and a test can own another
/// pointed at a temporary file. Reads and writes happen on the main actor where
/// AppState uses it, so there is no lock here and no promise of one.
final class EnvironmentHistory {
    private static let limit = 300

    private let fileURL: URL
    private(set) var entries: [EnvironmentHistoryEntry]

    init(fileURL: URL = EnvironmentHistory.defaultFileURL()) {
        self.fileURL = fileURL
        self.entries = Self.load(from: fileURL)
    }

    static func defaultFileURL() -> URL {
        CleanupEngine.supportDirectoryURL()
            .appendingPathComponent("terminal-health.json")
    }

    /// Newest first, capped. A failed write is not worth surfacing: the history
    /// is a convenience, and the reading on screen is unaffected by it.
    func record(kind: EnvironmentHistoryEntry.Kind, summary: String, detail: [String] = []) {
        entries.insert(EnvironmentHistoryEntry(kind: kind, summary: summary, detail: detail), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            // Nothing to do: the file is a record, not a source of truth.
        }
    }

    private static func load(from url: URL) -> [EnvironmentHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([EnvironmentHistoryEntry].self, from: data)) ?? []
    }
}
