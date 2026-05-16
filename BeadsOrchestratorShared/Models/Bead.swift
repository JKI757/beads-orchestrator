import Foundation

enum BeadSourceType: String, CaseIterable, Codable, Identifiable {
    case manual
    case localGit
    case githubIssue
    case githubPullRequest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .localGit: "Local Git"
        case .githubIssue: "GitHub Issue"
        case .githubPullRequest: "GitHub PR"
        }
    }
}

enum BeadPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case normal
    case high
    case urgent

    var id: String { rawValue }
}

struct Bead: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var summary: String
    var sourceType: BeadSourceType
    var sourceURL: URL?
    var branchName: String?
    var issueNumber: Int?
    var pullRequestNumber: Int?
    var labels: [String]
    var priority: BeadPriority
    var isBlocked: Bool
    var isStale: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        sourceType: BeadSourceType = .manual,
        sourceURL: URL? = nil,
        branchName: String? = nil,
        issueNumber: Int? = nil,
        pullRequestNumber: Int? = nil,
        labels: [String] = [],
        priority: BeadPriority = .normal,
        isBlocked: Bool = false,
        isStale: Bool = false,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.branchName = branchName
        self.issueNumber = issueNumber
        self.pullRequestNumber = pullRequestNumber
        self.labels = labels
        self.priority = priority
        self.isBlocked = isBlocked
        self.isStale = isStale
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = nil
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}
