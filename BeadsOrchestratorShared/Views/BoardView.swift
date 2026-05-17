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

enum HierarchyPresentation {
    case mac
    case tabletPortrait
    case tabletLandscape
    case compact
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
        10
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
            HStack(spacing: 8) {
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
                    .fixedSize()
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
                .frame(width: 22, height: 22)
                .buttonStyle(.plain)
            }
            .frame(width: contentWidth, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(beads) { bead in
                        BeadCardView(bead: bead, density: density)
                            .frame(width: contentWidth, alignment: .leading)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.bottom, 8)
            }
            .frame(width: contentWidth)
            #if os(iOS)
            .refreshable {
                await store.pullFromRemoteServer()
            }
            #endif
        }
        .padding(.vertical, columnPadding)
        .padding(.horizontal, contentInset)
        .frame(width: width)
        .clipped()
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

struct HierarchyView: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    var presentation: HierarchyPresentation
    @State private var expandedIDs: Set<String> = []
    @State private var initializedBoardID: Board.ID?

    private var isCompact: Bool {
        presentation == .compact
    }

    private var rows: [HierarchyRowNode] {
        HierarchyOutlineBuilder.rows(
            from: store.visibleBeads(in: board),
            expandedIDs: expandedIDs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HierarchyHeader(board: board, isCompact: isCompact)

            if rows.isEmpty {
                ContentUnavailableView("No Beads", systemImage: "list.bullet.indent", description: Text("No beads match the current filters."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rows) { node in
                        HierarchyRowLink(
                            node: node,
                            presentation: presentation,
                            isExpanded: expandedIDs.contains(node.bead.relationshipID),
                            toggleExpansion: {
                                toggleExpansion(for: node.bead)
                            }
                        )
                        .listRowInsets(rowInsets(for: node.depth))
                    }
                }
                #if os(macOS)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                #else
                .listStyle(.insetGrouped)
                .refreshable {
                    await store.pullFromRemoteServer()
                }
                #endif
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
        .onAppear {
            initializeExpansion()
        }
        .onChange(of: board.id) {
            initializeExpansion(reset: true)
        }
        .onChange(of: board.updatedAt) {
            initializeExpansion()
        }
    }

    private func toggleExpansion(for bead: Bead) {
        let relationshipID = bead.relationshipID
        if expandedIDs.contains(relationshipID) {
            expandedIDs.remove(relationshipID)
        } else {
            expandedIDs.insert(relationshipID)
        }
    }

    private func initializeExpansion(reset: Bool = false) {
        let parentIDs = Set(
            store.visibleBeads(in: board)
                .filter { !$0.childBeadsIDs.isEmpty }
                .map(\.relationshipID)
        )

        if reset || initializedBoardID != board.id {
            expandedIDs = parentIDs
            initializedBoardID = board.id
        } else {
            expandedIDs.formUnion(parentIDs)
        }
    }

    private func rowInsets(for depth: Int) -> EdgeInsets {
        let leading = (isCompact ? 12 : 16) + CGFloat(min(depth, 5)) * (isCompact ? 18 : 22)
        return EdgeInsets(top: 6, leading: leading, bottom: 6, trailing: isCompact ? 12 : 16)
    }
}

private struct HierarchyHeader: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(board.repositoryName)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                Text(board.repositoryPath ?? "No local repository connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(store.visibleBeads(in: board).count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, isCompact ? 16 : 18)
        .padding(.vertical, isCompact ? 10 : 12)
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

private struct HierarchyRowLink: View {
    @EnvironmentObject private var store: BoardStore
    let node: HierarchyRowNode
    let presentation: HierarchyPresentation
    let isExpanded: Bool
    let toggleExpansion: () -> Void

    var body: some View {
        #if os(iOS)
        if presentation == .compact {
            NavigationLink {
                BeadDetailView(bead: node.bead)
            } label: {
                row
            }
            .simultaneousGesture(TapGesture().onEnded {
                store.select(node.bead)
            })
        } else {
            Button {
                store.select(node.bead)
            } label: {
                row
            }
            .buttonStyle(.plain)
        }
        #else
        Button {
            store.select(node.bead)
        } label: {
            row
        }
        .buttonStyle(.plain)
        #endif
    }

    private var row: some View {
        HierarchyRow(
            node: node,
            isExpanded: isExpanded,
            statusText: node.bead.status ?? store.columnName(for: node.bead) ?? "No status",
            isSelected: store.selectedBeadID == node.bead.id,
            toggleExpansion: toggleExpansion
        )
    }
}

private struct HierarchyRow: View {
    let node: HierarchyRowNode
    let isExpanded: Bool
    let statusText: String
    let isSelected: Bool
    let toggleExpansion: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: node.hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "circle.fill")
                .font(node.hasChildren ? .caption.weight(.semibold) : .system(size: 5))
                .foregroundStyle(node.hasChildren ? Color.accentColor : Color.secondary.opacity(0.55))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard node.hasChildren else { return }
                    toggleExpansion()
                }
                .accessibilityLabel(node.hasChildren ? (isExpanded ? "Collapse" : "Expand") : "No children")
                .accessibilityAddTraits(node.hasChildren ? .isButton : [])

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.bead.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if node.hasChildren {
                        Label("\(node.childCount)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer(minLength: 8)

                    if node.bead.isBlocked {
                        Text("Blocked")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    HierarchyChip(text: node.bead.issueType ?? node.bead.sourceType.displayName, systemImage: "tag")
                    HierarchyChip(text: statusText, systemImage: "circle.dotted")
                    HierarchyChip(text: node.bead.priority.rawValue.capitalized, systemImage: "flag")

                    if node.bead.isStale {
                        HierarchyChip(text: "Stale", systemImage: "clock", color: .orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct HierarchyChip: View {
    let text: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct HierarchyRowNode: Identifiable {
    let bead: Bead
    let depth: Int
    let hasChildren: Bool
    let childCount: Int

    var id: String {
        bead.relationshipID
    }
}

private enum HierarchyOutlineBuilder {
    static func rows(from beads: [Bead], expandedIDs: Set<String>) -> [HierarchyRowNode] {
        let orderedBeads = beads.filter { !$0.isArchived }
        let beadsByID = Dictionary(
            orderedBeads.map { ($0.relationshipID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let visibleIDs = Set(beadsByID.keys)
        let childIDsByParent = childMap(for: orderedBeads, visibleIDs: visibleIDs)
        var rootIDs: [String] = []
        var parentedIDs = Set<String>()

        for bead in orderedBeads {
            let relationshipID = bead.relationshipID
            if let parentID = bead.parentBeadsID, visibleIDs.contains(parentID) {
                parentedIDs.insert(relationshipID)
            } else {
                rootIDs.append(relationshipID)
            }
        }

        for childIDs in childIDsByParent.values {
            parentedIDs.formUnion(childIDs)
        }
        rootIDs.removeAll { parentedIDs.contains($0) }

        var result: [HierarchyRowNode] = []
        var visitedIDs = Set<String>()

        func append(_ relationshipID: String, depth: Int) {
            guard !visitedIDs.contains(relationshipID), let bead = beadsByID[relationshipID] else { return }
            visitedIDs.insert(relationshipID)

            let childIDs = childIDsByParent[relationshipID] ?? []
            result.append(
                HierarchyRowNode(
                    bead: bead,
                    depth: depth,
                    hasChildren: !childIDs.isEmpty,
                    childCount: childIDs.count
                )
            )

            guard expandedIDs.contains(relationshipID) else { return }
            for childID in childIDs {
                append(childID, depth: depth + 1)
            }
        }

        for rootID in rootIDs {
            append(rootID, depth: 0)
        }

        for bead in orderedBeads where !visitedIDs.contains(bead.relationshipID) {
            append(bead.relationshipID, depth: 0)
        }

        return result
    }

    private static func childMap(for beads: [Bead], visibleIDs: Set<String>) -> [String: [String]] {
        var childIDsByParent: [String: [String]] = [:]

        for bead in beads {
            guard let parentID = bead.parentBeadsID, visibleIDs.contains(parentID) else { continue }
            childIDsByParent[parentID, default: []].append(bead.relationshipID)
        }

        for bead in beads {
            let visibleChildIDs = bead.childBeadsIDs.filter { visibleIDs.contains($0) }
            guard !visibleChildIDs.isEmpty else { continue }

            var children = childIDsByParent[bead.relationshipID, default: []]
            for childID in visibleChildIDs where !children.contains(childID) {
                children.append(childID)
            }
            childIDsByParent[bead.relationshipID] = children
        }

        return childIDsByParent
    }
}
