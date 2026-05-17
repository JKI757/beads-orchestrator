import SwiftUI

struct BeadDetailView: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead?
    var presentation: BeadDetailPresentation = .automatic
    @State private var showingEditor = false

    var body: some View {
        Group {
            if let bead = displayedBead {
                #if os(macOS)
                MacBeadInspector(bead: bead, showingEditor: $showingEditor)
                #else
                if presentation == .tabletLandscape {
                    TabletLandscapeBeadInspector(bead: bead, showingEditor: $showingEditor)
                } else {
                    FormBeadInspector(bead: bead, showingEditor: $showingEditor)
                }
                #endif
            } else {
                ContentUnavailableView("No Bead Selected", systemImage: "circle.hexagongrid", description: Text("Select a bead to inspect repository context."))
            }
        }
    }

    private var displayedBead: Bead? {
        guard let bead else { return nil }
        if store.selectedBeadID == bead.id {
            return store.selectedBead ?? bead
        }
        return store.selectedBead ?? bead
    }
}

enum BeadDetailPresentation {
    case automatic
    case tabletLandscape
}

private struct RelationshipControls: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead
    @State private var showingChildEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showingChildEditor = true
            } label: {
                Label("New Child Bead", systemImage: "plus.square.on.square")
            }

            if let parent = store.parentBead(for: bead) {
                RelationshipButton(title: "Parent", bead: parent) {
                    store.select(parent)
                }
            } else if let parentBeadsID = bead.parentBeadsID {
                LabeledContent("Parent", value: parentBeadsID)
            }

            if !bead.childBeadsIDs.isEmpty {
                RelationshipGroup(title: "Children", beads: store.childBeads(for: bead), missingIDs: missingIDs(bead.childBeadsIDs, resolved: store.childBeads(for: bead)))
            }

            if !bead.dependencyBeadsIDs.isEmpty {
                RelationshipGroup(title: "Depends On", beads: store.dependencyBeads(for: bead), missingIDs: missingIDs(bead.dependencyBeadsIDs, resolved: store.dependencyBeads(for: bead)))
            }

            if !bead.dependentBeadsIDs.isEmpty {
                RelationshipGroup(title: "Blocks", beads: store.dependentBeads(for: bead), missingIDs: missingIDs(bead.dependentBeadsIDs, resolved: store.dependentBeads(for: bead)))
            }
        }
        .sheet(isPresented: $showingChildEditor) {
            BeadEditorSheet(mode: .create(parent: bead))
        }
    }

    private func missingIDs(_ ids: [String], resolved: [Bead]) -> [String] {
        let resolvedIDs = Set(resolved.map(\.relationshipID))
        return ids.filter { !resolvedIDs.contains($0) }
    }
}

private struct RelationshipGroup: View {
    @EnvironmentObject private var store: BoardStore
    let title: String
    let beads: [Bead]
    let missingIDs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(beads) { bead in
                RelationshipButton(title: title, bead: bead) {
                    store.select(bead)
                }
            }

            ForEach(missingIDs, id: \.self) { missingID in
                Text(missingID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

private struct RelationshipButton: View {
    let title: String
    let bead: Bead
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(bead.title, systemImage: bead.issueType == "epic" ? "square.stack.3d.up" : "circle")
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let status = bead.status {
                    Text(status.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(bead.title)")
    }
}

private struct PlanReviewControls: View {
    @EnvironmentObject private var store: BoardStore
    #if os(macOS)
    @EnvironmentObject private var server: BeadsHTTPServer
    #endif

    let bead: Bead
    @State private var response: BeadPlanReviewResponse?
    @State private var errorMessage: String?
    @State private var reviewingScope: BeadPlanReviewScope?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    requestReview(scope: .bead)
                } label: {
                    Label("Review Bead", systemImage: "sparkles")
                }
                .disabled(reviewingScope != nil)

                Button {
                    requestReview(scope: .subtree)
                } label: {
                    Label("Review Subtree", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(reviewingScope != nil)
            }
            .controlSize(.small)

            if let reviewingScope {
                ProgressView("Reviewing \(reviewingScope.displayName.lowercased())")
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let response {
                Text(response.message)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if !response.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Findings")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(response.findings) { finding in
                            PlanReviewFindingRow(finding: finding)
                        }
                    }
                }

                if !response.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Proposed Changes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(response.changes) { change in
                            PlanReviewChangeRow(change: change) {
                                apply(change)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestReview(scope: BeadPlanReviewScope) {
        errorMessage = nil
        reviewingScope = scope
        Task {
            do {
                let reviewRequest = BeadPlanReviewRequest(boardID: store.selectedBoardID, beadID: bead.id, scope: scope)
                let review: BeadPlanReviewResponse
                #if os(macOS)
                review = try await server.reviewPlan(request: reviewRequest)
                #else
                review = try await store.reviewPlan(for: bead.id, scope: scope)
                #endif
                response = review
            } catch {
                errorMessage = error.localizedDescription
            }
            reviewingScope = nil
        }
    }

    private func apply(_ change: BeadPlanReviewChange) {
        _ = store.apply(change, fallbackBead: bead)
    }
}

private struct PlanReviewFindingRow: View {
    let finding: BeadPlanReviewFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(finding.severity.rawValue.capitalized, systemImage: severityIcon)
                    .foregroundStyle(severityColor)
                Text(finding.category.displayName)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Text(finding.title)
                .font(.callout.weight(.semibold))
            Text(finding.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var severityIcon: String {
        switch finding.severity {
        case .info:
            "info.circle"
        case .warning:
            "exclamationmark.triangle"
        case .critical:
            "exclamationmark.octagon"
        }
    }

    private var severityColor: Color {
        switch finding.severity {
        case .info:
            .secondary
        case .warning:
            .orange
        case .critical:
            .red
        }
    }
}

private struct PlanReviewChangeRow: View {
    let change: BeadPlanReviewChange
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(change.kind.displayName, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Button("Apply", action: apply)
                    .controlSize(.small)
            }

            Text(primaryText)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(change.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var primaryText: String {
        switch change.kind {
        case .updateField:
            "\(change.field?.displayName ?? "Field"): \(change.value ?? "")"
        case .createBead:
            change.title ?? "Create bead"
        case .createChildBead:
            change.title ?? "Create child bead"
        case .addDependency:
            "Depend on \(change.value ?? "selected bead")"
        case .setParent:
            "Set parent to \(change.value ?? "selected bead")"
        case .setStatus:
            "Set status to \(change.value ?? "selected status")"
        case .setBlocked:
            boolText("Blocked", value: change.value, defaultValue: true)
        case .setStale:
            boolText("Stale", value: change.value, defaultValue: true)
        }
    }

    private var icon: String {
        switch change.kind {
        case .updateField:
            "square.and.pencil"
        case .createBead:
            "plus.square"
        case .createChildBead:
            "plus.square.on.square"
        case .addDependency:
            "link"
        case .setParent:
            "arrowshape.turn.up.left"
        case .setStatus:
            "arrow.left.arrow.right"
        case .setBlocked:
            "exclamationmark.octagon"
        case .setStale:
            "clock.badge.exclamationmark"
        }
    }

    private func boolText(_ label: String, value: String?, defaultValue: Bool) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isOn = normalized.map { !["false", "no", "0", "unblocked", "active"].contains($0) } ?? defaultValue
        return "\(isOn ? "Mark" : "Clear") \(label)"
    }
}

#if os(iOS)
private struct FormBeadInspector: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead
    @Binding var showingEditor: Bool

    var body: some View {
        Form {
            Section {
                Button {
                    showingEditor = true
                } label: {
                    Label("Edit Bead", systemImage: "square.and.pencil")
                }
            }

            Section("Overview") {
                LabeledContent("Title", value: bead.title)
                LabeledContent("Source", value: bead.sourceType.displayName)
                LabeledContent("Priority", value: bead.priority.rawValue.capitalized)
                LabeledContent("Updated") {
                    Text(bead.updatedAt, style: .relative)
                }
            }

            if !bead.summary.isEmpty {
                Section("Summary") {
                    Text(bead.summary)
                }
            }

            Section("Repository") {
                LabeledContent("Branch", value: bead.branchName ?? "None")
                LabeledContent("Issue", value: bead.issueNumber.map { "#\($0)" } ?? "None")
                LabeledContent("Pull Request", value: bead.pullRequestNumber.map { "#\($0)" } ?? "None")
                if let sourceURL = bead.sourceURL {
                    Link("Open Source", destination: sourceURL)
                }
            }

            if !bead.labels.isEmpty {
                Section("Labels") {
                    Text(bead.labels.joined(separator: ", "))
                }
            }

            if !bead.notes.isEmpty {
                Section("Notes") {
                    Text(bead.notes)
                }
            }

            Section("Relationships") {
                RelationshipControls(bead: bead)
            }

            Section("AI Plan Review") {
                PlanReviewControls(bead: bead)
            }

            if let board = store.selectedBoard {
                Section("AI Status Report") {
                    StatusReportButton(board: board, bead: bead, scope: .subtree)
                }
            }

            WorkflowSection(bead: bead)
        }
        .navigationTitle("Bead")
        .sheet(isPresented: $showingEditor) {
            BeadEditorSheet(mode: .edit(bead))
        }
    }
}

private struct TabletLandscapeBeadInspector: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead
    @Binding var showingEditor: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(bead.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(3)

                        Spacer(minLength: 0)

                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit Bead", systemImage: "square.and.pencil")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Edit Bead")
                    }

                    HStack(spacing: 8) {
                        Text(bead.sourceType.displayName)
                        Text(bead.priority.rawValue.capitalized)
                        Text(bead.updatedAt, style: .relative)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !bead.summary.isEmpty {
                    InspectorSection("Summary") {
                        Text(bead.summary)
                            .font(.callout)
                    }
                }

                InspectorSection("Repository") {
                    InspectorRow(label: "Branch", value: bead.branchName ?? "None")
                    InspectorRow(label: "Issue", value: bead.issueNumber.map { "#\($0)" } ?? "None")
                    InspectorRow(label: "Pull Request", value: bead.pullRequestNumber.map { "#\($0)" } ?? "None")
                    if let sourceURL = bead.sourceURL {
                        Link("Open Source", destination: sourceURL)
                    }
                }

                if !bead.labels.isEmpty {
                    InspectorSection("Labels") {
                        Text(bead.labels.joined(separator: ", "))
                            .font(.callout)
                    }
                }

                if !bead.notes.isEmpty {
                    InspectorSection("Notes") {
                        Text(bead.notes)
                            .font(.callout)
                    }
                }

                InspectorSection("Relationships") {
                    RelationshipControls(bead: bead)
                }

                InspectorSection("AI Plan Review") {
                    PlanReviewControls(bead: bead)
                }

                if let board = store.selectedBoard {
                    InspectorSection("AI Status Report") {
                        StatusReportButton(board: board, bead: bead, scope: .subtree)
                    }
                }

                WorkflowSection(bead: bead)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Bead")
        .sheet(isPresented: $showingEditor) {
            BeadEditorSheet(mode: .edit(bead))
        }
    }
}

private struct WorkflowSection: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead

    var body: some View {
        Section("Workflow") {
            if let board = store.selectedBoard {
                Picker("Column", selection: Binding(
                    get: { store.selectedColumnID ?? board.columns.first?.id ?? UUID() },
                    set: { store.moveBead(bead.id, to: $0) }
                )) {
                    ForEach(board.columns) { column in
                        Text(column.name).tag(column.id)
                    }
                }
            }

            Button("Archive", role: .destructive) {
                store.archiveBead(bead.id)
            }
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
#endif

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#if os(macOS)
private struct MacBeadInspector: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead
    @Binding var showingEditor: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Inspector", systemImage: "sidebar.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 12) {
                        Text(bead.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit Bead", systemImage: "square.and.pencil")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .help("Edit Bead")
                    }

                    HStack(spacing: 6) {
                        MacStatusPill(text: bead.sourceType.displayName, systemImage: "note.text")
                        MacStatusPill(text: bead.priority.rawValue.capitalized, systemImage: "flag")
                        Spacer(minLength: 0)
                    }
                }

                if !bead.summary.isEmpty {
                    InspectorSection("Summary") {
                        Text(bead.summary)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                InspectorSection("Repository") {
                    InspectorRow(label: "Branch", value: bead.branchName ?? "None")
                    InspectorRow(label: "Issue", value: bead.issueNumber.map { "#\($0)" } ?? "None")
                    InspectorRow(label: "Pull Request", value: bead.pullRequestNumber.map { "#\($0)" } ?? "None")
                    if let sourceURL = bead.sourceURL {
                        Link("Open Source", destination: sourceURL)
                    }
                }

                if !bead.labels.isEmpty {
                    InspectorSection("Labels") {
                        Text(bead.labels.joined(separator: ", "))
                            .font(.callout)
                    }
                }

                if !bead.notes.isEmpty {
                    InspectorSection("Notes") {
                        Text(bead.notes)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                InspectorSection("Relationships") {
                    RelationshipControls(bead: bead)
                }

                InspectorSection("AI Plan Review") {
                    PlanReviewControls(bead: bead)
                }

                if let board = store.selectedBoard {
                    InspectorSection("AI Status Report") {
                        StatusReportButton(board: board, bead: bead, scope: .subtree)
                    }
                }

                InspectorSection("Workflow") {
                    InspectorRow(label: "Updated", value: bead.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let board = store.selectedBoard {
                        Picker("Column", selection: Binding(
                            get: { store.selectedColumnID ?? board.columns.first?.id ?? UUID() },
                            set: { store.moveBead(bead.id, to: $0) }
                        )) {
                            ForEach(board.columns) { column in
                                Text(column.name).tag(column.id)
                            }
                        }
                    }

                    Button("Archive", role: .destructive) {
                        store.archiveBead(bead.id)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
        .navigationTitle("Bead")
        .sheet(isPresented: $showingEditor) {
            BeadEditorSheet(mode: .edit(bead))
        }
    }
}

private struct MacStatusPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 1)
            }
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
#endif
