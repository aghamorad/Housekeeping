import Foundation

// Housekeeping — the commit check
//
// The published releases for this repository lag well behind `main`, so a check
// built on the releases feed would report "you are current" for a copy that is
// months old. The live signal is the commit history, and GitHub's compare
// endpoint is the one call that answers the question that actually matters: not
// "what is the newest thing" but "how far behind am I, and what would I get".
//
// No token is used. The repository is public, and the endpoint answers without
// one — but it answers with a 403 rather than an error body when the request
// carries no `User-Agent`, so that header is not optional.

/// Reads the published commit history for Housekeeping's repository.
final class SelfUpdateChecker {
    static let owner = "aghamorad"
    static let repo = "Housekeeping"
    static let branch = "main"
    static let slug = "\(owner)/\(repo)"
    static let repositoryURL = URL(string: "https://github.com/\(owner)/\(repo)")!

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 24
        // A cached answer to "what is the newest commit" is the one answer that
        // must not be stale, and `URLSession` would otherwise happily serve one
        // from an earlier check in the same launch.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// Compares the commit this copy was built from against the head of the
    /// published branch.
    ///
    /// A copy with no provenance is not compared at all — there is nothing to
    /// compare — but the newest published commit is still fetched, so the screen
    /// can show what exists while saying plainly that it does not know how this
    /// copy relates to it.
    func check(provenance: BuildProvenance) async -> SelfUpdateState {
        guard let local = provenance.commit else {
            let latest = try? await newestCommit()
            return .unknown(
                reason: "This copy was built from a source folder and does not record which commit it came from, so there is nothing to compare it against. Builds made by the release script carry that stamp.",
                latest: latest
            )
        }
        return await compare(local: local)
    }

    /// The one comparison that matters. `compare/{base}...{head}` reports
    /// `ahead_by` as the number of commits `head` has that `base` does not, so
    /// with this copy's commit as the base, `ahead_by` is exactly how far behind
    /// this copy is.
    private func compare(local: String) async -> SelfUpdateState {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.slug)/compare/\(local)...\(Self.branch)") else {
            return .unknown(reason: "Housekeeping could not form the address to ask about its own commits.", latest: nil)
        }

        switch await get(url) {
        case .failure(let reason):
            return .unknown(reason: reason, latest: nil)

        case .success(let data):
            guard let payload = try? JSONDecoder().decode(ComparePayload.self, from: data) else {
                return .unknown(reason: "GitHub answered, but not with a comparison Housekeeping could read.", latest: nil)
            }

            let commits = (payload.commits ?? []).map(\.asCommit).reversed()

            // `identical` and `behind` both mean this copy has nothing to
            // collect: the first is level with `main`, the second is ahead of it
            // — a build from a commit that was later rewritten or reverted.
            // Neither is a reason to offer an update.
            if payload.status == "identical" || payload.status == "behind" {
                return .upToDate(
                    SelfUpdateReport(
                        localCommit: local,
                        remoteCommit: payload.commits?.last?.sha ?? local,
                        behindBy: 0,
                        commits: []
                    )
                )
            }

            guard payload.status == "ahead" else {
                return .unknown(
                    reason: "This copy was built from a commit that has since left the published history, so there is no straight line between the two. Updating by hand is the honest answer here.",
                    latest: payload.commits?.last?.asCommit
                )
            }

            let behind = payload.ahead_by ?? commits.count
            let report = SelfUpdateReport(
                localCommit: local,
                remoteCommit: payload.commits?.last?.sha ?? "",
                behindBy: behind,
                commits: Array(commits)
            )
            return .available(report)
        }
    }

    private func newestCommit() async throws -> SelfUpdateCommit? {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.slug)/commits/\(Self.branch)?per_page=1") else {
            return nil
        }
        switch await get(url) {
        case .success(let data):
            return try? JSONDecoder().decode([CommitPayload].self, from: data).first?.asCommit
        case .failure:
            return nil
        }
    }

    // MARK: - Transport

    private enum Answer {
        case success(Data)
        case failure(String)
    }

    private func get(_ url: URL) async -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Housekeeping", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200...299:
                return .success(data)
            case 404:
                return .failure("GitHub does not know the commit this copy was built from. It may have been built from a branch that was never published.")
            case 403, 429:
                return .failure("GitHub is refusing requests from this machine right now (rate limit or network). That is not the same as being up to date — try again later.")
            default:
                return .failure("GitHub answered with status \(status), so Housekeeping could not find out what the newest commit is.")
            }
        } catch {
            return .failure("Housekeeping could not reach GitHub. That is not the same as being up to date — try again when the connection is back.")
        }
    }

    // MARK: - Wire formats

    private struct ComparePayload: Decodable {
        let status: String
        let ahead_by: Int?
        let behind_by: Int?
        let commits: [CommitPayload]?
    }

    private struct CommitPayload: Decodable {
        let sha: String
        let commit: Inner
        let author: Person?

        struct Inner: Decodable {
            let message: String
            let author: Person?
        }

        struct Person: Decodable {
            let name: String?
            let date: String?
        }

        var asCommit: SelfUpdateCommit {
            SelfUpdateCommit(
                sha: sha,
                message: commit.message,
                author: commit.author?.name ?? author?.name ?? "unknown",
                date: (commit.author?.date ?? author?.date).flatMap(BuildProvenance.parseDate)
            )
        }
    }
}
