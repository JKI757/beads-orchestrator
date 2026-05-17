import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import CoreImage.CIFilterBuiltins
#elseif os(iOS)
import AVFoundation
#endif

struct RootView: View {
    @EnvironmentObject private var store: BoardStore
    #if os(macOS)
    @EnvironmentObject private var server: BeadsHTTPServer
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var showingNewBoard = false
    @State private var showingImportBoard = false
    @State private var showingNewBead = false
    @State private var showingRepositoryImporter = false
    @State private var showingConnectionSettings = false
    @State private var workspaceMode: WorkspaceMode = .board
    #if os(macOS)
    @State private var showingPairingCode = false
    @State private var showingLLMSettings = false
    @State private var showingAIPMDashboard = false
    #endif

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            CompactRootView()
        } else {
            TabletRootView()
        }
        #else
        regularRoot
        #endif
    }

    private var regularRoot: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            if let board = store.selectedBoard {
                switch workspaceMode {
                case .board:
                    BoardView(board: board, presentation: .mac)
                case .hierarchy:
                    HierarchyView(board: board, presentation: .mac)
                }
            } else {
                ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create or connect a repository to start tracking beads."))
            }
        } detail: {
            BeadDetailView(bead: store.selectedBead)
        }
        .searchable(text: $store.searchText, prompt: "Search beads")
        .toolbar {
            ToolbarItemGroup {
                WorkspaceModePicker(selection: $workspaceMode)
                    .disabled(store.selectedBoard == nil)

                Menu {
                    Button("All Sources") {
                        store.sourceFilter = nil
                    }

                    Divider()

                    ForEach(BeadSourceType.allCases) { sourceType in
                        Button(sourceType.displayName) {
                            store.sourceFilter = sourceType
                        }
                    }

                    Divider()

                    Toggle("Needs Attention", isOn: $store.attentionOnly)
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }

                #if os(macOS)
                Menu {
                    if server.isRunning {
                        Button("Stop Server") {
                            server.stop()
                        }
                    } else {
                        Button("Start Server") {
                            server.start()
                        }
                    }

                    if !server.listeningURLString.isEmpty {
                        Button("Show Pairing QR") {
                            showingPairingCode = true
                        }

                        Button("Copy Server URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(server.listeningURLString, forType: .string)
                        }

                        Button("Copy Pairing Payload") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(server.pairingPayloadString, forType: .string)
                        }

                        Button("Copy Pairing Token") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(server.pairingToken, forType: .string)
                        }

                        Button("Regenerate Pairing Token") {
                            server.regeneratePairingToken()
                        }

                        Button("Regenerate and Copy Token") {
                            server.regeneratePairingToken()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(server.pairingToken, forType: .string)
                        }
                    }

                    Divider()

                    Button("LLM Settings") {
                        showingLLMSettings = true
                    }

                    Button("AI PM Dashboard") {
                        showingAIPMDashboard = true
                    }

                    Text(server.llmConfiguration.status.message)

                    Text(server.statusMessage)
                } label: {
                    Label(server.isRunning ? "Server On" : "Server Off", systemImage: server.isRunning ? "network" : "network.slash")
                }
                #else
                Button {
                    showingConnectionSettings = true
                } label: {
                    Label("Server", systemImage: "network")
                }
                #endif

                Button {
                    showingNewBead = true
                } label: {
                    Label("New Bead", systemImage: "plus")
                }
                .disabled(store.selectedBoard == nil)

                Menu {
                    Button("New Empty Board") {
                        showingNewBoard = true
                    }

                    Button("Import Existing Beads Project") {
                        showingImportBoard = true
                    }

                    #if os(macOS)
                    Button("Scan Local Git Repository") {
                        showingRepositoryImporter = true
                    }
                    #endif
                } label: {
                    Label("Boards", systemImage: "rectangle.stack")
                }
            }
        }
        .sheet(isPresented: $showingNewBoard) {
            BoardEditorSheet(mode: .create)
        }
        .sheet(isPresented: $showingImportBoard) {
            BoardEditorSheet(mode: .importExisting)
        }
        .sheet(isPresented: $showingNewBead) {
            BeadEditorSheet(mode: .create(parent: nil))
        }
        .sheet(isPresented: $showingConnectionSettings) {
            ConnectionSettingsSheet()
        }
        #if os(macOS)
        .sheet(isPresented: $showingPairingCode) {
            PairingCodeSheet()
                .environmentObject(server)
        }
        .sheet(isPresented: $showingLLMSettings) {
            LLMSettingsSheet(configurationStore: server.llmConfiguration)
        }
        .sheet(isPresented: $showingAIPMDashboard) {
            AIPMDashboardSheet(pmState: server.aiPMState)
                .environmentObject(server)
        }
        #endif
        #if os(macOS)
        .fileImporter(
            isPresented: $showingRepositoryImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            Task {
                await store.importLocalRepository(at: url)
            }
        }
        #endif
        .alert("Import Error", isPresented: Binding(
            get: { store.importErrorMessage != nil },
            set: { if !$0 { store.importErrorMessage = nil } }
        )) {
            Button("OK") {
                store.importErrorMessage = nil
            }
        } message: {
            Text(store.importErrorMessage ?? "")
        }
    }
}

private enum WorkspaceMode: String, CaseIterable, Identifiable {
    case board
    case hierarchy

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .board: "Board"
        case .hierarchy: "Hierarchy"
        }
    }

    var systemImage: String {
        switch self {
        case .board: "rectangle.3.group"
        case .hierarchy: "list.bullet.indent"
        }
    }
}

private struct WorkspaceModePicker: View {
    @Binding var selection: WorkspaceMode

    var body: some View {
        Picker("View", selection: $selection) {
            ForEach(WorkspaceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 188)
    }
}

private struct WorkspaceModeMenuButton: View {
    @Binding var selection: WorkspaceMode

    var body: some View {
        Menu {
            ForEach(WorkspaceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.title, systemImage: mode == selection ? "checkmark" : mode.systemImage)
                }
            }
        } label: {
            Label(selection.title, systemImage: selection.systemImage)
        }
    }
}

#if os(iOS)
private struct TabletRootView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNewBoard = false
    @State private var showingImportBoard = false
    @State private var showingNewBead = false
    @State private var showingConnectionSettings = false
    @State private var workspaceMode: WorkspaceMode = .board

    var body: some View {
        GeometryReader { proxy in
            if isLandscape(proxy.size) {
                TabletLandscapeWorkspace(
                    showingNewBoard: $showingNewBoard,
                    showingImportBoard: $showingImportBoard,
                    showingNewBead: $showingNewBead,
                    showingConnectionSettings: $showingConnectionSettings,
                    workspaceMode: $workspaceMode
                )
            } else {
                TabletPortraitWorkspace(
                    showingNewBoard: $showingNewBoard,
                    showingImportBoard: $showingImportBoard,
                    showingNewBead: $showingNewBead,
                    showingConnectionSettings: $showingConnectionSettings,
                    workspaceMode: $workspaceMode
                )
            }
        }
        .sheet(isPresented: $showingNewBoard) {
            BoardEditorSheet(mode: .create)
        }
        .sheet(isPresented: $showingImportBoard) {
            BoardEditorSheet(mode: .importExisting)
        }
        .sheet(isPresented: $showingNewBead) {
            BeadEditorSheet(mode: .create(parent: nil))
        }
        .sheet(isPresented: $showingConnectionSettings) {
            ConnectionSettingsSheet()
        }
        .task {
            await store.pullFromRemoteServerIfPaired()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                await store.pullFromRemoteServerIfPaired()
            }
        }
    }

    private func isLandscape(_ size: CGSize) -> Bool {
        let screenBounds = UIScreen.main.bounds
        let nativeBounds = UIScreen.main.nativeBounds
        let sceneIsLandscape = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation.isLandscape ?? false

        return sceneIsLandscape
            || size.width > size.height
            || screenBounds.width > screenBounds.height
            || nativeBounds.width > nativeBounds.height
    }
}

private struct TabletPortraitWorkspace: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var showingNewBoard: Bool
    @Binding var showingImportBoard: Bool
    @Binding var showingNewBead: Bool
    @Binding var showingConnectionSettings: Bool
    @Binding var workspaceMode: WorkspaceMode

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            if let board = store.selectedBoard {
                switch workspaceMode {
                case .board:
                    BoardView(board: board, presentation: .tabletPortrait)
                case .hierarchy:
                    HierarchyView(board: board, presentation: .tabletPortrait)
                }
            } else {
                ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create or connect a repository to start tracking beads."))
            }
        } detail: {
            BeadDetailView(bead: store.selectedBead)
        }
        .searchable(text: $store.searchText, prompt: "Search beads")
        .toolbar {
            ToolbarItemGroup {
                WorkspaceModePicker(selection: $workspaceMode)
                    .disabled(store.selectedBoard == nil)

                Button {
                    showingConnectionSettings = true
                } label: {
                    Label("Server", systemImage: "network")
                }

                FilterMenuButton()

                Button {
                    showingNewBead = true
                } label: {
                    Label("New Bead", systemImage: "plus.circle")
                }
                .disabled(store.selectedBoard == nil)

                BoardMenuButton(showingNewBoard: $showingNewBoard, showingImportBoard: $showingImportBoard)
            }
        }
    }
}

private struct TabletLandscapeWorkspace: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var showingNewBoard: Bool
    @Binding var showingImportBoard: Bool
    @Binding var showingNewBead: Bool
    @Binding var showingConnectionSettings: Bool
    @Binding var workspaceMode: WorkspaceMode

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if let board = store.selectedBoard {
                    switch workspaceMode {
                    case .board:
                        BoardView(board: board, presentation: .tabletLandscape)
                            .frame(maxWidth: .infinity)
                    case .hierarchy:
                        HierarchyView(board: board, presentation: .tabletLandscape)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create or connect a repository to start tracking beads."))
                        .frame(maxWidth: .infinity)
                }

                Divider()

                BeadDetailView(bead: store.selectedBead, presentation: .tabletLandscape)
                    .frame(width: 420)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .navigationTitle(store.selectedBoard?.name ?? "Boards")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $store.searchText, prompt: "Search beads")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(store.activeBoards) { board in
                            Button(board.name) {
                                store.select(board)
                            }
                        }

                        Divider()

                        Button("New Empty Board") {
                            showingNewBoard = true
                        }

                        Button("Import Existing Beads Project") {
                            showingImportBoard = true
                        }
                    } label: {
                        Label("Boards", systemImage: "sidebar.left")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    WorkspaceModePicker(selection: $workspaceMode)
                        .disabled(store.selectedBoard == nil)

                    Button {
                        showingConnectionSettings = true
                    } label: {
                        Label("Server", systemImage: "network")
                    }

                    FilterMenuButton()

                    Button {
                        showingNewBead = true
                    } label: {
                        Label("New Bead", systemImage: "plus")
                    }
                    .disabled(store.selectedBoard == nil)
                }
            }
        }
    }
}

private struct CompactRootView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNewBoard = false
    @State private var showingImportBoard = false
    @State private var showingNewBead = false
    @State private var showingConnectionSettings = false
    @State private var selectedColumnID: BoardColumn.ID?
    @State private var workspaceMode: WorkspaceMode = .board

    var body: some View {
        NavigationStack {
            Group {
                if let board = store.selectedBoard {
                    switch workspaceMode {
                    case .board:
                        CompactBoardView(board: board, selectedColumnID: $selectedColumnID)
                    case .hierarchy:
                        HierarchyView(board: board, presentation: .compact)
                    }
                } else {
                    ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create a board to start tracking beads."))
                }
            }
            .navigationTitle(store.selectedBoard?.name ?? "Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CompactBoardSwitcherButton(
                        showingNewBoard: $showingNewBoard,
                        showingImportBoard: $showingImportBoard
                    )
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    WorkspaceModeMenuButton(selection: $workspaceMode)
                        .disabled(store.selectedBoard == nil)

                    Button {
                        showingConnectionSettings = true
                    } label: {
                        Label("Server", systemImage: "network")
                    }

                    FilterMenuButton()

                    Button {
                        showingNewBead = true
                    } label: {
                        Label("New Bead", systemImage: "plus")
                    }
                    .disabled(store.selectedBoard == nil)
                }
            }
            .sheet(isPresented: $showingNewBoard) {
                BoardEditorSheet(mode: .create)
            }
            .sheet(isPresented: $showingImportBoard) {
                BoardEditorSheet(mode: .importExisting)
            }
            .sheet(isPresented: $showingNewBead) {
                BeadEditorSheet(mode: .create(parent: nil))
            }
            .sheet(isPresented: $showingConnectionSettings) {
                ConnectionSettingsSheet()
            }
        }
        .task {
            await store.pullFromRemoteServerIfPaired()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                await store.pullFromRemoteServerIfPaired()
            }
        }
    }
}

private struct CompactBoardSwitcherButton: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var showingNewBoard: Bool
    @Binding var showingImportBoard: Bool

    var body: some View {
        Menu {
            if store.activeBoards.isEmpty {
                Text("No Boards")
            } else {
                ForEach(store.activeBoards) { board in
                    Button {
                        store.select(board)
                    } label: {
                        Label(board.name, systemImage: board.id == store.selectedBoardID ? "checkmark.circle.fill" : "rectangle")
                    }
                }

                Divider()
            }

            Button("New Empty Board") {
                showingNewBoard = true
            }

            Button("Import Existing Beads Project") {
                showingImportBoard = true
            }
        } label: {
            Label("Boards", systemImage: "rectangle.stack")
        }
    }
}

private struct CompactBoardView: View {
    @EnvironmentObject private var store: BoardStore
    let board: Board
    @Binding var selectedColumnID: BoardColumn.ID?

    private var selectedColumn: BoardColumn {
        board.columns.first { $0.id == selectedColumnID } ?? board.columns.first ?? BoardColumn(name: "Backlog")
    }

    var body: some View {
        VStack(spacing: 0) {
            CompactBoardHeader(board: board)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(board.columns) { column in
                        let count = store.visibleBeads(in: column).count
                        Button {
                            selectedColumnID = column.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(column.name)
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(column.id == selectedColumn.id ? .accentColor : .secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            CompactSearchField()

            List {
                Section {
                    ForEach(store.visibleBeads(in: selectedColumn)) { bead in
                        NavigationLink {
                            BeadDetailView(bead: bead)
                        } label: {
                            BeadCardContent(bead: bead, density: .compact, showsSourceBadge: true)
                                .padding(.vertical, 4)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            store.select(bead)
                        })
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    Text(selectedColumn.name)
                } footer: {
                    if store.visibleBeads(in: selectedColumn).isEmpty {
                        Text("No beads match the current filters.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await store.pullFromRemoteServer()
            }
        }
        .onAppear {
            selectedColumnID = selectedColumnID ?? board.columns.first?.id
        }
        .onChange(of: board.id) {
            selectedColumnID = board.columns.first?.id
        }
    }
}

private struct CompactSearchField: View {
    @EnvironmentObject private var store: BoardStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Title, label, branch", text: $store.searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

private struct CompactBoardHeader: View {
    let board: Board

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(board.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text(board.repositoryPath ?? "No local repository connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            StatusReportButton(board: board, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
#endif

private struct FilterMenuButton: View {
    @EnvironmentObject private var store: BoardStore

    var body: some View {
        Menu {
            Button("All Sources") {
                store.sourceFilter = nil
            }

            Divider()

            ForEach(BeadSourceType.allCases) { sourceType in
                Button(sourceType.displayName) {
                    store.sourceFilter = sourceType
                }
            }

            Divider()

            Toggle("Needs Attention", isOn: $store.attentionOnly)
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

private struct BoardMenuButton: View {
    @Binding var showingNewBoard: Bool
    @Binding var showingImportBoard: Bool

    var body: some View {
        Menu {
            Button("New Empty Board") {
                showingNewBoard = true
            }

            Button("Import Existing Beads Project") {
                showingImportBoard = true
            }
        } label: {
            Label("Boards", systemImage: "rectangle.stack")
        }
    }
}

private struct ConnectionSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BoardStore

    @State private var serverURLString = ""
    @State private var pairingToken = ""
    #if os(iOS)
    @State private var showingScanner = false
    @State private var showingAIPMDashboard = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac Server") {
                    TextField("Server URL", text: $serverURLString)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()

                    SecureField("Pairing token", text: $pairingToken)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Text(store.remoteStatusMessage)
                        .foregroundStyle(.secondary)

                    if let info = store.remoteServerInfo {
                        LabeledContent("Boards", value: "\(info.boardCount)")
                        LabeledContent("Version", value: info.version)
                        LabeledContent("Auth", value: info.authRequired ? "Required" : "Open")

                        if let llmStatus = info.llmStatus {
                            LabeledContent("AI Planning", value: llmStatus.isAvailable ? "Available" : "Unavailable")
                            LabeledContent("AI Provider", value: llmStatus.provider)
                            if let model = llmStatus.model {
                                LabeledContent("AI Model", value: model)
                            }
                            Text(llmStatus.message)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                #if os(iOS)
                if store.remoteConfiguration.isPaired {
                    Section("AI PM") {
                        Button {
                            showingAIPMDashboard = true
                        } label: {
                            Label("Open AI PM", systemImage: "sparkles")
                        }

                        Button {
                            save()
                            Task { await store.fetchRemoteAIPMState() }
                        } label: {
                            Label("Refresh AI PM", systemImage: "arrow.clockwise")
                        }

                        Text(store.remoteAIPMStatusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                Section {
                    #if os(iOS)
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Pairing QR", systemImage: "qrcode.viewfinder")
                    }
                    #endif

                    Button {
                        save()
                        Task { await store.testRemoteConnection() }
                    } label: {
                        Label("Test Connection", systemImage: "checkmark.circle")
                    }

                    Button {
                        save()
                        Task { await store.pullFromRemoteServer() }
                    } label: {
                        Label("Download Latest from Mac", systemImage: "arrow.down.circle")
                    }

                    Button {
                        save()
                        Task { await store.pushToRemoteServer() }
                    } label: {
                        Label("Overwrite Mac with This Device", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .onAppear {
            serverURLString = store.remoteConfiguration.serverURLString
            pairingToken = store.remoteConfiguration.pairingToken
        }
        #if os(iOS)
        .sheet(isPresented: $showingScanner) {
            QRScannerSheet { payloadString in
                applyPairingPayload(payloadString)
                showingScanner = false
            }
        }
        .sheet(isPresented: $showingAIPMDashboard) {
            RemoteAIPMDashboardSheet()
                .environmentObject(store)
        }
        #endif
    }

    private func save() {
        store.saveRemoteConfiguration(BeadsRemoteConfiguration(serverURLString: serverURLString, pairingToken: pairingToken))
    }

    private func applyPairingPayload(_ payloadString: String) {
        guard
            let data = payloadString.data(using: .utf8),
            let payload = try? BeadsJSON.decoder.decode(BeadsPairingPayload.self, from: data)
        else {
            store.remoteStatusMessage = "The QR code was not a Beads-Orchestrator pairing code."
            return
        }

        serverURLString = payload.serverURLString
        pairingToken = payload.pairingToken
        save()
        Task {
            await store.testRemoteConnection()
            await store.pullFromRemoteServerIfPaired()
        }
    }
}

#if os(macOS)
private struct LLMSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var configurationStore: LLMServerConfigurationStore
    @State private var draft = LLMServerConfiguration()
    @State private var discoveredModels: [String] = []
    @State private var endpointMessage: String?
    @State private var isDiscoveringModels = false
    @State private var isTestingEndpoint = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Provider") {
                    Picker("Provider", selection: $draft.provider) {
                        ForEach(LLMProviderKind.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    if draft.provider.requiresEndpoint {
                        TextField("Endpoint URL", text: $draft.endpointURLString)
                            .textFieldStyle(.roundedBorder)

                        if discoveredModels.isEmpty {
                            TextField("Model", text: $draft.modelName)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("Model", selection: $draft.modelName) {
                                ForEach(discoveredModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }

                        HStack {
                            Button {
                                Task { await discoverModels() }
                            } label: {
                                Label("Discover Models", systemImage: "magnifyingglass")
                            }
                            .disabled(isDiscoveringModels || isTestingEndpoint)

                            Button {
                                Task { await testEndpoint() }
                            } label: {
                                Label("Test Endpoint", systemImage: "checkmark.circle")
                            }
                            .disabled(isDiscoveringModels || isTestingEndpoint)
                        }
                    }

                    if draft.provider != .disabled {
                        SecureField("API key", text: $draft.apiKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Optional for local or unauthenticated OpenAI-compatible endpoints.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isDiscoveringModels || isTestingEndpoint {
                        ProgressView(isDiscoveringModels ? "Discovering models..." : "Testing endpoint...")
                    }

                    if let endpointMessage {
                        Text(endpointMessage)
                            .foregroundStyle(endpointMessageColor)
                    }
                }

                Section("Status") {
                    let status = configurationStore.status
                    LabeledContent("Availability", value: status.isAvailable ? "Available" : "Unavailable")
                    LabeledContent("Provider", value: status.provider)
                    if let model = status.model {
                        LabeledContent("Model", value: model)
                    }
                    Text(status.message)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Disable") {
                    draft.provider = .disabled
                    configurationStore.save(draft)
                    dismiss()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Apply") {
                    configurationStore.save(draft)
                    endpointMessage = "Settings applied."
                }

                Button("Save & Close") {
                    configurationStore.save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle("LLM Settings")
        .frame(width: 520)
        .frame(minHeight: 360)
        .onAppear {
            draft = configurationStore.configuration
            discoveredModels = draft.trimmedModelName.isEmpty ? [] : [draft.trimmedModelName]
        }
        .onChange(of: draft.provider) {
            discoveredModels = draft.trimmedModelName.isEmpty ? [] : [draft.trimmedModelName]
            endpointMessage = nil
        }
        .onChange(of: draft.endpointURLString) {
            discoveredModels = draft.trimmedModelName.isEmpty ? [] : [draft.trimmedModelName]
            endpointMessage = nil
        }
    }

    private func discoverModels() async {
        isDiscoveringModels = true
        defer { isDiscoveringModels = false }

        do {
            let models = try await configurationStore.discoverModels(for: draft)
            discoveredModels = models
            if draft.trimmedModelName.isEmpty, let firstModel = models.first {
                draft.modelName = firstModel
            }
            endpointMessage = models.isEmpty
                ? "Endpoint responded, but returned no models."
                : "Endpoint returned \(models.count) model\(models.count == 1 ? "" : "s")."
        } catch {
            endpointMessage = error.localizedDescription
        }
    }

    private func testEndpoint() async {
        isTestingEndpoint = true
        defer { isTestingEndpoint = false }

        let result = await configurationStore.testEndpoint(draft)
        if !result.models.isEmpty {
            discoveredModels = result.models
            if draft.trimmedModelName.isEmpty, let firstModel = result.models.first {
                draft.modelName = firstModel
            }
        }
        endpointMessage = result.message
    }

    private var endpointMessageColor: Color {
        guard let endpointMessage else { return .secondary }
        if endpointMessage.hasPrefix("Endpoint returned") || endpointMessage == "Settings applied." {
            return .green
        }
        return .secondary
    }
}

private struct AIPMDashboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var server: BeadsHTTPServer
    @EnvironmentObject private var store: BoardStore
    @ObservedObject var pmState: AIPMStateStore

    @State private var draft = AIPMAutomationSettings()
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var proposalToApply: AIPMDecisionProposal?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Automation") {
                    Toggle("AI PM enabled", isOn: $draft.isEnabled)

                    Picker("Cadence", selection: $draft.cadence) {
                        ForEach(AIPMCadence.allCases) { cadence in
                            Text(cadence.displayName).tag(cadence)
                        }
                    }

                    Picker("Autonomy", selection: $draft.autonomyLevel) {
                        ForEach(AIPMAutonomyLevel.allCases) { autonomy in
                            Text(autonomy.displayName).tag(autonomy)
                        }
                    }

                    Toggle("Review backlog", isOn: $draft.reviewsBacklog)
                    Toggle("Generate status reports", isOn: $draft.generatesReports)

                    Stepper(value: $draft.maximumProposals, in: 1...20) {
                        LabeledContent("Maximum proposals", value: "\(draft.maximumProposals)")
                    }
                }

                Section("Status") {
                    LabeledContent("Last run", value: lastRunText)
                    LabeledContent("Next run", value: nextRunText)
                    if let summary = pmState.state.lastRunSummary, !summary.isEmpty {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }
                    if let error = pmState.state.lastRunError, !error.isEmpty {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    LabeledContent("Pending decisions", value: "\(pmState.state.pendingProposals.count)")
                    Text(server.llmConfiguration.status.message)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section("Run Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Project Intelligence") {
                    if let intelligence = pmState.state.latestIntelligence {
                        AIPMProjectIntelligenceView(intelligence: intelligence)
                    } else {
                        Text("No project intelligence generated yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pending Decisions") {
                    if pmState.state.pendingProposals.isEmpty {
                        Text("No pending decisions.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pmState.state.pendingProposals) { proposal in
                            AIPMProposalRow(
                                proposal: proposal,
                                applyProposal: {
                                    if proposal.changes.isEmpty {
                                        pmState.updateProposal(proposal.id, status: .accepted)
                                    } else {
                                        proposalToApply = proposal
                                    }
                                },
                                updateStatus: { status in
                                    pmState.updateProposal(proposal.id, status: status)
                                }
                            )
                        }
                    }
                }

                Section("Recent Reports") {
                    if pmState.state.reports.isEmpty {
                        Text("No reports generated yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pmState.state.reports.prefix(5)) { report in
                            AIPMReportRow(report: report)
                        }
                    }
                }

                Section("Audit History") {
                    if pmState.state.auditEvents.isEmpty {
                        Text("No audit events yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pmState.state.auditEvents.prefix(8)) { event in
                            AIPMAuditEventRow(event: event)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Run Now") {
                    Task { await runPM() }
                }
                .disabled(isRunning || !draft.isEnabled || !server.llmConfiguration.status.isAvailable)

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle("AI PM")
        .frame(width: 640)
        .frame(minHeight: 620)
        .onAppear {
            draft = pmState.state.settings
        }
        .sheet(item: $proposalToApply) { proposal in
            AIPMProposalApplySheet(proposal: proposal) { status in
                pmState.updateProposal(proposal.id, status: status)
            }
            .environmentObject(store)
        }
    }

    private var lastRunText: String {
        guard let date = pmState.state.lastRunAt else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var nextRunText: String {
        guard pmState.state.settings.isEnabled, pmState.state.settings.cadence != .manual else { return "Not scheduled" }
        guard let date = pmState.state.nextRunAt else { return "Pending" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func save() {
        server.saveAIPMSettings(draft)
        draft = pmState.state.settings
    }

    private func runPM() async {
        save()
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        do {
            _ = try await server.runAIPM()
            draft = pmState.state.settings
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AIPMProposalRow: View {
    let proposal: AIPMDecisionProposal
    var applyProposal: () -> Void
    var updateStatus: (AIPMProposalStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.title)
                    .font(.headline)
                Spacer()
                Text(proposal.category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(proposal.risk.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(riskColor)
            }

            Text(proposal.summary)
                .foregroundStyle(.secondary)
            Text(proposal.rationale)
                .font(.callout)

            if !proposal.changes.isEmpty {
                Text("\(proposal.changes.count) proposed change\(proposal.changes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(proposal.changes.isEmpty ? "Mark Accepted" : "Review & Apply") {
                    applyProposal()
                }
                Button("Dismiss") {
                    updateStatus(.dismissed)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private var riskColor: Color {
        switch proposal.risk {
        case .low:
            .secondary
        case .medium:
            .orange
        case .high:
            .red
        }
    }
}

private struct AIPMProposalApplySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var server: BeadsHTTPServer
    @EnvironmentObject private var store: BoardStore

    let proposal: AIPMDecisionProposal
    var updateStatus: (AIPMProposalStatus) -> Void

    @State private var selectedChangeIndexes: Set<Int> = []
    @State private var results: [BeadChangeApplicationResult] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Proposal") {
                    Text(proposal.title)
                        .font(.headline)
                    Text(proposal.summary)
                        .foregroundStyle(.secondary)
                    Text(proposal.rationale)
                }

                Section("Changes") {
                    ForEach(Array(proposal.changes.enumerated()), id: \.offset) { index, change in
                        Toggle(isOn: Binding(
                            get: { selectedChangeIndexes.contains(index) },
                            set: { isSelected in
                                if isSelected {
                                    selectedChangeIndexes.insert(index)
                                } else {
                                    selectedChangeIndexes.remove(index)
                                }
                            }
                        )) {
                            AIPMChangeSummary(change: change)
                        }
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { result in
                            Label(result.message, systemImage: result.status.systemImage)
                                .foregroundStyle(result.status.color)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button(results.isEmpty ? "Cancel" : "Done") {
                    dismiss()
                }

                Spacer()

                Button("Apply Selected") {
                    applySelectedChanges()
                }
                .disabled(selectedChangeIndexes.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle("Apply Proposal")
        .frame(width: 560)
        .frame(minHeight: 520)
        .onAppear {
            selectedChangeIndexes = Set(proposal.changes.indices)
        }
    }

    private func applySelectedChanges() {
        results = selectedChangeIndexes
            .sorted()
            .map { store.apply(proposal.changes[$0]) }
        for result in results {
            server.aiPMState.recordActionApplication(
                proposal: proposal,
                change: result.change,
                resultStatus: result.status.auditValue,
                resultMessage: result.message
            )
        }

        if results.allSatisfy({ $0.status != .failed }) {
            updateStatus(.accepted)
        }
    }
}

private struct AIPMChangeSummary: View {
    let change: BeadPlanReviewChange

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(change.kind.displayName, systemImage: icon)
                .font(.caption.weight(.semibold))

            Text(primaryText)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(change.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
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

private extension BeadChangeApplicationStatus {
    var auditValue: String {
        switch self {
        case .applied:
            "applied"
        case .skipped:
            "skipped"
        case .failed:
            "failed"
        }
    }

    var systemImage: String {
        switch self {
        case .applied:
            "checkmark.circle"
        case .skipped:
            "minus.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .applied:
            .green
        case .skipped:
            .secondary
        case .failed:
            .red
        }
    }
}

private struct AIPMReportRow: View {
    let report: AIPMReportSnapshot

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.summary)
                    .foregroundStyle(.secondary)

                ForEach(report.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        ForEach(section.items, id: \.self) { item in
                            Text(item)
                                .font(.callout)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PairingCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var server: BeadsHTTPServer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pair iPhone or iPad")
                        .font(.title2.weight(.semibold))
                    Text(server.listeningURLString)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }

            if let image = QRCodeImageGenerator.image(from: server.pairingPayloadString) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("Pairing Unavailable", systemImage: "qrcode", description: Text("Start the server to generate a pairing code."))
            }

            HStack {
                Button("Copy Pairing Payload") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.pairingPayloadString, forType: .string)
                }

                Button("Copy Token") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.pairingToken, forType: .string)
                }

                Button("Regenerate Token") {
                    server.regeneratePairingToken()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private enum QRCodeImageGenerator {
    static func image(from string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let representation = NSCIImageRep(ciImage: scaledImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
#endif

#if os(iOS)
private struct QRScannerSheet: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            showUnavailableMessage()
            return
        }

        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showUnavailableMessage()
            return
        }

        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach {
            $0.frame = view.bounds
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue
        else { return }

        session.stopRunning()
        onScan?(value)
    }

    private func showUnavailableMessage() {
        let label = UILabel()
        label.text = "Camera unavailable"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

private struct RemoteAIPMDashboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BoardStore
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Text(store.remoteAIPMStatusMessage)
                        .foregroundStyle(.secondary)

                    if let state = store.remoteAIPMState {
                        LabeledContent("Last run", value: lastRunText(for: state))
                        LabeledContent("Next run", value: nextRunText(for: state))
                        LabeledContent("Pending decisions", value: "\(state.pendingProposals.count)")
                        LabeledContent("Cadence", value: state.settings.cadence.displayName)
                        LabeledContent("Autonomy", value: state.settings.autonomyLevel.displayName)
                        if let summary = state.lastRunSummary, !summary.isEmpty {
                            Text(summary)
                                .foregroundStyle(.secondary)
                        }
                        if let error = state.lastRunError, !error.isEmpty {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Project Intelligence") {
                    if let state = store.remoteAIPMState, let intelligence = state.latestIntelligence {
                        AIPMProjectIntelligenceView(intelligence: intelligence)
                    } else {
                        Text("No project intelligence generated yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task { await runPM() }
                    } label: {
                        Label("Run AI PM", systemImage: "play.circle")
                    }
                    .disabled(isRunning)

                    if isRunning {
                        ProgressView()
                    }
                }

                Section("Pending Decisions") {
                    if let state = store.remoteAIPMState, !state.pendingProposals.isEmpty {
                        ForEach(state.pendingProposals) { proposal in
                            RemoteAIPMProposalRow(proposal: proposal)
                        }
                    } else {
                        Text("No pending decisions.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Recent Reports") {
                    if let state = store.remoteAIPMState, !state.reports.isEmpty {
                        ForEach(state.reports.prefix(5)) { report in
                            RemoteAIPMReportRow(report: report)
                        }
                    } else {
                        Text("No reports generated yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Audit History") {
                    if let state = store.remoteAIPMState, !state.auditEvents.isEmpty {
                        ForEach(state.auditEvents.prefix(8)) { event in
                            AIPMAuditEventRow(event: event)
                        }
                    } else {
                        Text("No audit events yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI PM")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        await store.fetchRemoteAIPMState()
    }

    private func runPM() async {
        isRunning = true
        defer { isRunning = false }
        await store.runRemoteAIPM()
    }

    private func lastRunText(for state: AIPMState) -> String {
        guard let date = state.lastRunAt else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func nextRunText(for state: AIPMState) -> String {
        guard state.settings.isEnabled, state.settings.cadence != .manual else { return "Not scheduled" }
        guard let date = state.nextRunAt else { return "Pending" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct RemoteAIPMProposalRow: View {
    let proposal: AIPMDecisionProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.title)
                    .font(.headline)
                Spacer()
                Text(proposal.category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(proposal.risk.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(riskColor)
            }

            Text(proposal.summary)
                .foregroundStyle(.secondary)
            Text(proposal.rationale)
                .font(.callout)

            if !proposal.changes.isEmpty {
                Text("\(proposal.changes.count) proposed change\(proposal.changes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var riskColor: Color {
        switch proposal.risk {
        case .low:
            .secondary
        case .medium:
            .orange
        case .high:
            .red
        }
    }
}

private struct RemoteAIPMReportRow: View {
    let report: AIPMReportSnapshot

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.summary)
                    .foregroundStyle(.secondary)

                ForEach(report.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        ForEach(section.items, id: \.self) { item in
                            Text(item)
                                .font(.callout)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif

private struct AIPMProjectIntelligenceView: View {
    let intelligence: AIPMProjectIntelligenceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabeledContent("Active", value: "\(intelligence.totalActiveBeads)")
                LabeledContent("Blocked", value: "\(intelligence.blockedBeads)")
                LabeledContent("Stale", value: "\(intelligence.staleBeads)")
            }
            .font(.caption)

            Text("Generated \(intelligence.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(intelligence.signals.prefix(6)) { signal in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(signal.severity.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: signal.severity))
                        Text(signal.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(signal.title)
                        .font(.subheadline.weight(.semibold))
                    Text(signal.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !signal.beadIDs.isEmpty {
                        Text(signal.beadIDs.prefix(6).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func color(for severity: AIPMProjectSignalSeverity) -> Color {
        switch severity {
        case .info:
            .secondary
        case .warning:
            .orange
        case .critical:
            .red
        }
    }
}

private struct AIPMAuditEventRow: View {
    let event: AIPMAuditEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.kind.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kindColor)
                Spacer()
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(event.summary)
                .font(.subheadline.weight(.semibold))
            if let message = event.resultMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let change = event.change {
                Text(change.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var kindColor: Color {
        switch event.kind {
        case .runFailed:
            .red
        case .proposalActionApplied:
            .blue
        case .proposalStatusChanged:
            .orange
        case .runCompleted:
            .secondary
        }
    }
}

private enum BoardEditorMode: Equatable {
    case create
    case importExisting

    var title: String {
        switch self {
        case .create:
            "New Empty Board"
        case .importExisting:
            "Import Beads Project"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .create:
            "Create"
        case .importExisting:
            "Import"
        }
    }
}

private struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BoardStore

    let mode: BoardEditorMode

    @State private var name = ""
    @State private var repositoryName = ""
    @State private var selectedRepositoryURL: URL?
    @State private var selectedFolderHasBeadsProject = false
    @State private var showingFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .create:
                    createForm
                case .importExisting:
                    importForm
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmationTitle) {
                        save()
                    }
                    .disabled(confirmationDisabled)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            selectFolder(url)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 320)
        #endif
    }

    private var createForm: some View {
        Group {
            Section("Board") {
                TextField("Name", text: $name)
                TextField("Repository", text: $repositoryName)
            }

            Section("Repository Folder") {
                folderPickerRow

                if selectedFolderHasBeadsProject {
                    Text("This folder already contains a .beads project. Use Import Existing Beads Project to bring those beads into the board.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var importForm: some View {
        Section("Existing Beads Project") {
            folderPickerRow

            if let selectedRepositoryURL {
                if selectedFolderHasBeadsProject {
                    Label("A .beads project will be imported from \(selectedRepositoryURL.lastPathComponent).", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Choose a repository folder that contains a .beads directory.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Choose a repository folder or its .beads directory.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var folderPickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }

                if selectedRepositoryURL != nil {
                    Button("Clear") {
                        selectedRepositoryURL = nil
                        selectedFolderHasBeadsProject = false
                    }
                }
            }

            Text(selectedRepositoryURL?.path(percentEncoded: false) ?? "No folder selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func selectFolder(_ url: URL) {
        selectedRepositoryURL = url
        selectedFolderHasBeadsProject = BeadsProjectImporter.hasBeadsProject(at: url)

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.lastPathComponent == ".beads" ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
        }

        if repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            repositoryName = name
        }
    }

    private func save() {
        switch mode {
        case .create:
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let boardName = trimmedName.isEmpty ? "Untitled Board" : trimmedName
            let trimmedRepositoryName = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            store.createBoard(
                name: boardName,
                repositoryName: trimmedRepositoryName.isEmpty ? boardName : trimmedRepositoryName,
                repositoryPath: selectedRepositoryURL?.path(percentEncoded: false)
            )
        case .importExisting:
            guard let selectedRepositoryURL else { return }
            store.importBeadsProject(at: selectedRepositoryURL)
        }
        dismiss()
    }

    private var confirmationDisabled: Bool {
        switch mode {
        case .create:
            selectedFolderHasBeadsProject
        case .importExisting:
            !selectedFolderHasBeadsProject
        }
    }
}

enum BeadEditorMode {
    case create(parent: Bead?)
    case edit(Bead)

    var title: String {
        switch self {
        case .create(let parent): parent == nil ? "New Bead" : "New Child Bead"
        case .edit: "Edit Bead"
        }
    }

    var editingBeadID: Bead.ID? {
        switch self {
        case .create:
            nil
        case .edit(let bead):
            bead.id
        }
    }
}

struct BeadEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BoardStore
    #if os(macOS)
    @EnvironmentObject private var server: BeadsHTTPServer
    #endif

    let mode: BeadEditorMode
    @State private var draft: BeadDraft
    @State private var suggestionResponse: BeadFieldSuggestionResponse?
    @State private var suggestionErrorMessage: String?
    @State private var isRequestingSuggestions = false

    init(mode: BeadEditorMode) {
        self.mode = mode
        switch mode {
        case .create(let parent):
            var draft = BeadDraft()
            draft.parentBeadsID = parent?.relationshipID
            _draft = State(initialValue: draft)
        case .edit(let bead):
            _draft = State(initialValue: BeadDraft(bead: bead))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bead") {
                    TextField("Title", text: $draft.title)
                    TextField("Summary", text: $draft.summary, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Issue Type", text: Binding(
                        get: { draft.issueType ?? "" },
                        set: { draft.issueType = $0.nilIfBlank }
                    ))
                    TextField("Labels", text: $draft.labelsText)
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(BeadPriority.allCases) { priority in
                            Text(priority.rawValue.capitalized).tag(priority)
                        }
                    }
                }

                Section("Source") {
                    Picker("Type", selection: $draft.sourceType) {
                        ForEach(BeadSourceType.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    TextField("Branch", text: $draft.branchName)
                    TextField("Issue", value: $draft.issueNumber, format: .number)
                    TextField("Pull Request", value: $draft.pullRequestNumber, format: .number)
                }

                Section("Relationships") {
                    Picker("Parent", selection: Binding(
                        get: { draft.parentBeadsID ?? "" },
                        set: { draft.parentBeadsID = $0.nilIfBlank }
                    )) {
                        Text("None").tag("")
                        ForEach(store.possibleParentBeads(excluding: mode.editingBeadID)) { bead in
                            Text(bead.title).tag(bead.relationshipID)
                        }
                    }

                    if !draft.childBeadsIDs.isEmpty {
                        LabeledContent("Children", value: "\(draft.childBeadsIDs.count)")
                    }
                    if !draft.dependencyBeadsIDs.isEmpty {
                        LabeledContent("Depends On", value: "\(draft.dependencyBeadsIDs.count)")
                    }
                    if !draft.dependentBeadsIDs.isEmpty {
                        LabeledContent("Blocks", value: "\(draft.dependentBeadsIDs.count)")
                    }
                }

                Section("Status") {
                    Toggle("Blocked", isOn: $draft.isBlocked)
                    Toggle("Stale", isOn: $draft.isStale)
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("AI Suggestions") {
                    Button {
                        requestSuggestions()
                    } label: {
                        Label(
                            isRequestingSuggestions ? "Requesting Suggestions" : "Suggest Missing Fields",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isRequestingSuggestions)

                    if let suggestionErrorMessage {
                        Text(suggestionErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let suggestionResponse {
                        Text(suggestionResponse.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(suggestionResponse.suggestions) { suggestion in
                            BeadSuggestionRow(suggestion: suggestion) {
                                applySuggestion(suggestion)
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        switch mode {
                        case .create(let parent):
                            if let parent {
                                store.createChildBead(parent: parent, draft: draft)
                            } else {
                                store.createBead(draft: draft)
                            }
                        case .edit(let bead):
                            store.updateBead(bead.id, with: draft)
                        }
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func requestSuggestions() {
        isRequestingSuggestions = true
        suggestionErrorMessage = nil

        Task {
            do {
                let request = BeadFieldSuggestionRequest(
                    boardID: store.selectedBoardID,
                    editingBeadID: mode.editingBeadID,
                    draft: draft
                )

                let response: BeadFieldSuggestionResponse
                #if os(macOS)
                response = try await server.suggestBeadFields(request: request)
                #else
                response = try await store.suggestBeadFields(for: draft, editingBeadID: mode.editingBeadID)
                #endif

                suggestionResponse = response
            } catch {
                suggestionErrorMessage = error.localizedDescription
            }
            isRequestingSuggestions = false
        }
    }

    private func applySuggestion(_ suggestion: BeadFieldSuggestion) {
        switch suggestion.field {
        case .title:
            draft.title = suggestion.value
        case .summary:
            draft.summary = suggestion.value
        case .notes:
            draft.notes = appendedValue(existing: draft.notes, suggested: suggestion.value)
        case .labels:
            draft.labelsText = mergedCommaList(draft.labelsText, suggestion.value)
        case .priority:
            if let priority = BeadPriority(rawValue: suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                draft.priority = priority
            }
        case .issueType:
            draft.issueType = suggestion.value.nilIfBlank
        case .status:
            draft.status = suggestion.value.nilIfBlank
        case .isBlocked:
            draft.isBlocked = boolValue(from: suggestion.value, defaultValue: true)
        case .isStale:
            draft.isStale = boolValue(from: suggestion.value, defaultValue: true)
        case .parentBeadsID:
            draft.parentBeadsID = suggestion.value.nilIfBlank
        case .dependencyBeadsIDs:
            draft.dependencyBeadsIDs = parsedCommaList(suggestion.value)
            draft.dependencyCount = draft.dependencyBeadsIDs.count
        }
    }

    private func boolValue(from value: String, defaultValue: Bool) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return defaultValue }
        switch normalized {
        case "true", "yes", "1", "blocked", "stale":
            return true
        case "false", "no", "0", "unblocked", "active":
            return false
        default:
            return defaultValue
        }
    }

    private func appendedValue(existing: String, suggested: String) -> String {
        let existing = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggested = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty else { return suggested }
        guard !suggested.isEmpty else { return existing }
        return existing + "\n\n" + suggested
    }

    private func mergedCommaList(_ existing: String, _ suggested: String) -> String {
        let values = parsedCommaList(existing) + parsedCommaList(suggested)
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }.joined(separator: ", ")
    }

    private func parsedCommaList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct BeadSuggestionRow: View {
    let suggestion: BeadFieldSuggestion
    var apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(suggestion.field.displayName, systemImage: "sparkle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Apply") {
                    apply()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(suggestion.value)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text(suggestion.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
