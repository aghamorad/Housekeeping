import SwiftUI
import AppKit

/// A manual reading. No timer, startup service or automatic cleanup is installed.
struct BackgroundActivityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var snapshot = ActivitySnapshot()
    @State private var loaded = false
    @State private var busy = false
    @State private var reading: Task<Void, Never>?
    @State private var section = Section.recommendations
    @State private var filter = Filter.thirdParty
    @State private var sort = Order.memory
    @State private var query = ""

    private enum Section: String, CaseIterable, Identifiable {
        case recommendations = "Recommendations", running = "Running Now", startup = "Startup Files", registered = "Background Permissions"
        var id: String { rawValue }
    }
    private enum Filter: String, CaseIterable, Identifiable {
        case thirdParty = "Apps & Tools", helpers = "Background Helpers", widgets = "Widgets", all = "Include macOS"
        var id: String { rawValue }
    }
    private enum Order: String, CaseIterable, Identifiable {
        case memory = "Most Memory", cpu = "Most Processor Use", disk = "Largest on Disk", name = "Name"
        var id: String { rawValue }
    }

    private var apps: [ActivityApp] {
        snapshot.apps.filter { app in
            let scope: Bool
            switch filter {
            case .all: scope = true
            case .thirdParty: scope = !app.isSystem
            case .helpers: scope = !app.isSystem && !app.isOpen
            case .widgets: scope = app.isWidget
            }
            return scope && (query.isEmpty || (app.name + " " + app.path).localizedCaseInsensitiveContains(query))
        }.sorted { a, b in
            switch sort {
            case .memory: return a.memoryBytes == b.memoryBytes ? a.path < b.path : a.memoryBytes > b.memoryBytes
            case .cpu: return a.cpu == b.cpu ? a.path < b.path : a.cpu > b.cpu
            case .disk: return a.diskBytes == b.diskBytes ? a.path < b.path : (a.diskBytes ?? -1) > (b.diskBytes ?? -1)
            case .name: return a.name == b.name ? a.path < b.path : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
    private var registrations: [ActivityRegistration] {
        snapshot.registrations.filter { query.isEmpty || ($0.name + " " + $0.identifier + " " + ($0.owner ?? "")).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    if let maintenanceMascot = HousekeeperMascot.loadMaintenance() {
                        Image(nsImage: maintenanceMascot)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Activity").font(.system(size: 28, weight: .bold))
                        Text("Find the apps, widgets and helpers using your Mac. Decide what you still need by checking their purpose and current use.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(busy ? "Reading your Mac…" : "Refresh reading") { refresh() }.disabled(busy)
                    Button("Open Login Items") { openLoginItems() }
                    Button("Review Uninstalled App Leftovers") { appState.cleaner.category = .orphans; appState.showClean = true }
                    Button("Uninstall Apps") { appState.showUninstaller = true }
                }.buttonStyle(.bordered).controlSize(.large)
                if busy {
                    HStack { ProgressView().controlSize(.small); Text("Reading processes, background permissions and disk footprints…") }
                }
                if loaded {
                    Text("Reading taken \(snapshot.captured.formatted(date: .omitted, time: .standard)). Refresh to see changes.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                ForEach(snapshot.notices, id: \.self) { Text($0).foregroundStyle(.orange) }
                Picker("Review", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).controlSize(.large)
                if section == .recommendations {
                    if loaded {
                        BackgroundReviewView(snapshot: snapshot, refresh: refresh, openStartup: { section = .startup })
                    } else if !busy { Text("Refresh the reading to build your recommendations.") }
                } else if section == .startup {
                    BackgroundItemsView()
                } else {
                    TextField("Search by app or path", text: $query).textFieldStyle(.roundedBorder).controlSize(.large)
                    if section == .running { runningBody } else { registrationBody }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if !loaded { refresh() } }
        .onDisappear { reading?.cancel(); busy = false }
    }

    private var runningBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Sort", selection: $sort) { ForEach(Order.allCases) { Text($0.rawValue).tag($0) } }
            }.controlSize(.large)
            Text("RAM is the resident memory reported by macOS, including helpers grouped under their app. Shared memory can be counted more than once. Processor use is a single reading and can exceed 100% across cores. Disk footprint is installed storage, not a promise of removable space; app data and caches are reviewed in Clean Up.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Text("Background Helpers means there is no ordinary app window registered for that group. Tools, services and menu bar apps can still be useful. A widget may appear under its owning app.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Text("\(apps.count) groups in this view · \(bytes(apps.reduce(0) { $0 + $1.memoryBytes })) reported RAM")
                .font(.system(size: 16, weight: .semibold))
            if loaded && apps.isEmpty { Text("No matching processes in this reading.") }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(apps) { app in appRow(app) }
            }
        }
    }

    private func appRow(_ app: ActivityApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 18, weight: .semibold))
                    Text(!app.path.hasPrefix("/") ? "Ownership unknown" : app.isSystem ? "macOS component" : app.isOpen ? "App open" : app.isWidget ? "Widget extension" : "Background helper or tool")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(bytes(app.memoryBytes)) RAM · \(app.cpu, specifier: "%.1f")% processor")
                    Text(app.diskBytes.map { bytes($0) + " on disk" } ?? "Disk footprint not measured")
                        .foregroundStyle(.secondary)
                }.font(.system(size: 15))
            }
            Text(app.advice).font(.system(size: 15))
            Text(app.path).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            DisclosureGroup("See \(app.processes.count) processes") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(app.processes.sorted { $0.residentBytes > $1.residentBytes }, id: \.pid) { process in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(URL(fileURLWithPath: process.path).lastPathComponent) · \(bytes(process.residentBytes)) RAM · \(process.cpu, specifier: "%.1f")% processor")
                                .font(.system(size: 14, weight: .medium))
                            Text("Process \(process.pid) · \(process.path)").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }.padding(.top, 10)
            }.font(.system(size: 15))
            if app.path.hasPrefix("/") {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button("Ask the Housekeeper") {
                    HousekeeperTopic.ask(HousekeeperTopic(id: "activity-" + app.id, title: app.name, label: "Background activity", tone: .plain,
                        facts: [app.path, "Reported RAM: " + bytes(app.memoryBytes), "Processor: \(app.cpu)%", app.advice],
                        opener: "What does this app or helper do, and what would I lose by disabling it?"))
                }
            }
    }

    private var registrationBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permission is separate from activity. An allowed item may be idle; a disallowed item can still run while its app is open. macOS manages these permissions in Login Items. App extensions listed here may instead be controlled by their own app or widget settings.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
            Text("\(registrations.count) registrations in this view").font(.system(size: 16, weight: .semibold))
            if loaded && registrations.isEmpty { Text("No matching registrations were available.") }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(registrations) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name).font(.system(size: 18, weight: .semibold))
                        Text(item.permissionLabel).font(.system(size: 15, weight: .medium))
                        Text(item.kind).foregroundStyle(.secondary)
                        Text(registrationUse(item)).font(.system(size: 15))
                        if let owner = item.owner { Text("Owning app: " + owner).textSelection(.enabled) }
                        if let path = item.path { Text(path).font(.system(size: 13, design: .monospaced)).textSelection(.enabled) }
                        if let executable = item.executable { Text("Executable: " + executable).font(.system(size: 13)).textSelection(.enabled) }
                        Text(item.identifier).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                        if let path = item.owner ?? item.path {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                                .buttonStyle(.bordered).controlSize(.large)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu {
                            Button("Ask the Housekeeper") {
                                HousekeeperTopic.ask(HousekeeperTopic(id: "registration-" + item.id, title: item.name, label: "Background permission", tone: .plain,
                                    facts: [item.identifier, item.permissionLabel, item.owner ?? "Owning app unknown", registrationUse(item)],
                                    opener: "What depends on this background item, and should I allow it at login?"))
                            }
                        }
                }
            }
        }
    }

    private func registrationUse(_ item: ActivityRegistration) -> String {
        guard let executable = item.executable else { return "Current activity unknown: this registration does not give an unambiguous executable path." }
        let matches = snapshot.apps.flatMap(\.processes).filter { $0.path == executable }
        guard !matches.isEmpty else { return "No matching executable in this reading. Related app activity may appear under Running Now." }
        return "Matching executable: \(matches.count) processes · \(bytes(matches.reduce(0) { $0 + $1.residentBytes })) reported RAM"
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .memory) }
    private func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func refresh() {
        guard !busy else { return }
        busy = true
        let open = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { $0.bundleURL?.path })
        reading = Task {
            let result = await BackgroundActivity.shared.scan(openApps: open)
            guard !Task.isCancelled else { return }
            snapshot = result
            loaded = true
            busy = false
        }
    }
}
