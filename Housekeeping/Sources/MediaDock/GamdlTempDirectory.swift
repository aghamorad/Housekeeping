import Foundation

enum GamdlTempDirectory {
    static var url: URL {
        let fileManager = FileManager.default
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)

        return cachesDirectory
            .appendingPathComponent("MediaDock9", isDirectory: true)
            .appendingPathComponent("gamdl-temp", isDirectory: true)
            .standardizedFileURL
    }

    static func prepare(
        at directory: URL = url,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = directory.standardizedFileURL
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw issue(
                    at: directory,
                    detail: "A file already exists where the temporary folder should be."
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

    static func arguments(preparingDirectory: Bool) throws -> [String] {
        let directory = preparingDirectory ? try prepare() : url
        return ["--temp-path", directory.path]
    }

    private static func issue(at directory: URL, detail: String) -> AppIssue {
        AppIssue.message(
            "MediaDock 9 could not prepare Gamdl's temporary folder at \(directory.path). " +
            "\(detail) Check that your Library/Caches folder is writable. Full Disk Access is not required."
        )
    }
}
