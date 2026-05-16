import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: BoardStore

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
    }
}

private struct BoardRow: View {
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
        }
        .padding(.vertical, 4)
    }

    private var activeBeadCount: Int {
        board.columns
            .flatMap(\.beads)
            .filter { !$0.isArchived }
            .count
    }
}
