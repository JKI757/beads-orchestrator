import SwiftUI

struct BeadDetailView: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead?
    var presentation: BeadDetailPresentation = .automatic
    @State private var showingEditor = false

    var body: some View {
        Group {
            if let bead {
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
}

enum BeadDetailPresentation {
    case automatic
    case tabletLandscape
}

#if os(iOS)
private struct FormBeadInspector: View {
    @EnvironmentObject private var store: BoardStore
    let bead: Bead
    @Binding var showingEditor: Bool

    var body: some View {
        Form {
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

            WorkflowSection(bead: bead)
        }
        .navigationTitle("Bead")
        .toolbar {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        .sheet(isPresented: $showingEditor) {
            BeadEditorSheet(mode: .edit(bead))
        }
    }
}

private struct TabletLandscapeBeadInspector: View {
    let bead: Bead
    @Binding var showingEditor: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bead.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
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

                WorkflowSection(bead: bead)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Bead")
        .toolbar {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
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
                    Text(bead.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

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
        .toolbar {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
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
