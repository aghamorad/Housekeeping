import Foundation

enum DownloadDirectory {
    static func prepare(
        at directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = directory.standardizedFileURL
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw issue(
                    at: directory,
                    detail: "A file exists where the download folder should be."
                )
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw issue(
                    at: directory,
                    detail: "The folder could not be created: \(error.localizedDescription)"
                )
            }
        }

        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw issue(at: directory, detail: "The folder is not writable by your user account.")
        }

        let probe = directory.appendingPathComponent(".mediadock-write-check-\(UUID().uuidString)")
        do {
            try Data("MediaDock 9 write check".utf8).write(to: probe)
            try fileManager.removeItem(at: probe)
        } catch {
            if fileManager.fileExists(atPath: probe.path) {
                try? fileManager.removeItem(at: probe)
            }
            throw issue(
                at: directory,
                detail: "MediaDock could not create and remove a test file there: \(error.localizedDescription)"
            )
        }

        return directory
    }

    private static func issue(at directory: URL, detail: String) -> AppIssue {
        AppIssue.message(
            "MediaDock 9 could not prepare the download folder at \(directory.path). " +
            "\(detail) Choose a different destination or correct that folder's permissions."
        )
    }
}
