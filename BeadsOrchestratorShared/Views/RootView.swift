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
    @State private var showingNewBead = false
    @State private var showingRepositoryImporter = false
    @State private var showingConnectionSettings = false
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
                BoardView(board: board, presentation: .mac)
            } else {
                ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create or connect a repository to start tracking beads."))
            }
        } detail: {
            BeadDetailView(bead: store.selectedBead)
        }
        .searchable(text: $store.searchText, prompt: "Search beads")
        .toolbar {
            ToolbarItemGroup {
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

                        Button("Regenerate Pairing Token") {
                            server.regeneratePairingToken()
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
                    Button("New Board") {
                        showingNewBoard = true
                    }

                    #if os(macOS)
                    Button("Import Local Repository") {
                        showingRepositoryImporter = true
                    }
                    #endif
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewBoard) {
            BoardEditorSheet()
        }
        .sheet(isPresented: $showingNewBead) {
            BeadEditorSheet(mode: .create)
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

#if os(iOS)
private struct TabletRootView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var showingNewBoard = false
    @State private var showingNewBead = false
    @State private var showingConnectionSettings = false

    var body: some View {
        GeometryReader { proxy in
            if isLandscape(proxy.size) {
                TabletLandscapeWorkspace(
                    showingNewBoard: $showingNewBoard,
                    showingNewBead: $showingNewBead,
                    showingConnectionSettings: $showingConnectionSettings
                )
            } else {
                TabletPortraitWorkspace(
                    showingNewBoard: $showingNewBoard,
                    showingNewBead: $showingNewBead,
                    showingConnectionSettings: $showingConnectionSettings
                )
            }
        }
        .sheet(isPresented: $showingNewBoard) {
            BoardEditorSheet()
        }
        .sheet(isPresented: $showingNewBead) {
            BeadEditorSheet(mode: .create)
        }
        .sheet(isPresented: $showingConnectionSettings) {
            ConnectionSettingsSheet()
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
    @Binding var showingNewBead: Bool
    @Binding var showingConnectionSettings: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            if let board = store.selectedBoard {
                BoardView(board: board, presentation: .tabletPortrait)
            } else {
                ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create or connect a repository to start tracking beads."))
            }
        } detail: {
            BeadDetailView(bead: store.selectedBead)
        }
        .searchable(text: $store.searchText, prompt: "Search beads")
        .toolbar {
            ToolbarItemGroup {
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

                BoardMenuButton(showingNewBoard: $showingNewBoard)
            }
        }
    }
}

private struct TabletLandscapeWorkspace: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var showingNewBoard: Bool
    @Binding var showingNewBead: Bool
    @Binding var showingConnectionSettings: Bool

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if let board = store.selectedBoard {
                    BoardView(board: board, presentation: .tabletLandscape)
                        .frame(maxWidth: .infinity)
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

                        Button("New Board") {
                            showingNewBoard = true
                        }
                    } label: {
                        Label("Boards", systemImage: "sidebar.left")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
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
    @State private var showingNewBoard = false
    @State private var showingNewBead = false
    @State private var showingConnectionSettings = false
    @State private var selectedColumnID: BoardColumn.ID?

    var body: some View {
        NavigationStack {
            Group {
                if let board = store.selectedBoard {
                    CompactBoardView(board: board, selectedColumnID: $selectedColumnID)
                } else {
                    ContentUnavailableView("No Board", systemImage: "rectangle.3.group", description: Text("Create a board to start tracking beads."))
                }
            }
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BoardMenuButton(showingNewBoard: $showingNewBoard)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
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
                BoardEditorSheet()
            }
            .sheet(isPresented: $showingNewBead) {
                BeadEditorSheet(mode: .create)
            }
            .sheet(isPresented: $showingConnectionSettings) {
                ConnectionSettingsSheet()
            }
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

    var body: some View {
        Button {
            showingNewBoard = true
        } label: {
            Label("New Board", systemImage: "rectangle.stack.badge.plus")
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
                        Label("Refresh From Mac", systemImage: "arrow.clockwise")
                    }

                    Button {
                        save()
                        Task { await store.pushToRemoteServer() }
                    } label: {
                        Label("Replace Mac Snapshot", systemImage: "square.and.arrow.up")
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
        Task { await store.testRemoteConnection() }
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

private struct BoardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BoardStore

    @State private var name = ""
    @State private var repositoryName = ""
    @State private var repositoryPath = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Board") {
                    TextField("Name", text: $name)
                    TextField("Repository", text: $repositoryName)
                    TextField("Repository path", text: $repositoryPath)
                }
            }
            .navigationTitle("New Board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.createBoard(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Board" : name,
                            repositoryName: repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : repositoryName,
                            repositoryPath: repositoryPath
                        )
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #endif
    }
}

enum BeadEditorMode {
    case create
    case edit(Bead)

    var title: String {
        switch self {
        case .create: "New Bead"
        case .edit: "Edit Bead"
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
        case .create:
            _draft = State(initialValue: BeadDraft())
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
                        case .create:
                            store.createBead(draft: draft)
                        case .edit(let bead):
                            store.updateBead(bead.id, with: draft)
                        }
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}
