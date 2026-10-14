import Foundation

// Housekeeping — self-update models
//
// Housekeeping has an updater already, and it is not this one. `Sources/Update/`
// updates *other* software — Homebrew casks, App Store apps, anything that
// arrived from a release page. This module updates Housekeeping itself, which is
// a different problem with a different answer every step of the way: the thing
// being replaced is the thing doing the replacing, and there is no download to
// fetch because this repository does not publish builds.
//
// So the comparison here is between the commit this copy was built from and the
// newest commit on `main`. That requires the copy to know its own commit, which
// is why `BuildProvenance` exists at all: a version string cannot be compared to
// a commit history, and a check that pretended otherwise would tell someone on
// an old copy that they were current.

/// Which commit of Housekeeping this copy was built from.
///
/// Stamped into `Info.plist` by `script/package_release.sh` at package time. A
/// copy built by Xcode carries no stamp, and says so — `.unknown` on screen is
/// the honest answer there, not "up to date".
struct BuildProvenance: Equatable {
    let commit: String?
    let branch: String?
    let builtAt: Date?
    let version: String
    let build: String

    /// The seven-character form, which is what every screen shows. The full
    /// forty is kept for the comparison, where shortening could in principle
    /// collide.
    var shortCommit: String? {
        commit.map { String($0.prefix(7)) }
    }

    static func current(bundle: Bundle = .main) -> BuildProvenance {
        func string(_ key: String) -> String? {
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
            return value
        }

        return BuildProvenance(
            commit: string("HousekeepingSourceCommit"),
            branch: string("HousekeepingSourceBranch"),
            builtAt: string("HousekeepingBuildDate").flatMap(Self.parseDate),
            version: string("CFBundleShortVersionString") ?? "",
            build: string("CFBundleVersion") ?? ""
        )
    }

    static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }
}

/// One commit, as the repository reports it.
struct SelfUpdateCommit: Identifiable, Equatable {
    let sha: String
    let message: String
    let author: String
    let date: Date?

    var id: String { sha }
    var shortSHA: String { String(sha.prefix(7)) }

    /// The first line only. A commit body is written for someone reading the
    /// log, not for a list that has one line per row.
    var headline: String {
        let firstLine = message.split(separator: "\n", omittingEmptySubsequences: false).first
        let text = firstLine.map(String.init) ?? message
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// What a check found, beyond whether it found anything.
struct SelfUpdateReport: Equatable {
    /// `nil` when the copy has no provenance. The count below is then unknown
    /// rather than zero, which is why it is optional too.
    let localCommit: String?
    let remoteCommit: String
    let behindBy: Int?
    let commits: [SelfUpdateCommit]

    var isCurrent: Bool { behindBy == 0 }
}

/// The verdict of a check. `.unknown` is deliberately its own case and not a
/// flavour of `.upToDate`: "I could not find out" and "you are current" lead to
/// different actions, and only one of them is safe to assume.
enum SelfUpdateState: Equatable {
    case idle
    case checking
    case upToDate(SelfUpdateReport)
    case available(SelfUpdateReport)
    /// The newest published commit is carried along when it was readable, so the
    /// screen can still show something true next to the reason.
    case unknown(reason: String, latest: SelfUpdateCommit?)
}

// MARK: - The local update

/// What the app found on disk when it went looking for the tree it was built
/// from. Updating in place is only possible when that tree is still there, so
/// this is the deciding fact for whether an update can run at all.
struct SelfUpdateSource: Equatable {
    let tree: URL
    /// True when the tree's `origin` points at the published repository. A tree
    /// that is a copy somewhere else can still be updated, but pulling from it
    /// would not be pulling from the published history, and the screen says so.
    let remoteMatches: Bool
    /// The bundle being replaced. Almost always `/Applications/Housekeeping.app`
    /// or a build inside the tree itself.
    let destination: URL

    var canWriteDestination: Bool {
        FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
    }
}

/// One step of an update, in the order it happens. The screen shows these before
/// anything runs — a plan, then the same list with ticks against it — because
/// this is the one action in Housekeeping that replaces the app you are looking
/// at, and it should not be a surprise.
enum SelfUpdateStep: String, CaseIterable, Identifiable {
    case fetch
    case pull
    case build
    case verify
    case swap
    case relaunch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fetch: return "Ask the repository for new commits"
        case .pull: return "Fast-forward the source folder"
        case .build: return "Build a new copy"
        case .verify: return "Check the new copy is signed and complete"
        case .swap: return "Move the old copy aside and put the new one in"
        case .relaunch: return "Reopen Housekeeping"
        }
    }

    var detail: String {
        switch self {
        case .fetch: return "git fetch origin main"
        case .pull: return "git merge --ff-only origin/main"
        case .build: return "script/package_release.sh"
        case .verify: return "codesign --verify --deep --strict"
        case .swap: return "keeps the old copy in Application Support"
        case .relaunch: return "the old copy stays until the new one opens"
        }
    }
}

/// How a step is going. Kept per step rather than as one status line so a failed
/// run can say exactly how far it got.
enum SelfUpdateStepState: Equatable {
    case pending
    case running
    case done(String)
    case failed(String)
}

/// Why an update stopped. Every one of these leaves the installed copy alone,
/// which is the property worth preserving: there is no path here that ends with
/// no Housekeeping at all.
enum SelfUpdateFailure: Error, LocalizedError, Equatable {
    case noSource
    case dirtyTree(files: [String])
    case notFastForward
    case commandFailed(step: SelfUpdateStep, message: String)
    case buildProducedNothing(path: String)
    case stageUnwritable(path: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noSource:
            return "Housekeeping could not find the folder it was built from, and it does not download builds. Point it at the folder and it can update from there."
        case .dirtyTree(let files):
            let list = files.prefix(5).joined(separator: "\n")
            let more = files.count > 5 ? "\n…and \(files.count - 5) more" : ""
            return "The source folder has changes that are not committed, so Housekeeping will not update over them. Nothing was pulled and nothing was built.\n\n\(list)\(more)"
        case .notFastForward:
            return "The source folder has moved away from the published history, so there is no clean fast-forward. Nothing was changed. Open the folder and decide how to reconcile them."
        case .commandFailed(let step, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = trimmed.isEmpty ? "It gave no reason." : String(trimmed.suffix(600))
            return "\(step.title) did not finish.\n\n\(shown)\n\nHousekeeping's installed copy was not touched."
        case .buildProducedNothing(let path):
            return "The build finished but there is no application at \(path). The installed copy was not touched."
        case .stageUnwritable(let path):
            return "The build is ready, but Housekeeping cannot write to \(path). Move the built copy in by hand — it is in the folder named below, and it is complete."
        case .cancelled:
            return "Stopped. The installed copy was not touched."
        }
    }
}
