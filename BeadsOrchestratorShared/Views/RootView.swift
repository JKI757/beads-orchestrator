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
        VStack(alignment: .leading, spacing: 4) {
            Text(board.name)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Text(board.repositoryPath ?? "No local repository connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
                    }
                }

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
#endif

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

    let mode: BeadEditorMode
    @State private var draft: BeadDraft

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
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
