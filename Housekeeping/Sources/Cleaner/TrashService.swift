// Housekeeping — Clean Up: the Trash, read and (only on request) emptied

import Foundation

/// The one place in the app where something can be lost. It is kept in a file
/// of its own, with a single guard at the bottom, so that the rule is easy to
/// see: this can only ever touch the direct contents of the home folder's Trash.
struct TrashService {
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    var trashURL: URL { home.appendingPathComponent(".Trash", isDirectory: true) }

    struct EmptyResult: Sendable {
        var removedCount = 0
        var removedBytes: Int64 = 0
        var failures: [String] = []
    }

    static func summary() -> TrashSummary {
        let service = TrashService()
        return service.read()
    }

    func read() -> TrashSummary {
        var summary = TrashSummary()
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            summary.unreadable = true
            return summary
        }

        for item in contents where item.lastPathComponent != ".DS_Store" {
            summary.count += 1
            summary.size += CleanerScanner.size(of: item)
        }
        return summary
    }

    /// Removes what is in the Trash. This is the one irreversible action in the
    /// app: there is no Quarantine copy afterwards. The caller is responsible
    /// for having asked, in words, with a typed confirmation.
    func empty(progress: @Sendable (Int, Int) -> Void = { _, _ in }) -> EmptyResult {
        guard isTheTrash() else {
            return EmptyResult(failures: ["That is not the Trash folder, so nothing was removed."])
        }

        var result = EmptyResult()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [],
            options: []
        )) ?? []

        for (offset, item) in contents.enumerated() {
            progress(offset, contents.count)
            guard item.lastPathComponent != ".DS_Store" else { continue }
            let size = CleanerScanner.size(of: item)
            do {
                try FileManager.default.removeItem(at: item)
                result.removedCount += 1
                result.removedBytes += size
            } catch {
                result.failures.append("\(item.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        progress(contents.count, contents.count)
        return result
    }

    /// The guard. Anything that is not exactly this machine's `~/.Trash` is
    /// refused, including a path that merely contains the word.
    private func isTheTrash() -> Bool {
        let expected = home.appendingPathComponent(".Trash", isDirectory: true).standardizedFileURL.path
        return trashURL.standardizedFileURL.path == expected
    }
}
