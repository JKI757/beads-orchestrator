import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct BoardView: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    var presentation: BoardPresentation = .automatic
    @State private var newColumnName = ""
    @State private var showsRelationshipOverlay = true

    private var relationshipFocus: RelationshipFocus? {
        guard
            let selectedBead = store.selectedBead,
            board.columns.flatMap(\.beads).contains(where: { $0.id == selectedBead.id }),
            !selectedBead.childBeadsIDs.isEmpty
        else { return nil }

        return RelationshipFocus(
            parentID: selectedBead.id,
            childIDs: Set(store.childBeads(for: selectedBead).map(\.id)),
            totalChildCount: selectedBead.childBeadsIDs.count
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = BoardMetrics(containerSize: proxy.size, presentation: presentation)
            let activeRelationshipFocus = showsRelationshipOverlay ? relationshipFocus : nil

            VStack(spacing: 0) {
                if metrics.showsHeader {
                    BoardHeader(
                        board: board,
                        isCompact: metrics.isCompactHeader,
                        relationshipOverlayAvailable: relationshipFocus != nil,
                        showsRelationshipOverlay: $showsRelationshipOverlay
                    )
                }

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: metrics.columnSpacing) {
                        ForEach(board.columns) { column in
                            ColumnView(
                                column: column,
                                beads: store.visibleBeads(in: column),
                                width: metrics.columnWidth,
                                density: metrics.cardDensity,
                                relationshipFocus: activeRelationshipFocus
                            )
                        }

                        AddColumnView(newColumnName: $newColumnName)
                            .frame(width: metrics.addColumnWidth)
                    }
                    .padding(metrics.outerPadding)
                }
            }
            .overlayPreferenceValue(BeadCardBoundsPreferenceKey.self) { anchors in
                RelationshipLinesOverlay(focus: activeRelationshipFocus, anchors: anchors)
            }
            .overlay(alignment: .topTrailing) {
                if !metrics.showsHeader, relationshipFocus != nil {
                    RelationshipOverlayToggle(
                        isOn: $showsRelationshipOverlay,
                        hiddenChildCount: hiddenChildCount(anchors: [:])
                    )
                    .padding(12)
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

    private func hiddenChildCount(anchors: [Bead.ID: Anchor<CGRect>]) -> Int {
        guard let focus = relationshipFocus else { return 0 }
        let visibleChildCount = focus.childIDs.filter { anchors[$0] != nil }.count
        return max(focus.totalChildCount - visibleChildCount, 0)
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
    var relationshipOverlayAvailable = false
    @Binding var showsRelationshipOverlay: Bool

    init(
        board: Board,
        isCompact: Bool = false,
        relationshipOverlayAvailable: Bool = false,
        showsRelationshipOverlay: Binding<Bool> = .constant(true)
    ) {
        self.board = board
        self.isCompact = isCompact
        self.relationshipOverlayAvailable = relationshipOverlayAvailable
        self._showsRelationshipOverlay = showsRelationshipOverlay
    }

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

            if relationshipOverlayAvailable {
                RelationshipOverlayToggle(isOn: $showsRelationshipOverlay)
            }

            StatusReportButton(board: board, compact: true)
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

private struct RelationshipFocus: Equatable {
    var parentID: Bead.ID
    var childIDs: Set<Bead.ID>
    var totalChildCount: Int
}

private struct BeadCardBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [Bead.ID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Bead.ID: Anchor<CGRect>], nextValue: () -> [Bead.ID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RelationshipLinesOverlay: View {
    let focus: RelationshipFocus?
    let anchors: [Bead.ID: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let focus, let parentAnchor = anchors[focus.parentID] {
                let parentRect = proxy[parentAnchor]
                let childRects = focus.childIDs.compactMap { childID in
                    anchors[childID].map { proxy[$0] }
                }
                let hiddenCount = max(focus.totalChildCount - childRects.count, 0)

                ZStack(alignment: .topTrailing) {
                    Path { path in
                        let start = CGPoint(x: parentRect.maxX, y: parentRect.midY)
                        for childRect in childRects {
                            let end = CGPoint(x: childRect.minX, y: childRect.midY)
                            let controlOffset = max(abs(end.x - start.x) * 0.35, 36)
                            path.move(to: start)
                            path.addCurve(
                                to: end,
                                control1: CGPoint(x: start.x + controlOffset, y: start.y),
                                control2: CGPoint(x: end.x - controlOffset, y: end.y)
                            )
                        }
                    }
                    .stroke(Color.accentColor.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))

                    if hiddenCount > 0 {
                        Text("\(hiddenCount) child\(hiddenCount == 1 ? "" : "ren") hidden")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RelationshipOverlayToggle: View {
    @Binding var isOn: Bool
    var hiddenChildCount: Int = 0

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(
                hiddenChildCount > 0 ? "\(hiddenChildCount) Hidden" : "Relationships",
                systemImage: isOn ? "point.3.connected.trianglepath.dotted" : "eye.slash"
            )
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(isOn ? "Hide Relationship Lines" : "Show Relationship Lines")
    }
}

struct StatusReportButton: View {
    @EnvironmentObject private var store: BoardStore
    #if os(macOS)
    @EnvironmentObject private var server: BeadsHTTPServer
    #endif

    let board: Board
    var bead: Bead?
    var scope: BeadStatusReportScope = .board
    var compact = false

    @State private var showingReport = false
    @State private var isGenerating = false
    @State private var report: BeadStatusReportResponse?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            showingReport = true
            generate()
        } label: {
            if compact {
                Image(systemName: "chart.bar.doc.horizontal")
            } else {
                Label("Status Report", systemImage: "chart.bar.doc.horizontal")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isGenerating)
        .help("Generate Status Report")
        .sheet(isPresented: $showingReport) {
            StatusReportSheet(
                title: scope == .board ? board.name : bead?.title ?? board.name,
                scope: scope,
                isGenerating: isGenerating,
                report: report,
                errorMessage: errorMessage,
                regenerate: generate,
                copyReport: copyReport,
                saveToNotes: bead == nil ? nil : saveToNotes
            )
        }
    }

    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        Task {
            do {
                let request = BeadStatusReportRequest(boardID: board.id, beadID: bead?.id, scope: scope)
                let generatedReport: BeadStatusReportResponse
                #if os(macOS)
                generatedReport = try await server.statusReport(request: request)
                #else
                generatedReport = try await store.statusReport(for: bead?.id, scope: scope)
                #endif
                report = generatedReport
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func copyReport() {
        guard let report else { return }
        let text = formatted(report: report)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    private func saveToNotes() {
        guard
            let bead,
            let report
        else { return }

        let target = store.bead(beadsID: bead.relationshipID) ?? bead
        var draft = BeadDraft(bead: target)
        let existingNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.notes = [existingNotes, formatted(report: report)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        store.updateBead(target.id, with: draft)
    }

    private func formatted(report: BeadStatusReportResponse) -> String {
        var lines = [
            report.title,
            "",
            report.summary
        ]

        for section in report.sections where !section.items.isEmpty {
            lines.append("")
            lines.append(section.title)
            lines.append(contentsOf: section.items.map { "- \($0)" })
        }

        lines.append("")
        lines.append("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
        return lines.joined(separator: "\n")
    }
}

private struct StatusReportSheet: View {
    let title: String
    let scope: BeadStatusReportScope
    let isGenerating: Bool
    let report: BeadStatusReportResponse?
    let errorMessage: String?
    let regenerate: () -> Void
    let copyReport: () -> Void
    let saveToNotes: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status Report")
                        .font(.title3.weight(.semibold))
                    Text(scope == .board ? title : "Subtree: \(title)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    regenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .disabled(isGenerating)

                Button {
                    copyReport()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(report == nil)

                if let saveToNotes {
                    Button {
                        saveToNotes()
                    } label: {
                        Label("Save to Notes", systemImage: "square.and.pencil")
                    }
                    .disabled(report == nil)
                }
            }
            .padding()

            Divider()

            Group {
                if isGenerating {
                    ProgressView("Generating report")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Report Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let report {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(report.title)
                                    .font(.title3.weight(.semibold))
                                Text(report.summary)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(report.sections) { section in
                                if !section.items.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(section.title)
                                            .font(.headline)
                                        ForEach(section.items, id: \.self) { item in
                                            Label(item, systemImage: "circle.fill")
                                                .font(.callout)
                                                .labelStyle(.titleAndIcon)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } else {
                    ContentUnavailableView("No Report", systemImage: "chart.bar.doc.horizontal")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        #if os(macOS)
        .frame(width: 620, height: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

private struct ColumnView: View {
    @EnvironmentObject private var store: BoardStore
    let column: BoardColumn
    let beads: [Bead]
    let width: CGFloat
    let density: BeadCardDensity
    let relationshipFocus: RelationshipFocus?
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
                            .overlay {
                                if let relationshipHighlight = relationshipHighlight(for: bead) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(relationshipHighlight.color, lineWidth: relationshipHighlight.lineWidth)
                                }
                            }
                            .anchorPreference(key: BeadCardBoundsPreferenceKey.self, value: .bounds) { anchor in
                                [bead.id: anchor]
                            }
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

    private func relationshipHighlight(for bead: Bead) -> (color: Color, lineWidth: CGFloat)? {
        guard let relationshipFocus else { return nil }
        if relationshipFocus.parentID == bead.id {
            return (.accentColor, 2)
        }
        if relationshipFocus.childIDs.contains(bead.id) {
            return (.accentColor.opacity(0.65), 1.5)
        }
        return nil
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
    @State private var nodeOffsets: [String: CGSize] = [:]
    @State private var mode: HierarchyGraphMode = .inspect
    @State private var pendingSourceID: String?
    @State private var graphMessage: String?

    private var isCompact: Bool {
        presentation == .compact
    }

    private var graph: HierarchyGraph {
        HierarchyGraphBuilder.graph(
            from: store.visibleBeads(in: board),
            presentation: presentation,
            offsets: nodeOffsets
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HierarchyHeader(
                board: board,
                graph: graph,
                isCompact: isCompact,
                mode: $mode,
                pendingSourceID: pendingSourceID,
                graphMessage: graphMessage
            )

            if graph.nodes.isEmpty {
                ContentUnavailableView("No Beads", systemImage: "point.3.connected.trianglepath.dotted", description: Text("No beads match the current filters."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HierarchyGraphView(
                    graph: graph,
                    presentation: presentation,
                    pendingSourceID: pendingSourceID,
                    selectedBeadID: store.selectedBeadID,
                    nodeOffsets: $nodeOffsets,
                    selectNode: handleNodeSelection(_:),
                    clearRelationship: clearRelationship(_:)
                )
                #if os(macOS)
                .background(Color(nsColor: .underPageBackgroundColor))
                #else
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
        .onChange(of: mode) {
            pendingSourceID = nil
            graphMessage = nil
        }
    }

    private func handleNodeSelection(_ node: HierarchyGraphNode) {
        store.select(node.bead)

        guard mode != .inspect else {
            pendingSourceID = nil
            graphMessage = nil
            return
        }

        guard let sourceID = pendingSourceID else {
            pendingSourceID = node.id
            graphMessage = "Choose another bead to create a \(mode.displayName.lowercased()) relationship."
            return
        }

        guard sourceID != node.id else {
            pendingSourceID = nil
            graphMessage = nil
            return
        }

        switch mode {
        case .inspect:
            break
        case .parent:
            store.setParent(of: node.bead.id, to: sourceID)
            graphMessage = "\(node.bead.title) is now a child of \(sourceID)."
        case .dependency:
            store.addDependency(to: node.bead.id, dependencyID: sourceID)
            graphMessage = "\(node.bead.title) now depends on \(sourceID)."
        }
        pendingSourceID = nil
    }

    private func clearRelationship(_ edge: HierarchyGraphEdge) {
        guard let target = graph.nodes.first(where: { $0.id == edge.toID }) else { return }
        switch edge.kind {
        case .parent:
            store.setParent(of: target.bead.id, to: nil)
            graphMessage = "Removed parent link from \(target.bead.title)."
        case .dependency:
            store.removeDependency(from: target.bead.id, dependencyID: edge.fromID)
            graphMessage = "Removed dependency from \(target.bead.title)."
        }
    }
}

private struct HierarchyHeader: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    let graph: HierarchyGraph
    let isCompact: Bool
    @Binding var mode: HierarchyGraphMode
    let pendingSourceID: String?
    let graphMessage: String?

    var body: some View {
        VStack(spacing: 8) {
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

            HStack(spacing: 6) {
                HierarchyLegendItem(label: "\(store.visibleBeads(in: board).count)", systemImage: "circle.grid.2x2", color: .secondary)
                if graph.parentEdgeCount > 0 {
                    HierarchyLegendItem(label: "\(graph.parentEdgeCount)", systemImage: "point.topleft.down.curvedto.point.bottomright.up", color: .blue)
                }
                if graph.dependencyEdgeCount > 0 {
                    HierarchyLegendItem(label: "\(graph.dependencyEdgeCount)", systemImage: "arrow.right", color: .red)
                }
            }

            StatusReportButton(board: board, compact: true)
            }

            HStack(spacing: 10) {
                Picker("Graph Mode", selection: $mode) {
                    ForEach(HierarchyGraphMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: isCompact ? .infinity : 360)

                if let pendingSourceID {
                    Text("Source: \(pendingSourceID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let graphMessage {
                    Text(graphMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
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

private struct HierarchyLegendItem: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.monospacedDigit())
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private enum HierarchyGraphMode: String, CaseIterable, Identifiable {
    case inspect
    case parent
    case dependency

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inspect: "Inspect"
        case .parent: "Parent"
        case .dependency: "Dependency"
        }
    }

    var systemImage: String {
        switch self {
        case .inspect: "cursorarrow"
        case .parent: "point.topleft.down.curvedto.point.bottomright.up"
        case .dependency: "arrow.right"
        }
    }
}

private struct HierarchyGraphView: View {
    let graph: HierarchyGraph
    let presentation: HierarchyPresentation
    let pendingSourceID: String?
    let selectedBeadID: Bead.ID?
    @Binding var nodeOffsets: [String: CGSize]
    @State private var dragStartOffsets: [String: CGSize] = [:]
    let selectNode: (HierarchyGraphNode) -> Void
    let clearRelationship: (HierarchyGraphEdge) -> Void
    private var isCompact: Bool { presentation == .compact }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    HierarchyEdgeCanvas(graph: graph)

                    ForEach(graph.edges) { edge in
                        HierarchyEdgeClearButton(edge: edge, graph: graph, clearRelationship: clearRelationship)
                    }

                    ForEach(graph.nodes) { node in
                        HierarchyGraphNodeView(
                            node: node,
                            isCompact: isCompact,
                            isSelected: selectedBeadID == node.bead.id,
                            isPendingSource: pendingSourceID == node.id,
                            selectNode: selectNode
                        )
                        .frame(width: graph.metrics.nodeWidth, height: graph.metrics.nodeHeight)
                        .position(x: node.frame.midX, y: node.frame.midY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartOffsets[node.id] == nil {
                                        dragStartOffsets[node.id] = nodeOffsets[node.id] ?? .zero
                                    }
                                    let startOffset = dragStartOffsets[node.id] ?? .zero
                                    nodeOffsets[node.id] = CGSize(
                                        width: startOffset.width + value.translation.width,
                                        height: startOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    dragStartOffsets[node.id] = nil
                                }
                        )
                    }
                }
                .frame(
                    width: max(graph.canvasSize.width, proxy.size.width),
                    height: max(graph.canvasSize.height, proxy.size.height),
                    alignment: .topLeading
                )
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

private struct HierarchyEdgeCanvas: View {
    let graph: HierarchyGraph

    var body: some View {
        Canvas { context, _ in
            for edge in graph.edges {
                guard let fromFrame = graph.frame(for: edge.fromID), let toFrame = graph.frame(for: edge.toID) else { continue }
                let from = edgeStartPoint(fromFrame: fromFrame, toFrame: toFrame)
                let to = edgeEndPoint(fromFrame: fromFrame, toFrame: toFrame)
                var path = Path()
                path.move(to: from)
                let controlOffset = max(50, abs(to.x - from.x) * 0.42)
                path.addCurve(
                    to: to,
                    control1: CGPoint(x: from.x + controlOffset, y: from.y),
                    control2: CGPoint(x: to.x - controlOffset, y: to.y)
                )

                context.stroke(
                    path,
                    with: .color(edge.color),
                    style: StrokeStyle(
                        lineWidth: edge.kind == .dependency ? 2.2 : 1.6,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: edge.kind == .dependency ? [] : [5, 4]
                    )
                )
                drawArrowhead(in: context, tip: to, from: from, color: edge.color)
            }
        }
        .frame(width: graph.canvasSize.width, height: graph.canvasSize.height)
        .allowsHitTesting(false)
    }

    private func edgeStartPoint(fromFrame: CGRect, toFrame: CGRect) -> CGPoint {
        toFrame.midX >= fromFrame.midX
            ? CGPoint(x: fromFrame.maxX, y: fromFrame.midY)
            : CGPoint(x: fromFrame.minX, y: fromFrame.midY)
    }

    private func edgeEndPoint(fromFrame: CGRect, toFrame: CGRect) -> CGPoint {
        toFrame.midX >= fromFrame.midX
            ? CGPoint(x: toFrame.minX, y: toFrame.midY)
            : CGPoint(x: toFrame.maxX, y: toFrame.midY)
    }

    private func drawArrowhead(in context: GraphicsContext, tip: CGPoint, from: CGPoint, color: Color) {
        let direction: CGFloat = tip.x >= from.x ? -1 : 1
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x + direction * 8, y: tip.y - 5))
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x + direction * 8, y: tip.y + 5))
        context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }
}

private struct HierarchyEdgeClearButton: View {
    let edge: HierarchyGraphEdge
    let graph: HierarchyGraph
    let clearRelationship: (HierarchyGraphEdge) -> Void

    var body: some View {
        if let fromFrame = graph.frame(for: edge.fromID), let toFrame = graph.frame(for: edge.toID) {
            Button {
                clearRelationship(edge)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .position(x: (fromFrame.midX + toFrame.midX) / 2, y: (fromFrame.midY + toFrame.midY) / 2)
            .accessibilityLabel("Remove relationship")
        }
    }
}

private struct HierarchyGraphNodeView: View {
    @EnvironmentObject private var store: BoardStore
    let node: HierarchyGraphNode
    let isCompact: Bool
    let isSelected: Bool
    let isPendingSource: Bool
    let selectNode: (HierarchyGraphNode) -> Void

    private var statusText: String {
        node.bead.status ?? store.columnName(for: node.bead) ?? "No status"
    }

    var body: some View {
        Button {
            selectNode(node)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.bead.title)
                        .font(isCompact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

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
                }

                HStack(spacing: 6) {
                    if node.childCount > 0 {
                        HierarchyChip(text: "\(node.childCount) child\(node.childCount == 1 ? "" : "ren")", systemImage: "point.topleft.down.curvedto.point.bottomright.up", color: .blue)
                    }
                    if node.dependencyCount > 0 {
                        HierarchyChip(text: "\(node.dependencyCount) blocker\(node.dependencyCount == 1 ? "" : "s")", systemImage: "arrow.left", color: .red)
                    }
                    if node.dependentCount > 0 {
                        HierarchyChip(text: "\(node.dependentCount) blocked", systemImage: "arrow.right", color: .orange)
                    }
                    if node.bead.isStale {
                        HierarchyChip(text: "Stale", systemImage: "clock", color: .orange)
                    }
                }
            }
            .padding(isCompact ? 9 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                #if os(macOS)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                #else
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                #endif
            }
            .overlay {
                RoundedRectangle(cornerRadius: isCompact ? 7 : 8, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected || isPendingSource ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .accessibilityLabel(Text("\(node.bead.title), \(statusText)"))
    }

    private var borderColor: Color {
        if isPendingSource {
            Color.orange
        } else if isSelected {
            Color.accentColor
        } else if node.bead.isBlocked {
            Color.red.opacity(0.38)
        } else {
            Color.secondary.opacity(0.18)
        }
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

private struct HierarchyGraph {
    let nodes: [HierarchyGraphNode]
    let edges: [HierarchyGraphEdge]
    let metrics: HierarchyGraphMetrics
    let canvasSize: CGSize

    private var framesByID: [String: CGRect] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.frame) })
    }

    var parentEdgeCount: Int {
        edges.filter { $0.kind == .parent }.count
    }

    var dependencyEdgeCount: Int {
        edges.filter { $0.kind == .dependency }.count
    }

    func frame(for id: String) -> CGRect? {
        framesByID[id]
    }
}

private struct HierarchyGraphNode: Identifiable {
    let bead: Bead
    let frame: CGRect
    let childCount: Int
    let dependencyCount: Int
    let dependentCount: Int

    var id: String {
        bead.relationshipID
    }
}

private struct HierarchyGraphEdge: Identifiable, Hashable {
    enum Kind {
        case parent
        case dependency
    }

    let fromID: String
    let toID: String
    let kind: Kind
    let isBlocked: Bool

    var id: String {
        "\(kind)-\(fromID)-\(toID)"
    }

    var color: Color {
        switch kind {
        case .parent:
            Color.blue.opacity(0.48)
        case .dependency:
            isBlocked ? Color.red.opacity(0.78) : Color.orange.opacity(0.70)
        }
    }
}

private struct HierarchyGraphMetrics {
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
    let inset: CGFloat

    static func metrics(for presentation: HierarchyPresentation) -> HierarchyGraphMetrics {
        switch presentation {
        case .compact:
            HierarchyGraphMetrics(nodeWidth: 236, nodeHeight: 118, columnGap: 70, rowGap: 18, inset: 18)
        case .tabletPortrait:
            HierarchyGraphMetrics(nodeWidth: 270, nodeHeight: 124, columnGap: 84, rowGap: 22, inset: 22)
        case .tabletLandscape:
            HierarchyGraphMetrics(nodeWidth: 280, nodeHeight: 124, columnGap: 96, rowGap: 22, inset: 24)
        case .mac:
            HierarchyGraphMetrics(nodeWidth: 300, nodeHeight: 128, columnGap: 106, rowGap: 24, inset: 26)
        }
    }
}

private enum HierarchyGraphBuilder {
    static func graph(from beads: [Bead], presentation: HierarchyPresentation, offsets: [String: CGSize]) -> HierarchyGraph {
        let orderedBeads = beads.filter { !$0.isArchived }
        let metrics = HierarchyGraphMetrics.metrics(for: presentation)
        let beadsByID = Dictionary(
            orderedBeads.map { ($0.relationshipID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let visibleIDs = Set(beadsByID.keys)
        let childIDsByParent = childMap(for: orderedBeads, visibleIDs: visibleIDs)
        let dependencyEdges = dependencyEdges(for: orderedBeads, visibleIDs: visibleIDs, beadsByID: beadsByID)
        let depthByID = depths(for: orderedBeads, childIDsByParent: childIDsByParent)
        let maxDepth = depthByID.values.max() ?? 0
        let IDsByDepth = Dictionary(grouping: orderedBeads.map(\.relationshipID)) { depthByID[$0] ?? 0 }
        var nodes: [HierarchyGraphNode] = []

        for depth in 0...maxDepth {
            let IDs = IDsByDepth[depth] ?? []
            for (row, relationshipID) in IDs.enumerated() {
                guard let bead = beadsByID[relationshipID] else { continue }
                let offset = offsets[relationshipID] ?? .zero
                let frame = CGRect(
                    x: metrics.inset + CGFloat(depth) * (metrics.nodeWidth + metrics.columnGap) + offset.width,
                    y: metrics.inset + CGFloat(row) * (metrics.nodeHeight + metrics.rowGap) + offset.height,
                    width: metrics.nodeWidth,
                    height: metrics.nodeHeight
                )
                nodes.append(
                    HierarchyGraphNode(
                        bead: bead,
                        frame: frame,
                        childCount: childIDsByParent[relationshipID]?.count ?? 0,
                        dependencyCount: bead.dependencyBeadsIDs.filter { visibleIDs.contains($0) }.count,
                        dependentCount: bead.dependentBeadsIDs.filter { visibleIDs.contains($0) }.count
                    )
                )
            }
        }

        let parentEdges = childIDsByParent.flatMap { parentID, childIDs in
            childIDs.map {
                HierarchyGraphEdge(fromID: parentID, toID: $0, kind: .parent, isBlocked: beadsByID[$0]?.isBlocked ?? false)
            }
        }
        let edges = stableUniqueEdges(parentEdges + dependencyEdges)
        let maxX = nodes.map(\.frame.maxX).max() ?? 0
        let maxY = nodes.map(\.frame.maxY).max() ?? 0
        let minX = min(nodes.map(\.frame.minX).min() ?? 0, 0)
        let minY = min(nodes.map(\.frame.minY).min() ?? 0, 0)
        let shiftedNodes = nodes.map { node in
            HierarchyGraphNode(
                bead: node.bead,
                frame: node.frame.offsetBy(dx: abs(minX), dy: abs(minY)),
                childCount: node.childCount,
                dependencyCount: node.dependencyCount,
                dependentCount: node.dependentCount
            )
        }

        return HierarchyGraph(
            nodes: shiftedNodes,
            edges: edges,
            metrics: metrics,
            canvasSize: CGSize(width: maxX + abs(minX) + metrics.inset, height: maxY + abs(minY) + metrics.inset)
        )
    }

    private static func depths(for beads: [Bead], childIDsByParent: [String: [String]]) -> [String: Int] {
        let orderedIDs = beads.map(\.relationshipID)
        let visibleIDs = Set(orderedIDs)
        var parentIDsByChild: [String: [String]] = [:]

        for bead in beads {
            let relationshipID = bead.relationshipID
            if let parentID = bead.parentBeadsID, visibleIDs.contains(parentID) {
                parentIDsByChild[relationshipID, default: []].append(parentID)
            }
        }

        for (parentID, childIDs) in childIDsByParent {
            for childID in childIDs {
                parentIDsByChild[childID, default: []].append(parentID)
            }
        }

        var memo: [String: Int] = [:]
        var visiting = Set<String>()

        func depth(for relationshipID: String) -> Int {
            if let depth = memo[relationshipID] {
                return depth
            }
            guard !visiting.contains(relationshipID) else {
                return 0
            }
            visiting.insert(relationshipID)
            let parentDepth = (parentIDsByChild[relationshipID] ?? [])
                .filter { visibleIDs.contains($0) }
                .map { depth(for: $0) + 1 }
                .max() ?? 0
            visiting.remove(relationshipID)
            memo[relationshipID] = parentDepth
            return parentDepth
        }

        for relationshipID in orderedIDs {
            memo[relationshipID] = depth(for: relationshipID)
        }

        return memo
    }

    private static func dependencyEdges(for beads: [Bead], visibleIDs: Set<String>, beadsByID: [String: Bead]) -> [HierarchyGraphEdge] {
        var edges: [HierarchyGraphEdge] = []

        for bead in beads {
            let beadID = bead.relationshipID
            for dependencyID in bead.dependencyBeadsIDs where visibleIDs.contains(dependencyID) {
                edges.append(
                    HierarchyGraphEdge(fromID: dependencyID, toID: beadID, kind: .dependency, isBlocked: bead.isBlocked)
                )
            }

            for dependentID in bead.dependentBeadsIDs where visibleIDs.contains(dependentID) {
                edges.append(
                    HierarchyGraphEdge(fromID: beadID, toID: dependentID, kind: .dependency, isBlocked: beadsByID[dependentID]?.isBlocked ?? false)
                )
            }
        }

        return edges
    }

    private static func stableUniqueEdges(_ edges: [HierarchyGraphEdge]) -> [HierarchyGraphEdge] {
        var seenIDs = Set<String>()
        var result: [HierarchyGraphEdge] = []

        for edge in edges where !seenIDs.contains(edge.id) {
            seenIDs.insert(edge.id)
            result.append(edge)
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
