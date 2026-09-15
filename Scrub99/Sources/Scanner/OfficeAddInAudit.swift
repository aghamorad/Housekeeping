import AppKit
import Foundation

/// Finds the residue Microsoft Office leaves behind when one of its add-ins is
/// taken off the disk without Office being told. That is a specific shape of
/// mess, and it is not the shape the rest of the scanner looks for: the files
/// are a few hundred bytes each, so no size floor finds them, and the folders
/// they sit in belong to an application that is very much still installed, so
/// the residue rule passes over them. It has to be looked for directly.
///
/// Two defects are looked for, and they are the two halves of the same incident:
///
/// * A companion file Office writes beside an add-in while it has it open, and
///   deletes when it closes. One still sitting there long after the application
///   last ran is leftover from a session that ended badly.
/// * An add-in path held in one of the Office applications' own settings, where
///   the file it names is gone. This is the one that keeps an application
///   complaining on every launch after the file itself was removed, and it is
///   the whole reason removing the file is not the whole fix.
///
/// Nothing here is guessed at from a file's name. The first is read off the
/// folder the file sits in, the second is read out of the settings file that
/// carries it, so an entry is reported only when Office itself still points at
/// it.
struct OfficeAddInAudit {
    enum Kind: Equatable {
        /// A `~$…` companion file in a startup folder whose application is not
        /// running, so nothing is using it.
        case staleCompanionFile
        /// A path held in an Office application's settings whose file is gone.
        case danglingRegistration
    }

    /// An add-in that one of the Office applications still names but that is no
    /// longer on the disk.
    struct Registration: Equatable {
        /// The path exactly as Office holds it.
        let namedPath: String
        /// The setting that decides whether the application acts on the entry,
        /// when one could be identified in the same part of the settings file.
        let switchName: String?
        /// What that setting is set to. Nil means the switch could not be found,
        /// which is said rather than guessed at — an entry with no visible switch
        /// and an entry that is switched off look identical from the outside and
        /// are not the same thing at all.
        let isSwitchedOn: Bool?
    }

    struct Finding: Equatable {
        let url: URL
        let kind: Kind
        let applicationName: String
        let bundleIdentifier: String
        /// For a dangling registration, the add-ins the settings still name.
        let registrations: [Registration]
        let reason: String
        let explanation: String
    }

    struct Outcome: Equatable {
        var findings: [Finding] = []
        /// Applications whose settings file exists but could not be read, so the
        /// audit could not answer for them either way.
        var unreadableSettings: [String] = []
        /// Applications that were running during the scan, so their companion
        /// files were left alone rather than judged.
        var applicationsRunning: [String] = []
        /// True when Office's shared folder exists but nothing inside it could be
        /// listed. An empty result then means "not looked at", not "clean".
        var startupFoldersUnreadable = false
        /// False when Office is not on this Mac at all, which is the one case
        /// where an empty result needs no explaining.
        var sharedFolderPresent = false
        /// How many Office startup folders were located and read. Zero while the
        /// shared folder is present means the folders were not where Scrub 99
        /// looked for them, which is worth saying rather than reporting nothing.
        var startupFoldersRead = 0
    }

    private struct OfficeApplication {
        let name: String
        let bundleIdentifier: String
        let startupFolderName: String
    }

    private static let officeApplications: [OfficeApplication] = [
        OfficeApplication(
            name: "Microsoft Word",
            bundleIdentifier: "com.microsoft.Word",
            startupFolderName: "Word"
        ),
        OfficeApplication(
            name: "Microsoft Excel",
            bundleIdentifier: "com.microsoft.Excel",
            startupFolderName: "Excel"
        ),
        OfficeApplication(
            name: "Microsoft PowerPoint",
            bundleIdentifier: "com.microsoft.Powerpoint",
            startupFolderName: "PowerPoint"
        )
    ]

    /// The folder Office's applications share. It is named by a fixed
    /// identifier Microsoft assigns to the Office team, which is the same on
    /// every Mac.
    static let sharedFolderRelativePath = "Library/Group Containers/UBF8T346G9.Office"

    /// Office names these two folders with a language suffix on most
    /// installations and without one on others. Both spellings are probed rather
    /// than one being assumed, because assuming the wrong one reads as "no
    /// add-ins here" rather than as an error.
    private static let startupFolderSpellings: [(content: String, startup: String)] = [
        ("User Content.localized", "Startup.localized"),
        ("User Content", "Startup")
    ]

    /// The extensions an Office add-in uses. Recognising the file by extension
    /// is what keeps this audit from reporting every path a settings file
    /// happens to mention — a settings file mentions window positions and recent
    /// documents too, and none of those are add-ins.
    private static let addInExtensions: Set<String> = ["dotm", "dot", "xlam", "xla", "ppam", "ppa"]

    /// The switches the Office applications use to decide whether to act on a
    /// registered add-in. Excel uses the first and PowerPoint the second; the
    /// pair is checked rather than one being assumed per application, because a
    /// wrong guess here would turn a switched-off leftover into a warning it is
    /// not.
    private static let switchNames = ["installed", "registered"]

    let homeDirectory: URL
    let fileManager: FileManager

    init(homeDirectory: URL, fileManager: FileManager = .default) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func run() -> Outcome {
        var outcome = Outcome()
        let sharedFolder = homeDirectory
            .appendingPathComponent(Self.sharedFolderRelativePath, isDirectory: true)
            .standardizedFileURL

        // No shared folder means Office is not on this Mac. That is not a
        // finding and not a failure, so the audit stops here without saying
        // anything about it.
        guard fileManager.fileExists(atPath: sharedFolder.path) else { return outcome }
        outcome.sharedFolderPresent = true

        var seenPaths: Set<String> = []

        for application in Self.officeApplications {
            if let folder = existingStartupFolder(for: application, under: sharedFolder) {
                appendCompanionFiles(in: folder, for: application, seenPaths: &seenPaths, to: &outcome)
            }
            appendDanglingRegistrations(for: application, seenPaths: &seenPaths, to: &outcome)
        }

        return outcome
    }

    // MARK: - Startup folders

    private func existingStartupFolder(for application: OfficeApplication, under sharedFolder: URL) -> URL? {
        for spelling in Self.startupFolderSpellings {
            let folder = sharedFolder
                .appendingPathComponent(spelling.content, isDirectory: true)
                .appendingPathComponent(spelling.startup, isDirectory: true)
                .appendingPathComponent(application.startupFolderName, isDirectory: true)
                .standardizedFileURL
            if fileManager.fileExists(atPath: folder.path) { return folder }
        }
        return nil
    }

    /// Companion files are only judged when their application is closed. `~$`
    /// beside an add-in means Word has it open right now; the same file beside
    /// an add-in Word has not touched in three years means something else
    /// entirely, and only the running/not-running distinction separates them.
    private func appendCompanionFiles(
        in folder: URL,
        for application: OfficeApplication,
        seenPaths: inout Set<String>,
        to outcome: inout Outcome
    ) {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            outcome.startupFoldersUnreadable = true
            return
        }
        outcome.startupFoldersRead += 1

        guard !Self.isRunning(application) else {
            outcome.applicationsRunning.append(application.name)
            return
        }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard entry.lastPathComponent.hasPrefix("~$") else { continue }
            let normalized = entry.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { continue }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }

            outcome.findings.append(Finding(
                url: normalized,
                kind: .staleCompanionFile,
                applicationName: application.name,
                bundleIdentifier: application.bundleIdentifier,
                registrations: [],
                reason: "\(application.name) left this companion file behind in its startup folder",
                explanation: Self.companionFileExplanation(applicationName: application.name)
            ))
        }
    }

    private static func companionFileExplanation(applicationName: String) -> String {
        let shortName = applicationName.replacingOccurrences(of: "Microsoft ", with: "")
        return """
        \(shortName) writes a small companion file like this beside a document or add-in while it \
        has that file open, and deletes it again when it closes. \(shortName) is not running now, so \
        this one was left over from a session that ended without tidying up — a crash or a force-quit \
        leaves one behind for good. It holds no part of the add-in it sat beside, only the name of the \
        account that had it open. Removing it is reversible, so nothing is lost by trying.
        """
    }

    // MARK: - Registered add-ins

    private func appendDanglingRegistrations(
        for application: OfficeApplication,
        seenPaths: inout Set<String>,
        to outcome: inout Outcome
    ) {
        for settingsURL in settingFileCandidates(for: application) {
            guard fileManager.fileExists(atPath: settingsURL.path) else { continue }

            guard let data = fileManager.contents(atPath: settingsURL.path) else {
                outcome.unreadableSettings.append(application.name)
                continue
            }
            guard let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) else { continue }

            let registrations = danglingRegistrations(in: plist)
            guard !registrations.isEmpty else { continue }

            let normalized = settingsURL.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { continue }

            outcome.findings.append(Finding(
                url: normalized,
                kind: .danglingRegistration,
                applicationName: application.name,
                bundleIdentifier: application.bundleIdentifier,
                registrations: registrations,
                reason: Self.registrationReason(
                    applicationName: application.name,
                    registrations: registrations
                ),
                explanation: Self.registrationExplanation(
                    applicationName: application.name,
                    registrations: registrations
                )
            ))
        }
    }

    /// Where an Office application keeps its settings on a modern Mac.
    ///
    /// The filename is deliberately not guessed at. Which of an application's
    /// settings files holds its add-in list is not documented anywhere, and a
    /// wrong guess does not look like a wrong guess — it looks like a clean Mac.
    /// So the applications' own settings folders are read and every settings file
    /// in them is examined. What is looked for inside is narrow enough that the
    /// cost of reading a few extra files is small next to the cost of reading the
    /// wrong one.
    private func settingFileCandidates(for application: OfficeApplication) -> [URL] {
        let identifier = application.bundleIdentifier
        var candidates: [URL] = []

        // Inside its own sandbox container every settings file belongs to this
        // application, so all of them are read.
        candidates += plists(in: "Library/Containers/\(identifier)/Data/Library/Preferences") { _ in true }

        // Office's shared container is Microsoft's rather than this
        // application's, so there only the files named after this application
        // are read.
        candidates += plists(in: "\(Self.sharedFolderRelativePath)/Library/Preferences") {
            $0.hasPrefix(identifier)
        }

        // The shared preferences folder holds every application on the Mac, so
        // there the one file named after this application is the only one read.
        candidates.append(
            homeDirectory
                .appendingPathComponent("Library/Preferences/\(identifier).plist")
                .standardizedFileURL
        )

        return candidates
    }

    /// Settings files in one folder, in name order. Shortcuts and nested folders
    /// are left out: a shortcut here points at a settings file belonging to
    /// somebody else, and reading through it would attribute another
    /// application's contents to this one.
    private func plists(in relativePath: String, isOwned: (String) -> Bool) -> [URL] {
        let folder = homeDirectory.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else { return [] }

        return entries
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter { entry in
                guard entry.pathExtension.lowercased() == "plist", isOwned(entry.lastPathComponent) else {
                    return false
                }
                let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                return values?.isDirectory != true && values?.isSymbolicLink != true
            }
            .map { $0.standardizedFileURL }
    }

    /// Walks the settings file for paths that end in an add-in extension and no
    /// longer exist on the disk. Anything else in the file is left alone: a
    /// settings file also names recent documents, template folders, and window
    /// positions, and reporting those as missing add-ins would be worse than
    /// reporting nothing.
    private func danglingRegistrations(in plist: Any) -> [Registration] {
        var found: [Registration] = []
        Self.walk(plist, inheritedSwitchName: nil, inheritedSwitchState: nil, into: &found)

        var best: [String: Registration] = [:]
        var order: [String] = []
        for registration in found {
            guard !fileManager.fileExists(atPath: registration.namedPath) else { continue }
            guard let existing = best[registration.namedPath] else {
                best[registration.namedPath] = registration
                order.append(registration.namedPath)
                continue
            }
            // The same path can appear more than once. The entry that came with a
            // visible switch is the one that says whether the application will
            // act on it, so it wins over one that did not.
            if existing.isSwitchedOn == nil, registration.isSwitchedOn != nil {
                best[registration.namedPath] = registration
            }
        }
        return order.compactMap { best[$0] }
    }

    private static func walk(
        _ node: Any,
        inheritedSwitchName: String?,
        inheritedSwitchState: Bool?,
        into found: inout [Registration]
    ) {
        if let dictionary = node as? [String: Any] {
            let switchName = switchName(in: dictionary) ?? inheritedSwitchName
            let switchState = switchState(in: dictionary) ?? inheritedSwitchState

            for key in dictionary.keys.sorted() {
                if let path = addInPath(in: key) {
                    found.append(Registration(
                        namedPath: path,
                        switchName: switchName,
                        isSwitchedOn: switchState
                    ))
                }
                if let value = dictionary[key] {
                    walk(value, inheritedSwitchName: switchName, inheritedSwitchState: switchState, into: &found)
                }
            }
            return
        }

        if let array = node as? [Any] {
            for element in array {
                walk(element, inheritedSwitchName: inheritedSwitchName, inheritedSwitchState: inheritedSwitchState, into: &found)
            }
            return
        }

        if let path = addInPath(in: node) {
            found.append(Registration(
                namedPath: path,
                switchName: inheritedSwitchName,
                isSwitchedOn: inheritedSwitchState
            ))
        }
    }

    /// A path only counts when it is absolute — Office can hold a relative one,
    /// and resolving that against the wrong folder would invent a finding.
    private static func addInPath(in value: Any) -> String? {
        guard let string = value as? String, string.hasPrefix("/") else { return nil }
        let ext = (string as NSString).pathExtension.lowercased()
        guard addInExtensions.contains(ext) else { return nil }
        return string
    }

    private static func switchName(in dictionary: [String: Any]) -> String? {
        switchNames.first { dictionary[$0] != nil }
    }

    private static func switchState(in dictionary: [String: Any]) -> Bool? {
        for name in switchNames {
            if let value = dictionary[name] as? Bool { return value }
            if let value = dictionary[name] as? Int { return value != 0 }
        }
        return nil
    }

    // MARK: - Copy

    private static func registrationReason(applicationName: String, registrations: [Registration]) -> String {
        let shortName = applicationName.replacingOccurrences(of: "Microsoft ", with: "")
        if registrations.count == 1 {
            return "\(shortName) still lists an add-in whose file is gone"
        }
        return "\(shortName) still lists \(registrations.count) add-ins whose files are gone"
    }

    private static func registrationExplanation(applicationName: String, registrations: [Registration]) -> String {
        let shortName = applicationName.replacingOccurrences(of: "Microsoft ", with: "")
        let names = registrations.map { ($0.namedPath as NSString).lastPathComponent }

        let named = names.joined(separator: ", ")
        let listed = names.count == 1
            ? "The list still names \(named), and that file is not on the disk."
            : "The list still names \(named), and none of those files are on the disk."

        var sentences = [
            "Office keeps its own list of add-ins inside this settings file, separately from the add-in files themselves. \(listed) This is what is left after an add-in is removed from the disk without being removed from the list."
        ]

        let switchedOn = registrations.filter { $0.isSwitchedOn == true }
        let switchedOff = registrations.filter { $0.isSwitchedOn == false }
        let unknown = registrations.filter { $0.isSwitchedOn == nil }

        if !switchedOn.isEmpty {
            sentences.append(
                "\(shortName) has \(switchedOn.count == 1 ? "this entry" : "these entries") switched on — the setting is called \(switchDescription(switchedOn)) — so \(shortName) will go looking for the file every time it starts and report it missing until the entry itself is cleared. Clearing it is a step inside \(shortName)'s own add-in list, and not something Scrub 99 can do for you."
            )
            sentences.append(
                "Moving this settings file to the quarantine folder does clear the entry, but it takes every other \(shortName) setting with it, which is a heavier fix than the problem calls for. It is reversible either way."
            )
        }

        if !switchedOff.isEmpty {
            sentences.append(
                "\(switchedOff.count == 1 ? "The other entry is" : "\(switchedOff.count) further entries are") switched off, so \(shortName) will not complain about \(switchedOff.count == 1 ? "it" : "them"). A switched-off entry is dormant rather than broken and needs nothing done to it."
            )
        }

        if !unknown.isEmpty {
            sentences.append(
                "For \(unknown.count == 1 ? "one entry" : "\(unknown.count) entries") Scrub 99 could not find the setting that switches it on or off in this file, so it cannot say whether \(shortName) will complain about \(unknown.count == 1 ? "it" : "them")."
            )
        }

        return sentences.joined(separator: " ")
    }

    private static func switchDescription(_ registrations: [Registration]) -> String {
        let names = Set(registrations.compactMap(\.switchName)).sorted()
        if names.count == 1, let name = names.first { return "“\(name)”" }
        return names.map { "“\($0)”" }.joined(separator: " or ")
    }

    // MARK: - Running applications

    private static func isRunning(_ application: OfficeApplication) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier).isEmpty
    }
}
