import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection = .download
    @Published var urlText = ""
    @Published var sourceChoice: SourceChoice {
        didSet { defaults.set(sourceChoice.rawValue, forKey: Keys.sourceChoice) }
    }
    @Published var mediaKind: MediaKind {
        didSet { defaults.set(mediaKind.rawValue, forKey: Keys.mediaKind) }
    }
    @Published var audioFormat: AudioFormat {
        didSet { defaults.set(audioFormat.rawValue, forKey: Keys.audioFormat) }
    }
    @Published var videoContainer: VideoContainer {
        didSet { defaults.set(videoContainer.rawValue, forKey: Keys.videoContainer) }
    }
    @Published var audioQuality: AudioQuality {
        didSet { defaults.set(audioQuality.rawValue, forKey: Keys.audioQuality) }
    }
    @Published var videoQuality: VideoQuality {
        didSet { defaults.set(videoQuality.rawValue, forKey: Keys.videoQuality) }
    }
    @Published var playlistMode: Bool {
        didSet { defaults.set(playlistMode, forKey: Keys.playlistMode) }
    }
    @Published var includeMetadata: Bool {
        didSet { defaults.set(includeMetadata, forKey: Keys.includeMetadata) }
    }
    @Published var includeArtwork: Bool {
        didSet { defaults.set(includeArtwork, forKey: Keys.includeArtwork) }
    }
    @Published var includeSubtitles: Bool {
        didSet { defaults.set(includeSubtitles, forKey: Keys.includeSubtitles) }
    }
    @Published var includeLyrics: Bool {
        didSet { defaults.set(includeLyrics, forKey: Keys.includeLyrics) }
    }
    @Published var useArchive: Bool {
        didSet { defaults.set(useArchive, forKey: Keys.useArchive) }
    }
    @Published var subtitleLanguages: String {
        didSet { defaults.set(subtitleLanguages, forKey: Keys.subtitleLanguages) }
    }
    @Published var useYouTubeCookies: Bool {
        didSet { defaults.set(useYouTubeCookies, forKey: Keys.useYouTubeCookies) }
    }
    @Published var browserChoice: BrowserChoice {
        didSet { defaults.set(browserChoice.rawValue, forKey: Keys.browserChoice) }
    }
    @Published var appleCookiesPath: String {
        didSet { defaults.set(appleCookiesPath, forKey: Keys.appleCookiesPath) }
    }
    @Published var youtubeFolder: String {
        didSet { defaults.set(youtubeFolder, forKey: Keys.youtubeFolder) }
    }
    @Published var spotifyFolder: String {
        didSet { defaults.set(spotifyFolder, forKey: Keys.spotifyFolder) }
    }
    @Published var appleMusicFolder: String {
        didSet { defaults.set(appleMusicFolder, forKey: Keys.appleMusicFolder) }
    }

    @Published private(set) var dependencies: [DependencyStatus] = []
    @Published private(set) var isScanning = false
    @Published var pendingCommands: [CommandSpec] = []
    @Published var reviewTitle = "Review commands"
    @Published var showCommandReview = false
    @Published var alertMessage: String?

    let runner = CommandRunner()
    private let defaults: UserDefaults
    private var runnerObservation: AnyCancellable?

    private enum Keys {
        static let sourceChoice = "sourceChoice"
        static let mediaKind = "mediaKind"
        static let audioFormat = "audioFormat"
        static let videoContainer = "videoContainer"
        static let audioQuality = "audioQuality"
        static let videoQuality = "videoQuality"
        static let playlistMode = "playlistMode"
        static let includeMetadata = "includeMetadata"
        static let includeArtwork = "includeArtwork"
        static let includeSubtitles = "includeSubtitles"
        static let includeLyrics = "includeLyrics"
        static let useArchive = "useArchive"
        static let subtitleLanguages = "subtitleLanguages"
        static let useYouTubeCookies = "useYouTubeCookies"
        static let browserChoice = "browserChoice"
        static let appleCookiesPath = "appleCookiesPath"
        static let youtubeFolder = "youtubeFolder"
        static let spotifyFolder = "spotifyFolder"
        static let appleMusicFolder = "appleMusicFolder"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        sourceChoice = SourceChoice(rawValue: defaults.string(forKey: Keys.sourceChoice) ?? "") ?? .automatic
        mediaKind = MediaKind(rawValue: defaults.string(forKey: Keys.mediaKind) ?? "") ?? .video
        audioFormat = AudioFormat(rawValue: defaults.string(forKey: Keys.audioFormat) ?? "") ?? .mp3
        videoContainer = VideoContainer(rawValue: defaults.string(forKey: Keys.videoContainer) ?? "") ?? .mp4
        audioQuality = AudioQuality(rawValue: defaults.string(forKey: Keys.audioQuality) ?? "") ?? .source
        videoQuality = VideoQuality(rawValue: defaults.string(forKey: Keys.videoQuality) ?? "") ?? .best
        playlistMode = defaults.object(forKey: Keys.playlistMode) as? Bool ?? true
        includeMetadata = defaults.object(forKey: Keys.includeMetadata) as? Bool ?? true
        includeArtwork = defaults.object(forKey: Keys.includeArtwork) as? Bool ?? true
        includeSubtitles = defaults.object(forKey: Keys.includeSubtitles) as? Bool ?? false
        includeLyrics = defaults.object(forKey: Keys.includeLyrics) as? Bool ?? true
        useArchive = defaults.object(forKey: Keys.useArchive) as? Bool ?? true
        subtitleLanguages = defaults.string(forKey: Keys.subtitleLanguages) ?? "en.*,en"
        useYouTubeCookies = defaults.object(forKey: Keys.useYouTubeCookies) as? Bool ?? false
        browserChoice = BrowserChoice(rawValue: defaults.string(forKey: Keys.browserChoice) ?? "") ?? .safari
        appleCookiesPath = defaults.string(forKey: Keys.appleCookiesPath) ?? ""
        youtubeFolder = defaults.string(forKey: Keys.youtubeFolder) ?? "\(downloads)/YouTube"
        spotifyFolder = defaults.string(forKey: Keys.spotifyFolder) ?? "\(downloads)/Spotify"
        appleMusicFolder = defaults.string(forKey: Keys.appleMusicFolder) ?? "\(downloads)/AppleMusic"

        // CommandRunner owns the live process state. Forward its changes so every
        // view observing AppModel redraws while commands and log output arrive.
        runnerObservation = runner.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        runner.onBatchFinished = { [weak self] _ in self?.refreshDependencies() }
    }

    var effectiveSource: MediaSource? {
        sourceChoice.explicitSource ?? MediaSource.detect(from: urlText)
    }

    var detectedSourceText: String {
        if sourceChoice != .automatic { return "Manual source: \(sourceChoice.rawValue)" }
        if let source = MediaSource.detect(from: urlText) { return "Detected: \(source.rawValue)" }
        return urlText.isEmpty ? "Waiting for a link" : "Source not recognized — choose it manually"
    }

    var commandPreview: String {
        guard !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Paste a link to see the exact command."
        }
        do {
            return try makeDownloadCommand(requireInstalledTool: false).displayCommand
        } catch {
            return error.localizedDescription
        }
    }

    var canStartDownload: Bool {
        !runner.isRunning && effectiveSource != nil && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func dependency(_ id: DependencyID) -> DependencyStatus? {
        dependencies.first(where: { $0.id == id })
    }

    func outputFolder(for source: MediaSource) -> String {
        switch source {
        case .youtube: return youtubeFolder
        case .spotify: return spotifyFolder
        case .appleMusic: return appleMusicFolder
        }
    }

    func refreshDependencies() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            dependencies = await DependencyScanner.scan()
            isScanning = false
        }
    }

    func startDownload() {
        do {
            guard let source = effectiveSource else {
                throw AppIssue.message("MediaDock 9 cannot identify this link. Choose YouTube, Spotify, or Apple Music explicitly.")
            }
            let command = try makeDownloadCommand(requireInstalledTool: true)
            _ = try DownloadDirectory.prepare(at: URL(fileURLWithPath: outputFolder(for: source), isDirectory: true))
            runner.run([command])
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func requestInstall(_ dependencyID: DependencyID) {
        do {
            pendingCommands = try installCommands(for: dependencyID)
            reviewTitle = "Install \(dependencyID.title)"
            showCommandReview = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func requestUpdateAll() {
        do {
            let commands = try updateCommands()
            guard !commands.isEmpty else {
                throw AppIssue.message("No Homebrew- or pipx-managed MediaDock tools are currently available to update.")
            }
            pendingCommands = commands
            reviewTitle = "Update managed tools"
            showCommandReview = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func runReviewedCommands() {
        let commands = pendingCommands
        pendingCommands = []
        showCommandReview = false
        runner.run(commands)
    }

    func chooseOutputFolder(for source: MediaSource) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(source.rawValue) download folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: outputFolder(for: source))
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        switch source {
        case .youtube: youtubeFolder = path
        case .spotify: spotifyFolder = path
        case .appleMusic: appleMusicFolder = path
        }
    }

    func chooseAppleCookies() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apple Music cookies.txt"
        panel.message = "MediaDock 9 remembers only the path. It never opens or displays the cookie contents."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        appleCookiesPath = path
    }

    func revealOutputFolder() {
        guard let source = effectiveSource else { return }
        let path = outputFolder(for: source)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            alertMessage = "That folder does not exist yet. The selected downloader will create it when a download begins."
        }
    }

    func openWebPage(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportLog() {
        let panel = NSSavePanel()
        panel.title = "Export MediaDock 9 log"
        panel.nameFieldStringValue = "MediaDock9-log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try runner.plainTextLog.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            alertMessage = "The log could not be saved: \(error.localizedDescription)"
        }
    }

    func diagnosticSummary() -> String {
        var lines = ["MediaDock 9 diagnostic summary", "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for id in DependencyID.allCases {
            if let status = dependency(id) {
                lines.append("\(id.title): \(status.version ?? "installed") | \(status.path ?? "not found") | \(status.manager.rawValue)")
            } else {
                lines.append("\(id.title): not scanned")
            }
        }
        lines.append("Apple cookies: \(appleCookiesPath.isEmpty ? "not selected" : "path selected; contents not inspected")")
        return lines.joined(separator: "\n")
    }

    func makeDownloadCommand(requireInstalledTool: Bool) throws -> CommandSpec {
        let cleanURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: cleanURL), parsed.scheme == "https" || parsed.scheme == "http" else {
            throw AppIssue.message("Enter a complete http:// or https:// link.")
        }
        guard let source = effectiveSource else {
            throw AppIssue.message("MediaDock 9 cannot identify this link. Choose YouTube, Spotify, or Apple Music explicitly.")
        }
        if parsed.scheme?.lowercased() != "https" && (source == .appleMusic || (source == .youtube && useYouTubeCookies)) {
            throw AppIssue.message("Use an https:// link when account cookies are involved.")
        }

        let toolStatus = dependency(source.toolID)
        let executable: String
        if let path = toolStatus?.path {
            executable = path
        } else if requireInstalledTool {
            throw AppIssue.message("\(source.toolID.title) is not installed or is not on the app's search path. Open Setup to install or rescan it.")
        } else {
            executable = source.toolID.commandName
        }

        switch source {
        case .youtube:
            return youtubeCommand(executable: executable, url: cleanURL)
        case .spotify:
            return spotifyCommand(executable: executable, url: cleanURL)
        case .appleMusic:
            return try appleMusicCommand(executable: executable, url: cleanURL, requireCookieFile: requireInstalledTool)
        }
    }

    private func youtubeCommand(executable: String, url: String) -> CommandSpec {
        var arguments = ["--newline", "--no-overwrites", "-P", youtubeFolder]
        if playlistMode {
            arguments += ["--yes-playlist", "-o", "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"]
        } else {
            arguments += ["--no-playlist", "-o", "%(title)s.%(ext)s"]
        }

        if mediaKind == .audio {
            arguments += ["-x", "--audio-format", audioFormat.rawValue, "--audio-quality", audioQuality.ytDlpValue]
        } else {
            let selector: String
            if let height = videoQuality.height {
                selector = "bv*[height<=\(height)]+ba/b[height<=\(height)]"
            } else {
                selector = "bv*+ba/b"
            }
            arguments += ["-f", selector, "--merge-output-format", videoContainer.rawValue]
        }

        if includeMetadata { arguments.append("--embed-metadata") }
        if includeArtwork { arguments.append("--embed-thumbnail") }
        if includeSubtitles && mediaKind == .video {
            arguments += ["--write-subs", "--write-auto-subs", "--sub-langs", subtitleLanguages, "--embed-subs"]
        }
        if useArchive {
            arguments += ["--download-archive", (youtubeFolder as NSString).appendingPathComponent("archive.txt")]
        }
        if useYouTubeCookies {
            arguments += ["--cookies-from-browser", browserChoice.rawValue]
        }
        arguments.append(url)

        return CommandSpec(
            name: "YouTube download",
            executable: executable,
            arguments: arguments,
            explanation: "yt-dlp fetches the selected media. FFmpeg merges or converts streams when needed; existing files are not overwritten."
        )
    }

    private func spotifyCommand(executable: String, url: String) -> CommandSpec {
        let outputTemplate = (spotifyFolder as NSString).appendingPathComponent("{artists} - {title}.{output-ext}")
        var arguments = [
            "download", url,
            "--format", audioFormat.rawValue,
            "--bitrate", audioQuality.spotDLValue(format: audioFormat),
            "--output", outputTemplate,
            "--overwrite", "skip",
            "--print-errors"
        ]
        if playlistMode { arguments.append("--playlist-retain-track-cover") }
        if includeLyrics { arguments += ["--lyrics", "synced", "--generate-lrc"] }
        if useArchive {
            arguments += ["--archive", (spotifyFolder as NSString).appendingPathComponent("archive.spotdl.txt")]
        }

        return CommandSpec(
            name: "Spotify-matched audio download",
            executable: executable,
            arguments: arguments,
            explanation: "SpotDL reads Spotify metadata, finds a matching recording through its audio providers, downloads it, and tags it. It does not copy Spotify's audio stream."
        )
    }

    private func appleMusicCommand(executable: String, url: String, requireCookieFile: Bool) throws -> CommandSpec {
        if requireCookieFile {
            guard !appleCookiesPath.isEmpty else {
                throw AppIssue.message("Apple Music requires a cookies.txt file. Use the Cookies screen to choose it first.")
            }
            guard FileManager.default.fileExists(atPath: appleCookiesPath) else {
                throw AppIssue.message("The selected Apple Music cookie file no longer exists. Choose it again on the Cookies screen.")
            }
        }

        let cookiePath = appleCookiesPath.isEmpty ? "/path/to/cookies.txt" : appleCookiesPath
        var arguments = try GamdlTempDirectory.arguments(preparingDirectory: requireCookieFile) + [
            "--cookies-path", cookiePath,
            "--output-path", appleMusicFolder,
            "--log-level", "INFO",
            "--song-codec-priority", "aac-web"
        ]

        let requestedHeight = videoQuality.height ?? 1080
        let supportedHeight = [240, 360, 480, 540, 720, 1080, 1440, 2160].min(by: { abs($0 - requestedHeight) < abs($1 - requestedHeight) }) ?? 1080
        arguments += ["--music-video-resolution", "\(supportedHeight)p", "--music-video-remux-format", "mp4"]
        if supportedHeight > 1080 {
            arguments += ["--music-video-codec-priority", "h265"]
        }

        if includeLyrics {
            arguments += ["--synced-lyrics-format", "lrc"]
        } else {
            arguments.append("--no-synced-lyrics")
        }
        if !includeMetadata { arguments += ["--exclude-tags", "all"] }
        if includeArtwork { arguments.append("--save-cover") }
        if playlistMode {
            arguments += ["--save-playlist", "--artist-auto-select", "all-albums"]
        }
        if useArchive {
            arguments += ["--database-path", (appleMusicFolder as NSString).appendingPathComponent("MediaDock9-downloads.sqlite")]
        }
        arguments.append(url)

        return CommandSpec(
            name: "Apple Music download",
            executable: executable,
            arguments: arguments,
            explanation: "Gamdl handles the Apple Music session and media workflow. MediaDock 9 only passes visible options and your selected cookie-file path; it contains no DRM or decryption implementation."
        )
    }

    private func installCommands(for dependencyID: DependencyID) throws -> [CommandSpec] {
        if dependency(dependencyID)?.isInstalled == true {
            throw AppIssue.message("\(dependencyID.title) is already installed. Use Update All for managed tools.")
        }

        if dependencyID == .homebrew {
            let script = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
            return [CommandSpec(
                name: "Install Homebrew",
                executable: "/bin/bash",
                arguments: ["-c", #"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"#],
                explanation: "Downloads and runs Homebrew's official installer. The installer may require an administrator password; if this GUI session cannot provide it, copy the shown command into Terminal.",
                displayOverride: script
            )]
        }

        guard let brewPath = dependency(.homebrew)?.path else {
            throw AppIssue.message("Install Homebrew first; it is the manager used for this dependency.")
        }

        if let formula = dependencyID.brewFormula {
            var commands = [CommandSpec(
                name: "Install \(dependencyID.title)",
                executable: brewPath,
                arguments: ["install", formula],
                explanation: "Homebrew downloads \(dependencyID.title), verifies its package, and links its executable into Homebrew's bin folder."
            )]
            if dependencyID == .pipx {
                let pipxPath = ((brewPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("pipx")
                commands.append(CommandSpec(
                    name: "Add pipx apps to your shell path",
                    executable: pipxPath,
                    arguments: ["ensurepath"],
                    explanation: "pipx adds its application directory to your shell configuration. It does not install a Python app yet."
                ))
            }
            return commands
        }

        if let package = dependencyID.pipxPackage {
            guard let pipxPath = dependency(.pipx)?.path else {
                throw AppIssue.message("Install pipx first so \(dependencyID.title) can live in an isolated Python environment.")
            }
            return [CommandSpec(
                name: "Install \(dependencyID.title)",
                executable: pipxPath,
                arguments: ["install", package],
                explanation: "pipx downloads \(dependencyID.title) into its own Python environment and exposes only the command-line app."
            )]
        }

        throw AppIssue.message("No supported installer is configured for \(dependencyID.title).")
    }

    private func updateCommands() throws -> [CommandSpec] {
        var commands: [CommandSpec] = []
        let brewPath = dependency(.homebrew)?.path
        let pipxPath = dependency(.pipx)?.path
        let managedBrewTools = dependencies.filter { $0.manager == .homebrew && $0.id.brewFormula != nil }
        let managedPipxTools = dependencies.filter { $0.manager == .pipx && $0.id.pipxPackage != nil }

        if let brewPath, !managedBrewTools.isEmpty {
            commands.append(CommandSpec(
                name: "Refresh Homebrew package information",
                executable: brewPath,
                arguments: ["update"],
                explanation: "Downloads Homebrew's current package index. It does not upgrade packages by itself."
            ))
            for status in managedBrewTools {
                guard let formula = status.id.brewFormula else { continue }
                commands.append(CommandSpec(
                    name: "Update \(status.id.title)",
                    executable: brewPath,
                    arguments: ["upgrade", formula],
                    explanation: "Upgrades only the installed \(formula) formula. Homebrew leaves it unchanged if it is already current."
                ))
            }
        }

        if let pipxPath {
            for status in managedPipxTools {
                guard let package = status.id.pipxPackage else { continue }
                commands.append(CommandSpec(
                    name: "Update \(status.id.title)",
                    executable: pipxPath,
                    arguments: ["upgrade", package],
                    explanation: "Upgrades only the isolated \(package) pipx environment and its dependencies."
                ))
            }
        }
        return commands
    }
}
