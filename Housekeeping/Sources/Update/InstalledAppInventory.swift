import Foundation

// Housekeeping — Update inventory
//
// The list of things that could be updated is built from two sources that are
// asked separately and then joined: the `.app` bundles on disk, and Homebrew's
// own record of what it installed. Neither is trusted to describe the other. The
// bundles say what exists; Homebrew says what it owns; the join is by the app's
// filename *inside the bundle path*, because that is the value Homebrew's own
// artifact list carries. Matching on the bundle identifier would look tidier and
// would be wrong — Homebrew does not record it.
//
// Nothing here launches an application or reads a version by asking the app. An
// `Info.plist` is a file, and reading a file is what Housekeeping already knows
// how to do safely.

/// Everything one pass over the machine produced. The notes are for the screen:
/// the reasons a source could not be read belong in front of the reader, not in
/// a log.
struct UpdateInventory {
    let applications: [InstalledApplication]
    let packages: [BrewPackage]
    let notes: [String]
    /// True when `brew` was found. False turns every Homebrew row into an honest
    /// "Homebrew is not installed here" rather than a silent omission.
    let homebrewAvailable: Bool
}

enum AppInventory {
    /// The folders searched. `/System/Applications` is included so the sheet can
    /// list what belongs to macOS and say plainly that it will not be touched;
    /// an omission would leave a reader wondering where those apps went.
    static func scanDirectories(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            homeDirectory.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
        ]
    }

    /// Walks the folders, joins against Homebrew, and classifies each bundle. The
    /// work is serial: every classification runs `codesign` and `xattr`, and
    /// running those against a whole machine at once would spawn hundreds of
    /// processes to no benefit.
    static func scan(
        using runner: ProcessRunner,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) async throws -> UpdateInventory {
        var notes: [String] = []

        // Homebrew first, so its answers are in hand when the bundles are read.
        var caskByApp: [String: CaskMatch] = [:]
        var caskPackages: [BrewPackage] = []
        var formulaPackages: [BrewPackage] = []
        var homebrewAvailable = false

        if let brew = ProcessRunner.brewPath(fileManager: fileManager) {
            homebrewAvailable = true
            let caskResult = try await readCasks(brew: brew, runner: runner)
            caskByApp = caskResult.byApp
            caskPackages = caskResult.packages
            if let note = caskResult.note { notes.append(note) }
            let formulaResult = try await readFormulae(brew: brew, runner: runner)
            formulaPackages = formulaResult
        } else {
            notes.append("Homebrew is not installed on this Mac, so its packages are not listed.")
        }

        // Then the bundles.
        var applications: [InstalledApplication] = []
        var seenPaths = Set<String>()
        let directories = scanDirectories(homeDirectory: homeDirectory)

        for directory in directories {
            try Task.checkCancellation()
            let entries = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries where entry.pathExtension == "app" {
                try Task.checkCancellation()
                let standardized = entry.standardizedFileURL.resolvingSymlinksInPath()
                guard !seenPaths.contains(standardized.path) else { continue }
                seenPaths.insert(standardized.path)
                if let application = await readApplication(
                    at: entry,
                    cask: caskByApp[entry.lastPathComponent],
                    runner: runner,
                    fileManager: fileManager
                ) {
                    applications.append(application)
                }
            }
        }

        // A cask whose bundle is not on disk — the helper casks with no `.app`,
        // and the cases where the app was removed by hand. Only the ones that
        // were never matched to a bundle become rows of their own.
        let matchedTokens = Set(caskByApp.values.map(\.token))
        let unmatchedCasks = caskPackages.filter { !matchedTokens.contains($0.name) }

        applications.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let packages = (unmatchedCasks + formulaPackages)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return UpdateInventory(
            applications: applications,
            packages: packages,
            notes: notes,
            homebrewAvailable: homebrewAvailable
        )
    }

    // MARK: - One bundle

/// A Homebrew cask that installs a `.app`: the token it is upgraded by, and the
/// description Homebrew carries for it. Both come from the same answer, and both
/// are needed at the moment the bundle itself is read.
struct CaskMatch: Equatable {
    let token: String
    let summary: String
}

    static func readApplication(
        at url: URL,
        cask: CaskMatch?,
        runner: ProcessRunner,
        fileManager: FileManager = .default
    ) async -> InstalledApplication? {
        guard let info = readInfoPlist(bundleAt: url, fileManager: fileManager) else { return nil }
        let identifier = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A bundle with no identifier is not offered for update: every key this
        // feature uses to recognise an application a second time would be absent.
        guard !identifier.isEmpty else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? ""
        let build = info["CFBundleVersion"] as? String
        let feedURL = (info["SUFeedURL"] as? String).flatMap { URL(string: $0) }
        let category = info["LSApplicationCategoryType"] as? String

        let facts = BundleFacts(
            url: url,
            bundleIdentifier: identifier,
            name: name,
            version: version,
            build: build,
            feedURL: feedURL,
            homebrewCaskToken: cask?.token,
            githubRepo: AppUpdateEngine.knownGitHubRepos[identifier]
        )
        let (provenance, evidence) = await AppProvenance.assess(facts: facts, using: runner)
        let signature = await AppProvenance.readSignature(bundleAt: url, using: runner)

        return InstalledApplication(
            bundleIdentifier: identifier,
            name: name,
            path: url.path,
            version: version,
            build: build,
            team: signature.teamIdentifier,
            isAdHoc: signature.isAdHoc || !signature.isSigned,
            feedURL: feedURL,
            // Homebrew's own line first when this bundle is one of its casks. It
            // was written by someone who knows what the program does, where the
            // bundle's own plist usually offers only that it is "a utility".
            summary: cask?.summary.isEmpty == false
                ? cask?.summary
                : AppDescription.sentence(
                    category: category,
                    copyright: info["NSHumanReadableCopyright"] as? String,
                    signer: AppDescription.signer(from: signature.authorities),
                    provenance: provenance
                ),
            provenance: provenance,
            evidence: evidence
        )
    }

    /// Reads `Contents/Info.plist` without opening the application. A bundle is a
    /// directory of files and this is one of them; `Bundle(url:)` would also work
    /// but caches, which is the last thing wanted when the point is to observe
    /// what is on disk right now.
    static func readInfoPlist(bundleAt url: URL, fileManager: FileManager = .default) -> [String: Any]? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return parsed as? [String: Any]
    }

    // MARK: - Homebrew

    private struct CaskRead {
        let byApp: [String: CaskMatch]
        let packages: [BrewPackage]
        let note: String?
    }

    private static func readCasks(brew: String, runner: ProcessRunner) async throws -> CaskRead {
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: brew,
                arguments: ["info", "--json=v2", "--installed", "--cask"],
                timeout: 60
            )
        } catch {
            return CaskRead(byApp: [:], packages: [], note: "Homebrew's list of installed applications could not be read.")
        }
        guard result.succeeded else {
            return CaskRead(byApp: [:], packages: [], note: "Homebrew returned an error while listing installed applications.")
        }
        guard let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else {
            return CaskRead(byApp: [:], packages: [], note: "Homebrew's list of installed applications was not in the expected form.")
        }

        var byApp: [String: CaskMatch] = [:]
        var packages: [BrewPackage] = []
        for cask in casks {
            guard let token = cask["token"] as? String else { continue }
            let installed = (cask["installed"] as? String) ?? ""
            let versions = cask["versions"] as? [String: Any]
            let current = (versions?["stable"] as? String) ?? installed
            let description = (cask["desc"] as? String) ?? ""

            var appFilenames: [String] = []
            for artifact in (cask["artifacts"] as? [[String: Any]]) ?? [] {
                if let apps = artifact["app"] as? [String] {
                    appFilenames.append(contentsOf: apps.map { ($0 as NSString).lastPathComponent })
                }
            }

            if appFilenames.isEmpty {
                packages.append(BrewPackage(
                    name: token, isCask: true,
                    summary: description,
                    installedVersion: installed, currentVersion: current, isPinned: false
                ))
            } else {
                let match = CaskMatch(token: token, summary: description)
                for filename in appFilenames { byApp[filename] = match }
            }
        }
        return CaskRead(byApp: byApp, packages: packages, note: nil)
    }

    private static func readFormulae(brew: String, runner: ProcessRunner) async throws -> [BrewPackage] {
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: brew,
                arguments: ["info", "--json=v2", "--installed"],
                timeout: 60
            )
        } catch {
            return []
        }
        guard result.succeeded,
              let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]] else {
            return []
        }

        var packages: [BrewPackage] = []
        for formula in formulae {
            guard let name = formula["name"] as? String else { continue }
            let installedList = (formula["installed"] as? [[String: Any]]) ?? []
            let installed = installedList.compactMap { $0["version"] as? String }.last ?? ""
            let versions = formula["versions"] as? [String: Any]
            let current = (versions?["stable"] as? String) ?? installed
            let isPinned = (formula["pinned"] as? Bool) ?? false
            packages.append(BrewPackage(
                name: name, isCask: false,
                summary: (formula["desc"] as? String) ?? "",
                installedVersion: installed, currentVersion: current, isPinned: isPinned
            ))
        }
        return packages
    }
}

// MARK: - What an application is

/// Builds the one sentence that says what an application is, out of three things
/// already on disk: the category the bundle files itself under, the maker its own
/// copyright line names, and the route the provenance assessment found. Every part
/// is optional and the sentence drops whatever is missing, so the failure mode is
/// silence rather than an invention.
///
/// This is the whole reason the update list is worth looking at. A reader deciding
/// whether to update `dav1d` is not helped by its version number; they are helped
/// by being told it is a video decoder installed with Homebrew.
enum AppDescription {

    /// Apple's own category values, said the way a person would. A value that is
    /// not on this list is left out rather than reprinted: `public.app-category.x`
    /// in front of a reader fills the line without explaining anything.
    private static let categories: [String: String] = [
        "business": "a business app",
        "developer-tools": "a developer tool",
        "education": "an education app",
        "entertainment": "an entertainment app",
        "finance": "a finance app",
        "games": "a game",
        "graphics-design": "a graphics or design app",
        "healthcare-fitness": "a health and fitness app",
        "lifestyle": "a lifestyle app",
        "medical": "a medical app",
        "music": "a music app",
        "news": "a news app",
        "photography": "a photography app",
        "productivity": "a productivity app",
        "reference": "a reference app",
        "social-networking": "a social networking app",
        "sports": "a sports app",
        "travel": "a travel app",
        "utilities": "a utility",
        "video": "a video app",
        "weather": "a weather app",
    ]

    static func sentence(
        category: String?,
        copyright: String?,
        signer: String?,
        provenance: Provenance
    ) -> String? {
        var head: [String] = []
        if let category, let named = categories[stripped(category)] {
            head.append(named)
        }
        // Who made it, from the two places that say so. The copyright line is the
        // application's own claim about itself; the signature is an observation,
        // and it is the one still standing when the plist says nothing — which is
        // the ordinary case for a bundle distributed outside the App Store. An
        // application that names neither stays silent rather than being given a
        // maker it never claimed.
        if let maker = maker(fromCopyright: copyright) {
            head.append("from \(maker)")
        } else if case .signedByDeveloper = provenance, let signer {
            head.append("from \(signer)")
        }
        let arrival = route(provenance)
        guard !head.isEmpty || arrival != nil else { return nil }

        var sentence = head.joined(separator: " ")
        if let arrival {
            sentence = sentence.isEmpty ? arrival : "\(sentence), \(arrival)"
        }
        guard let first = sentence.first else { return nil }
        return first.uppercased() + sentence.dropFirst() + "."
    }

    private static func stripped(_ category: String) -> String {
        let prefix = "public.app-category."
        return category.hasPrefix(prefix) ? String(category.dropFirst(prefix.count)) : category
    }

    /// The maker, dug out of a line that is mostly years and legal boilerplate:
    /// `"Copyright © 2026 The Chromium Authors. All rights reserved."` is a maker
    /// with three distractions around it. What survives has to still look like a
    /// name — a licence paragraph that happened to outlive the tidying is dropped
    /// rather than shown as though it were one.
    private static func maker(fromCopyright line: String?) -> String? {
        guard var text = line, !text.isEmpty else { return nil }
        for noise in [
            "All rights reserved.", "All rights reserved",
            "Alle Rechte vorbehalten.", "Todos los derechos reservados.",
            "Tous droits réservés.", "©",
        ] {
            text = text.replacingOccurrences(of: noise, with: " ", options: [.caseInsensitive])
        }
        text = text.replacingOccurrences(of: "Copyright", with: " ", options: [.caseInsensitive])
        // The years say when, not who — including the ranges applications like to
        // write. Done after the words above, so "2026" cannot survive inside them.
        text = text.replacingOccurrences(
            of: #"(19|20)\d{2}\s*([-–]\s*((19|20)?\d{2}))?"#,
            with: " ",
            options: [.regularExpression]
        )
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: [.regularExpression])
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,-–—()\t"))
        guard !text.isEmpty, text.count <= 48 else { return nil }
        return text
    }

    /// The name inside a signing certificate, which `codesign` reports as
    /// `"Developer ID Application: Google LLC (EQHXZ8M8AV)"` — a maker with the
    /// kind of certificate in front of it and an identifier behind it. Only the
    /// first entry is the signer; the ones after it are the chain up to Apple, and
    /// a chain link names no maker, so an entry with no colon in it is refused
    /// rather than printed as though it were a person or a company.
    static func signer(from authorities: [String]) -> String? {
        guard let leaf = authorities.first,
              let separator = leaf.range(of: ": ") else { return nil }
        var text = String(leaf[separator.upperBound...])
        text = text.replacingOccurrences(
            of: #"\s*\([A-Z0-9]{10}\)\s*$"#,
            with: "",
            options: [.regularExpression]
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 48 else { return nil }
        return text
    }

    /// How it arrived, where the assessment established that. The two cases left
    /// out say nothing a summary could use: a signed bundle with no feed does not
    /// record where it came from, and an altered copy's own row already says what
    /// is wrong with it.
    private static func route(_ provenance: Provenance) -> String? {
        switch provenance {
        case .macAppStore: return "installed from the Mac App Store"
        case .homebrewCask, .homebrewFormula: return "installed with Homebrew"
        case .githubRelease(let repo): return "installed from \(repo) on GitHub"
        case .sparkleFeed: return "updated by its own update feed"
        case .appleSystem: return "shipped with macOS"
        case .unsignedOrSelfSigned: return "carrying no signature saying who built it"
        case .signedByDeveloper, .alteredCopy: return nil
        }
    }
}
