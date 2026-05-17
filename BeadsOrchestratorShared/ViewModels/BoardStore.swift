import Foundation
import Combine

@MainActor
final class BoardStore: ObservableObject {
    @Published var boards: [Board]
    @Published var selectedBoardID: Board.ID?
    @Published var selectedBeadID: Bead.ID?
    @Published var searchText = ""
    @Published var sourceFilter: BeadSourceType?
    @Published var attentionOnly = false
    @Published var lastRepositorySnapshot: RepositorySnapshot?
    @Published var importErrorMessage: String?
    @Published var remoteConfiguration = BeadsRemoteConfiguration(serverURLString: "")
    @Published var remoteStatusMessage = "Not connected"
    @Published var remoteServerInfo: BeadsServerInfo?

    private let persistenceURL: URL

    init(
        boards: [Board]? = nil,
        persistenceURL: URL = BoardStore.defaultPersistenceURL
    ) {
        self.persistenceURL = persistenceURL

        let loadedBoards = boards ?? Self.loadBoards(from: persistenceURL) ?? []
        let initialBoards = Self.removingBundledSampleContent(from: loadedBoards)
        self.boards = initialBoards
        self.selectedBoardID = initialBoards.first?.id
        self.selectedBeadID = initialBoards.first?.columns.first?.beads.first?.id
        self.remoteConfiguration = Self.loadRemoteConfiguration()
        if initialBoards != loadedBoards {
            persist(syncRemote: false)
        }
    }

    var selectedBoard: Board? {
        activeBoards.first { $0.id == selectedBoardID }
    }

    var activeBoards: [Board] {
        boards.filter { !$0.isArchived }
    }

    var selectedBead: Bead? {
        guard let selectedBeadID else { return nil }

        return selectedBoard?.columns
            .flatMap(\.beads)
            .first { $0.id == selectedBeadID }
    }

    var selectedColumnID: BoardColumn.ID? {
        guard let selectedBeadID else { return selectedBoard?.columns.first?.id }
        return selectedBoard?.columns.first { column in
            column.beads.contains { $0.id == selectedBeadID }
        }?.id
    }

    func select(_ board: Board) {
        selectedBoardID = board.id
        selectedBeadID = board.columns.flatMap(\.beads).first { !$0.isArchived }?.id
    }

    func select(_ bead: Bead) {
        selectedBeadID = bead.id
    }

    func visibleBeads(in column: BoardColumn) -> [Bead] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeBeads = column.beads.filter { !$0.isArchived }

        return activeBeads.filter { bead in
            let matchesSearch = trimmedSearch.isEmpty
                || bead.title.localizedCaseInsensitiveContains(trimmedSearch)
                || bead.summary.localizedCaseInsensitiveContains(trimmedSearch)
                || bead.notes.localizedCaseInsensitiveContains(trimmedSearch)
                || bead.labels.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
                || (bead.branchName?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)

            let matchesSource = sourceFilter == nil || bead.sourceType == sourceFilter
            let matchesAttention = !attentionOnly || bead.isBlocked || bead.isStale || bead.priority == .urgent

            return matchesSearch && matchesSource && matchesAttention
        }
    }

    func createBoard(name: String, repositoryName: String, repositoryPath: String? = nil) {
        let board = Board(
            name: name,
            repositoryName: repositoryName,
            repositoryPath: repositoryPath,
            columns: Self.defaultColumns
        )
        boards.insert(board, at: 0)
        select(board)
        persist()
    }

    func updateSelectedBoard(name: String, repositoryName: String, repositoryPath: String?) {
        guard let boardIndex = indexOfSelectedBoard else { return }
        boards[boardIndex].name = name
        boards[boardIndex].repositoryName = repositoryName
        boards[boardIndex].repositoryPath = repositoryPath?.nilIfBlank
        boards[boardIndex].updatedAt = .now
        persist()
    }

    func archiveSelectedBoard() {
        guard let boardIndex = indexOfSelectedBoard else { return }
        boards[boardIndex].archivedAt = .now
        selectedBoardID = activeBoards.first?.id
        selectedBeadID = activeBoards.first?.columns.flatMap(\.beads).first?.id
        persist()
    }

    func addColumn(named name: String) {
        guard let boardIndex = indexOfSelectedBoard else { return }
        boards[boardIndex].columns.append(BoardColumn(name: name))
        boards[boardIndex].updatedAt = .now
        persist()
    }

    func renameColumn(_ columnID: BoardColumn.ID, name: String) {
        guard let indexes = indexes(forColumnID: columnID) else { return }
        boards[indexes.board].columns[indexes.column].name = name
        boards[indexes.board].updatedAt = .now
        persist()
    }

    func createBead(in columnID: BoardColumn.ID? = nil, draft: BeadDraft) {
        guard let boardIndex = indexOfSelectedBoard else { return }
        let targetColumnID = columnID ?? selectedColumnID ?? boards[boardIndex].columns.first?.id
        guard let columnIndex = boards[boardIndex].columns.firstIndex(where: { $0.id == targetColumnID }) else { return }

        let bead = draft.makeBead()
        boards[boardIndex].columns[columnIndex].beads.insert(bead, at: 0)
        boards[boardIndex].updatedAt = .now
        selectedBeadID = bead.id
        persist()
    }

    func updateBead(_ beadID: Bead.ID, with draft: BeadDraft) {
        guard let indexes = indexes(forBeadID: beadID) else { return }
        var bead = draft.makeBead(id: beadID)
        bead.createdAt = boards[indexes.board].columns[indexes.column].beads[indexes.bead].createdAt
        bead.archivedAt = boards[indexes.board].columns[indexes.column].beads[indexes.bead].archivedAt
        bead.updatedAt = .now
        boards[indexes.board].columns[indexes.column].beads[indexes.bead] = bead
        boards[indexes.board].updatedAt = .now
        persist()
    }

    func archiveBead(_ beadID: Bead.ID) {
        guard let indexes = indexes(forBeadID: beadID) else { return }
        boards[indexes.board].columns[indexes.column].beads[indexes.bead].archivedAt = .now
        boards[indexes.board].columns[indexes.column].beads[indexes.bead].updatedAt = .now
        boards[indexes.board].updatedAt = .now
        selectedBeadID = selectedBoard?.columns.flatMap(\.beads).first { !$0.isArchived }?.id
        persist()
    }

    func moveBead(_ beadID: Bead.ID, to columnID: BoardColumn.ID) {
        guard
            let source = indexes(forBeadID: beadID),
            let boardIndex = indexOfSelectedBoard,
            let destinationColumnIndex = boards[boardIndex].columns.firstIndex(where: { $0.id == columnID })
        else { return }

        var bead = boards[source.board].columns[source.column].beads.remove(at: source.bead)
        bead.updatedAt = .now
        boards[boardIndex].columns[destinationColumnIndex].beads.insert(bead, at: 0)
        boards[boardIndex].updatedAt = .now
        selectedBeadID = beadID
        persist()
    }

    func replaceBoards(_ boards: [Board]) {
        self.boards = boards
        if selectedBoard == nil {
            selectedBoardID = activeBoards.first?.id
        }
        if selectedBead == nil {
            selectedBeadID = selectedBoard?.columns.flatMap(\.beads).first { !$0.isArchived }?.id
        }
        persist(syncRemote: false)
    }

    func saveRemoteConfiguration(_ configuration: BeadsRemoteConfiguration) {
        remoteConfiguration = configuration
        remoteServerInfo = nil
        remoteStatusMessage = "Not connected"
        Self.persistRemoteConfiguration(configuration)
    }

    func testRemoteConnection() async {
        do {
            let info = remoteConfiguration.isPaired
                ? try await remoteClient.verifyPairing()
                : try await remoteClient.health()
            remoteServerInfo = info
            remoteStatusMessage = remoteConfiguration.isPaired ? "Paired with \(info.name)" : "Server reachable; pairing required"
        } catch {
            remoteServerInfo = nil
            remoteStatusMessage = error.localizedDescription
        }
    }

    func pullFromRemoteServer() async {
        do {
            let boards = try await remoteClient.boards()
            replaceBoards(boards)
            remoteServerInfo = try? await remoteClient.health()
            remoteStatusMessage = "Pulled \(boards.count) boards"
        } catch {
            remoteStatusMessage = error.localizedDescription
        }
    }

    func pushToRemoteServer() async {
        do {
            try await remoteClient.replaceBoards(boards)
            remoteServerInfo = try? await remoteClient.health()
            remoteStatusMessage = "Updated Mac server with \(boards.count) boards"
        } catch {
            remoteStatusMessage = error.localizedDescription
        }
    }

    func addImportedBeads(_ beads: [Bead], toColumnNamed columnName: String = "Ready") {
        guard let boardIndex = indexOfSelectedBoard, !beads.isEmpty else { return }
        let columnIndex = boards[boardIndex].columns.firstIndex { $0.name == columnName } ?? 0
        let existingKeys = Set(boards[boardIndex].columns.flatMap(\.beads).map(Self.dedupeKey(for:)))
        let newBeads = beads.filter { !existingKeys.contains(Self.dedupeKey(for: $0)) }
        boards[boardIndex].columns[columnIndex].beads.insert(contentsOf: newBeads, at: 0)
        boards[boardIndex].updatedAt = .now
        selectedBeadID = newBeads.first?.id ?? selectedBeadID
        persist()
    }

    #if os(macOS)
    func importLocalRepository(at url: URL) async {
        importErrorMessage = nil
        do {
            let source = LocalGitRepositorySource(repositoryURL: url)
            let snapshot = try await source.snapshot()
            lastRepositorySnapshot = snapshot

            if selectedBoard == nil {
                createBoard(
                    name: snapshot.repositoryName,
                    repositoryName: snapshot.repositoryName,
                    repositoryPath: snapshot.repositoryPath
                )
            } else if let boardIndex = indexOfSelectedBoard {
                boards[boardIndex].repositoryName = snapshot.repositoryName
                boards[boardIndex].repositoryPath = snapshot.repositoryPath
            }

            let beads = try await source.suggestedBeads()
            addImportedBeads(beads)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
    #endif

    func persist(syncRemote: Bool = true) {
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.beadsEncoder.encode(boards)
            try data.write(to: persistenceURL, options: [.atomic])
            if syncRemote {
                pushCacheToCanonicalServer()
            }
        } catch {
            importErrorMessage = "Could not save boards: \(error.localizedDescription)"
        }
    }

    private var indexOfSelectedBoard: Int? {
        guard let selectedBoardID else { return nil }
        return boards.firstIndex { $0.id == selectedBoardID }
    }

    private func indexes(forColumnID columnID: BoardColumn.ID) -> (board: Int, column: Int)? {
        guard let boardIndex = indexOfSelectedBoard else { return nil }
        guard let columnIndex = boards[boardIndex].columns.firstIndex(where: { $0.id == columnID }) else { return nil }
        return (boardIndex, columnIndex)
    }

    private func indexes(forBeadID beadID: Bead.ID) -> (board: Int, column: Int, bead: Int)? {
        guard let boardIndex = indexOfSelectedBoard else { return nil }
        for columnIndex in boards[boardIndex].columns.indices {
            if let beadIndex = boards[boardIndex].columns[columnIndex].beads.firstIndex(where: { $0.id == beadID }) {
                return (boardIndex, columnIndex, beadIndex)
            }
        }
        return nil
    }

    private static func loadBoards(from url: URL) -> [Board]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.beadsDecoder.decode([Board].self, from: data)
    }

    private var remoteClient: BeadsServerClient {
        get throws {
            guard let url = remoteConfiguration.serverURL else {
                throw BeadsNetworkError.invalidServerURL
            }
            return BeadsServerClient(baseURL: url, pairingToken: remoteConfiguration.pairingToken)
        }
    }

    private func pushCacheToCanonicalServer() {
        guard remoteConfiguration.isPaired else { return }
        let boards = boards
        let configuration = remoteConfiguration

        Task {
            do {
                guard let url = configuration.serverURL else {
                    throw BeadsNetworkError.invalidServerURL
                }
                try await BeadsServerClient(baseURL: url, pairingToken: configuration.pairingToken)
                    .replaceBoards(boards)
                remoteStatusMessage = "Saved to Mac server"
            } catch {
                remoteStatusMessage = "Saved locally; server update failed: \(error.localizedDescription)"
            }
        }
    }

    private static func loadRemoteConfiguration() -> BeadsRemoteConfiguration {
        guard
            let data = try? Data(contentsOf: remoteConfigurationURL),
            let configuration = try? BeadsJSON.decoder.decode(BeadsRemoteConfiguration.self, from: data)
        else {
            return BeadsRemoteConfiguration(serverURLString: "")
        }
        return configuration
    }

    private static func persistRemoteConfiguration(_ configuration: BeadsRemoteConfiguration) {
        do {
            let directory = remoteConfigurationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try BeadsJSON.encoder.encode(configuration)
            try data.write(to: remoteConfigurationURL, options: [.atomic])
        } catch {
            // Connection settings are non-critical; the UI reports connection failures directly.
        }
    }

    private static func dedupeKey(for bead: Bead) -> String {
        [
            bead.sourceType.rawValue,
            bead.branchName ?? "",
            bead.issueNumber.map(String.init) ?? "",
            bead.pullRequestNumber.map(String.init) ?? "",
            bead.title
        ].joined(separator: "|")
    }

    private static func removingBundledSampleContent(from boards: [Board]) -> [Board] {
        boards.compactMap { board in
            var migratedBoard = board
            migratedBoard.columns = migratedBoard.columns.map { column in
                var migratedColumn = column
                migratedColumn.beads = migratedColumn.beads.filter { !isBundledSampleBead($0) }
                return migratedColumn
            }

            let isEmptyDefaultSampleBoard = migratedBoard.name == "Beads Orchestrator"
                && migratedBoard.repositoryName == "Beads-Orchestrator"
                && migratedBoard.repositoryPath == nil
                && migratedBoard.columns.map(\.name) == defaultColumns.map(\.name)
                && migratedBoard.columns.allSatisfy { $0.beads.isEmpty }

            return isEmptyDefaultSampleBoard ? nil : migratedBoard
        }
    }

    private static func isBundledSampleBead(_ bead: Bead) -> Bool {
        switch (bead.title, bead.summary) {
        case ("Design local Git scanner", "Read branches, remotes, dirty files, and recent commits without mutating the repository."),
             ("Define import rules", "Keep the first generated board focused on active PRs, assigned issues, and local changes."),
             ("Create shared SwiftUI board", "Reusable kanban columns and bead cards for macOS, iPadOS, and iOS."),
             ("Scaffold single Xcode project", "One project with iOS/iPadOS and macOS targets consuming shared source."),
             ("Confirm GitHub OAuth scopes", "Choose minimum scopes for issue and pull request import."),
             ("Review board terminology", "Decide whether the UI says bead, card, or both."):
            true
        default:
            false
        }
    }

    private static var defaultColumns: [BoardColumn] {
        ["Backlog", "Ready", "In Progress", "Blocked", "Review", "Done"].map { BoardColumn(name: $0) }
    }

    private nonisolated static var defaultPersistenceURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Beads-Orchestrator", isDirectory: true)
            .appendingPathComponent("boards.json")
    }

    private nonisolated static var remoteConfigurationURL: URL {
        defaultPersistenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("remote-server.json")
    }
}

struct BeadDraft {
    var title = ""
    var summary = ""
    var sourceType: BeadSourceType = .manual
    var sourceURL: URL?
    var branchName = ""
    var issueNumber: Int?
    var pullRequestNumber: Int?
    var labelsText = ""
    var priority: BeadPriority = .normal
    var isBlocked = false
    var isStale = false
    var notes = ""

    init() {}

    init(bead: Bead) {
        title = bead.title
        summary = bead.summary
        sourceType = bead.sourceType
        sourceURL = bead.sourceURL
        branchName = bead.branchName ?? ""
        issueNumber = bead.issueNumber
        pullRequestNumber = bead.pullRequestNumber
        labelsText = bead.labels.joined(separator: ", ")
        priority = bead.priority
        isBlocked = bead.isBlocked
        isStale = bead.isStale
        notes = bead.notes
    }

    func makeBead(id: UUID = UUID()) -> Bead {
        Bead(
            id: id,
            title: title.nilIfBlank ?? "Untitled bead",
            summary: summary,
            sourceType: sourceType,
            sourceURL: sourceURL,
            branchName: branchName.nilIfBlank,
            issueNumber: issueNumber,
            pullRequestNumber: pullRequestNumber,
            labels: labelsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            priority: priority,
            isBlocked: isBlocked,
            isStale: isStale,
            notes: notes
        )
    }
}

private extension JSONEncoder {
    static var beadsEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var beadsDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
