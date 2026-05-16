import Foundation

enum RepositorySourceError: LocalizedError {
    case unsupportedPlatform
    case notGitRepository(String)
    case commandFailed(String)
    case invalidGitHubRepository(String)
    case githubRequestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "Local Git scanning is currently available on macOS."
        case .notGitRepository(let path):
            "No Git repository was found at \(path)."
        case .commandFailed(let message):
            message
        case .invalidGitHubRepository(let repository):
            "Expected a GitHub repository in owner/name form, but got \(repository)."
        case .githubRequestFailed(let statusCode):
            "GitHub returned HTTP \(statusCode)."
        }
    }
}

struct RepositorySnapshot: Hashable {
    var repositoryName: String
    var repositoryPath: String?
    var remoteURL: String?
    var currentBranch: String?
    var dirtyFileCount: Int
    var changedFiles: [String]
    var recentBranches: [String]
    var recentCommits: [String]
    var openPullRequestCount: Int
    var openIssueCount: Int
    var capturedAt: Date

    init(
        repositoryName: String,
        repositoryPath: String? = nil,
        remoteURL: String? = nil,
        currentBranch: String? = nil,
        dirtyFileCount: Int = 0,
        changedFiles: [String] = [],
        recentBranches: [String] = [],
        recentCommits: [String] = [],
        openPullRequestCount: Int = 0,
        openIssueCount: Int = 0,
        capturedAt: Date = .now
    ) {
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.remoteURL = remoteURL
        self.currentBranch = currentBranch
        self.dirtyFileCount = dirtyFileCount
        self.changedFiles = changedFiles
        self.recentBranches = recentBranches
        self.recentCommits = recentCommits
        self.openPullRequestCount = openPullRequestCount
        self.openIssueCount = openIssueCount
        self.capturedAt = capturedAt
    }
}

protocol RepositorySource {
    func snapshot() async throws -> RepositorySnapshot
    func suggestedBeads() async throws -> [Bead]
}

struct PreviewRepositorySource: RepositorySource {
    func snapshot() async throws -> RepositorySnapshot {
        RepositorySnapshot(
            repositoryName: "Beads-Orchestrator",
            repositoryPath: FileManager.default.currentDirectoryPath,
            currentBranch: "main",
            dirtyFileCount: 3,
            changedFiles: ["BeadsOrchestratorShared/ViewModels/BoardStore.swift"],
            recentBranches: ["main"],
            recentCommits: ["Scaffold SwiftUI board"],
            openPullRequestCount: 1,
            openIssueCount: 4
        )
    }

    func suggestedBeads() async throws -> [Bead] {
        BoardStore.sampleBoards[0].columns.flatMap(\.beads)
    }
}

struct GitHubRepositorySource: RepositorySource {
    let owner: String
    let repository: String
    var token: String?

    init(repositoryPath: String, token: String? = nil) throws {
        let parts = repositoryPath.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            throw RepositorySourceError.invalidGitHubRepository(repositoryPath)
        }
        self.owner = parts[0]
        self.repository = parts[1]
        self.token = token
    }

    init(owner: String, repository: String, token: String? = nil) {
        self.owner = owner
        self.repository = repository
        self.token = token
    }

    func snapshot() async throws -> RepositorySnapshot {
        async let issues = fetchIssues()
        async let pullRequests = fetchPullRequests()

        return RepositorySnapshot(
            repositoryName: "\(owner)/\(repository)",
            remoteURL: "https://github.com/\(owner)/\(repository)",
            openPullRequestCount: try await pullRequests.count,
            openIssueCount: try await issues.count,
            capturedAt: .now
        )
    }

    func suggestedBeads() async throws -> [Bead] {
        async let issues = fetchIssues()
        async let pullRequests = fetchPullRequests()

        let staleIssueDate = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        let stalePullRequestDate = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast

        let issueBeads = try await issues.map { issue in
            Bead(
                title: issue.title,
                summary: issue.body ?? "",
                sourceType: .githubIssue,
                sourceURL: issue.htmlURL,
                issueNumber: issue.number,
                labels: issue.labels.map(\.name),
                priority: .normal,
                isStale: issue.updatedAt < staleIssueDate,
                updatedAt: issue.updatedAt
            )
        }

        let pullRequestBeads = try await pullRequests.map { pullRequest in
            Bead(
                title: pullRequest.title,
                summary: pullRequest.body ?? "",
                sourceType: .githubPullRequest,
                sourceURL: pullRequest.htmlURL,
                branchName: pullRequest.head.ref,
                pullRequestNumber: pullRequest.number,
                labels: ["pr", pullRequest.state],
                priority: .high,
                isStale: pullRequest.updatedAt < stalePullRequestDate,
                updatedAt: pullRequest.updatedAt
            )
        }

        return issueBeads + pullRequestBeads
    }

    private func fetchIssues() async throws -> [GitHubIssue] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/issues?state=open&per_page=100")!
        let issues: [GitHubIssue] = try await request(url)
        return issues.filter { $0.pullRequest == nil }
    }

    private func fetchPullRequests() async throws -> [GitHubPullRequest] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/pulls?state=open&per_page=100")!
        let pullRequests: [GitHubPullRequest] = try await request(url)
        return pullRequests
    }

    private func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Beads-Orchestrator", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw RepositorySourceError.githubRequestFailed(httpResponse.statusCode)
        }
        return try JSONDecoder.githubDecoder.decode(Response.self, from: data)
    }
}

struct GitHubIssue: Decodable, Hashable {
    struct Label: Decodable, Hashable {
        var name: String
    }

    struct PullRequestMarker: Decodable, Hashable {}

    var number: Int
    var title: String
    var body: String?
    var labels: [Label]
    var htmlURL: URL
    var updatedAt: Date
    var pullRequest: PullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case body
        case labels
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case pullRequest = "pull_request"
    }
}

struct GitHubPullRequest: Decodable, Hashable {
    struct Head: Decodable, Hashable {
        var ref: String
    }

    var number: Int
    var title: String
    var body: String?
    var state: String
    var htmlURL: URL
    var updatedAt: Date
    var head: Head

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case body
        case state
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case head
    }
}

#if os(macOS)
struct LocalGitRepositorySource: RepositorySource {
    let repositoryURL: URL

    func snapshot() async throws -> RepositorySnapshot {
        let path = repositoryURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path + "/.git") else {
            throw RepositorySourceError.notGitRepository(path)
        }

        async let branch = runGit(["branch", "--show-current"])
        async let remote = runGit(["remote", "get-url", "origin"])
        async let status = runGit(["status", "--short"])
        async let branches = runGit(["branch", "--sort=-committerdate", "--format=%(refname:short)"])
        async let commits = runGit(["log", "--oneline", "-8"])

        let statusLines = try await status.lines.filter { !$0.isEmpty }
        return RepositorySnapshot(
            repositoryName: repositoryURL.lastPathComponent,
            repositoryPath: path,
            remoteURL: try? await remote.trimmedNonEmpty,
            currentBranch: try await branch.trimmedNonEmpty,
            dirtyFileCount: statusLines.count,
            changedFiles: statusLines.map(Self.changedFileName(from:)),
            recentBranches: try await Array(branches.lines.prefix(8)),
            recentCommits: try await Array(commits.lines.prefix(8)),
            capturedAt: .now
        )
    }

    func suggestedBeads() async throws -> [Bead] {
        let snapshot = try await snapshot()
        var beads: [Bead] = []

        if snapshot.dirtyFileCount > 0 {
            beads.append(
                Bead(
                    title: "Review \(snapshot.dirtyFileCount) uncommitted file\(snapshot.dirtyFileCount == 1 ? "" : "s")",
                    summary: snapshot.changedFiles.prefix(6).joined(separator: "\n"),
                    sourceType: .localGit,
                    branchName: snapshot.currentBranch,
                    labels: ["local", "working-tree"],
                    priority: .high,
                    isStale: false
                )
            )
        }

        for branch in snapshot.recentBranches where branch != snapshot.currentBranch {
            beads.append(
                Bead(
                    title: "Check branch \(branch)",
                    summary: "Recently updated branch in \(snapshot.repositoryName).",
                    sourceType: .localGit,
                    branchName: branch,
                    labels: ["branch"],
                    priority: .normal
                )
            )
        }

        for commit in snapshot.recentCommits.prefix(3) {
            beads.append(
                Bead(
                    title: "Review commit \(commit.prefix(10))",
                    summary: String(commit),
                    sourceType: .localGit,
                    branchName: snapshot.currentBranch,
                    labels: ["commit"],
                    priority: .low
                )
            )
        }

        return beads
    }

    private func runGit(_ arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            let error = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", repositoryURL.path(percentEncoded: false)] + arguments
            process.standardOutput = output
            process.standardError = error

            try process.run()
            process.waitUntilExit()

            let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw RepositorySourceError.commandFailed(errorText.isEmpty ? outputText : errorText)
            }

            return outputText
        }.value
    }

    private static func changedFileName(from statusLine: String) -> String {
        let trimmed = statusLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 3 else { return trimmed }
        return String(trimmed.dropFirst(3))
    }
}
#endif

private extension String {
    var lines: [String] {
        split(whereSeparator: \.isNewline).map(String.init)
    }

    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension JSONDecoder {
    static var githubDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
