// Housekeeping — Core Data Models
// Foundation types for the application

import Foundation

// MARK: - Scan Result

struct ScanResults {
    let scannedPaths: [URL]
    var foundItems: [FoundItem]
    let summary: Summary
    let scanDuration: TimeInterval
    let scanNotes: [ScanNote]  // Top-level type from Scanner module

    struct Summary {
        let totalSize: Int64
        let itemCount: Int
        let appsFound: [String: Int64]
        let remnantsFound: Int
        let sharedResourcesFound: Int
    }

    struct ScanNote {
        let phase: String
        let message: String

        static func findingPhase(_ message: String) -> ScanNote {
            ScanNote(phase: "🔍", message: message)
        }

        static func cautionPhase(_ message: String) -> ScanNote {
            ScanNote(phase: "⚠️", message: message)
        }
    }
}

// MARK: - Found Item (individual file/dir)

struct FoundItem: Identifiable, Codable, Equatable {
    let id: UUID
    let path: URL
    let size: Int64
    let modified: Date?
    let lastAccessed: Date?
    let isSymlink: Bool
    let resolvedPath: URL?

    // Classification
    var category: ItemCategory
    var safetyLevel: SafetyLevel
    var association: Association

    // Application context
    let primaryApplication: ApplicationRef?
    let contributingApplications: [ApplicationRef]

    // Metadata
    let reason: String?
    let explanation: String?
    var tags: [Tag]

    /// True when the sweep measured this path but no rule in the database
    /// describes it. Such an item can be reported and inspected, but nothing
    /// states what it contains or whether it can be recreated, so it is never
    /// eligible for one-click quarantine.
    var isUndeclared: Bool

    // Selection state
    var isSelected: Bool
    var isExpanded: Bool

    init(
        id: UUID = UUID(),
        path: URL,
        size: Int64,
        modified: Date? = nil,
        lastAccessed: Date? = nil,
        isSymlink: Bool = false,
        resolvedPath: URL? = nil,
        category: ItemCategory,
        safetyLevel: SafetyLevel,
        association: Association,
        primaryApplication: ApplicationRef? = nil,
        contributingApplications: [ApplicationRef] = [],
        reason: String? = nil,
        explanation: String? = nil,
        tags: [Tag] = [],
        isUndeclared: Bool = false,
        isSelected: Bool = false,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.modified = modified
        self.lastAccessed = lastAccessed
        self.isSymlink = isSymlink
        self.resolvedPath = resolvedPath
        self.category = category
        self.safetyLevel = safetyLevel
        self.association = association
        self.primaryApplication = primaryApplication
        self.contributingApplications = contributingApplications
        self.reason = reason
        self.explanation = explanation
        self.tags = tags
        self.isUndeclared = isUndeclared
        self.isSelected = isSelected
        self.isExpanded = isExpanded
    }

    // Convenience: is this item part of a larger group?
    var isGroupItem: Bool {
        category == .shared
    }
}

// MARK: - Item Category

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case cache
    case logs
    case downloadedModels
    case applicationData
    case preferences
    case conversationData
    case credentials
    case projectData
    case pythonEnvironment
    case shared
    case unknown

    var displayName: String {
        switch self {
        case .cache: return "Cache"
        case .logs: return "Logs"
        case .downloadedModels: return "Downloaded Models"
        case .applicationData: return "Application Data"
        case .preferences: return "Preferences"
        case .conversationData: return "Conversation / History Data"
        case .credentials: return "Credentials / API Configuration"
        case .projectData: return "Project Data"
        case .pythonEnvironment: return "Python Environment"
        case .shared: return "Shared Resource"
        case .unknown: return "Unknown"
        }
    }

    var id: String { rawValue }

    var description: String {
        switch self {
        case .cache:
            return "Cache — Temporary data an application keeps for faster access. Can be safely recreated."
        case .logs:
            return "Logs — Diagnostic and historical logging data. Normally safe to remove."
        case .downloadedModels:
            return "Model File — The actual language model used by a local AI application. Safe to remove, but downloading again may take considerable time."
        case .applicationData:
            return "Application Support — Data the application expects to survive between launches. May contain harmless generated files or potentially important databases."
        case .preferences:
            return "Preferences — Application settings and configuration. Small, may be useful if you reinstall."
        case .conversationData:
            return "Conversation Data — User conversations, prompts, and history. Valuable data that may be lost."
        case .credentials:
            return "Credentials — API keys, authentication data, and credentials. Very important to preserve."
        case .projectData:
            return "Project Data — User-created work, documents, or source code. Never delete automatically."
        case .pythonEnvironment:
            return "Python Environment — An isolated Python installation with libraries. Used by some AI applications. If the app is removed, this may be unnecessary."
        case .shared:
            return "Shared Resource — Used by multiple applications. Not automatically selected."
        case .unknown:
            return "Unknown — Housekeeping cannot confidently classify this data. Manual review recommended."
        }
    }

    var isAutoSelectable: Bool {
        switch self {
        case .cache, .logs: return true
        case .downloadedModels: return false  // expensive to redownload
        case .preferences: return false  // may be useful
        case .applicationData: return false
        case .conversationData: return false
        case .credentials: return false
        case .projectData: return false
        case .pythonEnvironment: return false
        case .shared: return false
        case .unknown: return false
        }
    }
}

// MARK: - Safety Level

enum SafetyLevel: String, Codable, CaseIterable, Identifiable {
    case safeToReplace = "Safe to Replace"
    case usuallySafe = "Usually Safe"
    case reviewFirst = "Review First"
    case userDataType = "User Data"
    case sharedResource = "Shared Resource"
    case doNotAutoSelect = "Do Not Auto-Select"
    case unknown = "Unknown"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .safeToReplace: return "⚪"
        case .usuallySafe: return "🟡"
        case .reviewFirst: return "🟠"
        case .userDataType: return "🔴"
        case .sharedResource: return "🔵"
        case .doNotAutoSelect: return "⛔"
        case .unknown: return "❓"
        }
    }

    var explanation: String {
        switch self {
        case .safeToReplace:
            return "This is temporary data that the application can recreate if needed. Removing it should not affect your documents, account, or settings."
        case .usuallySafe:
            return "This data is generally safe to remove, but the application may need to recreate it later."
        case .reviewFirst:
            return "This directory may contain application settings, history, or other persistent data. Removing it may reset the application."
        case .userDataType:
            return "This appears to be data you created or care about. Housekeeping will never delete user data automatically."
        case .sharedResource:
            return "Multiple applications may rely on this directory. Removing it could affect more than one program."
        case .doNotAutoSelect:
            return "This is important data. Housekeeping will not select it for cleanup without your explicit review."
        case .unknown:
            return "Housekeeping cannot confidently classify this data. Please review it manually before deciding."
        }
    }
}

// MARK: - Association

enum Association: String, Codable, Identifiable {
    case confirmed = "Confirmed"
    case veryLikely = "Very Likely"
    case possible = "Possible"
    case shared = "Shared"
    case unknown = "Unknown"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .confirmed:
            return "The folder name, bundle identifier, and files inside all correspond to this application. Housekeeping is confident in this association."
        case .veryLikely:
            return "The folder name, bundle identifier, and files inside correspond to this application, but Housekeeping cannot prove that another program does not also use this directory."
        case .possible:
            return "Housekeeping found evidence suggesting this may belong to the application, but the match is not certain. File types and directory names provide partial evidence."
        case .shared:
            return "Several programs may use this folder. Housekeeping found evidence that multiple applications share this directory."
        case .unknown:
            return "Housekeeping could not determine which application created this data, or found conflicting evidence."
        }
    }

    var color: String {
        switch self {
        case .confirmed: return "green"
        case .veryLikely: return "blue"
        case .possible: return "orange"
        case .shared: return "purple"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Application Reference

struct ApplicationRef: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let bundleIdentifier: String?
    let isInstalled: Bool
    let iconPath: URL?
    let version: String?
    let lastUsed: Date?

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String? = nil,
        isInstalled: Bool = true,
        iconPath: URL? = nil,
        version: String? = nil,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isInstalled = isInstalled
        self.iconPath = iconPath
        self.version = version
        self.lastUsed = lastUsed
    }
}

// MARK: - Tag

enum Tag: String, Codable, CaseIterable {
    case model = "Model"
    case weights = "Model Weights"
    case gguf = "GGUF"
    case safetensors = "Safetensors"
    case checkpoints = "Checkpoints"
    case python = "Python"
    case venv = "Virtual Environment"
    case pipCache = "pip Cache"
    case uvCache = "uv Cache"
    case ollamaModel = "Ollama Model"
    case huggingFace = "Hugging Face"
    case launcher = "Launcher"
    case helper = "Helper Process"
    case launchAgent = "LaunchAgent"
    case loginItem = "Login Item"
    case symlink = "Symlink"
    case container = "Sandbox Container"
    case largeFile = "Large File"
    case duplicate = "Possible Duplicate"
    case old = "Old"
    case unused = "Unused"

    var description: String {
        switch self {
        case .model: return "Model file"
        case .weights: return "Model weights"
        case .gguf: return "GGUF format model"
        case .safetensors: return "Safetensors format model"
        case .checkpoints: return "Training or inference checkpoint"
        case .python: return "Python-related"
        case .venv: return "Virtual environment"
        case .pipCache: return "pip package cache"
        case .uvCache: return "uv package cache"
        case .ollamaModel: return "Ollama model"
        case .huggingFace: return "Hugging Face cache"
        case .launcher: return "Application launcher"
        case .helper: return "Helper process"
        case .launchAgent: return "LaunchAgent"
        case .loginItem: return "Login item"
        case .symlink: return "Symbolic link"
        case .container: return "Sandbox container"
        case .largeFile: return "Large file"
        case .duplicate: return "Possible duplicate"
        case .old: return "Old file"
        case .unused: return "Appears unused"
        }
    }
}

// MARK: - Size Formatting

extension Int64 {
    var humanReadable: String {
        let bytes = Double(self)
        if bytes < 1024 {
            return "\(Int(bytes)) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
        }
    }

    /// The same size, except that nothing at all is not reported as "0 B".
    ///
    /// Zero is what the scanner leaves behind when it could not read a size, and
    /// printing "0 B" for a cache it failed to measure states something false.
    /// Saying so plainly is the point: an unmeasured item cannot be judged by
    /// its size, and the reader deserves to know which items those are.
    var sizeDescription: String {
        self == 0 ? "Not measured" : humanReadable
    }
}

// MARK: - When was this last used?

extension FoundItem {
    /// Past this age an item reads as a leftover rather than something in use.
    static let staleAfterDays = 180

    /// The best answer available to "when was this last used?".
    ///
    /// macOS keeps a separate access date, and it is the honest signal: it moves
    /// when something reads the file. But it is recorded lazily and sometimes not
    /// at all, so this falls back to the change date. `lastUsedIsRecorded` says
    /// which of the two the reader is being shown.
    var lastUsedDate: Date? { lastAccessed ?? modified }

    /// False when the date below came from the change date rather than a real
    /// access date, so the wording can say so instead of overstating it.
    var lastUsedIsRecorded: Bool { lastAccessed != nil }

    /// Whole days between the last use and today, nil when no date exists at all.
    var lastUsedDays: Int? {
        guard let date = lastUsedDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day
    }

    /// How long ago that was, in the words a person would actually use.
    var lastUsedDescription: String {
        guard let days = lastUsedDays else { return "never recorded" }
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 14 { return "last week" }
        if days < 31 { return "\(days / 7) weeks ago" }
        if days < 61 { return "last month" }
        if days < 365 { return "\(days / 30) months ago" }
        if days < 730 { return "over a year ago" }
        return "\(days / 365) years ago"
    }

    /// Whether this has sat untouched long enough to look abandoned.
    var lastUsedIsStale: Bool {
        guard let days = lastUsedDays else { return false }
        return days > Self.staleAfterDays
    }
}

// MARK: - Reader-facing explanation

struct FindingReaderGuide: Equatable {
    enum Risk: String {
        case low = "Low risk"
        case medium = "Medium risk"
        case high = "High risk"
        case unknown = "Unknown risk"
    }

    let whatItIs: String
    let whyItExists: String
    let necessity: String
    let risk: Risk
    let riskExplanation: String
}

extension FoundItem {
    var readerGuide: FindingReaderGuide {
        let name = path.lastPathComponent.lowercased()
        let components = path.pathComponents.map { $0.lowercased() }

        // Naming the actual app is most of what makes these read like a person
        // talking to you rather than a manual. Fall back to a neutral phrase,
        // never to nothing, so every sentence still has a subject.
        let who = primaryApplication?.name ?? "the app"
        let Who = primaryApplication?.name ?? "The app"

        if name == ".git" {
            return FindingReaderGuide(
                whatItIs: "This folder is the project's memory — every commit, branch, and tag Git has recorded in it.",
                whyItExists: "Git made it the moment this folder became a repository. It is the part that remembers what changed and when.",
                necessity: "Keep this one. Your files would survive without it, but the story of how they got there would not.",
                risk: .high,
                riskExplanation: "You would still have the current files, sitting there looking completely normal — but with no history, no branches, and no way to push or pull. The only way back is a copy somewhere else."
            )
        }

        if name == "node_modules" {
            return FindingReaderGuide(
                whatItIs: "The JavaScript libraries this project needs in order to build or run.",
                whyItExists: "Your package manager — npm, pnpm, Yarn — downloaded them from the project's list of dependencies.",
                necessity: "Safe to clear if you are not working on this project right now. It rebuilds from package.json next time you install.",
                risk: .medium,
                riskExplanation: "The project will not run again until you reinstall, which is usually one command. It does need the lockfile intact and a working connection to the registry, and those are the two things that pick the worst moment to fail."
            )
        }

        if name == ".venv" || name == "venv" || category == .pythonEnvironment {
            return FindingReaderGuide(
                whatItIs: "A private set of Python packages built for one project, kept apart from everything else on the Mac.",
                whyItExists: "So this project's libraries cannot collide with any other project's.",
                necessity: "Rebuildable whenever there is a requirements or lock file. Keep it if you would rather not find out whether yours is complete.",
                risk: .medium,
                riskExplanation: "Python stops working for this project until you rebuild the environment. Any version that was never written down is hard to get back exactly."
            )
        }

        if [".next", "dist", "build", "deriveddata"].contains(name) {
            return FindingReaderGuide(
                whatItIs: "Build output — what the source code turns into once it is compiled.",
                whyItExists: "A compiler, framework, or IDE made it so the project could run, be tested, or be packaged.",
                necessity: "Safe to clear. It is rebuilt from the source the next time you build.",
                risk: .low,
                riskExplanation: "Your next build takes longer, and that is the whole cost. The source files are untouched. Worth keeping only if you need to ship or run something right now, offline."
            )
        }

        if name == "out" {
            return FindingReaderGuide(
                whatItIs: "An output folder. It usually holds generated results — but the name gets used loosely, so that is not a promise.",
                whyItExists: "A project script or the application wrote its finished output here.",
                necessity: "Have a look before you touch this one. Sometimes it rebuilds itself; sometimes it is the only copy of finished work.",
                risk: .high,
                riskExplanation: "The folder name tells you nothing reliable. Open it. If you do not recognise what is inside, leave it where it is."
            )
        }

        if components.contains(".claude") && name == "projects" {
            return FindingReaderGuide(
                whatItIs: "Claude Code's notes from past sessions in your projects — not the projects themselves.",
                whyItExists: "It is how Claude Code remembers what you were working on last time.",
                necessity: "Your code is completely fine without it. Whether you want to keep it is about continuity, not safety.",
                risk: .high,
                riskExplanation: "Earlier Claude Code sessions become unavailable until you restore them. Nothing in your actual projects is harmed."
            )
        }

        switch category {
        case .cache:
            return FindingReaderGuide(
                whatItIs: "A pile of shortcuts \(who) keeps so it does not have to work things out twice.",
                whyItExists: "It stores pages, images, and calculations it has already done, so the next time round is quicker.",
                necessity: "Safe to clear. This is the genuinely disposable kind of clutter — \(who) rebuilds what it needs, usually within seconds.",
                risk: .low,
                riskExplanation: "The first launch afterwards feels a little slow while it refills. That is the entire cost."
            )
        case .logs:
            return FindingReaderGuide(
                whatItIs: "A written record of what \(who) has been doing — mostly interesting when something goes wrong.",
                whyItExists: "\(Who) writes these so a crash or a bug can be traced back to its cause later.",
                necessity: "Safe to clear, unless you are in the middle of chasing a problem right now.",
                risk: .low,
                riskExplanation: "Nothing breaks. You simply lose the paper trail — so if something is misbehaving today, tidy this after you have solved it, not before."
            )
        case .downloadedModels:
            return FindingReaderGuide(
                whatItIs: "An AI model that \(who) downloaded so it can think on your Mac instead of in the cloud.",
                whyItExists: "This is the part that actually does the work — the file that makes answers possible at all.",
                necessity: "Worth keeping only if you still use this model. If you have moved on, it is dead weight taking up real room.",
                risk: .medium,
                riskExplanation: "The model stops working until it is downloaded again. On a slow or filtered connection that can mean hours — and every so often the exact version is no longer there to fetch."
            )
        case .applicationData:
            return FindingReaderGuide(
                whatItIs: "\(Who)'s own filing cabinet — notes, settings, history, extensions, whatever it keeps between launches.",
                whyItExists: "Without it, \(who) would forget everything the moment you quit.",
                necessity: "Worth a look before you touch this one. Some of it rebuilds itself; some of it is the only copy there is.",
                risk: .high,
                riskExplanation: "You could come back to an app that is signed out, reset, or missing things you set up long ago. Open the folder and read the names before you decide."
            )
        case .preferences:
            return FindingReaderGuide(
                whatItIs: "A small file holding your settings for \(who) — your choices, not your content.",
                whyItExists: "It was created the first time you changed something away from the default.",
                necessity: "Keep it, unless you genuinely want a fresh start with \(who).",
                risk: .medium,
                riskExplanation: "\(Who) opens up with everything back at factory settings. Your files are untouched — only your preferences go."
            )
        case .conversationData:
            return FindingReaderGuide(
                whatItIs: "Your conversations with \(who), stored here on this Mac.",
                whyItExists: "So you can look back, search, and pick up where you left off.",
                necessity: "Keep it if that history matters to you. Nothing rebuilds it.",
                risk: .high,
                riskExplanation: "Those conversations disappear from the app. Having an account is not the same as having them synced — assume anything kept only here is kept only here."
            )
        case .credentials:
            return FindingReaderGuide(
                whatItIs: "The keys and tokens that let \(who) sign in as you.",
                whyItExists: "So you do not have to type your password every single time.",
                necessity: "Keep it. This is never worth the few kilobytes it would save.",
                risk: .high,
                riskExplanation: "You would be signed out and have to log in again — and if it holds something you no longer have, you might not get back in at all. Housekeeping refuses known credential locations outright."
            )
        case .projectData:
            return FindingReaderGuide(
                whatItIs: "Your actual work — a project or workspace with source, documents, and data in it.",
                whyItExists: "You made this. It is not housekeeping.",
                necessity: "Keep it. Clear a project only when you know it is finished and you have a copy of it elsewhere.",
                risk: .high,
                riskExplanation: "The whole folder leaves its place. Anything pointing at that path — an editor, a script, a scheduled job — stops finding it until you put it back."
            )
        case .pythonEnvironment:
            return FindingReaderGuide(
                whatItIs: "A private set of Python packages built for one tool, kept separate from everything else.",
                whyItExists: "So this tool's libraries cannot collide with any other tool's.",
                necessity: "Rebuildable, as long as the dependency list is complete. Keep it if you would rather not find out whether yours is.",
                risk: .medium,
                riskExplanation: "The tool will not start until the environment is rebuilt — and if a version was never pinned anywhere, you may not get the same one back."
            )
        case .shared:
            return FindingReaderGuide(
                whatItIs: "Something more than one tool reads from — a shared cache, or a common store of packages.",
                whyItExists: "So the same thing is not downloaded and kept several times over.",
                necessity: "Worth a look first. It might be doing nothing at all, or half your tools might quietly be running on it.",
                risk: .high,
                riskExplanation: "Several apps can be affected at once, and the refill can be large. Worth knowing who uses it before you decide."
            )
        case .unknown:
            return FindingReaderGuide(
                whatItIs: "Something Housekeeping found but could not identify.",
                whyItExists: "There was not enough evidence to say whose it is or what it does.",
                necessity: "Keep it for now. Not knowing is itself a good reason to leave it alone.",
                risk: .unknown,
                riskExplanation: "Housekeeping cannot tell you what happens, so it will not pretend to know. Open the folder, have a look, and decide once you recognise it."
            )
        }
    }
}

// MARK: - Path display

extension URL {
    /// `/Users/Morad/Library/Logs` becomes `~/Library/Logs`. A path outside the
    /// home directory is returned unchanged.
    ///
    /// Every row in the list lives under the same home directory, so that prefix
    /// says nothing about any one of them — and it is the part that gets dropped
    /// first when a long path is cut short to fit. Removing it is what lets the
    /// part that actually differs between two rows survive.
    var homeAbbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let full = path
        guard full == home || full.hasPrefix(home + "/") else { return full }
        return "~" + full.dropFirst(home.count)
    }
}
