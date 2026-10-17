import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case download = "Download"
    case setup = "Setup"
    case cookies = "Cookies"
    case troubleshooting = "Troubleshooting"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .download: return "arrow.down.to.line"
        case .setup: return "wrench.and.screwdriver"
        case .cookies: return "key"
        case .troubleshooting: return "lifepreserver"
        }
    }
}

enum MediaSource: String, CaseIterable, Identifiable {
    case youtube = "YouTube"
    case spotify = "Spotify"
    case appleMusic = "Apple Music"

    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .youtube: return "YouTube"
        case .spotify: return "Spotify"
        case .appleMusic: return "AppleMusic"
        }
    }

    var toolID: DependencyID {
        switch self {
        case .youtube: return .ytDlp
        case .spotify: return .spotdl
        case .appleMusic: return .gamdl
        }
    }

    static func detect(from text: String) -> MediaSource? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return nil }
        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") {
            return .youtube
        }
        if host == "spotify.com" || host.hasSuffix(".spotify.com") {
            return .spotify
        }
        if host == "music.apple.com" || host.hasSuffix(".music.apple.com") {
            return .appleMusic
        }
        return nil
    }
}

enum SourceChoice: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case youtube = "YouTube"
    case spotify = "Spotify"
    case appleMusic = "Apple Music"

    var id: String { rawValue }

    var explicitSource: MediaSource? {
        switch self {
        case .automatic: return nil
        case .youtube: return .youtube
        case .spotify: return .spotify
        case .appleMusic: return .appleMusic
        }
    }
}

enum MediaKind: String, CaseIterable, Identifiable {
    case video = "Video"
    case audio = "Audio"
    var id: String { rawValue }
}

enum AudioFormat: String, CaseIterable, Identifiable {
    case mp3, m4a, flac, opus, wav
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum VideoContainer: String, CaseIterable, Identifiable {
    case mp4, mkv, webm
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case best = "Best available"
    case p2160 = "Up to 2160p"
    case p1440 = "Up to 1440p"
    case p1080 = "Up to 1080p"
    case p720 = "Up to 720p"
    case p480 = "Up to 480p"

    var id: String { rawValue }
    var height: Int? {
        switch self {
        case .best: return nil
        case .p2160: return 2160
        case .p1440: return 1440
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

enum AudioQuality: String, CaseIterable, Identifiable {
    case source = "Source / best"
    case high = "High"
    case medium = "Medium"
    case compact = "Compact"

    var id: String { rawValue }

    var ytDlpValue: String {
        switch self {
        case .source: return "0"
        case .high: return "2"
        case .medium: return "5"
        case .compact: return "7"
        }
    }

    func spotDLValue(format: AudioFormat) -> String {
        switch self {
        case .source:
            return (format == .m4a || format == .opus) ? "disable" : "auto"
        case .high: return "192k"
        case .medium: return "128k"
        case .compact: return "96k"
        }
    }
}

enum BrowserChoice: String, CaseIterable, Identifiable {
    case safari, chrome, firefox, brave, edge, chromium, vivaldi
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum DependencyID: String, CaseIterable, Identifiable {
    case homebrew, pipx, ffmpeg, deno, ytDlp, spotdl, gamdl
    var id: String { rawValue }

    var title: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .pipx: return "pipx"
        case .ffmpeg: return "FFmpeg"
        case .deno: return "Deno"
        case .ytDlp: return "yt-dlp"
        case .spotdl: return "SpotDL"
        case .gamdl: return "Gamdl"
        }
    }

    var commandName: String {
        switch self {
        case .homebrew: return "brew"
        case .ytDlp: return "yt-dlp"
        default: return rawValue.lowercased()
        }
    }

    var purpose: String {
        switch self {
        case .homebrew: return "Installs and updates native command-line tools."
        case .pipx: return "Keeps Python command-line apps isolated."
        case .ffmpeg: return "Merges, converts, and tags audio or video."
        case .deno: return "Provides the JavaScript runtime used by current YouTube extraction."
        case .ytDlp: return "Downloads media from YouTube and supplies transfer support to other tools."
        case .spotdl: return "Matches Spotify metadata to audio found through YouTube."
        case .gamdl: return "Orchestrates Apple Music downloads using your own account session."
        }
    }

    var versionArguments: [String] {
        switch self {
        case .homebrew, .pipx, .deno, .ytDlp, .spotdl, .gamdl: return ["--version"]
        case .ffmpeg: return ["-version"]
        }
    }

    var brewFormula: String? {
        switch self {
        case .pipx: return "pipx"
        case .ffmpeg: return "ffmpeg"
        case .deno: return "deno"
        case .ytDlp: return "yt-dlp"
        default: return nil
        }
    }

    var pipxPackage: String? {
        switch self {
        case .spotdl: return "spotdl"
        case .gamdl: return "gamdl"
        default: return nil
        }
    }
}

enum InstallManager: String {
    case homebrew = "Homebrew"
    case pipx = "pipx"
    case external = "External"
    case unknown = "Unknown"
}

struct DependencyStatus: Identifiable {
    let id: DependencyID
    let path: String?
    let version: String?
    let manager: InstallManager
    var isInstalled: Bool { path != nil }
}

struct CommandSpec: Identifiable {
    let id = UUID()
    let name: String
    let executable: String
    let arguments: [String]
    let explanation: String
    let displayOverride: String?

    init(name: String, executable: String, arguments: [String], explanation: String, displayOverride: String? = nil) {
        self.name = name
        self.executable = executable
        self.arguments = arguments
        self.explanation = explanation
        self.displayOverride = displayOverride
    }

    var displayCommand: String {
        if let displayOverride { return displayOverride }
        return ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:=+,%@-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum LogKind {
    case info, command, output, success, error
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let kind: LogKind
}

enum AppIssue: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return "Unknown error"
    }
}
