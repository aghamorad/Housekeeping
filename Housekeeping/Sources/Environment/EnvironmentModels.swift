// Housekeeping — the setup audit: what it found, and what can be done about it
//
// Everything the app knows about the *shape* of a Mac — which copy of a command
// actually runs, what the shell's search path looks like once the profile files
// have had their say, whether Homebrew's links are intact, whether a second
// package manager is quietly winning, whether a symlink points at something that
// moved.
//
// The cleaner's model is a file: it has a path, a size, and a category. None of
// that describes any of the failures here. A duplicated `yt-dlp` is not a large
// file, it is a *wrong answer to a question* — `which yt-dlp` returns a path that
// is not the one the package manager thinks it installed. So a finding here is
// not a path and a size; it is a claim, the evidence for the claim, and the one
// action that makes the claim false.
//
// Two rules run through the file.
//
// The first is that a fix is only offered when the app can state, in one
// sentence, why running it is safe and what puts it back. A finding with no such
// sentence gets `steps` instead — commands written out for the reader to run
// themselves — and no checkbox. The Python framework and the MacPorts tree are
// both in that group: they are owned by the system, so moving them needs an
// administrator, and an item quarantined by an administrator is one Housekeeping
// can no longer put back with the same click. Handing over the command is the
// honest version of that.
//
// The second is that nothing here is inferred from a name. Every finding is
// built from a path that was read, a symlink that was resolved, or a command's
// own output. A name that looks like a duplicate but resolves into the right
// place is not reported, because reporting it would train the reader to ignore
// the screen.

import Foundation

// MARK: - The groups

/// How a finding is grouped on screen. The grouping is the reader's map: a
/// Mac-wide audit with one flat list of forty rows is a wall, and the first
/// question anyone asks is "what kind of problem is this".
enum EnvironmentCategory: String, CaseIterable, Identifiable {
    /// The yt-dlp class: a command name that resolves to a copy the package
    /// manager did not put there.
    case shadowing
    /// The Hermes class: a symlink whose target has gone, and a configuration
    /// file naming a program that no longer exists.
    case brokenLinks
    /// The shell's own search path: entries repeated, entries that lead nowhere.
    case shellPath
    /// Homebrew's own links, dependencies, taps and formulae.
    case homebrew
    /// Two package managers installed at once, and which one is winning.
    case packageManagers
    /// Language runtimes installed outside a package manager.
    case runtimes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shadowing: return "Commands that run the wrong copy"
        case .brokenLinks: return "Links that lead nowhere"
        case .shellPath: return "Your shell's search path"
        case .homebrew: return "Homebrew's own health"
        case .packageManagers: return "Two package managers"
        case .runtimes: return "Runtimes installed by hand"
        }
    }

    /// The group's contract, written above its rows rather than hidden in a
    /// tooltip. Each one says what was read and what the app will and will not
    /// do about it, because those differ by group and the reader should not have
    /// to guess which group they are in.
    var method: String {
        switch self {
        case .shadowing:
            return "For every Homebrew formula with programs in it, Housekeeping walked your search path to see which file would actually run. A name is only reported when the copy that wins is not the one Homebrew installed. Reported names can be re-linked, or the stray copy moved to Quarantine."
        case .brokenLinks:
            return "Every entry in the standard binary folders was followed to its target. A link whose target has gone is reported; where the same program still exists inside the same application bundle, the link is re-pointed at it. Links that lead nowhere can be moved to Quarantine. Configuration files that name a missing program are read only, never rewritten — Housekeeping has no business editing another application's settings."
        case .shellPath:
            return "Your profile files were read and assembled in the order a shell would read them. Repeated entries inside one file can be tidied, with a copy of the original kept beside it. An entry repeated across two different files is reported but left alone: which file should keep it depends on whether a shell is a login shell, and Housekeeping cannot know that. A line that sets the path from a command's output is counted but not interpreted, because reading is not running."
        case .homebrew:
            return "This is Homebrew's own report on itself, read rather than re-derived, with each name checked against the list of what is actually installed. Unlinked packages can be linked. Deprecated packages, missing dependencies, and third-party taps are offered but never pre-ticked, because each of them can affect something else."
        case .packageManagers:
            return "Two package managers on one Mac each keep their own copy of common tools, and the one earlier in your search path wins. Housekeeping lists the names they both provide and can move the older one later in the path — a change to one line of your profile, with a backup. Removing a package manager outright is written out as commands rather than done here."
        case .runtimes:
            return "Language runtimes installed outside any package manager, and whether anything on this Mac still points at them. Nothing is changed in this group: runtimes live in system folders, which need an administrator, and an item moved by an administrator is one Housekeeping cannot restore on its own. What you get is the list of what still refers to it."
        }
    }

    var order: Int {
        switch self {
        case .shadowing: return 0
        case .brokenLinks: return 1
        case .homebrew: return 2
        case .shellPath: return 3
        case .packageManagers: return 4
        case .runtimes: return 5
        }
    }
}

/// How much is actually wrong. Kept separate from the group because the two
/// answer different questions: the group says what kind of thing this is, the
/// severity says whether it is costing anything today.
enum EnvironmentSeverity {
    /// Something does not work, or does not do what it says.
    case broken
    /// Everything works, but not the copy you think you are running.
    case shadowed
    /// Nothing is broken. This is drift, and it will confuse someone later.
    case untidy

    var label: String {
        switch self {
        case .broken: return "Not working"
        case .shadowed: return "Wrong copy"
        case .untidy: return "Untidy"
        }
    }
}

// MARK: - The one action

/// The single thing Housekeeping will do about a finding. One action per
/// finding, deliberately: a fix that is really a sequence is a script, and a
/// script is something the reader cannot judge from one sentence.
enum EnvironmentFix: Equatable {
    /// `brew link`, which points Homebrew's shared folders at a package it has
    /// installed but not linked. `overwrite` is the yt-dlp case: a file is
    /// already sitting where the link wants to go, and Homebrew will not touch
    /// it without being told to.
    case brewLink(formula: String, overwrite: Bool)
    /// Stops Homebrew tracking a third-party tap. Packages already installed
    /// from it stay installed.
    case brewUntap(tap: String)
    /// Installs a dependency Homebrew says is missing. Downloads over the
    /// network, so it is never pre-ticked.
    case brewInstall(formula: String)
    /// Removes a formula. Only ever offered for something Homebrew itself has
    /// marked deprecated or disabled, and never pre-ticked.
    case brewUninstall(formula: String)
    /// The whole yt-dlp shape in one action: move the copy that is winning out
    /// of the way, then let Homebrew own the name again.
    case unshadow(formula: String, stray: String?)
    /// Moves a path into the app's Quarantine folder, with the same record an
    /// ordinary cleanup writes, so the same screen puts it back.
    case quarantine(path: String)
    /// Points a symlink at the file inside the same application bundle that the
    /// link was always meant to reach.
    case repointSymlink(path: String, target: String)
    /// Rewrites one profile file with the corrected lines, keeping a copy of the
    /// original beside it.
    case rewriteShellConfig(path: String, newContents: String)

    /// What the button says. Written out per case rather than assembled from the
    /// pieces, because "Link cjson" and "Link yt-dlp over the old copy" are
    /// different sentences, not one sentence with a name dropped into it.
    var label: String {
        switch self {
        case .brewLink(let name, false): return "Link \(name)"
        case .brewLink(_, true): return "Let Homebrew replace it"
        case .brewUntap(let tap): return "Stop tracking \(tap)"
        case .brewInstall(let name): return "Install \(name)"
        case .brewUninstall(let name): return "Remove \(name)"
        case .unshadow(let formula, let stray):
            return stray == nil ? "Let Homebrew take the name back" : "Move the old \(formula) aside"
        case .quarantine: return "Move to Quarantine"
        case .repointSymlink: return "Point it at the right file"
        case .rewriteShellConfig: return "Tidy the file"
        }
    }

    /// What running it changes, and what puts it back. Every fix on this screen
    /// has one of these; a finding that could not have one has no fix at all.
    var explanation: String {
        switch self {
        case .brewLink(let name, let overwrite):
            let base = overwrite
                ? "Homebrew will replace whatever is sitting in its folder with a link to the \(name) it installed."
                : "Homebrew will point its shared folders at the \(name) already in its cellar."
            return base + " `brew unlink \(name)` undoes it."
        case .brewUntap(let tap):
            return "Homebrew stops tracking \(tap). Anything already installed from it stays installed and keeps working; you simply stop receiving formula updates from it. `brew tap \(tap)` adds it back."
        case .brewInstall(let name):
            return "Downloads and installs \(name) from Homebrew. This is the package the installed one says it needs. `brew uninstall \(name)` undoes it."
        case .brewUninstall(let name):
            return "Removes \(name) and leaves its files in Homebrew's cellar. Anything that depends on it will notice, which is why this is not ticked for you. `brew install \(name)` puts it back."
        case .unshadow(let formula, let stray):
            if let stray {
                return "Moves \(stray) to Quarantine — Housekeeping's own recovery folder, so the same screen can put it back — then links Homebrew's \(formula) into place. Nothing is deleted."
            }
            return "Homebrew will replace the existing file with a link to the \(formula) in its cellar. The file it replaces is the one Homebrew itself installed earlier, so nothing you put there by hand is touched unless it is the only copy of the name. `brew unlink \(formula)` undoes it."
        case .quarantine:
            return "Moves it to Quarantine, where it can be put back from the same screen that restores everything else. Nothing is deleted."
        case .repointSymlink:
            return "Re-creates the link so it points at the file that is there now. The link that was there is replaced, not deleted, and the file it points at does not move."
        case .rewriteShellConfig:
            return "Writes the corrected file and keeps the original beside it as a dated backup. Your next new terminal window reads the new one; nothing already running is affected."
        }
    }

    /// Whether the action touches Homebrew, so the sheet can run the whole
    /// batch through one lock and skip the rest when `brew` is not installed.
    var needsHomebrew: Bool {
        switch self {
        case .brewLink, .brewUntap, .brewInstall, .brewUninstall, .unshadow: return true
        case .quarantine, .repointSymlink, .rewriteShellConfig: return false
        }
    }
}

// MARK: - One finding

struct EnvironmentFinding: Identifiable, Equatable {
    /// Stable across readings, so a selection survives a re-check. Built from
    /// the thing the finding is about — the path, or the command name — never
    /// from an index into the list.
    let id: String
    let category: EnvironmentCategory
    let severity: EnvironmentSeverity
    /// The headline, in the reader's terms rather than the tool's. "yt-dlp runs
    /// an older copy than the one Homebrew installed" beats "shadowed binary".
    let title: String
    /// One sentence saying what that actually means for the reader.
    let summary: String
    /// The facts the claim was worked out from: paths, symlink targets, the
    /// command's own words. Shown when the reader wants to check the working.
    let evidence: [String]
    /// Commands for the reader to run when Housekeeping will not act. Present
    /// and non-empty only on findings with no `fix`.
    let steps: [String]
    /// What the app will do, when it will do anything.
    let fix: EnvironmentFix?
    /// Whether the row starts ticked. Only ever true for a change that is
    /// reversible by the reader in one command and affects nothing else.
    var isSelected: Bool

    /// Whether this row can be run at all. The footer's count and the run
    /// itself use this same property, so the number on screen and the number of
    /// things that happen cannot disagree.
    var canFix: Bool { fix != nil }

    /// The path this finding is about, when it is about one, so a reading can
    /// drop a row whose subject has gone between being read and being shown — a
    /// fix offered for a file that is no longer there can only fail.
    var subjectPath: String? {
        switch fix {
        case .quarantine(let path), .repointSymlink(let path, _), .rewriteShellConfig(let path, _):
            return path
        case .unshadow(_, let stray):
            return stray
        case .brewLink, .brewInstall, .brewUninstall, .brewUntap, .none:
            return nil
        }
    }

    /// The sentence that says why this one is or is not ticked for the reader,
    /// shown on the row rather than in a tooltip.
    var note: String {
        if fix == nil {
            return steps.isEmpty
                ? "Housekeeping reports this one and changes nothing."
                : "Housekeeping will not run this. The commands below are yours to run if you want them."
        }
        if isSelected { return "Ticked for you." }
        return "Left unticked: this one can affect something else, so you should decide."
    }
}

// MARK: - A whole reading

struct EnvironmentReport {
    var findings: [EnvironmentFinding]
    /// Things the reading noticed but did not turn into findings: which files
    /// the search path was assembled from, a command that was missing, a file
    /// that could not be read.
    var notes: [String]

    static let empty = EnvironmentReport(findings: [], notes: [])
}

/// The result of running one fix, in the same shape the update sheet uses so the
/// two screens report outcomes the same way.
struct EnvironmentOutcome: Identifiable, Equatable {
    let id: String
    let name: String
    let message: String
    let succeeded: Bool
}
