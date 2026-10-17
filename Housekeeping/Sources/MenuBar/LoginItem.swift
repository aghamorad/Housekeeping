// Housekeeping — opening at login
//
// macOS has one right answer for this, `SMAppService`, and it is what the toggle
// tries first. It is not always available: an ad-hoc signed build is not the same
// app from one compile to the next, and the system will refuse to remember it as a
// login item. So there is a second road — a launch agent in the user's own
// `LaunchAgents` folder, which needs no special signing and is still the user's to
// delete. Whichever road is taken, the box stays ticked, because the promise the
// reader made is "open at login", not "use a particular API".

import Foundation
import ServiceManagement

@MainActor
final class LoginItem: NSObject, ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var problem: String?

    private static let label = "com.housekeeping.app"
    private let agentPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    private override init() {
        super.init()
        refresh()
    }

    /// Reads the truth rather than trusting what was last set: the reader can turn
    /// a login item off in System Settings without this app being told.
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            enabled = true
            needsApproval = false
        case .requiresApproval:
            // Registered, but macOS will not act on it until the reader allows it.
            // The box stays ticked; the panel says what is missing.
            enabled = true
            needsApproval = true
        default:
            enabled = agentExists
            needsApproval = false
        }
    }

    func setEnabled(_ wanted: Bool) {
        problem = nil
        guard wanted != enabled else {
            refresh()
            return
        }

        if wanted {
            if registerWithSystem() {
                removeAgent()
            } else if writeAgent() {
                needsApproval = false
            } else {
                problem = "macOS would not add Housekeeping to your login items."
                refresh()
                return
            }
        } else {
            try? SMAppService.mainApp.unregister()
            removeAgent()
        }

        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Roads

    private func registerWithSystem() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            return false
        }
    }

    private var agentExists: Bool {
        FileManager.default.fileExists(atPath: agentPath.path)
    }

    private func writeAgent() -> Bool {
        let contents: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        do {
            try FileManager.default.createDirectory(
                at: agentPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: contents,
                format: .xml,
                options: 0
            )
            try data.write(to: agentPath, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func removeAgent() {
        guard agentExists else { return }
        try? FileManager.default.removeItem(at: agentPath)
    }
}
