// Housekeeping — Bookbind
//
// One sheet, and underneath it the page Bookbind has always had. This file is
// only the frame: a heading that says what the screen is, the web view itself,
// and a way out. The engine, the page, and the panels it asks for live in
// `BookbindEngine`, which owns them for the whole life of the app so that
// closing this sheet does not discard a file list or a merge in progress.

import AppKit
import SwiftUI
import WebKit

struct BookbindView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var engine: BookbindEngine
    @Environment(\.uiStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch engine.phase {
                case .idle, .starting:
                    starting
                case .ready:
                    WebViewHost(web: engine.web)
                case .failed(let text):
                    failure(text)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 1040, idealWidth: 1200, maxWidth: 1360,
               minHeight: 640, idealHeight: 780, maxHeight: 980)
        .background { HousekeepingBackdrop(style: style) }
        .preferredColorScheme(style.isRetro ? .light : nil)
        .onAppear {
            engine.applyTheme(appState.currentTheme)
            engine.startIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ThemeButton(title: "Back", systemImage: "chevron.left",
                        help: "Close Bookbind and go back to Housekeeping.") {
                appState.showBookbind = false
            }

            Image(systemName: "book.closed.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(style.accentLifted)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.accent.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Bookbind")
                    .font(style.titleFont)
                    .foregroundColor(style.text)
                Text("Turn a folder of loose audio into one chaptered audiobook.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Spacer()
            Text(engine.phase == .ready ? "ready" : stateWord)
                .font(style.labelFont)
                .foregroundColor(engine.phase == .ready ? style.positive : style.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var stateWord: String {
        switch engine.phase {
        case .idle, .starting: return "starting"
        case .ready: return "ready"
        case .failed: return "needs attention"
        }
    }

    private var starting: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Starting Bookbind's engine…")
                .font(style.bodyFont)
                .foregroundColor(style.secondaryText)
            Text("It runs on this Mac, on a port of its own. Nothing is uploaded.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The engine could not start. The message comes from the engine and says
    /// what is missing and what to type; this only lays it out.
    private func failure(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(style.caution)
            Text(text)
                .font(style.bodyFont)
                .foregroundColor(style.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: 520)
            HStack(spacing: 10) {
                ThemeButton(title: "Show the Log", systemImage: "doc.text",
                            help: "Open the engine's log in the default text app.") {
                    engine.openLog()
                }
                ThemeButton(title: "Try Again", systemImage: "arrow.clockwise",
                            isPrimary: true,
                            help: "Start the engine again, now that whatever it was missing is in place.") {
                    engine.retry()
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Runs on this Mac. Housekeeping starts the engine when this screen opens and stops it when the app quits.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            ThemeButton(title: "Show the Log", systemImage: "doc.text",
                        help: "Open the engine's log.") {
                engine.openLog()
            }
            ThemeButton(title: "Done", isPrimary: true,
                        help: "Close this screen. A merge already running finishes on its own.") {
                appState.showBookbind = false
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Hands the engine's one web view to SwiftUI without ever making a second one.
private struct WebViewHost: NSViewRepresentable {
    let web: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        install(in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The engine keeps one web view for the app's whole life. When the sheet
        // is closed and opened again SwiftUI builds a new host, so the view has
        // to be moved into it — and a moved subview takes its constraints with
        // it, which is why they are installed again rather than left behind.
        if web.superview !== nsView { install(in: nsView) }
    }

    private func install(in container: NSView) {
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
