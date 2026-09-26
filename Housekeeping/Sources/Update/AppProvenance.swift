import Foundation

// Housekeeping — Update provenance
//
// Before Housekeeping offers to update anything, it works out what the thing is.
// That question is answered by evidence on disk and by nothing else — not by the
// name of the folder, not by what the application says about itself in a place
// it controls. A name is a claim; a receipt, a signature, a quarantine flag, and
// a feed URL are observations, and observations are what this file collects.
//
// The output is a verdict *and* the lines that produced it. The screens show
// both, because a reader who disagrees with a conclusion should be able to see
// exactly which observation they disagree with rather than being told to trust
// the app.

/// The facts about a bundle that the inventory already read, handed here so the
/// two passes do not each parse the same `Info.plist` and drift apart on what a
/// missing key means.
struct BundleFacts {
    let url: URL
    let bundleIdentifier: String
    let name: String
    /// The version string the bundle declares for display.
    let version: String
    let build: String?
    /// The update feed the bundle declares, if any.
    let feedURL: URL?
    /// True when Homebrew's own cask list names this bundle, and the token it
    /// names it by. Homebrew is the authority here: a folder called "Firefox"
    /// proves nothing, but `brew info --json` listing the token is an answer.
    let homebrewCaskToken: String?
    /// The GitHub repository this bundle's identifier maps to, when the mapping
    /// table has an entry. A mapping is a record Housekeeping keeps, not a guess:
    /// an identifier that is not in the table yields nil and the copy is treated
    /// as unidentified rather than being attributed to the nearest match.
    let githubRepo: String?

    var isUnderSystemPaths: Bool {
        AppProvenance.systemPrefixes.contains { url.path.hasPrefix($0) }
    }
}

/// What `codesign` said about a bundle. `codesign -dv` writes to the error
/// stream, not the standard one — a reader that took only stdout would see an
/// empty answer and conclude the bundle was unsigned, which is the one wrong
/// answer with consequences. The runner captures both streams for this reason.
struct CodeSignature: Equatable {
    let isSigned: Bool
    let isAdHoc: Bool
    let authorities: [String]
    let teamIdentifier: String?
    let identifier: String?

    static let unsigned = CodeSignature(
        isSigned: false, isAdHoc: false, authorities: [], teamIdentifier: nil, identifier: nil
    )
}

enum AppProvenance {
    /// The folders that belong to macOS. A bundle here is updated by the system,
    /// and the flag is checked before any of the evidence gathering, because the
    /// answer cannot be improved by more of it.
    static let systemPrefixes: [String] = [
        "/System/Applications",
        "/System/Library/CoreServices",
        "/System/Library/CoreServices/Applications",
        "/Library/Apple",
    ]

    /// Names that appear in the signature of a copy that someone other than the
    /// developer repackaged. These are the common release-group and "patcher"
    /// identities: an application signed by one of them is a modified copy of
    /// someone else's work, whatever it was before. Kept as one list on purpose —
    /// it is the kind of fact that grows, and it should grow in one place.
    ///
    /// This is a report, never a refusal to look. A copy that names one of these
    /// still gets its evidence shown and its channel stated; it is simply never
    /// updated, because there is no honest way to know what the replacement
    /// should be.
    static let knownRepackagers: [String] = [
        "TNT",
        "Antibiotics",
        "TEAM EDiSO",
        "TEAM HCiSO",
        "https://macked.app",
        "Tinycast Self-Signed",
    ]

    // MARK: - Signature

    /// Runs `codesign` over a bundle and reads its answer. Returns an unsigned
    /// result when the tool is missing or the bundle is not signed; both are
    /// ordinary findings, not errors, so this never throws.
    static func readSignature(bundleAt url: URL, using runner: ProcessRunner) async -> CodeSignature {
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: "/usr/bin/codesign",
                arguments: ["-dv", "--verbose=2", url.path],
                timeout: 20
            )
        } catch {
            return .unsigned
        }

        // `codesign` prints its report to stderr. On an unsigned bundle it also
        // exits non-zero with "code object is not signed at all", which is the
        // same finding arrived at a different way.
        let report = result.stderr.isEmpty ? result.stdout : result.stderr

        guard result.succeeded else {
            return .unsigned
        }

        var authorities: [String] = []
        var team: String?
        var identifier: String?
        var isAdHoc = false

        for line in report.split(separator: "\n") {
            if let range = line.range(of: "Authority=") {
                authorities.append(String(line[range.upperBound...]))
            } else if let range = line.range(of: "TeamIdentifier=") {
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value != "not set" { team = value }
            } else if let range = line.range(of: "Identifier=") {
                identifier = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if line.contains("Signature=adhoc") {
                isAdHoc = true
            }
        }

        // A bundle with a `_CodeSignature` directory but no authorities and no
        // ad-hoc marker is rare; treat "signed but nameless" as unsigned, because
        // an identity that names nobody is not an identity.
        let isSigned = !authorities.isEmpty || (identifier != nil && !isAdHoc)
        return CodeSignature(
            isSigned: isSigned,
            isAdHoc: isAdHoc || authorities.isEmpty,
            authorities: authorities,
            teamIdentifier: team,
            identifier: identifier
        )
    }

    // MARK: - The verdict

    /// Gathered evidence for one bundle. Every observation is added as it is made,
    /// so the verdict is a reading of this array and never a separate opinion.
    static func assess(facts: BundleFacts, using runner: ProcessRunner) async -> (Provenance, [ProvenanceEvidence]) {
        var evidence: [ProvenanceEvidence] = []

        // 1. Homebrew's own list. This is checked first because it is the only
        //    source that names the thing directly rather than inferring it, and a
        //    bundle Homebrew claims should be explained in Homebrew's terms.
        if let token = facts.homebrewCaskToken {
            evidence.append(ProvenanceEvidence(
                finding: "Homebrew lists this bundle under the cask `\(token)`.",
                source: "brew info --json=v2 --installed --cask"
            ))
            return (.homebrewCask(token: token), evidence)
        }

        // 2. A receipt from Apple. The strong signal, and the one that decides the
        //    channel: only the store can honour a receipt, so nothing else matters
        //    once this is found.
        let receipt = facts.url.appendingPathComponent("Contents/_MASReceipt/receipt")
        if FileManager.default.fileExists(atPath: receipt.path) {
            evidence.append(ProvenanceEvidence(
                finding: "The bundle carries Apple's App Store receipt.",
                source: "Contents/_MASReceipt/receipt"
            ))
            return (.macAppStore, evidence)
        }

        // 3. The system folders. Checked before signatures: a system app is
        //    signed, and would otherwise be reported as an ordinary developer
        //    copy.
        if facts.isUnderSystemPaths {
            evidence.append(ProvenanceEvidence(
                finding: "This bundle lives in a folder that belongs to macOS.",
                source: facts.url.deletingLastPathComponent().path
            ))
            return (.appleSystem, evidence)
        }

        // 4. Extended attributes. Quarantine records where a download came from;
        //    a storefront attribute is a second sign of an App Store install.
        await collectAttributeEvidence(bundleAt: facts.url, using: runner, into: &evidence)

        // 5. The signature.
        let signature = await readSignature(bundleAt: facts.url, using: runner)
        recordSignatureEvidence(signature, into: &evidence)

        // 6. Altered copies, before anything else is decided. A repackaged copy is
        //    the answer to "where did this come from" and it stops the question.
        if let altered = alteredReason(signature: signature, facts: facts) {
            return (.alteredCopy(reasons: [altered]), evidence)
        }

        // 7. The feed the bundle declares, and whether it points at GitHub.
        let githubFromFeed = facts.feedURL.flatMap { repoFromRawGitHubFeed($0) }
        let githubRepo = facts.githubRepo ?? githubFromFeed

        if let repo = githubRepo {
            if let feed = facts.feedURL {
                evidence.append(ProvenanceEvidence(
                    finding: "The bundle declares an update feed at \(feed.host ?? feed.absoluteString).",
                    source: "Info.plist SUFeedURL"
                ))
            }
            evidence.append(ProvenanceEvidence(
                finding: "The release source is the GitHub repository \(repo).",
                source: githubFromFeed != nil ? "the declared feed's host" : "Housekeeping's release-source table"
            ))
            return (.githubRelease(repo: repo), evidence)
        }

        if let feed = facts.feedURL {
            evidence.append(ProvenanceEvidence(
                finding: "The bundle declares its own update feed at \(feed.host ?? feed.absoluteString).",
                source: "Info.plist SUFeedURL"
            ))
            return (.sparkleFeed(url: feed), evidence)
        }

        // 8. A developer signature with nothing pointing anywhere. Identified as
        //    to who signed it, and honestly silent about where it was downloaded.
        if let team = signature.teamIdentifier {
            evidence.append(ProvenanceEvidence(
                finding: "The signature names the developer team \(team), with no update feed.",
                source: "the bundle's own signature"
            ))
            return (.signedByDeveloper(team: team), evidence)
        }

        // 9. Everything else. Deliberately not an accusation: a locally built
        //    application and an app from a small regional vendor look alike here,
        //    and neither has done anything wrong.
        if signature.isSigned {
            evidence.append(ProvenanceEvidence(
                finding: "The bundle is signed, but the signature names no developer team.",
                source: "the bundle's own signature"
            ))
        } else {
            evidence.append(ProvenanceEvidence(
                finding: "The bundle has no signature Housekeeping can read. This is what a locally built application looks like.",
                source: "the bundle's own signature"
            ))
        }
        return (.unsignedOrSelfSigned, evidence)
    }

    // MARK: - Pieces

    private static func collectAttributeEvidence(
        bundleAt url: URL,
        using runner: ProcessRunner,
        into evidence: inout [ProvenanceEvidence]
    ) async {
        guard let result = try? await runner.run(
            executable: "/usr/bin/xattr",
            arguments: ["-l", url.path],
            timeout: 15
        ), result.succeeded else { return }

        for line in result.stdout.split(separator: "\n") {
            let text = String(line)
            if text.contains("com.apple.quarantine") {
                evidence.append(ProvenanceEvidence(
                    finding: "The bundle carries a quarantine flag, so macOS recorded it being downloaded.",
                    source: "xattr -l"
                ))
            } else if text.contains("com.apple.provenance") {
                evidence.append(ProvenanceEvidence(
                    finding: "macOS recorded a provenance note for this copy.",
                    source: "xattr -l"
                ))
            } else if text.lowercased().contains("storefront") || text.lowercased().contains("com.apple.mas") {
                evidence.append(ProvenanceEvidence(
                    finding: "An App Store attribute is present on the bundle.",
                    source: "xattr -l"
                ))
            }
        }
    }

    private static func recordSignatureEvidence(_ signature: CodeSignature, into evidence: inout [ProvenanceEvidence]) {
        if !signature.authorities.isEmpty {
            for authority in signature.authorities {
                evidence.append(ProvenanceEvidence(
                    finding: "Signature authority: \(authority)",
                    source: "codesign -dv --verbose=2"
                ))
            }
        }
        if let team = signature.teamIdentifier {
            evidence.append(ProvenanceEvidence(
                finding: "Signature team identifier: \(team)",
                source: "codesign -dv --verbose=2"
            ))
        }
        if signature.isAdHoc {
            evidence.append(ProvenanceEvidence(
                finding: "The signature is ad-hoc: it names no certifying authority.",
                source: "codesign -dv --verbose=2"
            ))
        } else if !signature.isSigned {
            evidence.append(ProvenanceEvidence(
                finding: "The bundle is not signed.",
                source: "codesign -dv --verbose=2"
            ))
        }
    }

    /// Why a copy should be treated as repackaged, or nil when it should not.
    ///
    /// Two rules, both grounded in something observed:
    ///
    /// - A signature authority names a known repackager. The copy announces who
    ///   modified it.
    /// - The copy is ad-hoc signed but declares a vendor update feed. An
    ///   application built locally for its author does not ship a Sparkle feed,
    ///   so a feed plus no certifying signature is the shape of a download that
    ///   was stripped of its signature and patched.
    ///
    /// A plain ad-hoc bundle with no feed is *not* altered — that is the shape of
    /// an application someone built on their own Mac, and calling it altered would
    /// be the false accusation the whole careful tone of this feature exists to
    /// avoid.
    private static func alteredReason(signature: CodeSignature, facts: BundleFacts) -> String? {
        for authority in signature.authorities {
            for repackager in knownRepackagers where authority.contains(repackager) {
                return "signed by “\(repackager)”, a name used to repackage other developers' applications"
            }
        }
        if signature.isAdHoc, facts.feedURL != nil {
            return "the copy is ad-hoc signed yet declares a vendor update feed, which is the shape of a signed download that was patched"
        }
        return nil
    }

    /// `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/...` → the repo.
    /// This is how a Sparkle feed hosted in a repository names its own source.
    static func repoFromRawGitHubFeed(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        guard host == "raw.githubusercontent.com" || host == "raw.github.com" else { return nil }
        let pieces = url.path.split(separator: "/")
        guard pieces.count >= 2 else { return nil }
        return "\(pieces[0])/\(pieces[1])"
    }
}
