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
    var beadsID: String?
    var issueType: String?
    var status: String?
    var parentBeadsID: String?
    var childBeadsIDs: [String]
    var dependencyBeadsIDs: [String]
    var dependentBeadsIDs: [String]
    var dependencyCount: Int
    var dependentCount: Int
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
        beadsID: String? = nil,
        issueType: String? = nil,
        status: String? = nil,
        parentBeadsID: String? = nil,
        childBeadsIDs: [String] = [],
        dependencyBeadsIDs: [String] = [],
        dependentBeadsIDs: [String] = [],
        dependencyCount: Int = 0,
        dependentCount: Int = 0,
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
        self.beadsID = beadsID
        self.issueType = issueType
        self.status = status
        self.parentBeadsID = parentBeadsID
        self.childBeadsIDs = childBeadsIDs
        self.dependencyBeadsIDs = dependencyBeadsIDs
        self.dependentBeadsIDs = dependentBeadsIDs
        self.dependencyCount = dependencyCount
        self.dependentCount = dependentCount
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

    var hasRelationshipMetadata: Bool {
        parentBeadsID != nil
            || !childBeadsIDs.isEmpty
            || !dependencyBeadsIDs.isEmpty
            || !dependentBeadsIDs.isEmpty
            || dependencyCount > 0
            || dependentCount > 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case beadsID
        case issueType
        case status
        case parentBeadsID
        case childBeadsIDs
        case dependencyBeadsIDs
        case dependentBeadsIDs
        case dependencyCount
        case dependentCount
        case title
        case summary
        case sourceType
        case sourceURL
        case branchName
        case issueNumber
        case pullRequestNumber
        case labels
        case priority
        case isBlocked
        case isStale
        case notes
        case createdAt
        case updatedAt
        case archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        beadsID = try container.decodeIfPresent(String.self, forKey: .beadsID)
        issueType = try container.decodeIfPresent(String.self, forKey: .issueType)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        parentBeadsID = try container.decodeIfPresent(String.self, forKey: .parentBeadsID)
        childBeadsIDs = try container.decodeIfPresent([String].self, forKey: .childBeadsIDs) ?? []
        dependencyBeadsIDs = try container.decodeIfPresent([String].self, forKey: .dependencyBeadsIDs) ?? []
        dependentBeadsIDs = try container.decodeIfPresent([String].self, forKey: .dependentBeadsIDs) ?? []
        dependencyCount = try container.decodeIfPresent(Int.self, forKey: .dependencyCount) ?? dependencyBeadsIDs.count
        dependentCount = try container.decodeIfPresent(Int.self, forKey: .dependentCount) ?? dependentBeadsIDs.count
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceType = try container.decodeIfPresent(BeadSourceType.self, forKey: .sourceType) ?? .manual
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
        issueNumber = try container.decodeIfPresent(Int.self, forKey: .issueNumber)
        pullRequestNumber = try container.decodeIfPresent(Int.self, forKey: .pullRequestNumber)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        priority = try container.decodeIfPresent(BeadPriority.self, forKey: .priority) ?? .normal
        isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? false
        isStale = try container.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}
