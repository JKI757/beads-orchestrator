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

enum BeadsProjectImportError: LocalizedError {
    case noBeadsDirectory(String)
    case unreadableIssues(String)

    var errorDescription: String? {
        switch self {
        case .noBeadsDirectory(let path):
            "No .beads project was found at \(path)."
        case .unreadableIssues(let path):
            "Could not read beads issues at \(path)."
        }
    }
}

struct BeadsProjectImporter {
    static func hasBeadsProject(at url: URL) -> Bool {
        let rootURL = normalizedProjectRoot(for: url)
        return FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".beads", isDirectory: true).path(percentEncoded: false))
    }

    static func issuesModificationDate(at url: URL) -> Date? {
        let rootURL = normalizedProjectRoot(for: url)
        let issuesURL = rootURL
            .appendingPathComponent(".beads", isDirectory: true)
            .appendingPathComponent("issues.jsonl")

        guard
            let values = try? issuesURL.resourceValues(forKeys: [.contentModificationDateKey])
        else {
            return nil
        }

        return values.contentModificationDate
    }

    static func importBoard(from url: URL, defaultColumns: [BoardColumn]) throws -> Board {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let rootURL = normalizedProjectRoot(for: url)
        let rootPath = rootURL.path(percentEncoded: false)
        let beadsDirectoryURL = rootURL.appendingPathComponent(".beads", isDirectory: true)
        guard FileManager.default.fileExists(atPath: beadsDirectoryURL.path(percentEncoded: false)) else {
            throw BeadsProjectImportError.noBeadsDirectory(rootPath)
        }

        var columns = defaultColumns
        let issuesURL = beadsDirectoryURL.appendingPathComponent("issues.jsonl")
        if FileManager.default.fileExists(atPath: issuesURL.path(percentEncoded: false)) {
            let importedIssues = try readIssues(from: issuesURL)
            for issue in importedIssues {
                let columnName = columnName(for: issue.status)
                let columnIndex = columns.firstIndex { $0.name == columnName } ?? 0
                columns[columnIndex].beads.append(issue.makeBead())
            }
        }

        return Board(
            name: rootURL.lastPathComponent,
            repositoryName: rootURL.lastPathComponent,
            repositoryPath: rootPath,
            columns: columns
        )
    }

    private static func normalizedProjectRoot(for url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        return standardizedURL.lastPathComponent == ".beads"
            ? standardizedURL.deletingLastPathComponent()
            : standardizedURL
    }

    private static func readIssues(from url: URL) throws -> [BeadsIssueRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw BeadsProjectImportError.unreadableIssues(url.path(percentEncoded: false))
        }

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let data = Data(line.utf8)
                return try? JSONDecoder.beadsIssuesDecoder.decode(BeadsIssueRecord.self, from: data)
            }
    }

    private static func columnName(for status: String?) -> String {
        switch status?.lowercased() {
        case "closed", "done", "resolved":
            "Done"
        case "in_progress", "in-progress", "started", "doing":
            "In Progress"
        case "blocked":
            "Blocked"
        case "review", "in_review", "in-review":
            "Review"
        case "ready":
            "Ready"
        default:
            "Backlog"
        }
    }
}

private struct BeadsIssueRecord: Decodable {
    var id: String?
    var title: String?
    var description: String?
    var acceptanceCriteria: String?
    var status: String?
    var priority: Int?
    var issueType: String?
    var createdAt: Date?
    var updatedAt: Date?
    var closedAt: Date?
    var closeReason: String?
    var labels: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case acceptanceCriteria = "acceptance_criteria"
        case status
        case priority
        case issueType = "issue_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case closeReason = "close_reason"
        case labels
    }

    func makeBead() -> Bead {
        let issueTitle = title?.nilIfBlank ?? id ?? "Untitled bead"
        let issueLabels = Array(Set((labels ?? []) + [issueType?.nilIfBlank].compactMap(\.self))).sorted()
        let notes = [
            id.map { "Beads ID: \($0)" },
            acceptanceCriteria?.nilIfBlank.map { "Acceptance Criteria:\n\($0)" },
            closeReason?.nilIfBlank.map { "Close Reason: \($0)" }
        ]
            .compactMap(\.self)
            .joined(separator: "\n\n")

        return Bead(
            title: issueTitle,
            summary: description ?? "",
            sourceType: .manual,
            labels: issueLabels,
            priority: beadPriority,
            isBlocked: status?.localizedCaseInsensitiveContains("blocked") ?? false,
            notes: notes,
            createdAt: createdAt ?? updatedAt ?? .now,
            updatedAt: updatedAt ?? createdAt ?? .now
        )
    }

    private var beadPriority: BeadPriority {
        guard let priority else { return .normal }
        switch priority {
        case ...0:
            return .urgent
        case 1:
            return .high
        case 2:
            return .normal
        default:
            return .low
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
        []
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

    var nilIfBlank: String? {
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

    static var beadsIssuesDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
