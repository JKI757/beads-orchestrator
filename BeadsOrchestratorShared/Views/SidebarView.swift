import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: BoardStore
    #if os(macOS)
    private let localRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    #endif

    var body: some View {
        List(selection: $store.selectedBoardID) {
            Section("Boards") {
                ForEach(store.activeBoards) { board in
                    BoardRow(board: board)
                        .tag(board.id)
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        #endif
        .navigationTitle("Beads-Orchestrator")
        #if os(macOS)
        .onReceive(localRefreshTimer) { _ in
            store.refreshLocalBoardsFromDiskIfChanged()
        }
        #endif
    }
}

private struct BoardRow: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(board.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(board.repositoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(activeBeadCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            #if os(macOS)
            if canRefreshFromDisk {
                Button {
                    store.refreshLocalBoardFromDisk(board.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Refresh from Disk")
                .accessibilityLabel("Refresh \(board.name) from disk")
            }
            #endif
        }
        .padding(.vertical, 4)
    }

    private var activeBeadCount: Int {
        board.columns
            .flatMap(\.beads)
            .filter { !$0.isArchived }
            .count
    }

    #if os(macOS)
    private var canRefreshFromDisk: Bool {
        guard let repositoryPath = board.repositoryPath else { return false }
        return BeadsProjectImporter.hasBeadsProject(at: URL(fileURLWithPath: repositoryPath, isDirectory: true))
    }
    #endif
}
