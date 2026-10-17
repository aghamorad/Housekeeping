// Housekeeping — Extras
//
// Two apps built here, each with its own repository and its own release. They
// are not jobs Housekeeping performs and it does not change them: it carries
// them inside its own bundle and opens them, so the one window a reader already
// keeps open is also the place they can be found. Nothing on this screen acts on
// the Mac — it starts another app and then gets out of the way.
//
// A bundle that is not in this build is a normal state rather than a failure —
// a source checkout has neither — so the card says where to get it instead of
// offering a button that cannot work.

import SwiftUI
import AppKit

struct ExtraApp: Identifiable {
    let id: String
    let title: String
    let tagline: String
    let detail: String
    let systemImage: String
    let tint: Color
    /// The bundle name as it travels inside `Contents/Resources/Extras`.
    let bundleName: String
    /// Where a development copy lives, tried only when the bundle is not inside
    /// this app. Tilde paths, so one list works for any account.
    let devPaths: [String]
    let repository: String
}

enum ExtraApps {
    static let all: [ExtraApp] = [
        ExtraApp(
            id: "mediadock",
            title: "MediaDock 9",
            tagline: "A retro front end for yt-dlp, spotdl and gamdl.",
            detail: "Paste a link and pick where it goes: it fetches the video, the audio, or the artwork, and shows the queue while it works. The downloaders still do the downloading — this is the window in front of them.",
            systemImage: "play.rectangle.fill",
            tint: Color(red: 0.36, green: 0.63, blue: 0.94),
            bundleName: "MediaDock 9.app",
            devPaths: ["~/Claude/Apps & Games/MediaDock9/dist/MediaDock 9.app"],
            repository: "https://github.com/aghamorad/MediaDock9"
        ),
        ExtraApp(
            id: "bookbind",
            title: "Bookbind",
            tagline: "Turn a folder of loose audio into one chaptered audiobook.",
            detail: "Give it the files in order and it merges them into a single .m4b with chapters, looks up the book online for its metadata and cover, checks the result, and keeps one click of undo.",
            systemImage: "book.closed.fill",
            tint: Color(red: 0.91, green: 0.60, blue: 0.36),
            bundleName: "Bookbind.app",
            devPaths: ["~/Claude/Bookbind/Bookbind.app"],
            repository: "https://github.com/aghamorad/bookbind"
        )
    ]

    /// The copy inside this bundle first, because that is the one a reader who
    /// downloaded Housekeeping has; the development folders second, so the screen
    /// is not empty while the app is being built.
    static func path(for app: ExtraApp) -> String? {
        var candidates: [String] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Extras/\(app.bundleName)").path)
        }
        candidates += app.devPaths.map { ($0 as NSString).expandingTildeInPath }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func version(for app: ExtraApp) -> String? {
        guard let path = path(for: app), let bundle = Bundle(path: path) else { return nil }
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Returns nil on success, or one line saying what stopped it. The caller
    /// shows that line where the buttons are, because a launch that did nothing
    /// and said nothing is the one failure a reader cannot diagnose.
    @discardableResult
    static func open(_ app: ExtraApp) -> String? {
        guard let path = path(for: app) else {
            return "\(app.title) is not in this copy of Housekeeping. Get it from \(app.repository)."
        }
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) { return nil }
        return "macOS would not open \(app.title) from \(path)."
    }

    /// Opens the folder the extras travel in rather than selecting the app
    /// itself. Finder resolves an app bundle by its identity, so asking it to
    /// reveal this copy can land on whichever copy it knows about — an installed
    /// release, a checkout, even one that has been moved — which is not the copy
    /// this screen is talking about. A folder has no identity to resolve.
    static func reveal(_ app: ExtraApp) {
        guard let path = path(for: app) else { return }
        let folder = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true))
    }

    static func openRepository(_ app: ExtraApp) {
        guard let url = URL(string: app.repository) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct ExtrasView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @State private var message = ""
    @State private var isError = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("These are separate apps, not parts of Housekeeping. Opening one starts it exactly as if you had double-clicked it in Finder; Housekeeping does not change it, update it, or keep it running.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(ExtraApps.all) { app in
                        card(app)
                    }

                    if !message.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                                .foregroundColor(isError ? style.caution : style.secondaryText)
                            Text(message)
                                .font(style.smallFont)
                                .foregroundColor(isError ? style.caution : style.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        // A fixed width, not a minimum: a ScrollView hands its content an
        // unbounded width, so a `minWidth` only sets the floor and the sheet
        // then grows to the longest line of prose — wider than the window it
        // is attached to, hanging off both sides. The width has to be decided
        // here so the text wraps inside it.
        .frame(minWidth: 760, maxWidth: 760, minHeight: 470, idealHeight: 560)
        .background(style.windowBackground)
        .preferredColorScheme(style.isRetro ? .light : .dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extras")
                    .font(style.titleFont)
                    .foregroundColor(style.text)
                Text("The other apps built here, kept in the same place as this one.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func card(_ app: ExtraApp) -> some View {
        let path = ExtraApps.path(for: app)
        let version = ExtraApps.version(for: app)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: app.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(app.tint)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(app.tint.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(app.tint.opacity(0.35), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(app.title)
                            .font(style.bodyFont.bold())
                            .foregroundColor(style.text)
                        if let version {
                            Text("version \(version)")
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                        }
                        if path == nil {
                            Text("not included")
                                .font(style.labelFont)
                                .foregroundColor(style.caution)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(style.caution.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(app.tagline)
                        .font(style.smallFont)
                        .foregroundColor(style.text.opacity(0.9))
                    Text(app.detail)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    ThemeButton(
                        title: "Open",
                        systemImage: "arrow.up.forward.app",
                        isPrimary: path != nil,
                        isEnabled: path != nil,
                        help: path == nil
                            ? "\(app.title) is not inside this copy of Housekeeping."
                            : "Start \(app.title) as its own app. Housekeeping takes no part in what it does."
                    ) {
                        if let failure = ExtraApps.open(app) {
                            message = failure
                            isError = true
                        } else {
                            message = "\(app.title) opened in its own window."
                            isError = false
                        }
                    }

                    if path != nil {
                        ThemeButton(
                            title: "Show in Finder",
                            systemImage: "folder",
                            isPrimary: false,
                            help: "Open the folder inside Housekeeping that carries \(app.title), so you can see the file itself."
                        ) {
                            ExtraApps.reveal(app)
                        }
                    }
                }
            }

            if path == nil {
                HStack(spacing: 8) {
                    Text("This build was made without \(app.title) inside it.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                    Button("Open the repository") {
                        ExtraApps.openRepository(app)
                    }
                    .buttonStyle(.plain)
                    .font(style.smallFont)
                    .foregroundColor(style.accent)
                    .help(app.repository)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.groupingBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(style.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Text("Both apps carry their own update check.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Spacer()
            ThemeButton(title: "Done", isPrimary: true, help: "Close this screen. Nothing has been changed on the Mac.") {
                appState.showExtras = false
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
