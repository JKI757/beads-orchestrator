import Foundation

struct BoardColumn: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var beads: [Bead]

    init(id: UUID = UUID(), name: String, beads: [Bead] = []) {
        self.id = id
        self.name = name
        self.beads = beads
    }
}

struct Board: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var repositoryName: String
    var repositoryPath: String?
    var columns: [BoardColumn]
    var updatedAt: Date
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        repositoryName: String,
        repositoryPath: String? = nil,
        columns: [BoardColumn],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.columns = columns
        self.updatedAt = updatedAt
        self.archivedAt = nil
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}
