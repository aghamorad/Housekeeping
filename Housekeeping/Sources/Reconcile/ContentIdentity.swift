// Housekeeping — Deciding whether two files are the same file
//
// The whole reason a comparison of a terabyte library can finish in minutes is
// that almost no bytes are ever read. macOS already keeps a size and a
// modification date for every file, and two files that agree on both are treated
// as the same file without either being opened.
//
// Only when the sizes agree and the dates do not is anything read. Then both
// copies are hashed and the hashes decide. That is the narrow band where the
// cheap answer is genuinely ambiguous — same length, different timestamp, which
// is what a copy looks like when the tool that made it did not preserve dates.
//
// A hash is never the primary key, and never stored. It is expensive, and it
// buys nothing here: a file whose contents changed keeps neither its old size
// nor its old date, so the cheap pair has already caught every real edit.

import Foundation
import CryptoKit

enum ContentIdentity {
    /// The cheap key, built from what the filesystem already recorded. Seconds
    /// rather than nanoseconds on purpose: two filesystems — APFS and a FAT
    /// stick, say — round dates differently, and a sub-second difference is not
    /// a difference anybody means.
    static func fastKey(size: Int64, modified: Date) -> String {
        "\(size)-\(Int(modified.timeIntervalSince1970))"
    }

    /// Whether two records agree on the cheap key.
    static func agreesCheaply(_ a: FileRecord, _ b: FileRecord) -> Bool {
        a.size == b.size && sameSecond(a.modified, b.modified)
    }

    static func sameSecond(_ a: Date, _ b: Date) -> Bool {
        Int(a.timeIntervalSince1970) == Int(b.timeIntervalSince1970)
    }

    /// SHA-256 of a file, read in one-megabyte chunks.
    ///
    /// Streamed rather than loaded, because the files this is pointed at include
    /// multi-gigabyte video and this Mac has 16 GB of memory. Returns nil for
    /// anything that cannot be opened, which the caller must treat as "not
    /// known to be the same" rather than as a match.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
