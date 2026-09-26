// Housekeeping — Update models
//
// Updating software is not one action. A Homebrew cask is a command and an
// answer; a Mac App Store app belongs to the store and can only be asked; an app
// that arrived as a file from a GitHub release or a vendor's own feed has to be
// fetched and swapped, and that is a different kind of risk from either.
//
// So the thing this feature deals in is not "apps" but *channels*, and every
// screen below is built on that split. A single "Update All" that ran one
// command over everything would be wrong for at least three of the four.

import Foundation

// MARK: - Channels

/// Where an application's updates actually come from. This is decided by
/// evidence on disk — a receipt, a package manager's own list, a feed URL, a
/// signature — never by the application's name.
enum UpdateChannel: String, Codable, CaseIterable {
    /// Installed by `brew install --cask`. Housekeeping can update it itself.
    case homebrewCask
    /// A Homebrew formula: a command-line tool or library, no `.app` bundle.
    case homebrewFormula
    /// Carries a Mac App Store receipt. Only the store can update it.
    case macAppStore
    /// A `.app` downloaded from a GitHub release. Fetchable, but the replacement
    /// has to be checked before it goes in.
    case githubRelease
    /// A `.app` that carries its own update feed (Sparkle or the same shape).
    /// The application already knows how to update itself; Housekeeping reads
    /// that feed and can fetch the same enclosure the application would.
    case sparkleFeed
    /// Ships with macOS and is updated by the system, not by anything here.
    case systemSoftware
    /// Evidence does not establish where it came from. Listed, explained, and
    /// not updateable by Housekeeping.
    case unidentified

    /// Group order on screen: the channels Housekeeping can actually finish come
    /// first, then the ones that need the store or a download, then the rest.
    var order: Int {
        switch self {
        case .homebrewCask: return 0
        case .homebrewFormula: return 1
        case .macAppStore: return 2
        case .githubRelease: return 3
        case .sparkleFeed: return 4
        case .systemSoftware: return 5
        case .unidentified: return 6
        }
    }

    var title: String {
        switch self {
        case .homebrewCask: return "Homebrew applications"
        case .homebrewFormula: return "Homebrew packages"
        case .macAppStore: return "Mac App Store"
        case .githubRelease: return "From GitHub releases"
        case .sparkleFeed: return "Applications that update themselves"
        case .systemSoftware: return "Part of macOS"
        case .unidentified: return "Where this came from is unclear"
        }
    }

    /// What Housekeeping does for this channel, said as one line rather than
    /// implied by a button. This is the sentence that keeps "Update All" honest.
    var method: String {
        switch self {
        case .homebrewCask:
            return "Housekeeping runs `brew upgrade --cask` for each one. Homebrew checks the checksum, so this is the safest update in the list."
        case .homebrewFormula:
            return "Housekeeping runs `brew upgrade` for these. They are command-line tools and libraries, not applications."
        case .macAppStore:
            return "Only the App Store can install these, because the receipt Apple issued has to be honoured. Housekeeping asks the store to update them and reports what it was told."
        case .githubRelease:
            return "Housekeeping downloads the new release and swaps the application. It checks the signature against the copy you already have first, and puts the old one back if anything fails."
        case .sparkleFeed:
            return "These carry their own update feed. Housekeeping reads it for the new version and can fetch the same download the application's own updater would, under the same checks."
        case .systemSoftware:
            return "Updated by macOS itself, under System Settings → General → Software Update. Housekeeping will not touch these."
        case .unidentified:
            return "Housekeeping can say what it found and cannot say what it means. Nothing here is updated."
        }
    }

    /// Whether Housekeeping is willing to perform an update on this channel by
    /// itself. False is not a gap to be filled later; for the App Store it is the
    /// only correct answer, and for the unidentified channel it is the point.
    var canInstall: Bool {
        switch self {
        case .homebrewCask, .homebrewFormula, .githubRelease, .sparkleFeed: return true
        case .macAppStore, .systemSoftware, .unidentified: return false
        }
    }
}

// MARK: - Provenance

/// What the evidence on disk says an application is. Deliberately separate from
/// `UpdateChannel`: an altered copy is a provenance answer, and the reason it has
/// no channel is the answer itself.
enum Provenance: Equatable {
    /// A receipt from Apple, and the signature still matches it.
    case macAppStore
    /// A Homebrew cask, named by Homebrew rather than guessed from the folder.
    case homebrewCask(token: String)
    case homebrewFormula(name: String)
    /// The signature names a developer team and the feed says GitHub.
    case githubRelease(repo: String)
    /// Carries an update feed and a developer-team signature.
    case sparkleFeed(url: URL?)
    /// Signed by a developer team, with nothing to say where it was downloaded.
    case signedByDeveloper(team: String)
    /// No signature worth the name and nothing to explain it. Not an accusation:
    /// applications built locally and some regional distributions land here.
    case unsignedOrSelfSigned
    /// The copy has been modified after signing, or was repackaged by someone who
    /// is not the developer. Housekeeping reports it and does not touch it.
    case alteredCopy(reasons: [String])
    /// Ships with macOS.
    case appleSystem

    var isAltered: Bool {
        if case .alteredCopy = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .macAppStore: return "Mac App Store"
        case .homebrewCask: return "Homebrew cask"
        case .homebrewFormula: return "Homebrew formula"
        case .githubRelease: return "GitHub release"
        case .sparkleFeed: return "Own update feed"
        case .signedByDeveloper(let team): return "Signed by \(team)"
        case .unsignedOrSelfSigned: return "Unsigned"
        case .alteredCopy: return "Signature does not match its origin"
        case .appleSystem: return "macOS"
        }
    }

    var channel: UpdateChannel {
        switch self {
        case .macAppStore: return .macAppStore
        case .homebrewCask: return .homebrewCask
        case .homebrewFormula: return .homebrewFormula
        case .githubRelease: return .githubRelease
        case .sparkleFeed: return .sparkleFeed
        case .appleSystem: return .systemSoftware
        case .signedByDeveloper, .unsignedOrSelfSigned, .alteredCopy: return .unidentified
        }
    }
}

/// One fact, and what it was read from. The screens show these rather than a
/// verdict alone, because a reader who disagrees with Housekeeping should be able
/// to see exactly which observation they disagree with.
struct ProvenanceEvidence: Equatable, Codable {
    let finding: String
    let source: String
}

// MARK: - An installed application

/// One `.app` bundle found on disk, with everything established about it.
struct InstalledApplication: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let path: String
    let version: String
    let build: String?
    /// The developer team the signature names, when it names one.
    let team: String?
    /// True when the signature is ad-hoc or absent, which is what a locally
    /// built application and a patched commercial one look like alike.
    let isAdHoc: Bool
    /// The update feed the bundle itself declares, if any.
    let feedURL: URL?
    let provenance: Provenance
    let evidence: [ProvenanceEvidence]

    var id: String { bundleIdentifier }
    var channel: UpdateChannel { provenance.channel }
    var url: URL { URL(fileURLWithPath: path) }

    /// The name shown in a row. A bundle with no readable identifier still needs
    /// something, and the folder name is what the reader sees in the Finder.
    var displayVersion: String { version.isEmpty ? "unknown version" : version }
}

// MARK: - What a check came back with

/// A Homebrew package with no `.app` of its own. It is not an application, so it
/// gets its own row type rather than being forced into the application list.
struct BrewPackage: Identifiable, Equatable {
    let name: String
    let isCask: Bool
    let installedVersion: String
    let currentVersion: String
    let isPinned: Bool

    var id: String { (isCask ? "cask:" : "formula:") + name }
    var channel: UpdateChannel { isCask ? .homebrewCask : .homebrewFormula }
}

/// A download Housekeeping is willing to make, once it has decided to.
struct UpdateDownload: Equatable {
    let url: URL
    /// The version the download claims to be, for the row to show.
    let version: String
    let kind: DownloadKind

    enum DownloadKind: String, Equatable {
        case diskImage
        case zip
        case other
    }
}

/// The answer to "is there a newer one", kept as a three-way answer for the same
/// reason the version footer is: a failure to find out is not news that you are
/// current, and a row that said so would leave someone on an old copy.
enum UpdateCheck: Equatable {
    case checking
    case current
    /// A newer version exists. Carries its number, and the download to use when
    /// the channel is one Housekeeping installs for.
    case available(version: String, download: UpdateDownload?)
    /// Asked and not answered: offline, throttled, no feed, no mapping.
    case unknown(reason: String)
    /// Answered, and the answer is that this copy must not be updated: it has
    /// been altered, or it belongs to the system.
    case refused(reason: String)

    var newerVersion: String? {
        if case .available(let version, _) = self { return version }
        return nil
    }

    var shortLabel: String {
        switch self {
        case .checking: return "Checking…"
        case .current: return "Up to date"
        case .available(let version, _): return "\(version) available"
        case .unknown: return "Could not check"
        case .refused: return "Not updated"
        }
    }
}

// MARK: - Rows on screen

/// One line of the update list: an application or package, its channel, what the
/// check found, and whether the reader has said to leave it alone.
struct UpdateRow: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let channel: UpdateChannel
    let installedVersion: String
    let check: UpdateCheck
    /// How the update is applied for this row, when it can be.
    let action: UpdateAction?
    /// True when the reader has told Housekeeping to stop offering this one.
    /// Not `let`: the left-alone list can change while the list is on screen, and
    /// the row has to be able to say so without a whole new reading.
    var isExcepted: Bool
    /// True when the reader ticked it. Default comes from the channel: the ones
    /// Housekeeping can finish safely are ticked, the ones it cannot are not.
    var isSelected: Bool
    let evidence: [ProvenanceEvidence]
    let path: String?

    var canUpdate: Bool { action != nil && !isExcepted }

    /// Whether this row is ticked when the list first appears. Only the channels
    /// Housekeeping can complete end to end, only when the copy is genuine, and
    /// never when the reader has already said otherwise.
    static func defaultSelection(channel: UpdateChannel, check: UpdateCheck, isExcepted: Bool) -> Bool {
        guard !isExcepted, channel.canInstall else { return false }
        // Ticked on "there is something to do", not on "there is a download".
        // Homebrew knows its own versions and hands back no URL at all, so asking
        // for one would leave every formula and cask unticked in a list whose whole
        // point is that they can be updated.
        guard case .available = check else { return false }
        return true
    }
}

/// What Housekeeping will actually do for one row.
enum UpdateAction: Equatable {
    /// `brew upgrade --cask <token>` or `brew upgrade <formula>`.
    case brewPackage(name: String, isCask: Bool)
    /// `mas upgrade <id>` — the store's own tool, when it is installed and the
    /// reader is signed in.
    case appStoreUpgrade(adamID: String)
    /// Open the store's Updates page instead. The honest fallback when there is
    /// no `mas`, because the receipt can only be honoured by the store.
    case openAppStoreUpdates
    /// Fetch the URL, check it, swap the bundle, keep the old one until it works.
    case replaceBundle(download: UpdateDownload)

    var isSelfService: Bool {
        if case .openAppStoreUpdates = self { return false }
        return true
    }
}

/// The outcome of one row's update, as reported afterwards.
struct UpdateOutcome: Identifiable, Equatable {
    let id: String
    let name: String
    let message: String
    let succeeded: Bool
}
