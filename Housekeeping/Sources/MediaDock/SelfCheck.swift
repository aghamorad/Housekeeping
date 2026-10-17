import Combine
import Foundation

@MainActor
enum SelfCheck {
    static func run() -> [String] {
        var failures: [String] = []
        check(MediaSource.detect(from: "https://youtu.be/abc") == .youtube, "YouTube short-link detection", into: &failures)
        check(MediaSource.detect(from: "https://www.youtube.com/watch?v=abc") == .youtube, "YouTube host detection", into: &failures)
        check(MediaSource.detect(from: "https://open.spotify.com/track/abc") == .spotify, "Spotify detection", into: &failures)
        check(MediaSource.detect(from: "https://music.apple.com/us/album/example/123") == .appleMusic, "Apple Music detection", into: &failures)
        check(MediaSource.detect(from: "https://example.com/file") == nil, "Unknown host rejection", into: &failures)
        check(MediaSource.detect(from: "https://evilyoutube.com/watch?v=abc") == nil, "Lookalike host rejection", into: &failures)
        check(CommandSpec.shellQuote("two words") == "'two words'", "Shell whitespace quoting", into: &failures)
        check(CommandSpec.shellQuote("it's") == "'it'\\''s'", "Shell apostrophe quoting", into: &failures)

        let tempTestRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaDock9-self-check-\(UUID().uuidString)", isDirectory: true)
        let tempTestDirectory = tempTestRoot.appendingPathComponent("gamdl-temp", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempTestRoot) }
        do {
            let preparedDirectory = try GamdlTempDirectory.prepare(at: tempTestDirectory)
            var isDirectory: ObjCBool = false
            check(
                FileManager.default.fileExists(atPath: preparedDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "Gamdl temp directory creation",
                into: &failures
            )
            check(FileManager.default.isWritableFile(atPath: preparedDirectory.path), "Gamdl temp directory writability", into: &failures)
            let residualProbes = (try? FileManager.default.contentsOfDirectory(atPath: preparedDirectory.path))?
                .filter { $0.hasPrefix(".mediadock-write-check-") } ?? []
            check(residualProbes.isEmpty, "Gamdl temp write-check cleanup", into: &failures)
        } catch {
            failures.append("Gamdl temp directory preparation threw: \(error.localizedDescription)")
        }

        let downloadTestRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaDock9-download-self-check-\(UUID().uuidString)", isDirectory: true)
        let downloadTestDirectory = downloadTestRoot.appendingPathComponent("AppleMusic", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: downloadTestRoot) }
        do {
            let preparedDirectory = try DownloadDirectory.prepare(at: downloadTestDirectory)
            var isDirectory: ObjCBool = false
            check(
                FileManager.default.fileExists(atPath: preparedDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "Download directory creation",
                into: &failures
            )
            check(FileManager.default.isWritableFile(atPath: preparedDirectory.path), "Download directory writability", into: &failures)
            let residualProbes = (try? FileManager.default.contentsOfDirectory(atPath: preparedDirectory.path))?
                .filter { $0.hasPrefix(".mediadock-write-check-") } ?? []
            check(residualProbes.isEmpty, "Download directory write-check cleanup", into: &failures)
        } catch {
            failures.append("Download directory preparation threw: \(error.localizedDescription)")
        }

        let suiteName = "com.morad.mediadock9.selfcheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append("Could not create isolated self-test preferences")
            return failures
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        do {
            let model = AppModel(defaults: defaults)
            var forwardedRunnerChange = false
            let observation = model.objectWillChange.sink {
                forwardedRunnerChange = true
            }
            model.runner.clear()
            check(forwardedRunnerChange, "Runner changes refresh the MediaDock UI", into: &failures)
            withExtendedLifetime(observation) {}
        }

        do {
            let model = AppModel(defaults: defaults)
            model.sourceChoice = .youtube
            model.urlText = "https://youtu.be/example"
            model.mediaKind = .audio
            model.audioFormat = .flac
            model.playlistMode = false
            model.useYouTubeCookies = true
            model.browserChoice = .safari
            let command = try model.makeDownloadCommand(requireInstalledTool: false)
            check(command.executable == "yt-dlp", "YouTube executable", into: &failures)
            check(command.arguments.contains("--audio-format") && command.arguments.contains("flac"), "YouTube audio flags", into: &failures)
            check(command.arguments.contains("--no-playlist"), "YouTube single-item mode", into: &failures)
            check(command.arguments.contains("--cookies-from-browser"), "YouTube browser cookies", into: &failures)
        } catch {
            failures.append("YouTube command builder threw: \(error.localizedDescription)")
        }

        do {
            let model = AppModel(defaults: defaults)
            model.sourceChoice = .spotify
            model.urlText = "https://open.spotify.com/track/example"
            let command = try model.makeDownloadCommand(requireInstalledTool: false)
            check(command.executable == "spotdl", "SpotDL executable", into: &failures)
            check(command.arguments.first == "download", "SpotDL operation", into: &failures)
            check(command.arguments.contains("--overwrite") && command.arguments.contains("skip"), "SpotDL overwrite protection", into: &failures)
        } catch {
            failures.append("Spotify command builder threw: \(error.localizedDescription)")
        }

        do {
            let model = AppModel(defaults: defaults)
            model.sourceChoice = .appleMusic
            model.urlText = "https://music.apple.com/us/album/example/123"
            model.appleCookiesPath = "/private/example/cookies.txt"
            let command = try model.makeDownloadCommand(requireInstalledTool: false)
            check(command.executable == "gamdl", "Gamdl executable", into: &failures)
            check(command.arguments.filter { $0 == "--temp-path" }.count == 1, "Gamdl has one explicit temp-path option", into: &failures)
            if let tempPathIndex = command.arguments.firstIndex(of: "--temp-path"), command.arguments.indices.contains(tempPathIndex + 1) {
                let tempPath = command.arguments[tempPathIndex + 1]
                check(tempPath == GamdlTempDirectory.url.path, "Gamdl uses the MediaDock cache temp path", into: &failures)
                check(tempPath.hasPrefix("/"), "Gamdl temp path is absolute", into: &failures)
            } else {
                failures.append("Gamdl temp-path value")
            }
            check(command.arguments.contains("--cookies-path") && command.arguments.contains(model.appleCookiesPath), "Gamdl cookie path", into: &failures)
            check(command.arguments.contains("aac-web"), "Gamdl safe web codec", into: &failures)
            check(!command.arguments.contains("--use-wrapper"), "Gamdl wrapper exclusion", into: &failures)
        } catch {
            failures.append("Apple Music command builder threw: \(error.localizedDescription)")
        }

        return failures
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String, into failures: inout [String]) {
        if !condition() { failures.append(name) }
    }
}
