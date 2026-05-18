import SwiftUI

#if os(macOS)
struct AIPMWorkspaceView: View {
    @EnvironmentObject private var server: BeadsHTTPServer
    @EnvironmentObject private var store: BoardStore
    @ObservedObject var pmState: AIPMStateStore
    var openLLMSettings: () -> Void = {}

    @State private var draft = AIPMAutomationSettings()
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var proposalToApply: AIPMDecisionProposal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AIPMWorkspaceHeader(
                    boardName: store.selectedBoard?.name ?? "No board selected",
                    hasBoard: store.selectedBoard != nil,
                    status: pmState.state,
                    llmStatus: server.llmConfiguration.status,
                    isRunning: isRunning,
                    runPM: { Task { await runPM() } },
                    saveSettings: save,
                    openLLMSettings: openLLMSettings
                )

                if store.selectedBoard == nil {
                    AIPMWorkspaceAvailabilityBanner(
                        title: "No Board Selected",
                        systemImage: "rectangle.3.group",
                        message: "Select a board before running AI PM."
                    )
                } else if !server.llmConfiguration.status.isAvailable {
                    AIPMWorkspaceAvailabilityBanner(
                        title: "Provider Needs Setup",
                        systemImage: "exclamationmark.triangle",
                        message: server.llmConfiguration.status.message,
                        actionTitle: "LLM Settings",
                        action: openLLMSettings
                    )
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    AIPMMetricCard(title: "Pending", value: "\(pmState.state.pendingProposals.count)", systemImage: "exclamationmark.bubble")
                    AIPMMetricCard(title: "High Risk", value: "\(pmState.state.highRiskPendingProposals.count)", systemImage: "exclamationmark.triangle")
                    AIPMMetricCard(title: "Reports", value: "\(pmState.state.reports.count)", systemImage: "chart.bar.doc.horizontal")
                    AIPMMetricCard(title: "Signals", value: "\(pmState.state.latestIntelligence?.signals.count ?? 0)", systemImage: "waveform.path.ecg")
                }

                AIPMStatusPanel(
                    state: pmState.state,
                    llmStatus: server.llmConfiguration.status,
                    errorMessage: errorMessage,
                    lastRunText: lastRunText,
                    nextRunText: nextRunText,
                    openLLMSettings: openLLMSettings
                )

                GroupBox {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        Toggle("AI PM enabled", isOn: $draft.isEnabled)
                        Toggle("Review backlog", isOn: $draft.reviewsBacklog)
                        Toggle("Generate reports", isOn: $draft.generatesReports)
                        Toggle("Notify on this Mac", isOn: $draft.sendsNotifications)
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
                        Stepper(value: $draft.maximumProposals, in: 1...20) {
                            Text("Max proposals: \(draft.maximumProposals)")
                        }
                    }
                } label: {
                    Label("Automation", systemImage: "slider.horizontal.3")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            if pmState.state.pendingProposals.isEmpty {
                                ContentUnavailableView(
                                    "No Pending Decisions",
                                    systemImage: "checkmark.seal",
                                    description: Text("Run the AI PM to surface risks, sequencing problems, and decisions that need review.")
                                )
                            } else {
                                ForEach(pmState.state.pendingProposals.prefix(6)) { proposal in
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
                                    Divider()
                                }
                            }
                        }
                    } label: {
                        Label("Pending Decisions", systemImage: "person.crop.circle.badge.exclamationmark")
                    }

                    GroupBox {
                        if let intelligence = pmState.state.latestIntelligence {
                            AIPMProjectIntelligenceView(intelligence: intelligence)
                        } else {
                            ContentUnavailableView(
                                "No Project Intelligence",
                                systemImage: "waveform.path.ecg",
                                description: Text("Project signals are generated during each AI PM run.")
                            )
                        }
                    } label: {
                        Label("Project Intelligence", systemImage: "waveform.path.ecg")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            if pmState.state.reports.isEmpty {
                                ContentUnavailableView(
                                    "No Reports",
                                    systemImage: "doc.text.magnifyingglass",
                                    description: Text("Reports appear after AI PM runs with reporting enabled.")
                                )
                            } else {
                                ForEach(pmState.state.reports.prefix(4)) { report in
                                    AIPMReportRow(report: report)
                                }
                            }
                        }
                    } label: {
                        Label("Recent Reports", systemImage: "doc.text.magnifyingglass")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            if pmState.state.auditEvents.isEmpty {
                                ContentUnavailableView(
                                    "No Audit Events",
                                    systemImage: "clock.arrow.circlepath",
                                    description: Text("Runs, failures, proposal decisions, and applied actions are recorded here.")
                                )
                            } else {
                                ForEach(pmState.state.auditEvents.prefix(6)) { event in
                                    AIPMAuditEventRow(event: event)
                                }
                            }
                        }
                    } label: {
                        Label("Audit History", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("AI PM")
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
            _ = try await server.runAIPM(request: AIPMRunRequest(boardID: store.selectedBoardID))
            draft = pmState.state.settings
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AIPMWorkspaceHeader: View {
    let boardName: String
    let hasBoard: Bool
    let status: AIPMState
    let llmStatus: BeadsLLMStatus
    let isRunning: Bool
    var runPM: () -> Void
    var saveSettings: () -> Void
    var openLLMSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI PM")
                        .font(.largeTitle.weight(.semibold))
                    Text(boardName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(status.lastRunSummary ?? "Run the AI PM to generate decisions, reports, and project intelligence.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack {
                    Button {
                        runPM()
                    } label: {
                        Label("Run", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)

                    Button {
                        saveSettings()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openLLMSettings()
                    } label: {
                        Label("LLM", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                Label(status.settings.isEnabled ? "Enabled" : "Disabled", systemImage: status.settings.isEnabled ? "checkmark.circle" : "pause.circle")
                Label(llmStatus.isAvailable ? "Provider Ready" : "Provider Needs Setup", systemImage: llmStatus.isAvailable ? "bolt.circle" : "exclamationmark.triangle")
                if isRunning {
                    Label("Running", systemImage: "hourglass")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var canRun: Bool {
        !isRunning && status.settings.isEnabled && llmStatus.isAvailable && hasBoard
    }
}

private struct AIPMWorkspaceAvailabilityBanner: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct AIPMStatusPanel: View {
    let state: AIPMState
    let llmStatus: BeadsLLMStatus
    let errorMessage: String?
    let lastRunText: String
    let nextRunText: String
    var openLLMSettings: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    LabeledContent("Last run", value: lastRunText)
                    LabeledContent("Next run", value: nextRunText)
                }
                .font(.callout)

                if let error = errorMessage ?? state.lastRunError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(llmStatus.message)
                        if let model = llmStatus.model, !model.isEmpty {
                            Text("\(llmStatus.provider) / \(model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !llmStatus.isAvailable {
                        Button("Open LLM Settings") {
                            openLLMSettings()
                        }
                    }
                }
            }
        } label: {
            Label("Status", systemImage: "sparkles")
        }
    }
}

private struct AIPMMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AIPMDashboardSheet: View {
    @ObservedObject var pmState: AIPMStateStore

    var body: some View {
        AIPMDashboardContent(pmState: pmState, showsSheetActions: true)
            .frame(width: 640)
            .frame(minHeight: 620)
    }
}

private struct AIPMDashboardContent: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var server: BeadsHTTPServer
    @EnvironmentObject private var store: BoardStore
    @ObservedObject var pmState: AIPMStateStore
    var showsSheetActions = false

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

                Section("Notifications") {
                    Toggle("Notify on this Mac", isOn: $draft.sendsNotifications)
                    Toggle("High-risk proposals", isOn: $draft.notifiesHighRiskProposals)
                        .disabled(!draft.sendsNotifications)
                    Toggle("Run failures", isOn: $draft.notifiesRunFailures)
                        .disabled(!draft.sendsNotifications)
                    Text("Notifications point back to the AI PM dashboard so decisions stay reviewable in the canonical server state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            if showsSheetActions {
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
        }
        .navigationTitle("AI PM")
        .toolbar {
            ToolbarItemGroup {
                if !showsSheetActions {
                    Button {
                        Task { await runPM() }
                    } label: {
                        Label("Run AI PM", systemImage: "play.circle")
                    }
                    .disabled(isRunning || !draft.isEnabled || !server.llmConfiguration.status.isAvailable)

                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle")
                    }

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
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
#endif

struct AIPMProjectIntelligenceView: View {
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

struct AIPMAuditEventRow: View {
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
