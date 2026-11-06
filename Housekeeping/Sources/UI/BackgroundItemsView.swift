import SwiftUI
import AppKit

struct BackgroundItemsView: View {
    @State private var items: [BackgroundAuditItem] = []
    @State private var notices: [String] = []
    @State private var busy = false
    @State private var loaded = false
    @State private var pending: BackgroundAuditItem?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What starts in the background?").font(.system(size: 22, weight: .bold))
            Text("Review startup configurations, broken links, scheduled updaters and optional integrations. A background helper being present does not prove it is using power or causing a network conflict.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
            HStack {
                Button(busy ? "Reading…" : "Scan startup items") { refresh() }.disabled(busy)
                Button("Open Login Items") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }.buttonStyle(.bordered).controlSize(.large)
            Text("Use Background Permissions to see app-managed login items and their permission state. This tab reviews startup files. A schedule is not evidence of continuous CPU or memory use. Turning off a VPN helper may prevent it connecting until you re-enable it.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            if let notice { Text(notice).font(.system(size: 15)).textSelection(.enabled) }
            ForEach(notices, id: \.self) { Text($0).foregroundStyle(.orange) }
            if loaded && items.isEmpty { Text("No startup files were found in the locations that could be read.") }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    auditRow(item)
                }
            }
        }
        .task { if !loaded { refresh() } }
        .alert("Move this startup item to Trash?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Move to Trash", role: .destructive) {
                guard let reviewed = pending else { return }
                pending = nil
                busy = true
                Task {
                    do {
                        try await BackgroundItemAudit.shared.trash(reviewed)
                        notice = "Moved to Trash. Restore it from Trash to undo; its app may need reopening afterward."
                    } catch { notice = error.localizedDescription }
                    busy = false
                    refresh()
                }
            }
        } message: {
            Text("\(pending?.url.path ?? "")\n\nHousekeeping will unload this item if it is registered, then move its configuration to Trash. Its feature will stop. System items require macOS administrator approval. Keep it if you are unsure.")
        }
    }

    private func auditRow(_ item: BackgroundAuditItem) -> some View {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(item.label, systemImage: item.canTrash ? "exclamationmark.circle" : "info.circle")
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.finding).font(.system(size: 15))
                        Text(item.url.path).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        if !item.target.isEmpty {
                            Text("Runs: \(item.target)").font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        HStack {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            if item.canTrash {
                                Button("Review removal…") { pending = item }.disabled(busy)
                            }
                        }.buttonStyle(.bordered).controlSize(.large)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu {
                            Button("Ask the Housekeeper") {
                                HousekeeperTopic.ask(HousekeeperTopic(id: "startup-" + item.id, title: item.label,
                                    label: "Startup item", tone: .plain,
                                    facts: ["Configuration: " + item.url.path, "Configured executable: " + item.target, item.finding],
                                    opener: "What does this background item do, what depends on it, and should I keep it?"))
                            }
                        }
    }

    private func refresh() {
        guard !busy else { return }
        busy = true
        Task {
            let result = await BackgroundItemAudit.shared.scan()
            items = result.items
            notices = result.notices
            loaded = true
            busy = false
        }
    }
}
