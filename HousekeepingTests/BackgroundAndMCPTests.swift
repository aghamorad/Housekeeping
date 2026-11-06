import Foundation

@main
struct BackgroundAndMCPTests {
    static func main() async throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            assertions += 1
        }
        check(ExpressVPNMCPSettings.validatedURL("http://localhost:1234/mcp?token=fake")?.host == "127.0.0.1", "canonical loopback")
        for bad in ["https://example.com/mcp?token=x", "http://127.0.0.1.evil:123/mcp?token=x", "http://127.0.0.1:123/mcp", "http://user:pass@127.0.0.1:123/mcp?token=x", "http://127.0.0.1:123/other?token=x"] {
            check(ExpressVPNMCPSettings.validatedURL(bad) == nil, "reject unsafe address")
        }
        let json = Data(#"{"jsonrpc":"2.0","id":7,"result":{"ok":true}}"#.utf8)
        let decoded = try ExpressVPNMCP.decode(json, id: 7)
        check(decoded["ok"] as? Bool == true, "JSON response")
        let sse = Data("event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/test\"}\r\n\r\nevent: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"ok\":true}}\r\n\r\n".utf8)
        let streamed = try ExpressVPNMCP.decode(sse, id: 7)
        check(streamed["ok"] as? Bool == true, "SSE response after notification")
        do { _ = try ExpressVPNMCP.decode(json, id: 8); fatalError("unmatched id accepted") } catch { assertions += 1 }
        do { _ = try ExpressVPNMCP.decode(Data(#"{"id":7,"error":{"message":"SECRET"}}"#.utf8), id: 7); fatalError("RPC error accepted") }
        catch { check(!error.localizedDescription.contains("SECRET"), "server error redacted") }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("HousekeepingAuditTests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        func fixture(_ label: String, target: String, extra: [String: Any] = [:]) throws -> BackgroundAuditItem {
            var plist: [String: Any] = ["Label": label, "ProgramArguments": [target]]
            plist.merge(extra) { _, new in new }
            let file = root.appendingPathComponent(label + ".plist")
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file)
            return BackgroundItemAudit.inspect(file)!
        }
        let missing = try fixture("test.missing", target: root.appendingPathComponent("gone").path)
        check(missing.canTrash, "missing executable review")
        let existing = try fixture("test.present", target: "/bin/sh", extra: ["KeepAlive": true])
        check(!existing.canTrash && existing.finding.contains("stay running"), "working helper preserved")
        let personal = try fixture("com.morad.personal", target: root.appendingPathComponent("missing").path)
        check(!personal.canTrash, "personal service protected")
        let system = try fixture("com.apple.personal", target: root.appendingPathComponent("missing").path)
        check(!system.canTrash, "Apple service protected")
        let vpn = try fixture("com.vendor.vpn", target: "/bin/sh")
        check(!vpn.canTrash && vpn.finding.contains("current connection"), "VPN preserved")
        let schedule = try fixture("test.updater", target: "/bin/sh", extra: ["StartInterval": 3600])
        check(!schedule.canTrash && schedule.finding.contains("3600"), "scheduled updater explained")
        let relative = try fixture("test.relative", target: "helper")
        check(!relative.canTrash, "relative executable is not falsely missing")
        let link = root.appendingPathComponent("test.link.plist")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "missing-target")
        check(BackgroundItemAudit.inspect(link)?.canTrash == true, "broken relative symlink")
        let personalLink = root.appendingPathComponent("com.morad.link.plist")
        try fm.createSymbolicLink(atPath: personalLink.path, withDestinationPath: "missing-target")
        check(BackgroundItemAudit.inspect(personalLink)?.canTrash == false, "protected symlink")
        do { try await BackgroundItemAudit.shared.trash(missing); fatalError("outside launch root accepted") } catch { assertions += 1 }

        let processText = """
          100 1 501 1.2 2048 /Applications/My App.app/Contents/MacOS/My App
          101 100 501 0.1 1024 /usr/bin/python3
          200 1 0 0.0 512 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
          broken row
          201 1 0 1.2 -5 /bin/sh
        """
        let processes = BackgroundActivity.parseProcesses(processText)
        check(processes.count == 3, "process parser skips invalid rows")
        check(processes[0].path.hasSuffix("My App"), "process paths retain spaces")
        check(processes[0].residentBytes == 2_097_152, "RSS unit conversion")
        check(processes[0].cpu == 1.2, "CPU measurement")
        let index = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        check(BackgroundActivity.owner(processes[1], index: index) == "/Applications/My App.app", "interpreter follows app ancestor")
        check(BackgroundActivity.isSystemPath(processes[2].path), "Apple system path")
        check(!BackgroundActivity.isSystemPath("/Applications/Third Party.app"), "third party not system")
        check(BackgroundActivity.appPath("/Applications/A.app/Contents/Helpers/B.app/Contents/MacOS/B") == "/Applications/A.app", "nested helpers group under outer app")
        let cyclic = ActivityProcess(pid: 1, parent: 1, uid: 501, cpu: 0, residentBytes: 0, path: "/usr/local/bin/worker")
        check(BackgroundActivity.owner(cyclic, index: [1: cyclic]) == cyclic.path, "cycle safely terminates")
        let registrationsText = """
        Records for UID 501 : account
        #1:
            Name: My App
            Type: app (0x2)
            Identifier: app.owner
            URL: file:///Applications/My%20App.app/
        #2:
            Name: Helper
            Type: login item (0x10)
            Disposition: [enabled, disallowed, notified]
            Identifier: helper
            Parent Identifier: app.owner
            URL: Contents/Library/LoginItems/Helper.app
            Executable Path: Contents/MacOS/Helper
        #3:
            Name: Unknown
            Type: agent (0x8)
            Disposition: [disabled, allowed]
            Identifier: unknown
            Parent Identifier: app.owner
            URL: Contents/Library/LaunchAgents/unknown.plist
            Executable Path: Contents/MacOS/Unknown
        #4:
            Name: Escape
            Type: agent (0x8)
            Identifier: escape
            Parent Identifier: app.owner
            URL: ../Other.app
        Records for UID 502 : other-account
        #1:
            Name: Other Private Item
            Type: login item (0x10)
            Identifier: other-account-item
            URL: /Applications/Other.app
        Records for UID -2 : shared
        #1:
            Name: Shared
            Type: legacy daemon (0x10010)
            Disposition: [enabled, allowed]
            Identifier: shared
            URL: /Library/LaunchDaemons/shared.plist
            Executable Path: /Library/Shared Tool/run
        """
        let registrations = BackgroundActivity.parseRegistrations(registrationsText, uid: 501)
        check(registrations.count == 4, "app grouping and other accounts excluded")
        let helper = registrations.first { $0.identifier == "helper" }!
        check(helper.owner == "/Applications/My App.app", "percent encoded parent ownership")
        check(helper.path == "/Applications/My App.app/Contents/Library/LoginItems/Helper.app", "relative login item URL")
        check(helper.executable == "/Applications/My App.app/Contents/Library/LoginItems/Helper.app/Contents/MacOS/Helper", "relative executable resolves within helper bundle")
        check(!helper.isAllowed && helper.isEnabled, "disallowed not mistaken for allowed")
        check(helper.permissionLabel == "Background permission off", "permission label")
        let unknown = registrations.first { $0.identifier == "unknown" }!
        check(unknown.executable == nil, "ambiguous relative executable is unknown")
        check(!unknown.isEnabled && unknown.isAllowed, "disabled distinct from permission")
        check(registrations.first { $0.identifier == "escape" }?.path == nil, "relative traversal rejected")
        check(registrations.first { $0.identifier == "shared" }?.executable == "/Library/Shared Tool/run", "shared absolute executable preserved")
        check(BackgroundActivity.advice(name: "AnyDesk", path: "/Applications/AnyDesk.app", widget: false, isSystem: false, isOpen: false).contains("unattended"), "remote access consequence explained")
        check(BackgroundActivity.advice(name: "Word", path: "/Applications/Word.app", widget: true, isSystem: false, isOpen: false).contains("Edit Widgets"), "widget review keeps owning app")
        check(BackgroundActivity.advice(name: "ExpressVPN", path: "/Applications/ExpressVPN.app", widget: false, isSystem: false, isOpen: false).contains("current connection"), "VPN preserved")
        check(registrations.first { $0.identifier == "escape" }?.permissionLabel == "Permission unknown", "missing disposition never claims disabled")
        check(BackgroundActivity.isSystemPath("/usr/lib/swift/worker"), "system libraries classified")
        let group = ActivityApp(id: "test", name: "Test", path: "test", processes: Array(processes.prefix(2)), isOpen: false, isSystem: false, diskBytes: nil, advice: "")
        check(group.memoryBytes == 3_145_728 && group.diskBytes == nil, "group RSS measured and unknown disk never fabricated")

        let widgetRows = BackgroundWidgetControl.pluginRows("""
        - com.microsoft.Word.widgetextension(16.1)\tUUID\tdate\t/Applications/Microsoft Word.app/Contents/PlugIns/WordWidget_mac.appex
          com.example.default(1.0)\tUUID\tdate\t/Applications/Space App.app/Contents/PlugIns/Widget.appex
        + com.example.used(1.0)\tUUID\tdate\t/Applications/Used.app/Contents/PlugIns/Used.appex
        ? com.example.unknown(1.0)\tUUID\tdate\t/Applications/Unknown.app/Contents/PlugIns/Unknown.appex
          com.example.not-widget(1.0)\tUUID\tdate\t/Applications/Other.app
          invalid line
        """)
        check(widgetRows.count == 4, "plugin row parsing with spaces and invalid rows")
        check(widgetRows[0].election == "ignore" && widgetRows[1].election == "default" && widgetRows[2].election == "use" && widgetRows[3].election == "unknown", "widget elections distinguished")
        let widget = ActivityWidget(identifier: "com.vendor.widget", name: "Widget", path: "/Applications/Example.app/Contents/PlugIns/Widget.appex", executable: "/Applications/Example.app/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget", appPath: "/Applications/Example.app", election: "default")
        var reviewSnapshot = ActivitySnapshot()
        reviewSnapshot.processReadingAvailable = true
        reviewSnapshot.widgets = [widget]
        let widgetID = "widget|" + widget.identifier
        var review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.verdict == .review, "widget optional until usage answered")
        check(review.first?.appPath == nil && review.first?.widget == widget, "widget never recommends uninstalling owning app")
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [widgetID: .unused])
        check(review.first?.verdict == .unused, "unused widget recommendation uses recorded choice")
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [widgetID: .needed])
        check(review.first?.verdict == .keep, "needed widget kept")
        reviewSnapshot.processReadingAvailable = false
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.memoryBytes == nil, "unavailable process reading never claims zero memory")
        reviewSnapshot.widgets = [ActivityWidget(identifier: widget.identifier, name: widget.name, path: widget.path, executable: widget.executable, appPath: widget.appPath, election: "ignore")]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [widgetID: .unused])
        check(review.first?.verdict == .keep && review.first?.reason.contains("already disabled") == true, "disabled widgets not proposed as new savings")
        func reviewApp(_ path: String, open: Bool = false, memory: Int64 = 8_000_000_000, cpu: Double = 500) -> ActivityApp {
            ActivityApp(id: path, name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, path: path,
                        processes: [ActivityProcess(pid: 1001, parent: 1, uid: 501, cpu: cpu, residentBytes: memory, path: path + "/Contents/MacOS/main")], isOpen: open, isSystem: false, diskBytes: nil, advice: "")
        }
        reviewSnapshot = ActivitySnapshot(); reviewSnapshot.processReadingAvailable = true
        reviewSnapshot.apps = [reviewApp("/Applications/Unknown.app")]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.verdict == .unknown, "high RAM CPU alone never proves unnecessary")
        reviewSnapshot.apps = [reviewApp("/Applications/ChatGPT.app", open: true)]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.verdict == .keep, "active work kept absent usage decision")
        for path in ["/Applications/ExpressVPN.app", "/Applications/shecan-desktop.app", "/nix/store/shared", "/Applications/MLX.app"] {
            reviewSnapshot.apps = [reviewApp(path)]
            review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: ["app|" + path: .unused])
            check(review.first?.verdict == .keep && review.first?.protected == true, "protected dependency overrides unused choice")
        }
        reviewSnapshot.apps = [reviewApp("/Applications/GoogleUpdater.app")]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.verdict == .keep && review.first?.consequence.contains("unpatched") == true, "updater benefit explained")
        reviewSnapshot.apps = [reviewApp("/Applications/AnyDesk.app")]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.verdict == .review && review.first?.question?.contains("occasional") == true, "whole app use asked before app uninstall")
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: ["app|/Applications/AnyDesk.app": .unused])
        check(review.first?.verdict == .unused && review.first?.appPath == "/Applications/AnyDesk.app", "unused app links to targeted uninstaller review")
        reviewSnapshot.apps = [reviewApp("unknown-helper")]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: ["app|unknown-helper": .unused])
        check(review.first?.verdict == .unknown && review.first?.appPath == nil, "unresolved identity not offered app removal")
        reviewSnapshot.apps = []
        reviewSnapshot.installedApps = [ActivityInstalledApp(path: "/Applications/Bookbind.app", name: "Bookbind", diskBytes: 1000)]
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [], choices: [:])
        check(review.first?.verdict == .review && review.first?.reason.contains("overlaps") == true, "retired standalone overlap reviewed")
        reviewSnapshot = ActivitySnapshot()
        review = BackgroundReview.recommendations(snapshot: reviewSnapshot, startup: [missing, existing, personal, vpn], choices: ["startup|" + personal.id: .unused])
        check(review.first { $0.id == "startup|" + missing.id }?.verdict == .leftover, "missing target is likely leftover, not proven safe deletion")
        check(review.first { $0.id == "startup|" + personal.id }?.verdict == .keep, "personal startup preserved")
        check(review.first { $0.id == "startup|" + vpn.id }?.verdict == .keep, "VPN startup preserved")
        check(review.first { $0.id == "startup|" + existing.id }?.verdict != .leftover, "working startup not called leftover")
        let encodedChoices = try JSONEncoder().encode([widgetID: BackgroundUse.unused])
        let decodedChoices = try JSONDecoder().decode([String: BackgroundUse].self, from: encodedChoices)
        check(decodedChoices[widgetID] == .unused, "usage choices can round-trip locally")
        let fakeWidgetBundle = root.appendingPathComponent("Test.app/Contents/PlugIns/Widget.appex")
        try fm.createDirectory(at: fakeWidgetBundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let widgetInfo: [String: Any] = ["CFBundleIdentifier": "com.example.widget", "CFBundleExecutable": "Widget", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"]]
        try PropertyListSerialization.data(fromPropertyList: widgetInfo, format: .xml, options: 0).write(to: fakeWidgetBundle.appendingPathComponent("Contents/Info.plist"))
        let inspectedWidget = BackgroundWidgetControl.inspect(identifier: "com.example.widget", path: fakeWidgetBundle.path, election: "default")!
        check(!BackgroundWidgetControl.eligible(inspectedWidget), "widgets outside supported app roots cannot be changed")
        do { _ = try await BackgroundWidgetControl.shared.setElection("ignore", for: inspectedWidget); fatalError("unsupported widget changed") } catch { assertions += 1 }
        check(BackgroundWidgetControl.inspect(identifier: "com.other.widget", path: fakeWidgetBundle.path, election: "default") == nil, "widget identity revalidated")
        var wrongExtension = widgetInfo; wrongExtension["NSExtension"] = ["NSExtensionPointIdentifier": "com.apple.share-services"]
        try PropertyListSerialization.data(fromPropertyList: wrongExtension, format: .xml, options: 0).write(to: fakeWidgetBundle.appendingPathComponent("Contents/Info.plist"))
        check(BackgroundWidgetControl.inspect(identifier: "com.example.widget", path: fakeWidgetBundle.path, election: "default") == nil, "non-widget extension cannot be paused")

        reviewSnapshot.widgets = [widget]
        let reviewSummary = BackgroundReview.summary(snapshot: reviewSnapshot, choices: [:], limit: 1)
        check(reviewSummary.contains("This review has changed no apps or settings"), "offline review never claims cleanup occurred")
        check(reviewSummary.contains("Unknown items are not proven unnecessary"), "offline summary keeps uncertainty")
        check(BackgroundReview.summary(snapshot: reviewSnapshot, choices: [:], limit: -2).contains("Showing 0"), "summary limits bounded safely")
        var unverifiedSnapshot = ActivitySnapshot()
        unverifiedSnapshot.apps = [ActivityApp(id: "/Applications/Example.app", name: "Example", path: "/Applications/Example.app", processes: [ActivityProcess(pid: 44, parent: 1, uid: 501, cpu: 0, residentBytes: 1000, path: "/Applications/Example.app/Contents/PlugIns/ExampleWidget.appex/Contents/MacOS/Widget")], isOpen: false, isSystem: false, diskBytes: nil, advice: "")]
        let unverifiedReview = BackgroundReview.recommendations(snapshot: unverifiedSnapshot, startup: [], choices: ["app|/Applications/Example.app": .unused])
        check(unverifiedReview.first?.verdict == .unknown && unverifiedReview.first?.appPath == nil && unverifiedReview.first?.question == nil, "unverified widget cannot become owning-app uninstall recommendation")
        unverifiedSnapshot.apps = [reviewApp("/Library/Application Support/Vendor/Helper.app")]
        let helperReview = BackgroundReview.recommendations(snapshot: unverifiedSnapshot, startup: [], choices: ["app|/Library/Application Support/Vendor/Helper.app": .unused])
        check(helperReview.first?.appPath == nil, "support helper does not become installed app uninstall target")
        var versionsSnapshot = ActivitySnapshot()
        versionsSnapshot.widgets = [widget, ActivityWidget(identifier: widget.identifier, name: widget.name, path: widget.path.replacingOccurrences(of: "Example.app", with: "Example 2.app"), executable: widget.executable.replacingOccurrences(of: "Example.app", with: "Example 2.app"), appPath: "/Applications/Example 2.app", election: "default")]
        let versionsReview = BackgroundReview.recommendations(snapshot: versionsSnapshot, startup: [], choices: [widgetID: .unused])
        check(versionsReview.count == 2 && Set(versionsReview.map(\.rowID)).count == 2, "multiple registered versions have unique UI row identities")
        check(versionsReview.allSatisfy { $0.verdict == .unused }, "one feature-use answer applies to all widget versions")
        let address = URL(string: CommandLine.arguments[1])!
        let ping = try await ExpressVPNMCP(endpoint: address).call("expressvpn_ping")
        check(ping == "pong", "MCP handshake and read tool")
        let status = try await ExpressVPNMCP(endpoint: address).call("expressvpn_status")
        check(status == "Connected", "SSE tool response")
        let connect = try await ExpressVPNMCP(endpoint: address).call("expressvpn_connect", value: "test-only-region")
        check(connect == "accepted", "schema-directed mock mutation")
        do { _ = try await ExpressVPNMCP(endpoint: address).call("expressvpn_set_networklock"); fatalError("unapproved tool accepted") } catch { assertions += 1 }
        do { _ = try await ExpressVPNMCP(endpoint: address).call("expressvpn_disconnect"); fatalError("tool failure accepted") }
        catch { check(!error.localizedDescription.contains("SECRET"), "tool error redacted") }
        print("Background audit and MCP tests passed: \(assertions) assertions. Fixtures: \(root.path)")
    }
}
