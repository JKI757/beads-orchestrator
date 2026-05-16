import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    var presentation: BoardPresentation = .automatic
    @State private var newColumnName = ""

    var body: some View {
        GeometryReader { proxy in
            let metrics = BoardMetrics(containerSize: proxy.size, presentation: presentation)

            VStack(spacing: 0) {
                if metrics.showsHeader {
                    BoardHeader(board: board, isCompact: metrics.isCompactHeader)
                }

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: metrics.columnSpacing) {
                        ForEach(board.columns) { column in
                            ColumnView(
                                column: column,
                                beads: store.visibleBeads(in: column),
                                width: metrics.columnWidth,
                                density: metrics.cardDensity
                            )
                        }

                        AddColumnView(newColumnName: $newColumnName)
                            .frame(width: metrics.addColumnWidth)
                    }
                    .padding(metrics.outerPadding)
                }
            }
        }
        .background(.background)
        #if os(macOS)
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationSubtitle(board.repositoryPath ?? "No local repository connected")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(board.name)
    }
}

enum BoardPresentation {
    case automatic
    case mac
    case tabletPortrait
    case tabletLandscape
}

private struct BoardMetrics {
    let containerSize: CGSize
    let presentation: BoardPresentation

    private var containerWidth: CGFloat {
        containerSize.width
    }

    var showsHeader: Bool {
        presentation != .tabletLandscape
    }

    var isCompactHeader: Bool {
        presentation == .tabletPortrait || presentation == .mac
    }

    var columnWidth: CGFloat {
        #if os(macOS)
        min(min(max(containerWidth * 0.24, 240), 300), max(containerWidth - outerPadding * 2, 220))
        #else
        switch presentation {
        case .mac:
            min(min(max(containerWidth * 0.34, 300), 360), max(containerWidth - outerPadding * 2, 240))
        case .tabletLandscape:
            min(max((containerWidth - 48) / 3, 220), 280)
        case .tabletPortrait:
            min(min(max(containerWidth - outerPadding * 2, 280), 340), max(containerWidth - outerPadding * 2, 240))
        case .automatic:
            min(min(max(containerWidth * 0.34, 300), 360), max(containerWidth - outerPadding * 2, 240))
        }
        #endif
    }

    var addColumnWidth: CGFloat {
        #if os(macOS)
        200
        #else
        presentation == .tabletLandscape ? 220 : 260
        #endif
    }

    var columnSpacing: CGFloat {
        #if os(macOS)
        8
        #else
        presentation == .tabletLandscape ? 10 : 12
        #endif
    }

    var outerPadding: CGFloat {
        #if os(macOS)
        10
        #else
        presentation == .tabletLandscape ? 12 : 16
        #endif
    }

    var cardDensity: BeadCardDensity {
        #if os(macOS)
        .dense
        #else
        presentation == .tabletLandscape ? .dense : .regular
        #endif
    }
}

private struct BoardHeader: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    var isCompact = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(board.repositoryName)
                    .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                Text(board.repositoryPath ?? "No local repository connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let snapshot = store.lastRepositorySnapshot {
                Label("\(snapshot.dirtyFileCount) changed", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundStyle(snapshot.dirtyFileCount > 0 ? .orange : .secondary)
            }

            if let sourceFilter = store.sourceFilter {
                Text(sourceFilter.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            if store.attentionOnly {
                Text("Attention")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, 8)
        #if os(macOS)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 1)
        }
        #else
        .background(.bar)
        #endif
    }
}

private struct ColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let column: BoardColumn
    let beads: [Bead]
    let width: CGFloat
    let density: BeadCardDensity
    @State private var isRenaming = false
    @State private var columnName = ""

    private var columnPadding: CGFloat {
        #if os(macOS)
        8
        #else
        density == .dense ? 8 : 10
        #endif
    }

    private var cardGutter: CGFloat {
        #if os(macOS)
        6
        #else
        density == .dense ? 8 : 10
        #endif
    }

    private var contentInset: CGFloat {
        columnPadding + cardGutter
    }

    private var contentWidth: CGFloat {
        max(width - contentInset * 2, 120)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if isRenaming {
                    TextField("Column", text: $columnName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            store.renameColumn(column.id, name: columnName)
                            isRenaming = false
                        }
                } else {
                    Text(column.name)
                        #if os(macOS)
                        .font(.subheadline.weight(.semibold))
                        #else
                        .font(.headline)
                        #endif
                }
                Spacer()
                Text("\(beads.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Menu {
                    Button("Rename") {
                        columnName = column.name
                        isRenaming = true
                    }

                    Button("New Bead") {
                        store.createBead(in: column.id, draft: BeadDraft())
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.plain)
            }
            .frame(width: contentWidth)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(beads) { bead in
                        BeadCardView(bead: bead, density: density)
                            .frame(width: contentWidth)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.bottom, 8)
            }
            .frame(width: contentWidth)
        }
        .padding(.vertical, columnPadding)
        .padding(.horizontal, contentInset)
        .frame(width: width)
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        #else
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        #endif
    }
}

private struct AddColumnView: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var newColumnName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("New column", text: $newColumnName)
                .textFieldStyle(.roundedBorder)
            Button {
                store.addColumn(named: newColumnName.trimmingCharacters(in: .whitespacesAndNewlines))
                newColumnName = ""
            } label: {
                Label("Add Column", systemImage: "plus")
            }
            .disabled(newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        #if os(macOS)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        #else
        .padding(10)
        #endif
    }
}
