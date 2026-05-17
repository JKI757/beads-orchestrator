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
    @Published var localRefreshStatusMessage: String?

    private let persistenceURL: URL
    private var localBoardModificationDates: [Board.ID: Date] = [:]

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

        return selectedBoardBeads.first { $0.id == selectedBeadID }
    }

    var selectedBoardBeads: [Bead] {
        selectedBoard?.columns.flatMap(\.beads) ?? []
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

    func selectBead(beadsID: String) {
        guard let bead = bead(beadsID: beadsID) else { return }
        selectedBeadID = bead.id
    }

    func bead(beadsID: String) -> Bead? {
        selectedBoardBeads.first { $0.relationshipID == beadsID || $0.beadsID == beadsID }
    }

    func parentBead(for bead: Bead) -> Bead? {
        guard let parentBeadsID = bead.parentBeadsID else { return nil }
        return self.bead(beadsID: parentBeadsID)
    }

    func childBeads(for bead: Bead) -> [Bead] {
        beads(for: bead.childBeadsIDs)
    }

    func dependencyBeads(for bead: Bead) -> [Bead] {
        beads(for: bead.dependencyBeadsIDs)
    }

    func dependentBeads(for bead: Bead) -> [Bead] {
        beads(for: bead.dependentBeadsIDs)
    }

    func possibleParentBeads(excluding beadID: Bead.ID? = nil) -> [Bead] {
        selectedBoardBeads
            .filter { !$0.isArchived && $0.id != beadID }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func visibleBeads(in column: BoardColumn) -> [Bead] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeBeads = column.beads.filter { !$0.isArchived }

        return activeBeads.filter { bead in
            let matchesSearch = trimmedSearch.isEmpty
                || bead.title.localizedCaseInsensitiveContains(trimmedSearch)
                || bead.summary.localizedCaseInsensitiveContains(trimmedSearch)
                || bead.notes.localizedCaseInsensitiveContains(trimmedSearch)
                || (bead.beadsID?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                || (bead.issueType?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                || (bead.status?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                || (bead.parentBeadsID?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)
                || bead.childBeadsIDs.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
                || bead.dependencyBeadsIDs.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
                || bead.dependentBeadsIDs.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
                || bead.labels.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
                || (bead.branchName?.localizedCaseInsensitiveContains(trimmedSearch) ?? false)

            let matchesSource = sourceFilter == nil || bead.sourceType == sourceFilter
            let matchesAttention = !attentionOnly || bead.isBlocked || bead.isStale || bead.priority == .urgent

            return matchesSearch && matchesSource && matchesAttention
        }
    }

    func visibleBeads(in board: Board) -> [Bead] {
        board.columns.flatMap { visibleBeads(in: $0) }
    }

    func columnName(for bead: Bead) -> String? {
        selectedBoard?.columns.first { column in
            column.beads.contains { $0.id == bead.id }
        }?.name
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

    func importBeadsProject(at url: URL) {
        importErrorMessage = nil
        do {
            let board = try BeadsProjectImporter.importBoard(from: url, defaultColumns: Self.defaultColumns)
            boards.insert(board, at: 0)
            localBoardModificationDates[board.id] = BeadsProjectImporter.issuesModificationDate(at: url)
            select(board)
            persist()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func refreshLocalBoardFromDisk(_ boardID: Board.ID, reportsErrors: Bool = true) {
        guard
            let boardIndex = boards.firstIndex(where: { $0.id == boardID }),
            let repositoryPath = boards[boardIndex].repositoryPath?.nilIfBlank
        else { return }

        let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        do {
            var refreshedBoard = try BeadsProjectImporter.importBoard(from: repositoryURL, defaultColumns: Self.defaultColumns)
            let previousBoard = boards[boardIndex]
            refreshedBoard.id = previousBoard.id
            refreshedBoard.name = previousBoard.name
            refreshedBoard.archivedAt = previousBoard.archivedAt
            refreshedBoard.columns = Self.preservingExistingBeadIDs(
                in: refreshedBoard.columns,
                from: previousBoard.columns
            )
            refreshedBoard.updatedAt = .now
            boards[boardIndex] = refreshedBoard
            localBoardModificationDates[boardID] = BeadsProjectImporter.issuesModificationDate(at: repositoryURL)

            if selectedBoardID == boardID, selectedBead == nil {
                selectedBeadID = refreshedBoard.columns.flatMap(\.beads).first { !$0.isArchived }?.id
            }

            localRefreshStatusMessage = "Refreshed \(refreshedBoard.name) from disk"
            persist()
        } catch {
            if reportsErrors {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshLocalBoardsFromDiskIfChanged() {
        for board in boards {
            guard let repositoryPath = board.repositoryPath?.nilIfBlank else { continue }
            let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
            guard let modificationDate = BeadsProjectImporter.issuesModificationDate(at: repositoryURL) else { continue }

            if localBoardModificationDates[board.id] == nil {
                localBoardModificationDates[board.id] = modificationDate
                continue
            }

            if localBoardModificationDates[board.id] != modificationDate {
                refreshLocalBoardFromDisk(board.id, reportsErrors: false)
            }
        }
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

    @discardableResult
    func createBead(in columnID: BoardColumn.ID? = nil, draft: BeadDraft) -> Bead? {
        guard let boardIndex = indexOfSelectedBoard else { return nil }
        let targetColumnID = columnID ?? selectedColumnID ?? boards[boardIndex].columns.first?.id
        guard let columnIndex = boards[boardIndex].columns.firstIndex(where: { $0.id == targetColumnID }) else { return nil }

        let bead = draft.makeBead()
        boards[boardIndex].columns[columnIndex].beads.insert(bead, at: 0)
        reconcileParentLink(for: bead, previousParentID: nil)
        boards[boardIndex].updatedAt = .now
        selectedBeadID = bead.id
        persist()
        return bead
    }

    @discardableResult
    func createChildBead(parent: Bead, draft: BeadDraft) -> Bead? {
        var childDraft = draft
        childDraft.parentBeadsID = parent.relationshipID
        return createBead(draft: childDraft)
    }

    func updateBead(_ beadID: Bead.ID, with draft: BeadDraft) {
        guard let indexes = indexes(forBeadID: beadID) else { return }
        let existingBead = boards[indexes.board].columns[indexes.column].beads[indexes.bead]
        var bead = draft.makeBead(id: beadID)
        bead.createdAt = existingBead.createdAt
        bead.archivedAt = existingBead.archivedAt
        bead.updatedAt = .now
        boards[indexes.board].columns[indexes.column].beads[indexes.bead] = bead
        reconcileParentLink(for: bead, previousParentID: existingBead.parentBeadsID)
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
            remoteStatusMessage = "Downloaded \(boards.count) boards from Mac"
        } catch {
            remoteStatusMessage = error.localizedDescription
        }
    }

    func pullFromRemoteServerIfPaired() async {
        guard remoteConfiguration.isPaired else { return }
        await pullFromRemoteServer()
    }

    func pushToRemoteServer() async {
        do {
            try await remoteClient.replaceBoards(boards)
            remoteServerInfo = try? await remoteClient.health()
            remoteStatusMessage = "Overwrote Mac with \(boards.count) local boards"
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

    private func beads(for beadsIDs: [String]) -> [Bead] {
        let beadsByNativeID = Dictionary(
            selectedBoardBeads.map { bead in
                (bead.relationshipID, bead)
            },
            uniquingKeysWith: { existing, _ in existing }
        )
        return beadsIDs.compactMap { beadsByNativeID[$0] }
    }

    private func reconcileParentLink(for bead: Bead, previousParentID: String?) {
        let childID = bead.relationshipID

        if let previousParentID, previousParentID != bead.parentBeadsID {
            mutateBead(relationshipID: previousParentID) { parent in
                parent.childBeadsIDs.removeAll { $0 == childID }
            }
        }

        if let parentID = bead.parentBeadsID {
            mutateBead(relationshipID: parentID) { parent in
                if !parent.childBeadsIDs.contains(childID) {
                    parent.childBeadsIDs.append(childID)
                    parent.childBeadsIDs.sort()
                }
            }
        }
    }

    private func mutateBead(relationshipID: String, update: (inout Bead) -> Void) {
        guard let boardIndex = indexOfSelectedBoard else { return }
        for columnIndex in boards[boardIndex].columns.indices {
            guard let beadIndex = boards[boardIndex].columns[columnIndex].beads.firstIndex(where: { $0.relationshipID == relationshipID }) else {
                continue
            }
            update(&boards[boardIndex].columns[columnIndex].beads[beadIndex])
            boards[boardIndex].columns[columnIndex].beads[beadIndex].updatedAt = .now
            return
        }
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
                let client = BeadsServerClient(baseURL: url, pairingToken: configuration.pairingToken)
                let remoteBoards = try await client.boards()
                let mergedBoards = Self.mergingBoardsForCanonicalPush(localBoards: boards, remoteBoards: remoteBoards)
                try await client.replaceBoards(mergedBoards)
                replaceBoards(mergedBoards)
                remoteStatusMessage = "Saved to Mac server"
            } catch {
                remoteStatusMessage = "Saved locally; server update failed: \(error.localizedDescription)"
            }
        }
    }

    private static func mergingBoardsForCanonicalPush(localBoards: [Board], remoteBoards: [Board]) -> [Board] {
        var localBoardsByID = Dictionary(uniqueKeysWithValues: localBoards.map { ($0.id, $0) })

        var mergedBoards = remoteBoards.map { remoteBoard in
            guard let localBoard = localBoardsByID.removeValue(forKey: remoteBoard.id) else {
                return remoteBoard
            }

            return localBoard.updatedAt >= remoteBoard.updatedAt ? localBoard : remoteBoard
        }

        let localOnlyBoards = localBoards.filter { localBoardsByID[$0.id] != nil }
        mergedBoards.append(contentsOf: localOnlyBoards)
        return mergedBoards
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
        if let beadsID = bead.beadsID {
            return "beads|\(beadsID)"
        }

        return [
            bead.sourceType.rawValue,
            bead.branchName ?? "",
            bead.issueNumber.map(String.init) ?? "",
            bead.pullRequestNumber.map(String.init) ?? "",
            bead.title
        ].joined(separator: "|")
    }

    private static func preservingExistingBeadIDs(
        in refreshedColumns: [BoardColumn],
        from previousColumns: [BoardColumn]
    ) -> [BoardColumn] {
        let existingBeadsByKey = Dictionary(
            previousColumns
                .flatMap(\.beads)
                .map { (localDiskRefreshKey(for: $0), $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        return refreshedColumns.map { column in
            var refreshedColumn = column
            refreshedColumn.beads = refreshedColumn.beads.map { bead in
                guard let existingBead = existingBeadsByKey[localDiskRefreshKey(for: bead)] else {
                    return bead
                }

                var refreshedBead = bead
                refreshedBead.id = existingBead.id
                return refreshedBead
            }
            return refreshedColumn
        }
    }

    private static func localDiskRefreshKey(for bead: Bead) -> String {
        if let beadsID = bead.beadsID {
            return "beads|\(beadsID)"
        }

        if let firstLine = bead.notes
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { $0.hasPrefix("Beads ID: ") }) {
            return firstLine
        }

        return [bead.title, bead.summary, bead.labels.joined(separator: ",")].joined(separator: "|")
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
    var beadsID: String?
    var issueType: String?
    var status: String?
    var parentBeadsID: String?
    var childBeadsIDs: [String] = []
    var dependencyBeadsIDs: [String] = []
    var dependentBeadsIDs: [String] = []
    var dependencyCount = 0
    var dependentCount = 0
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
        beadsID = bead.beadsID
        issueType = bead.issueType
        status = bead.status
        parentBeadsID = bead.parentBeadsID
        childBeadsIDs = bead.childBeadsIDs
        dependencyBeadsIDs = bead.dependencyBeadsIDs
        dependentBeadsIDs = bead.dependentBeadsIDs
        dependencyCount = bead.dependencyCount
        dependentCount = bead.dependentCount
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
            beadsID: beadsID,
            issueType: issueType,
            status: status,
            parentBeadsID: parentBeadsID,
            childBeadsIDs: childBeadsIDs,
            dependencyBeadsIDs: dependencyBeadsIDs,
            dependentBeadsIDs: dependentBeadsIDs,
            dependencyCount: dependencyCount,
            dependentCount: dependentCount,
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
