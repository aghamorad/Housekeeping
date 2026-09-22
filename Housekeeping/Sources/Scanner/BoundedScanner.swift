import AppKit
import Foundation

/// Scans roots described by the rule database, plus a sweep of the places where
/// large undeclared data accumulates. The rule database can only describe what
/// someone thought to write down, so the sweep exists to measure and report the
/// rest rather than silently skipping it. A scan produces an inventory and never
/// mutates the filesystem.
final class Scanner {
    /// Undeclared paths below this size are measured but not reported. Reporting
    /// every stray 2 MB folder would bury the handful of folders that actually
    /// account for the disk.
    static let minimumUndeclaredSize: Int64 = 50_000_000

    private(set) var foundItems: [FoundItem] = []
    private(set) var scanNotes: [ScanResults.ScanNote] = []
    private(set) var scannedPaths: [URL] = []

    /// Paths Housekeeping could not read at all, and files it could not measure inside
    /// folders it did list. Kept as tallies rather than a note per path: a sandboxed
    /// Library yields hundreds of permission failures, and one note each would fill
    /// the results screen with the noise and push the findings off it.
    private var unreadableLocationCount = 0
    private var unmeasuredFileCount = 0

    /// How many entries the sandbox-container root holds, counted before the
    /// ownership test discards the ones that belong to installed applications.
    /// The summary needs the total to explain what is missing from the list.
    private var containerEntryCount = 0

    /// Notes produced while building targets rather than while scanning them.
    /// Held here so they can be appended in the order the results screen shows,
    /// which is not the order the targets are built in.
    private var officeAddInNotes: [ScanResults.ScanNote] = []

    private let applications: [ApplicationRule]
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let deepSweep: Bool

    init(
        applications: [ApplicationRule],
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        deepSweep: Bool = true
    ) {
        self.applications = applications
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.deepSweep = deepSweep
    }

    func scan(progressHandler: @escaping (ScanProgress) -> Void) async throws -> ScanResults {
        foundItems = []
        scanNotes = []
        scannedPaths = []
        unreadableLocationCount = 0
        unmeasuredFileCount = 0
        containerEntryCount = 0
        officeAddInNotes = []
        let startDate = Date()

        guard !applications.isEmpty else {
            throw ScanError.rulesUnavailable
        }

        progressHandler(.phase("Detecting installed applications..."))
        let installedApplicationNames = detectInstalledApplicationNames()
        let rootTargets = buildTargets(installedApplicationNames: installedApplicationNames)
        let targets = dedupeInventory(expandInventoryTargets(rootTargets))
        progressHandler(.phase(deepSweep
            ? "Auditing \(targets.count) storage locations, including undeclared ones..."
            : "Auditing \(targets.count) known storage locations..."))

        var undeclaredCount = 0
        var undeclaredSize: Int64 = 0
        var suppressedCount = 0
        var suppressedSize: Int64 = 0
        var flooredCount = 0
        var flooredSize: Int64 = 0

        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            scannedPaths.append(target.url)
            progressHandler(.pathProgress(
                path: target.url.abbreviatingWithTilde(homeDirectory: homeDirectory),
                current: index + 1,
                total: targets.count
            ))

            guard fileManager.fileExists(atPath: target.url.path) else { continue }
            guard let item = try await inspect(target) else { continue }

            if (target.isUndeclared || target.isSizeFloored) && item.size < Self.minimumUndeclaredSize {
                // Only swept paths are counted as swept paths. A floored
                // container is a finding that did not clear the bar, not an
                // undeclared folder, and the note below says which it is.
                if target.isUndeclared {
                    suppressedCount += 1
                    suppressedSize += item.size
                } else {
                    flooredCount += 1
                    flooredSize += item.size
                }
                continue
            }
            if target.isUndeclared {
                undeclaredCount += 1
                undeclaredSize += item.size
            }
            foundItems.append(item)
        }

        if deepSweep {
            scanNotes.append(.init(
                phase: "Sweep",
                message: undeclaredCount == 0
                    ? "No undeclared folder over \(Self.minimumUndeclaredSize.humanReadable) was found outside the rule database."
                    : "Found \(undeclaredCount) folders totaling \(undeclaredSize.humanReadable) that no rule in Housekeeping's database describes."
            ))
            if suppressedCount > 0 {
                scanNotes.append(.init(
                    phase: "Sweep",
                    message: "\(suppressedCount) undeclared folders under \(Self.minimumUndeclaredSize.humanReadable) (\(suppressedSize.humanReadable) combined) were measured but left out of the list to keep it readable."
                ))
            }
        }

        // The container audit runs on every scan, not only the deep one, so
        // this note sits outside the sweep block. Without it the list would
        // show one container and silently omit the thousand beside it.
        if containerEntryCount > 0 {
            scanNotes.append(.init(
                phase: "Containers",
                message: "\(containerEntryCount) sandbox containers were found. macOS gives each application its own container, and most belong to an application that is still installed, or to macOS itself, so they are not residue. \(flooredCount) belong to nothing installed but are under \(Self.minimumUndeclaredSize.humanReadable) each (\(flooredSize.humanReadable) combined), so they were measured and left out of the list."
            ))
        }

        // Built while the targets were, because the add-in folders are read
        // before the scan loop runs. Appended here so the results screen still
        // shows them in the order the scan happened.
        scanNotes.append(contentsOf: officeAddInNotes)

        if unreadableLocationCount > 0 {
            scanNotes.append(.cautionPhase(
                unreadableLocationCount == 1
                    ? "1 location could not be read, so it is missing from this list. macOS protects it from Housekeeping — usually because another app owns it."
                    : "\(unreadableLocationCount) locations could not be read, so they are missing from this list. macOS protects them from Housekeeping — usually because another app owns them."
            ))
        }

        if unmeasuredFileCount > 0 {
            scanNotes.append(.cautionPhase(
                unmeasuredFileCount == 1
                    ? "1 file inside a listed folder could not be measured, so that folder's size reads low."
                    : "\(unmeasuredFileCount) files inside listed folders could not be measured, so some sizes read low."
            ))
        }

        foundItems.sort {
            if $0.primaryApplication?.name == $1.primaryApplication?.name {
                return $0.path.path < $1.path.path
            }
            return ($0.primaryApplication?.name ?? "") < ($1.primaryApplication?.name ?? "")
        }

        let summary = buildSummary()
        let duration = Date().timeIntervalSince(startDate)
        scanNotes.append(.init(
            phase: "Found",
            message: "\(foundItems.count) locations totaling \(summary.totalSize.humanReadable)"
        ))

        let results = ScanResults(
            scannedPaths: scannedPaths,
            foundItems: foundItems,
            summary: summary,
            scanDuration: duration,
            scanNotes: scanNotes
        )
        progressHandler(.complete(results))
        return results
    }

    private struct ScanTarget {
        let url: URL
        let knownPath: KnownPath
        let rule: ApplicationRule
        let app: ApplicationRef
        let association: Association
        let isInventoryChild: Bool
        /// True only for paths discovered by the undeclared-path sweep, which are
        /// subject to the size floor and are described differently in the UI.
        let isUndeclared: Bool
        /// True for children of a root whose small entries are noise rather than
        /// findings, so the same size floor applies to them without their being
        /// undeclared. A Mac carries well over a thousand sandbox containers and
        /// almost every one is a few kilobytes of widget or extension state;
        /// without the floor the audit would bury one real finding under a
        /// thousand empty rows.
        var isSizeFloored: Bool = false
        /// Set by audits that have already worked out what to say. The Office
        /// add-in audit knows the difference between a companion file left
        /// behind and a registration still pointing at a file that is gone, and
        /// that difference is the entire finding — the generic wording below
        /// would throw it away.
        var customReason: String? = nil
        var customExplanation: String? = nil
        var customTags: [Tag]? = nil
    }

    private func buildTargets(installedApplicationNames: Set<String>) -> [ScanTarget] {
        var targets: [ScanTarget] = []
        var seenPaths: Set<String> = []

        for rule in applications.sorted(by: { $0.name < $1.name }) {
            let isInstalled = installedApplicationNames.contains(rule.name)
            let app = ApplicationRef(
                name: rule.name,
                bundleIdentifier: rule.bundleIdentifier,
                isInstalled: isInstalled
            )
            let association: Association = isInstalled ? .confirmed : .veryLikely

            for knownPath in rule.knownPaths {
                let url = knownPath.expand(to: homeDirectory).standardizedFileURL
                guard isInsideHome(url), seenPaths.insert(url.path).inserted else { continue }
                targets.append(ScanTarget(
                    url: url,
                    knownPath: knownPath,
                    rule: rule,
                    app: app,
                    association: association,
                    isInventoryChild: false,
                    isUndeclared: false
                ))
            }
        }

        targets.append(contentsOf: buildHousekeepingTargets(seenPaths: &seenPaths))

        // The installed-application inventory is one directory walk over the
        // application folders. Both audits below need it, so it is built once.
        let installedEvidence = installedApplicationEvidence()
        targets.append(contentsOf: buildPhantomApplicationTargets(
            seenPaths: &seenPaths,
            installed: installedEvidence
        ))
        // Runs before the sweep so the add-in folders have already been claimed
        // by name when the sweep reaches the shared container they sit in. The
        // sweep would otherwise describe the whole Office container as one
        // undeclared folder and lose the individual files inside it, which are
        // the only part worth reading.
        targets.append(contentsOf: buildOfficeAddInTargets(seenPaths: &seenPaths))
        if deepSweep {
            targets.append(contentsOf: buildUndeclaredTargets(
                seenPaths: &seenPaths,
                installed: installedEvidence
            ))
        }

        return targets
    }

    /// Collapses targets that resolve to the same path, preferring a target the
    /// rule database declared explicitly over one produced by expanding a parent
    /// into an inventory. `~/.gemini/users` is both a declared path (classified as
    /// conversation history) and a child of the depth-1 `~/.gemini` inventory; only
    /// the declared classification is correct, so it must win.
    private func dedupeInventory(_ targets: [ScanTarget]) -> [ScanTarget] {
        var best: [String: ScanTarget] = [:]
        var order: [String] = []

        for target in targets {
            let key = target.url.standardizedFileURL.path
            guard let existing = best[key] else {
                best[key] = target
                order.append(key)
                continue
            }
            if existing.isInventoryChild && !target.isInventoryChild {
                best[key] = target
            }
        }

        return order.compactMap { best[$0] }
    }

    // MARK: - Phantom application audit

    /// Enumerates the app-facing Library locations that commonly survive an
    /// uninstall. This is deliberately shallow: it reports the app namespace
    /// as one reviewable item and never guesses that its contents are junk.
    private func buildPhantomApplicationTargets(
        seenPaths: inout Set<String>,
        installed: InstalledApplicationEvidence
    ) -> [ScanTarget] {
        let housekeeping = ApplicationRule(
            name: "Phantom Application Audit",
            knownPaths: [],
            category: .system,
            description: "Application residue whose apparent owner is not installed."
        )
        var targets: [ScanTarget] = []

        // Root, category, description, and whether small children are noise.
        let roots: [(String, ItemCategory, String, Bool)] = [
            ("Library/Application Support", .applicationData, "Persistent application data found under Application Support.", false),
            ("Library/HTTPStorages", .applicationData, "HTTP cookies and web storage left by an application. This may contain sign-in state and requires review.", false),
            ("Library/Saved Application State", .applicationData, "Saved window and application state left by an application.", false),
            ("Library/Preferences", .preferences, "Application preference left after the apparent owner was removed.", false),
            ("Library/Caches", .cache, "Regenerable cache left by an application.", false),
            ("Library/Logs", .logs, "Diagnostic logs left by an application.", false),
            ("Library/Group Containers", .applicationData, "Sandbox group container left by an application.", false),
            ("Library/LaunchAgents", .applicationData, "Per-user launch agent whose apparent owning application is not installed.", false),
            // A sandbox container is the private storage area macOS gives an
            // application: its documents, its settings, and anything it
            // downloaded. Deleting an application does not delete its container,
            // so this is where a removed app most often leaves the most behind.
            // It is also the one root where the small entries outnumber the real
            // ones by a thousand to one, which is what the floor is for.
            ("Library/Containers", .applicationData, "A sandbox container: the private storage area macOS gives one application, holding its documents, settings, and downloaded files. Deleting an application does not delete its container.", true)
        ]

        for (relativeRoot, category, description, floorsChildren) in roots {
            let root = homeDirectory.appendingPathComponent(relativeRoot, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            if floorsChildren { containerEntryCount = children.count }

            for child in children {
                let normalized = child.standardizedFileURL
                // The ownership test must run before the path is marked as seen.
                // A path this audit rejects because an installed app owns it is
                // exactly the kind of path the undeclared sweep needs to see, so
                // recording it here would hide it from that sweep.
                guard shouldAuditAsPhantom(child, root: relativeRoot, installed: installed),
                      seenPaths.insert(normalized.path).inserted else { continue }

                let label = phantomApplicationName(for: child.lastPathComponent)
                let app = ApplicationRef(
                    name: label,
                    bundleIdentifier: probableBundleIdentifier(for: child.lastPathComponent),
                    isInstalled: false
                )
                targets.append(ScanTarget(
                    url: normalized,
                    knownPath: KnownPath(relativePath: relativeRoot, category: category, description: description),
                    rule: housekeeping,
                    app: app,
                    association: .veryLikely,
                    isInventoryChild: true,
                    isUndeclared: false,
                    isSizeFloored: floorsChildren
                ))
            }
        }

        return targets
    }

    // MARK: - Office add-in audit

    /// Reports what Microsoft Office leaves behind when one of its add-ins is
    /// taken off the disk without Office being told. The rest of the scanner
    /// cannot see this by construction: the files are a few hundred bytes, so no
    /// size floor surfaces them, and the folders they sit in belong to an
    /// application that is still very much installed, so the residue rule passes
    /// over them. It is looked for by name instead.
    private func buildOfficeAddInTargets(seenPaths: inout Set<String>) -> [ScanTarget] {
        let rule = ApplicationRule(
            name: "Office Add-in Audit",
            knownPaths: [],
            category: .system,
            description: "Residue in Microsoft Office's add-in folders and settings."
        )

        let outcome = OfficeAddInAudit(homeDirectory: homeDirectory, fileManager: fileManager).run()
        officeAddInNotes = Self.notes(for: outcome)

        return outcome.findings.compactMap { finding in
            guard fileManager.fileExists(atPath: finding.url.path) else { return nil }
            let normalized = finding.url.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { return nil }

            return ScanTarget(
                url: normalized,
                knownPath: KnownPath(
                    relativePath: Self.relativePath(of: normalized, under: homeDirectory),
                    category: .applicationData,
                    description: finding.reason
                ),
                rule: rule,
                app: ApplicationRef(
                    name: finding.applicationName,
                    bundleIdentifier: finding.bundleIdentifier,
                    isInstalled: NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: finding.bundleIdentifier
                    ) != nil
                ),
                // The audit read this out of Office's own folder or settings
                // file, so there is nothing left to be uncertain about.
                association: .confirmed,
                isInventoryChild: false,
                isUndeclared: false,
                customReason: finding.reason,
                customExplanation: finding.explanation,
                customTags: finding.kind == .staleCompanionFile ? [.old, .unused] : [.unused]
            )
        }
    }

    /// The notes that go with the audit, including the ones that report the
    /// audit's own blind spots. An audit that cannot read the folder it is
    /// supposed to be auditing has to say so: an empty list and an unread
    /// folder look identical on screen, and only one of them means the Mac is
    /// clean.
    private static func notes(for outcome: OfficeAddInAudit.Outcome) -> [ScanResults.ScanNote] {
        var notes: [ScanResults.ScanNote] = []

        let dangling = outcome.findings.filter { $0.kind == .danglingRegistration }
        let companions = outcome.findings.filter { $0.kind == .staleCompanionFile }

        if !dangling.isEmpty {
            notes.append(.cautionPhase(
                dangling.count == 1
                    ? "One Microsoft Office application still lists an add-in whose file is gone. Removing the file was not the whole fix — the entry itself is what makes the application complain, and the note beside that settings file says what is left to do."
                    : "\(dangling.count) Microsoft Office applications still list add-ins whose files are gone. Removing the files was not the whole fix — the entries themselves are what make the applications complain, and each settings file says what is left to do."
            ))
        }

        if !companions.isEmpty {
            notes.append(.init(
                phase: "Office add-ins",
                message: companions.count == 1
                    ? "One companion file was left behind in a Microsoft Office startup folder by a session that ended without tidying up."
                    : "\(companions.count) companion files were left behind in Microsoft Office startup folders by sessions that ended without tidying up."
            ))
        }

        if outcome.startupFoldersUnreadable {
            notes.append(.cautionPhase(
                "Microsoft Office's shared folder could not be read, so anything left inside its add-in folders is missing from this list. macOS protects it from Housekeeping."
            ))
        } else if outcome.sharedFolderPresent && outcome.startupFoldersRead == 0 {
            notes.append(.cautionPhase(
                "Microsoft Office's shared folder was found, but none of its three add-in folders could be located inside it, so Housekeeping could not report on them."
            ))
        }

        for name in Set(outcome.unreadableSettings).sorted() {
            notes.append(.cautionPhase(
                "\(name)'s settings file could not be read, so Housekeeping cannot say whether it still lists an add-in whose file is gone."
            ))
        }

        for name in Set(outcome.applicationsRunning).sorted() {
            notes.append(.init(
                phase: "Office add-ins",
                message: "\(name) was running during the scan, so the companion files in its add-in folder were left alone rather than judged. Quitting it and scanning again reports them."
            ))
        }

        return notes
    }

    private static func relativePath(of url: URL, under home: URL) -> String {
        let prefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }

    // MARK: - Undeclared path sweep

    /// Enumerates the places where large amounts of data actually accumulate and
    /// reports anything the rule database does not describe. This is the answer to
    /// "the app cleaned 4 GB but the disk still shrank by 37 GB": a rule database
    /// can only describe what someone wrote down, and the largest folders on a real
    /// machine are usually not in it.
    ///
    /// Swept paths are never assumed to be disposable. Ownership evidence decides
    /// the association, and anything without a confirmed owner is blocked from
    /// quarantine by `CleanupSafetyPolicy`.
    private func buildUndeclaredTargets(
        seenPaths: inout Set<String>,
        installed: InstalledApplicationEvidence
    ) -> [ScanTarget] {
        let rule = ApplicationRule(
            name: "Undeclared Paths",
            knownPaths: [],
            category: .system,
            description: "A real folder that Housekeeping's rule database does not describe."
        )

        // Root, category, and whether each child is an independent app namespace.
        let sweptRoots: [(String, ItemCategory, String)] = [
            ("Library/Application Support", .applicationData, "persistent application data"),
            ("Library/Group Containers", .applicationData, "a sandboxed group container"),
            ("Library/Caches", .cache, "an application cache"),
            ("Library/Logs", .logs, "an application log folder"),
            (".cache", .cache, "a tool cache in your home directory")
        ]

        var targets: [ScanTarget] = []

        for (relativeRoot, category, role) in sweptRoots {
            let root = homeDirectory.appendingPathComponent(relativeRoot, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }

            for child in children {
                let normalized = child.standardizedFileURL
                guard seenPaths.insert(normalized.path).inserted else { continue }
                targets.append(makeUndeclaredTarget(
                    normalized,
                    category: category,
                    role: role,
                    container: relativeRoot,
                    installed: installed,
                    rule: rule
                ))
            }
        }

        // Home dot-directories. Structural containers are skipped because their
        // contents are enumerated individually, and lumping them together would
        // report one enormous folder whose size no single decision can act on.
        // `.Trash` is skipped because its contents are already staged for
        // deletion and emptying it is a separate, all-or-nothing decision.
        let structuralDotDirectories: Set<String> = [
            ".Trash", ".config", ".npm", ".bun", ".git"
        ]
        if let dotEntries = try? fileManager.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        ) {
            for entry in dotEntries where entry.lastPathComponent.hasPrefix(".") {
                let name = entry.lastPathComponent
                guard !structuralDotDirectories.contains(name),
                      !name.hasPrefix(".DS_"),
                      name != ".DS_Store" else { continue }
                let normalized = entry.standardizedFileURL
                guard seenPaths.insert(normalized.path).inserted else { continue }
                targets.append(makeUndeclaredTarget(
                    normalized,
                    category: .applicationData,
                    role: "a hidden folder in your home directory",
                    container: "home",
                    installed: installed,
                    rule: rule
                ))
            }
        }

        return targets
    }

    private func makeUndeclaredTarget(
        _ url: URL,
        category: ItemCategory,
        role: String,
        container: String,
        installed: InstalledApplicationEvidence,
        rule: ApplicationRule
    ) -> ScanTarget {
        let rawName = url.lastPathComponent
        let evidence = undeclaredOwnerEvidence(for: rawName, installed: installed)

        let app = ApplicationRef(
            name: evidence.ownerName,
            bundleIdentifier: evidence.bundleIdentifier,
            isInstalled: evidence.isInstalled
        )

        let description: String
        if evidence.isSystemOwned {
            description = "No rule in Housekeeping's database describes this folder. Its name marks it as belonging to macOS or to a large vendor's own naming rather than to one application you installed, so it is not treated as residue from something you removed. It is \(role) inside \(container); check the path and contents before trusting it."
        } else if evidence.isInstalled {
            description = "No rule in Housekeeping's database describes this folder. It appears to belong to \(evidence.ownerName), which is installed on this Mac. Housekeeping cannot say what is inside it or whether it is safe to remove, so it is reported for inspection only."
        } else {
            description = "No rule in Housekeeping's database describes this folder. Its name suggests \(evidence.ownerName), but Housekeeping found no matching installed application. That makes it a candidate for residue left behind by something you removed. It is \(role) inside \(container); check the path and contents before trusting it."
        }

        return ScanTarget(
            url: url,
            knownPath: KnownPath(
                relativePath: url.path.replacingOccurrences(of: homeDirectory.path + "/", with: ""),
                category: category,
                description: description
            ),
            rule: rule,
            app: app,
            association: evidence.isInstalled ? .veryLikely : .possible,
            isInventoryChild: true,
            isUndeclared: true
        )
    }

    private struct UndeclaredOwnerEvidence {
        /// Best available name for whatever seems to own the folder. Always
        /// non-empty: it falls back to the folder's own name when nothing
        /// better can be established.
        var ownerName: String
        var bundleIdentifier: String?
        var isInstalled: Bool
        /// True when the name belongs to a system or vendor namespace rather
        /// than to one removable application, so the folder must not be
        /// described as residue from something the user removed.
        var isSystemOwned: Bool = false
    }

    /// Vendor and system namespaces that belong to a platform or to a large
    /// vendor rather than to a single removable application. Declared once so
    /// the phantom audit and the undeclared sweep agree on what they refuse to
    /// call residue: the sweep alone used to report Apple's own folders, and
    /// folders of installed applications such as Telegram Desktop, as leftover
    /// data from something the user had removed.
    private static let protectedNamespacePrefixes = [
        "com.apple.", "com.openai.", "com.anthropic.", "com.google.",
        "com.microsoft.", "com.adobe.", "com.dropbox.", "com.raycast.",
        "com.macpaw.cleanmymac5", "com.logi.", "com.logitech.",
        "com.malwarebytes.", "com.tdesktop.", "net.whatsapp.",
        "org.mozilla.", "org.videolan.", "org.openemu.", "org.swift.",
        "io.dictionaries.", "io.sentry.", "familycircled", "contactsd",
        "identityservicesd", "privatecloudcomputed", "networkserviceproxy",
        "software update utilities", "proapps", "cef", "crashreporter"
    ]

    private func isProtectedNamespace(_ rawName: String) -> Bool {
        let normalized = normalize(rawName.replacingOccurrences(of: ".plist", with: ""))
        return Self.protectedNamespacePrefixes.contains { normalized.hasPrefix(normalize($0)) }
    }

    /// True when an installed application plausibly owns a folder of this name,
    /// either because the folder name is its bundle identifier or because the
    /// two names overlap closely enough that a separate owner is implausible.
    private func ownedByInstalledApplication(
        _ rawName: String,
        installed: InstalledApplicationEvidence
    ) -> Bool {
        let normalized = normalize(rawName.replacingOccurrences(of: ".plist", with: ""))
        if let identifier = probableBundleIdentifier(for: rawName),
           installed.identifiers.contains(normalize(identifier)) { return true }
        if installed.names.contains(normalized) { return true }
        return installed.names.contains { name in
            name.count >= 4 && (normalized.contains(name) || name.contains(normalized))
        }
    }

    /// Identifies a likely owner for an undeclared folder using only local
    /// evidence: a reverse-DNS folder name, or a folder name matching an
    /// installed application. No guess is promoted to "installed".
    private func undeclaredOwnerEvidence(
        for rawName: String,
        installed: InstalledApplicationEvidence
    ) -> UndeclaredOwnerEvidence {
        let trimmed = rawName.replacingOccurrences(of: ".plist", with: "")
        let bundleIdentifier = probableBundleIdentifier(for: trimmed)
        let ownerName = phantomApplicationName(for: trimmed)

        if ownedByInstalledApplication(rawName, installed: installed) {
            return UndeclaredOwnerEvidence(
                ownerName: ownerName,
                bundleIdentifier: bundleIdentifier,
                isInstalled: true
            )
        }

        return UndeclaredOwnerEvidence(
            ownerName: ownerName,
            bundleIdentifier: bundleIdentifier,
            isInstalled: false,
            isSystemOwned: isProtectedNamespace(rawName)
        )
    }

    private struct InstalledApplicationEvidence {
        var names: Set<String> = []
        var identifiers: Set<String> = []
    }

    private func installedApplicationEvidence() -> InstalledApplicationEvidence {
        var evidence = InstalledApplicationEvidence()
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { continue }
                if let name = info["CFBundleDisplayName"] as? String { evidence.names.insert(normalize(name)) }
                if let name = info["CFBundleName"] as? String { evidence.names.insert(normalize(name)) }
                evidence.names.insert(normalize(url.deletingPathExtension().lastPathComponent))
                if let identifier = info["CFBundleIdentifier"] as? String { evidence.identifiers.insert(normalize(identifier)) }
            }
        }
        return evidence
    }

    private func shouldAuditAsPhantom(
        _ url: URL,
        root: String,
        installed: InstalledApplicationEvidence
    ) -> Bool {
        let rawName = url.lastPathComponent
        guard !rawName.isEmpty, rawName != ".DS_Store" else { return false }

        // OS-owned and intentionally shared namespaces are never phantom
        // residue, even when they do not correspond to a visible application.
        if isProtectedNamespace(rawName) { return false }

        // A generic support folder may be owned by an app whose bundle ID is
        // not in the folder name. A normalized app-name match is sufficient
        // to keep it out of the phantom list.
        if ownedByInstalledApplication(rawName, installed: installed) { return false }

        // Cache and log roots contain many harmless empty namespaces. They are
        // still useful to show when they have actual content.
        if ["Library/Caches", "Library/Logs"].contains(root) {
            return directoryOrFileHasContent(url)
        }
        return true
    }

    private func directoryOrFileHasContent(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
        if values.isDirectory != true { return true }
        return (try? fileManager.contentsOfDirectory(atPath: url.path).isEmpty == false) ?? false
    }

    private func probableBundleIdentifier(for name: String) -> String? {
        let withoutExtension = name.replacingOccurrences(of: ".plist", with: "")
        let components = withoutExtension.split(separator: ".")
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty }),
              components.first?.count ?? 0 >= 2 else { return nil }
        return withoutExtension
    }

    private func phantomApplicationName(for name: String) -> String {
        let trimmed = name.replacingOccurrences(of: ".plist", with: "")
        if let identifier = probableBundleIdentifier(for: trimmed) {
            return identifier.split(separator: ".").last.map(String.init) ?? trimmed
        }
        return trimmed
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func buildHousekeepingTargets(seenPaths: inout Set<String>) -> [ScanTarget] {
        let rule = ApplicationRule(
            name: "macOS Housekeeping",
            knownPaths: [],
            category: .system,
            description: "Regenerable operating-system and developer-tool leftovers."
        )
        let app = ApplicationRef(name: rule.name, isInstalled: true)
        let candidates: [(String, ItemCategory, String)] = [
            (".npm/_cacache", .cache, "npm package download cache. Regenerable packages used by Node projects."),
            (".npm/_npx", .cache, "Temporary npx command cache. Regenerable packages used by one-off Node commands."),
            (".bun/install/cache", .cache, "Bun package cache. Regenerable packages used by Bun projects."),
            (".cache/clang", .cache, "Compiler module cache. Regenerable build data."),
            (".cache/language_tool_python", .cache, "LanguageTool runtime/cache data. Regenerable if the tool is used again."),
            (".cache/opencode", .cache, "OpenCode cache. Regenerable application data."),
            (".cache/yt-dlp", .cache, "yt-dlp signature cache. Regenerable download metadata."),
            (".matplotlib", .cache, "Matplotlib cache and configuration. Regenerable plotting data."),
            (".idlerc", .cache, "Python IDLE user cache/configuration. Regenerable convenience data."),
            (".zcompdump", .cache, "zsh completion cache. Regenerated by the shell."),
            (".wget-hsts", .cache, "wget HSTS cache. Regenerable connection metadata."),
            (".DS_Store", .cache, "Finder view metadata. Regenerable, but removing it resets this folder's view settings.")
        ]
        var targets: [ScanTarget] = []
        for (relativePath, category, description) in candidates {
            let url = homeDirectory.appendingPathComponent(relativePath).standardizedFileURL
            guard isInsideHome(url), fileManager.fileExists(atPath: url.path), seenPaths.insert(url.path).inserted else { continue }
            targets.append(ScanTarget(
                url: url,
                knownPath: KnownPath(relativePath: relativePath, category: category, description: description),
                rule: rule,
                app: app,
                association: .confirmed,
                isInventoryChild: false,
                isUndeclared: false
            ))
        }

        let desktop = homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(at: desktop, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
            for child in children where child.lastPathComponent.hasPrefix("~$") && child.pathExtension.lowercased() == "docx" {
                let normalizedChild = child.standardizedFileURL
                guard seenPaths.insert(normalizedChild.path).inserted else { continue }
                targets.append(ScanTarget(
                    url: normalizedChild,
                    knownPath: KnownPath(
                        relativePath: normalizedChild.path.replacingOccurrences(of: homeDirectory.path + "/", with: ""),
                        category: .projectData,
                        description: "Microsoft Word lock file. Usually left while a document is open and may be orphaned after Word closes."
                    ),
                    rule: rule,
                    app: app,
                    association: .confirmed,
                    isInventoryChild: false,
                    isUndeclared: false
                ))
            }
        }
        return targets
    }

    private func expandInventoryTargets(_ rootTargets: [ScanTarget]) -> [ScanTarget] {
        rootTargets.flatMap { target in
            guard target.knownPath.inventoryDepth == 1,
                  fileManager.fileExists(atPath: target.url.path),
                  let values = try? target.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return [target]
            }

            do {
                let children = try fileManager.contentsOfDirectory(
                    at: target.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

                guard !children.isEmpty else { return [target] }
                return children.map { child in
                    ScanTarget(
                        url: child.standardizedFileURL,
                        knownPath: KnownPath(
                            relativePath: target.knownPath.relativePath,
                            category: target.knownPath.category,
                            description: target.knownPath.inventoryDescription ?? target.knownPath.description
                        ),
                        rule: target.rule,
                        app: target.app,
                        association: target.association,
                        isInventoryChild: true,
                        isUndeclared: target.isUndeclared
                    )
                }
            } catch {
                unreadableLocationCount += 1
                return [target]
            }
        }
    }

    private func inspect(_ target: ScanTarget) async throws -> FoundItem? {
        let values: URLResourceValues
        do {
            values = try target.url.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
                .contentAccessDateKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
            ])
        } catch {
            unreadableLocationCount += 1
            return nil
        }

        let isSymlink = values.isSymbolicLink == true
        let measurement: SizeMeasurement
        if values.isDirectory == true {
            measurement = try await directorySize(target.url)
        } else {
            measurement = SizeMeasurement(
                bytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                complete: true
            )
        }

        let safety: SafetyLevel
        if isSymlink || !measurement.complete {
            safety = .doNotAutoSelect
        } else {
            safety = initialSafety(for: target.knownPath.category)
        }

        return FoundItem(
            path: target.url,
            size: measurement.bytes,
            modified: values.contentModificationDate,
            lastAccessed: values.contentAccessDate,
            isSymlink: isSymlink,
            resolvedPath: isSymlink ? target.url.resolvingSymlinksInPath() : nil,
            category: target.knownPath.category,
            safetyLevel: safety,
            association: target.association,
            primaryApplication: target.app,
            reason: target.customReason ?? (target.isUndeclared
                ? "Found by sweeping \(target.url.deletingLastPathComponent().abbreviatingWithTilde(homeDirectory: homeDirectory)) — no rule describes this path"
                : (target.isInventoryChild
                    ? "Immediate child of an expanded inventory root in the \(target.rule.name) rule"
                    : "Exact path from the \(target.rule.name) rule")),
            explanation: target.customExplanation ?? (target.rule.name == "Phantom Application Audit"
                ? "\(target.knownPath.description) No installed application matching this namespace was found in the current application inventory. Reported separately so its exact path, size, and contents can be reviewed before reversible quarantine."
                : (target.isInventoryChild
                    ? "\(target.knownPath.description) Reported separately so its size and path can be reviewed."
                    : target.knownPath.description)),
            tags: isSymlink
                ? [.symlink]
                : (target.customTags ?? (target.rule.name == "Phantom Application Audit" ? [.old, .unused] : [])),
            isUndeclared: target.isUndeclared,
            isSelected: false
        )
    }

    private struct SizeMeasurement {
        var bytes: Int64
        var complete: Bool
    }

    private func directorySize(_ root: URL) async throws -> SizeMeasurement {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        var measurement = SizeMeasurement(bytes: 0, complete: true)

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { [weak self] _, _ in
                measurement.complete = false
                self?.unmeasuredFileCount += 1
                return true
            }
        ) else {
            return SizeMeasurement(bytes: 0, complete: false)
        }

        var entryCount = 0
        while let url = enumerator.nextObject() as? URL {
            entryCount += 1
            if entryCount.isMultiple(of: 512) {
                try Task.checkCancellation()
                await Task.yield()
            }

            guard let values = try? url.resourceValues(forKeys: keys) else {
                measurement.complete = false
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            measurement.bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return measurement
    }

    private func initialSafety(for category: ItemCategory) -> SafetyLevel {
        switch category {
        case .cache: return .safeToReplace
        case .logs: return .usuallySafe
        case .shared: return .sharedResource
        case .conversationData, .credentials, .projectData: return .userDataType
        case .downloadedModels, .applicationData, .preferences, .pythonEnvironment: return .reviewFirst
        case .unknown: return .doNotAutoSelect
        }
    }

    private func detectInstalledApplicationNames() -> Set<String> {
        Set(applications.compactMap { rule in
            if let bundleIdentifier = rule.bundleIdentifier,
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil {
                return rule.name
            }

            if let executableName = rule.executableName, executableExists(named: executableName) {
                return rule.name
            }

            if rule.bundleIdentifier == nil && rule.executableName == nil {
                return rule.name
            }
            return nil
        })
    }

    private func executableExists(named executableName: String) -> Bool {
        var searchDirectories = [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            searchDirectories.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
            })
        }

        let names = Set([executableName, executableName.lowercased()])
        return searchDirectories.contains { directory in
            names.contains { name in
                fileManager.isExecutableFile(atPath: directory.appendingPathComponent(name).path)
            }
        }
    }

    private func buildSummary() -> ScanResults.Summary {
        let totalSize = foundItems.reduce(0) { $0 + $1.size }
        let appGroups = Dictionary(grouping: foundItems) { $0.primaryApplication?.name ?? "Unknown" }
        return ScanResults.Summary(
            totalSize: totalSize,
            itemCount: foundItems.count,
            appsFound: appGroups.mapValues { $0.reduce(0) { $0 + $1.size } },
            remnantsFound: foundItems.filter {
                $0.primaryApplication?.isInstalled == false && $0.category != .projectData
            }.count,
            sharedResourcesFound: foundItems.filter { $0.category == .shared }.count
        )
    }

    private func isInsideHome(_ url: URL) -> Bool {
        let homeComponents = homeDirectory.pathComponents
        let candidateComponents = url.pathComponents
        guard candidateComponents.count > homeComponents.count else { return false }
        return Array(candidateComponents.prefix(homeComponents.count)) == homeComponents
    }
}

private extension URL {
    func abbreviatingWithTilde(homeDirectory: URL) -> String {
        guard path.hasPrefix(homeDirectory.path) else { return path }
        return "~" + String(path.dropFirst(homeDirectory.path.count))
    }
}
