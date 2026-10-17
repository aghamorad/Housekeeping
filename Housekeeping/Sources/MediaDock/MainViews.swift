import SwiftUI

struct DownloadView: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                RetroPanel(title: "Link & source") {
                    RetroTextField(placeholder: "Paste a YouTube, Spotify, or Apple Music URL", text: $model.urlText)
                    HStack(spacing: 10) {
                        Picker("Source", selection: $model.sourceChoice) {
                            ForEach(SourceChoice.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(model.detectedSourceText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(detectionColor)
                            .frame(minWidth: 220, alignment: .trailing)
                    }
                }

                if let source = model.effectiveSource {
                    formatPanel(for: source)
                    optionsPanel(for: source)
                    destinationPanel(for: source)
                }

                RetroPanel(title: "Exact command preview") {
                    Text(model.commandPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .insetBorder()
                    HStack {
                        Text("The app launches this executable with these arguments; it does not hide a second command.")
                            .font(skin.font(10))
                            .foregroundStyle(skin.ink.opacity(0.7))
                        Spacer()
                        Button("Copy") { model.copy(model.commandPreview) }
                            .buttonStyle(MediaDockButtonStyle())
                    }
                }

                HStack {
                    Text("Use only for media you are permitted to download. Service terms can change independently of this app.")
                        .font(skin.font(10))
                        .foregroundStyle(skin.ink.opacity(0.68))
                    Spacer()
                    Button("Download") { model.startDownload() }
                        .buttonStyle(MediaDockButtonStyle(prominent: true))
                        .disabled(!model.canStartDownload)
                }
            }
            .padding(14)
        }
        .background(skin.desktop)
    }

    @ViewBuilder
    private func formatPanel(for source: MediaSource) -> some View {
        RetroPanel(title: "Format & quality") {
            switch source {
            case .youtube:
                PropertyRow(label: "Media") {
                    Picker("Media", selection: $model.mediaKind) {
                        ForEach(MediaKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                if model.mediaKind == .video {
                    PropertyRow(label: "Container") {
                        Picker("Container", selection: $model.videoContainer) {
                            ForEach(VideoContainer.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 170)
                    }
                    PropertyRow(label: "Resolution") {
                        Picker("Resolution", selection: $model.videoQuality) {
                            ForEach(VideoQuality.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 210)
                    }
                } else {
                    audioRows
                }
            case .spotify:
                audioRows
                Text("SpotDL's quality control may transcode a lower-bitrate source; selecting a larger bitrate cannot create missing detail.")
                    .font(skin.font(10))
                    .foregroundStyle(skin.ink.opacity(0.68))
            case .appleMusic:
                PropertyRow(label: "Songs") {
                    Text("AAC Web · up to 256 kbps")
                    Text("No wrapper or local decryption component is configured.")
                        .foregroundStyle(skin.ink.opacity(0.62))
                }
                PropertyRow(label: "Music videos") {
                    Picker("Resolution", selection: $model.videoQuality) {
                        ForEach(VideoQuality.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 210)
                    Text("MP4")
                }
            }
        }
    }

    private var audioRows: some View {
        Group {
            PropertyRow(label: "Audio format") {
                Picker("Audio format", selection: $model.audioFormat) {
                    ForEach(AudioFormat.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().frame(width: 170)
            }
            PropertyRow(label: "Quality") {
                Picker("Quality", selection: $model.audioQuality) {
                    ForEach(AudioQuality.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 210)
            }
        }
    }

    @ViewBuilder
    private func optionsPanel(for source: MediaSource) -> some View {
        RetroPanel(title: "Handling & extras") {
            Toggle(source == .appleMusic ? "Treat collections and artist links as batches" : "Download playlists / collections", isOn: $model.playlistMode)
                .toggleStyle(.checkbox)
            Toggle(source == .appleMusic ? "Keep a download database" : "Skip items recorded in the archive", isOn: $model.useArchive)
                .toggleStyle(.checkbox)

            ThinRule()

            switch source {
            case .youtube:
                Toggle("Embed metadata", isOn: $model.includeMetadata).toggleStyle(.checkbox)
                Toggle("Embed artwork / thumbnail", isOn: $model.includeArtwork).toggleStyle(.checkbox)
                if model.mediaKind == .video {
                    Toggle("Write and embed subtitles", isOn: $model.includeSubtitles).toggleStyle(.checkbox)
                    if model.includeSubtitles {
                        PropertyRow(label: "Subtitle codes") {
                            RetroTextField(placeholder: "en.*,en", text: $model.subtitleLanguages)
                                .frame(width: 220)
                            Text("yt-dlp language pattern")
                                .foregroundStyle(skin.ink.opacity(0.6))
                        }
                    }
                }
                Toggle("Use browser sign-in cookies", isOn: $model.useYouTubeCookies).toggleStyle(.checkbox)
                if model.useYouTubeCookies {
                    PropertyRow(label: "Browser") {
                        Picker("Browser", selection: $model.browserChoice) {
                            ForEach(BrowserChoice.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 180)
                        Button("Cookie help") { model.section = .cookies }
                            .buttonStyle(MediaDockButtonStyle())
                    }
                }
            case .spotify:
                Text("SpotDL writes Spotify metadata and cover art as part of its matching workflow.")
                    .font(skin.font(11))
                Toggle("Generate synced LRC lyrics when available", isOn: $model.includeLyrics).toggleStyle(.checkbox)
            case .appleMusic:
                Toggle("Embed metadata tags", isOn: $model.includeMetadata).toggleStyle(.checkbox)
                Toggle("Also save cover artwork as a separate file", isOn: $model.includeArtwork).toggleStyle(.checkbox)
                Toggle("Download synced lyrics as LRC", isOn: $model.includeLyrics).toggleStyle(.checkbox)
                HStack {
                    StatusLight(color: model.appleCookiesPath.isEmpty ? skin.amber : skin.green)
                    Text(model.appleCookiesPath.isEmpty ? "Cookie file not selected" : "Cookie-file path selected")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Button("Cookie help") { model.section = .cookies }
                        .buttonStyle(MediaDockButtonStyle())
                }
            }
        }
    }

    private func destinationPanel(for source: MediaSource) -> some View {
        RetroPanel(title: "Destination") {
            HStack(spacing: 8) {
                Text(model.outputFolder(for: source))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetBorder()
                Button("Choose…") { model.chooseOutputFolder(for: source) }
                    .buttonStyle(MediaDockButtonStyle())
                Button("Reveal") { model.revealOutputFolder() }
                    .buttonStyle(MediaDockButtonStyle())
            }
            Text("Default: ~/Downloads/\(source.folderName). Existing files are preserved unless the underlying tool documents otherwise.")
                .font(skin.font(10))
                .foregroundStyle(skin.ink.opacity(0.66))
        }
    }

    private var detectionColor: Color {
        if model.sourceChoice != .automatic { return skin.ink.opacity(0.72) }
        return MediaSource.detect(from: model.urlText) == nil && !model.urlText.isEmpty ? skin.red : skin.ink.opacity(0.72)
    }
}

struct SetupView: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                RetroPanel(title: "Setup controls") {
                    HStack {
                        Text("MediaDock checks standard Apple Silicon, Intel Homebrew, pipx, and user-local command paths.")
                            .font(skin.font(11))
                        Spacer()
                        Button("Rescan") { model.refreshDependencies() }
                            .buttonStyle(MediaDockButtonStyle())
                            .disabled(model.isScanning || model.runner.isRunning)
                        Button("Update All") { model.requestUpdateAll() }
                            .buttonStyle(MediaDockButtonStyle(prominent: true))
                            .disabled(model.isScanning || model.runner.isRunning)
                    }
                    Text("Update All touches only MediaDock dependencies confirmed as Homebrew- or pipx-managed. You review every command first.")
                        .font(skin.font(10))
                        .foregroundStyle(skin.ink.opacity(0.68))
                }

                VStack(spacing: 7) {
                    ForEach(DependencyID.allCases) { dependencyID in
                        DependencyRow(dependencyID: dependencyID)
                    }
                }
            }
            .padding(14)
        }
        .background(skin.desktop)
    }
}

private struct DependencyRow: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel
    let dependencyID: DependencyID

    var status: DependencyStatus? { model.dependency(dependencyID) }

    var body: some View {
        HStack(spacing: 12) {
            StatusLight(color: lightColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(dependencyID.title)
                        .font(skin.font(13, weight: .bold))
                    if let status, status.isInstalled {
                        Text(status.manager.rawValue.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(Rectangle().stroke(skin.midEdge, lineWidth: 1))
                    }
                }
                Text(dependencyID.purpose)
                    .font(skin.font(10))
                    .foregroundStyle(skin.ink.opacity(0.67))
            }
            .frame(width: 330, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(status?.path ?? "Not on the MediaDock search path")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(skin.ink.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if status?.isInstalled != true {
                Button("Install…") { model.requestInstall(dependencyID) }
                    .buttonStyle(MediaDockButtonStyle())
                    .disabled(model.runner.isRunning || model.isScanning || installBlocked)
            } else if status?.manager == .external {
                Text("UPDATE MANUALLY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(skin.amber)
            } else {
                Text("MANAGED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(skin.green)
            }
        }
        .padding(12)
        .raisedBorder()
    }

    private var statusText: String {
        guard let status else { return model.isScanning ? "Checking…" : "Not scanned" }
        return status.version ?? (status.isInstalled ? "Installed" : "Missing")
    }

    private var lightColor: Color {
        guard let status else { return skin.amber }
        return status.isInstalled ? skin.green : skin.red
    }

    private var installBlocked: Bool {
        if dependencyID == .homebrew { return false }
        if dependencyID.pipxPackage != nil { return model.dependency(.pipx)?.isInstalled != true }
        return model.dependency(.homebrew)?.isInstalled != true
    }
}

struct CookiesView: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                RetroPanel(title: "Apple Music · cookies.txt") {
                    StepLine(number: 1, text: "Open music.apple.com in a browser and sign in to the Apple Music subscription you intend to use.")
                    StepLine(number: 2, text: "Export only after you are signed in. Gamdl requires Netscape/Mozilla cookie-file format; use the export method linked in Gamdl's own instructions.")
                    StepLine(number: 3, text: "Choose the resulting cookies.txt here. MediaDock remembers the path but never reads, copies, previews, uploads, or logs its contents.")

                    HStack {
                        Button("Open Apple Music") { model.openWebPage("https://music.apple.com") }
                            .buttonStyle(MediaDockButtonStyle())
                        Button("Open Gamdl instructions") { model.openWebPage("https://github.com/glomatico/gamdl#-prerequisites") }
                            .buttonStyle(MediaDockButtonStyle())
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        StatusLight(color: model.appleCookiesPath.isEmpty ? skin.amber : skin.green)
                        Text(model.appleCookiesPath.isEmpty ? "No file selected" : model.appleCookiesPath)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .insetBorder()
                        Button("Choose…") { model.chooseAppleCookies() }
                            .buttonStyle(MediaDockButtonStyle(prominent: true))
                        Button("Forget path") { model.appleCookiesPath = "" }
                            .buttonStyle(MediaDockButtonStyle())
                            .disabled(model.appleCookiesPath.isEmpty)
                    }

                    Text("Treat cookies.txt like a password. Store it privately, never paste it into a chat or log, and delete it when no longer needed. Signing out of Apple Music invalidates the session but may also require a fresh export later.")
                        .font(skin.font(10))
                        .foregroundStyle(skin.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RetroPanel(title: "YouTube · browser sign-in") {
                    Text("yt-dlp can ask the selected browser for its cookie database at run time. MediaDock passes only --cookies-from-browser and the browser name; no exported cookie file is created by this app.")
                        .font(skin.font(11))
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Use browser cookies for YouTube downloads", isOn: $model.useYouTubeCookies)
                        .toggleStyle(.checkbox)
                    PropertyRow(label: "Browser") {
                        Picker("Browser", selection: $model.browserChoice) {
                            ForEach(BrowserChoice.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    Text("Use this only for sign-in-required media you are authorized to access. Chromium-family browsers may lock their cookie database while open; quitting the browser and retrying can resolve that specific error.")
                        .font(skin.font(10))
                        .foregroundStyle(skin.ink.opacity(0.68))
                }

                RetroPanel(title: "What the app stores") {
                    PrivacyRow(item: "Stored", detail: "Cookie-file path, selected browser name, output folders, and download-option preferences.")
                    PrivacyRow(item: "Not stored", detail: "Cookie contents, Apple or Google passwords, tokens copied from logs, or a private command history file.")
                    PrivacyRow(item: "Visible", detail: "The exact command line, which includes the cookie-file path but never the file's contents.")
                }
            }
            .padding(14)
        }
        .background(skin.desktop)
    }
}

private struct StepLine: View {
    @Environment(\.mediaDockSkin) private var skin
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 20, height: 20)
                .overlay(Rectangle().stroke(skin.darkEdge, lineWidth: 1))
            Text(text).font(skin.font(11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrivacyRow: View {
    @Environment(\.mediaDockSkin) private var skin
    let item: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .frame(width: 78, alignment: .trailing)
            Text(detail).font(skin.font(11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TroubleshootingView: View {
    @Environment(\.mediaDockSkin) private var skin
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TroubleCard(
                    title: "1 · Update first",
                    symptom: "Extraction failures, unsupported URLs, or behavior that changed suddenly.",
                    recovery: "Open Setup, rescan, review Update All, and run it. yt-dlp and service-facing Python tools change often."
                ) {
                    Button("Open Setup") { model.section = .setup }
                        .buttonStyle(MediaDockButtonStyle())
                }

                TroubleCard(
                    title: "2 · Cookie or token rejected",
                    symptom: "Gamdl reports missing media-user-token, unauthorized, subscription, storefront, or cookie errors.",
                    recovery: "Sign in again at music.apple.com, create a fresh Netscape-format cookie export, choose the new file, then retry. Never paste cookie contents into the activity log."
                ) {
                    Button("Cookie help") { model.section = .cookies }
                        .buttonStyle(MediaDockButtonStyle())
                }

                TroubleCard(
                    title: "3 · YouTube asks for sign-in",
                    symptom: "“Sign in to confirm you're not a bot,” age restriction, members-only, or cookie database errors.",
                    recovery: "Enable browser cookies, select the browser in which you are signed in, and retry. If the browser database is locked, quit that browser once and retry."
                ) {
                    Button("Cookie help") { model.section = .cookies }
                        .buttonStyle(MediaDockButtonStyle())
                }

                TroubleCard(
                    title: "4 · Read timeout or stalled fragments",
                    symptom: "ReadTimeout, TLS/network failures, repeated fragment retries, or progress that remains at zero.",
                    recovery: "Stop cleanly, confirm the network works in the browser, disable unstable proxy/VPN routing for a controlled retry, then update the tool. Partial files are left for inspection rather than silently removed."
                )

                TroubleCard(
                    title: "5 · Command exists in Terminal but not here",
                    symptom: "Setup says Missing although the same command works in an interactive shell.",
                    recovery: "Rescan. MediaDock checks /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, recent user Python bin folders, and the inherited PATH. If installed elsewhere, link it into one of those locations or update it with its original manager."
                )

                RetroPanel(title: "Diagnostic summary") {
                    Text("This report contains tool versions and executable paths, but no cookie contents or pasted URL.")
                        .font(skin.font(11))
                    Text(model.diagnosticSummary())
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .insetBorder()
                    HStack {
                        Button("Rescan") { model.refreshDependencies() }
                            .buttonStyle(MediaDockButtonStyle())
                        Button("Copy summary") { model.copy(model.diagnosticSummary()) }
                            .buttonStyle(MediaDockButtonStyle(prominent: true))
                        Spacer()
                    }
                }
            }
            .padding(14)
        }
        .background(skin.desktop)
    }
}

private struct TroubleCard<Action: View>: View {
    @Environment(\.mediaDockSkin) private var skin
    let title: String
    let symptom: String
    let recovery: String
    @ViewBuilder var action: () -> Action

    init(title: String, symptom: String, recovery: String, @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.title = title
        self.symptom = symptom
        self.recovery = recovery
        self.action = action
    }

    var body: some View {
        RetroPanel(title: title) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(symptom)
                        .font(skin.font(11, weight: .semibold))
                    Text(recovery)
                        .font(skin.font(11))
                        .foregroundStyle(skin.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                action()
            }
        }
    }
}
