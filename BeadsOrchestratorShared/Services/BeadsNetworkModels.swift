import Foundation
import Combine

struct BeadsServerInfo: Codable, Equatable {
    var name: String
    var version: String
    var boardCount: Int
    var updatedAt: Date
    var authRequired: Bool
    var capabilities: [String]
    var llmStatus: BeadsLLMStatus?
}

struct BeadsLLMStatus: Codable, Equatable {
    var isAvailable: Bool
    var provider: String
    var model: String?
    var message: String
    var updatedAt: Date
}

struct BeadFieldSuggestionRequest: Codable, Equatable {
    var boardID: Board.ID?
    var editingBeadID: Bead.ID?
    var draft: BeadDraft
}

struct BeadFieldSuggestionResponse: Codable, Equatable {
    var message: String
    var suggestions: [BeadFieldSuggestion]
    var generatedAt: Date
}

struct BeadFieldSuggestion: Codable, Equatable, Identifiable {
    var field: BeadSuggestionField
    var value: String
    var rationale: String

    var id: String {
        "\(field.rawValue)|\(value)"
    }
}

struct BeadPlanReviewRequest: Codable, Equatable {
    var boardID: Board.ID?
    var beadID: Bead.ID
    var scope: BeadPlanReviewScope
}

enum BeadPlanReviewScope: String, Codable, CaseIterable, Identifiable {
    case bead
    case subtree

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .bead:
            "Bead"
        case .subtree:
            "Subtree"
        }
    }
}

struct BeadPlanReviewResponse: Codable, Equatable {
    var message: String
    var findings: [BeadPlanReviewFinding]
    var changes: [BeadPlanReviewChange]
    var generatedAt: Date
}

struct BeadPlanReviewFinding: Codable, Equatable, Identifiable {
    var severity: BeadPlanReviewSeverity
    var category: BeadPlanReviewCategory
    var title: String
    var detail: String

    var id: String {
        "\(severity.rawValue)|\(category.rawValue)|\(title)"
    }
}

enum BeadPlanReviewSeverity: String, Codable, CaseIterable, Identifiable {
    case info
    case warning
    case critical

    var id: String {
        rawValue
    }
}

enum BeadPlanReviewCategory: String, Codable, CaseIterable, Identifiable {
    case scope
    case acceptanceCriteria
    case dependencies
    case sequencing
    case risk
    case decomposition

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .scope:
            "Scope"
        case .acceptanceCriteria:
            "Acceptance Criteria"
        case .dependencies:
            "Dependencies"
        case .sequencing:
            "Sequencing"
        case .risk:
            "Risk"
        case .decomposition:
            "Decomposition"
        }
    }
}

struct BeadPlanReviewChange: Codable, Equatable, Identifiable {
    var kind: BeadPlanReviewChangeKind
    var targetBeadsID: String?
    var field: BeadSuggestionField?
    var value: String?
    var title: String?
    var summary: String?
    var notes: String?
    var labels: [String]?
    var priority: BeadPriority?
    var issueType: String?
    var rationale: String

    var id: String {
        [
            kind.rawValue,
            targetBeadsID ?? "",
            field?.rawValue ?? "",
            value ?? "",
            title ?? "",
            rationale
        ].joined(separator: "|")
    }
}

enum BeadPlanReviewChangeKind: String, Codable, CaseIterable, Identifiable {
    case updateField
    case createBead
    case createChildBead
    case addDependency
    case setParent
    case setStatus
    case setBlocked
    case setStale

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .updateField:
            "Update Field"
        case .createBead:
            "Create Bead"
        case .createChildBead:
            "Create Child"
        case .addDependency:
            "Add Dependency"
        case .setParent:
            "Set Parent"
        case .setStatus:
            "Set Status"
        case .setBlocked:
            "Set Blocked"
        case .setStale:
            "Set Stale"
        }
    }
}

struct BeadStatusReportRequest: Codable, Equatable {
    var boardID: Board.ID?
    var beadID: Bead.ID?
    var scope: BeadStatusReportScope
}

enum BeadStatusReportScope: String, Codable, CaseIterable, Identifiable {
    case board
    case subtree

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .board:
            "Board"
        case .subtree:
            "Subtree"
        }
    }
}

struct BeadStatusReportResponse: Codable, Equatable {
    var title: String
    var summary: String
    var sections: [BeadStatusReportSection]
    var generatedAt: Date
}

struct BeadStatusReportSection: Codable, Equatable, Identifiable {
    var title: String
    var items: [String]

    var id: String {
        title
    }
}

struct AIPMAutomationSettings: Codable, Equatable {
    var isEnabled: Bool
    var cadence: AIPMCadence
    var autonomyLevel: AIPMAutonomyLevel
    var reviewsBacklog: Bool
    var generatesReports: Bool
    var maximumProposals: Int

    init(
        isEnabled: Bool = true,
        cadence: AIPMCadence = .manual,
        autonomyLevel: AIPMAutonomyLevel = .surfaceDecisions,
        reviewsBacklog: Bool = true,
        generatesReports: Bool = true,
        maximumProposals: Int = 8
    ) {
        self.isEnabled = isEnabled
        self.cadence = cadence
        self.autonomyLevel = autonomyLevel
        self.reviewsBacklog = reviewsBacklog
        self.generatesReports = generatesReports
        self.maximumProposals = maximumProposals
    }
}

enum AIPMCadence: String, Codable, CaseIterable, Identifiable {
    case manual
    case hourly
    case daily

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .manual:
            "Manual"
        case .hourly:
            "Hourly"
        case .daily:
            "Daily"
        }
    }

    var intervalSeconds: TimeInterval? {
        switch self {
        case .manual:
            nil
        case .hourly:
            60 * 60
        case .daily:
            24 * 60 * 60
        }
    }
}

enum AIPMAutonomyLevel: String, Codable, CaseIterable, Identifiable {
    case surfaceDecisions
    case autonomousProposals

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .surfaceDecisions:
            "Surface Decisions"
        case .autonomousProposals:
            "Autonomous Proposals"
        }
    }
}

struct AIPMState: Codable, Equatable {
    var settings: AIPMAutomationSettings
    var lastRunAt: Date?
    var lastRunSummary: String?
    var lastRunError: String?
    var nextRunAt: Date?
    var latestIntelligence: AIPMProjectIntelligenceSummary?
    var proposals: [AIPMDecisionProposal]
    var reports: [AIPMReportSnapshot]
    var auditEvents: [AIPMAuditEvent]
    var updatedAt: Date

    init(
        settings: AIPMAutomationSettings = AIPMAutomationSettings(),
        lastRunAt: Date? = nil,
        lastRunSummary: String? = nil,
        lastRunError: String? = nil,
        nextRunAt: Date? = nil,
        latestIntelligence: AIPMProjectIntelligenceSummary? = nil,
        proposals: [AIPMDecisionProposal] = [],
        reports: [AIPMReportSnapshot] = [],
        auditEvents: [AIPMAuditEvent] = [],
        updatedAt: Date = .now
    ) {
        self.settings = settings
        self.lastRunAt = lastRunAt
        self.lastRunSummary = lastRunSummary
        self.lastRunError = lastRunError
        self.nextRunAt = nextRunAt
        self.latestIntelligence = latestIntelligence
        self.proposals = proposals
        self.reports = reports
        self.auditEvents = auditEvents
        self.updatedAt = updatedAt
    }

    var pendingProposals: [AIPMDecisionProposal] {
        proposals.filter { $0.status == .pending }
    }

    private enum CodingKeys: String, CodingKey {
        case settings
        case lastRunAt
        case lastRunSummary
        case lastRunError
        case nextRunAt
        case latestIntelligence
        case proposals
        case reports
        case auditEvents
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(AIPMAutomationSettings.self, forKey: .settings) ?? AIPMAutomationSettings()
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        lastRunSummary = try container.decodeIfPresent(String.self, forKey: .lastRunSummary)
        lastRunError = try container.decodeIfPresent(String.self, forKey: .lastRunError)
        nextRunAt = try container.decodeIfPresent(Date.self, forKey: .nextRunAt)
        latestIntelligence = try container.decodeIfPresent(AIPMProjectIntelligenceSummary.self, forKey: .latestIntelligence)
        proposals = try container.decodeIfPresent([AIPMDecisionProposal].self, forKey: .proposals) ?? []
        reports = try container.decodeIfPresent([AIPMReportSnapshot].self, forKey: .reports) ?? []
        auditEvents = try container.decodeIfPresent([AIPMAuditEvent].self, forKey: .auditEvents) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

struct AIPMDecisionProposal: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var category: AIPMProposalCategory
    var risk: AIPMProposalRisk
    var rationale: String
    var changes: [BeadPlanReviewChange]
    var status: AIPMProposalStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        category: AIPMProposalCategory,
        risk: AIPMProposalRisk,
        rationale: String,
        changes: [BeadPlanReviewChange] = [],
        status: AIPMProposalStatus = .pending,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.risk = risk
        self.rationale = rationale
        self.changes = changes
        self.status = status
        self.createdAt = createdAt
    }
}

enum AIPMProposalCategory: String, Codable, CaseIterable, Identifiable {
    case backlog
    case planning
    case risk
    case milestone
    case decision
    case handoff

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum AIPMProposalRisk: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String {
        rawValue
    }
}

enum AIPMProposalStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case dismissed

    var id: String {
        rawValue
    }
}

struct AIPMReportSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var sections: [BeadStatusReportSection]
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        sections: [BeadStatusReportSection],
        generatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sections = sections
        self.generatedAt = generatedAt
    }
}

struct AIPMAuditEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: AIPMAuditEventKind
    var actor: String
    var summary: String
    var proposalID: AIPMDecisionProposal.ID?
    var proposalTitle: String?
    var change: BeadPlanReviewChange?
    var resultStatus: String?
    var resultMessage: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AIPMAuditEventKind,
        actor: String = "AI PM",
        summary: String,
        proposalID: AIPMDecisionProposal.ID? = nil,
        proposalTitle: String? = nil,
        change: BeadPlanReviewChange? = nil,
        resultStatus: String? = nil,
        resultMessage: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.summary = summary
        self.proposalID = proposalID
        self.proposalTitle = proposalTitle
        self.change = change
        self.resultStatus = resultStatus
        self.resultMessage = resultMessage
        self.createdAt = createdAt
    }
}

enum AIPMAuditEventKind: String, Codable, CaseIterable, Identifiable {
    case runCompleted
    case runFailed
    case proposalStatusChanged
    case proposalActionApplied

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .runCompleted:
            "Run Completed"
        case .runFailed:
            "Run Failed"
        case .proposalStatusChanged:
            "Decision Updated"
        case .proposalActionApplied:
            "Action Applied"
        }
    }
}

struct AIPMProjectIntelligenceSummary: Codable, Equatable {
    var boardID: Board.ID
    var boardName: String
    var totalActiveBeads: Int
    var blockedBeads: Int
    var staleBeads: Int
    var urgentBeads: Int
    var orphanedChildren: Int
    var dependencyIssues: Int
    var signals: [AIPMProjectSignal]
    var generatedAt: Date
}

struct AIPMProjectSignal: Codable, Equatable, Identifiable {
    var id: UUID
    var severity: AIPMProjectSignalSeverity
    var category: AIPMProjectSignalCategory
    var title: String
    var detail: String
    var beadIDs: [String]

    init(
        id: UUID = UUID(),
        severity: AIPMProjectSignalSeverity,
        category: AIPMProjectSignalCategory,
        title: String,
        detail: String,
        beadIDs: [String] = []
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.detail = detail
        self.beadIDs = beadIDs
    }
}

enum AIPMProjectSignalSeverity: String, Codable, CaseIterable, Identifiable {
    case info
    case warning
    case critical

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum AIPMProjectSignalCategory: String, Codable, CaseIterable, Identifiable {
    case blocked
    case stale
    case workload
    case hierarchy
    case dependency
    case quality
    case health

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue.capitalized
    }
}

struct AIPMRunRequest: Codable, Equatable {
    var boardID: Board.ID?
}

enum BeadSuggestionField: String, Codable, CaseIterable, Identifiable {
    case title
    case summary
    case notes
    case labels
    case priority
    case issueType
    case status
    case isBlocked
    case isStale
    case parentBeadsID
    case dependencyBeadsIDs

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .title:
            "Title"
        case .summary:
            "Description"
        case .notes:
            "Acceptance Criteria"
        case .labels:
            "Labels"
        case .priority:
            "Priority"
        case .issueType:
            "Issue Type"
        case .status:
            "Status"
        case .isBlocked:
            "Blocked"
        case .isStale:
            "Stale"
        case .parentBeadsID:
            "Parent"
        case .dependencyBeadsIDs:
            "Dependencies"
        }
    }
}

struct BeadsRemoteConfiguration: Codable, Equatable {
    var serverURLString: String
    var pairingToken: String

    init(serverURLString: String, pairingToken: String = "") {
        self.serverURLString = serverURLString
        self.pairingToken = pairingToken
    }

    var serverURL: URL? {
        URL(string: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var normalizedPairingToken: String {
        pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isPaired: Bool {
        !normalizedPairingToken.isEmpty
    }
}

struct BeadsPairingPayload: Codable, Equatable {
    var serverURLString: String
    var pairingToken: String

    var remoteConfiguration: BeadsRemoteConfiguration {
        BeadsRemoteConfiguration(serverURLString: serverURLString, pairingToken: pairingToken)
    }
}

enum BeadsNetworkError: LocalizedError {
    case invalidServerURL
    case missingPairingToken
    case invalidResponse
    case httpStatus(Int)
    case httpMessage(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "Enter a valid server URL, such as http://100.64.0.10:8787."
        case .missingPairingToken:
            "Pair this device with the Mac server before syncing."
        case .invalidResponse:
            "The server returned an invalid response."
        case let .httpStatus(status):
            "The server returned HTTP \(status)."
        case let .httpMessage(status, message):
            "The server returned HTTP \(status): \(message)"
        }
    }
}

enum BeadsJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum LLMProviderKind: String, Codable, CaseIterable, Identifiable {
    case disabled
    case localOpenAICompatible
    case remoteOpenAICompatible

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .disabled:
            "Disabled"
        case .localOpenAICompatible:
            "Local OpenAI-Compatible"
        case .remoteOpenAICompatible:
            "Remote OpenAI-Compatible"
        }
    }

    var requiresEndpoint: Bool {
        self != .disabled
    }

    var requiresAPIKey: Bool {
        self == .remoteOpenAICompatible
    }
}

struct LLMServerConfiguration: Codable, Equatable {
    var provider: LLMProviderKind
    var endpointURLString: String
    var modelName: String
    var apiKey: String

    init(
        provider: LLMProviderKind = .disabled,
        endpointURLString: String = "http://127.0.0.1:11434/v1",
        modelName: String = "",
        apiKey: String = ""
    ) {
        self.provider = provider
        self.endpointURLString = endpointURLString
        self.modelName = modelName
        self.apiKey = apiKey
    }

    var trimmedEndpointURLString: String {
        endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelName: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var endpointURL: URL? {
        URL(string: trimmedEndpointURLString)
    }
}

#if os(macOS)
@MainActor
final class LLMServerConfigurationStore: ObservableObject {
    @Published private(set) var configuration: LLMServerConfiguration
    @Published private var lastFailureMessage: String?

    private let persistenceURL: URL

    init(persistenceURL: URL? = nil) {
        let persistenceURL = persistenceURL ?? Self.defaultPersistenceURL
        self.persistenceURL = persistenceURL
        self.configuration = Self.loadConfiguration(from: persistenceURL) ?? LLMServerConfiguration()
    }

    var status: BeadsLLMStatus {
        sanitizedStatus(for: configuration)
    }

    func save(_ configuration: LLMServerConfiguration) {
        var sanitizedConfiguration = configuration
        sanitizedConfiguration.endpointURLString = configuration.trimmedEndpointURLString
        sanitizedConfiguration.modelName = configuration.trimmedModelName
        sanitizedConfiguration.apiKey = configuration.trimmedAPIKey
        self.configuration = sanitizedConfiguration
        lastFailureMessage = nil
        persist()
    }

    func recordProviderFailure(_ message: String) {
        lastFailureMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedStatus(for configuration: LLMServerConfiguration) -> BeadsLLMStatus {
        let providerName = configuration.provider.displayName
        let modelName = configuration.trimmedModelName

        guard configuration.provider != .disabled else {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: nil,
                message: "Planning assistance is disabled on this Mac.",
                updatedAt: Date()
            )
        }

        guard isValidEndpoint(configuration.endpointURL) else {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: modelName.isEmpty ? nil : modelName,
                message: "Enter a valid HTTP endpoint for the LLM provider.",
                updatedAt: Date()
            )
        }

        guard !modelName.isEmpty else {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: nil,
                message: "Choose a model before enabling planning assistance.",
                updatedAt: Date()
            )
        }

        if configuration.provider.requiresAPIKey, configuration.trimmedAPIKey.isEmpty {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: modelName,
                message: "Add an API key for the remote LLM provider.",
                updatedAt: Date()
            )
        }

        if let lastFailureMessage, !lastFailureMessage.isEmpty {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: modelName,
                message: "LLM provider failed safely: \(lastFailureMessage)",
                updatedAt: Date()
            )
        }

        return BeadsLLMStatus(
            isAvailable: true,
            provider: providerName,
            model: modelName,
            message: "Planning assistance is configured on the Mac server.",
            updatedAt: Date()
        )
    }

    private func isValidEndpoint(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func persist() {
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try BeadsJSON.encoder.encode(configuration)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            lastFailureMessage = "Could not save LLM configuration."
        }
    }

    private static func loadConfiguration(from url: URL) -> LLMServerConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? BeadsJSON.decoder.decode(LLMServerConfiguration.self, from: data)
    }

    private static var defaultPersistenceURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root
            .appendingPathComponent("Beads-Orchestrator", isDirectory: true)
            .appendingPathComponent("llm-configuration.json")
    }
}
#endif

#if os(macOS)
@MainActor
final class AIPMStateStore: ObservableObject {
    @Published private(set) var state: AIPMState

    private let persistenceURL: URL

    init(persistenceURL: URL? = nil) {
        let persistenceURL = persistenceURL ?? Self.defaultPersistenceURL
        self.persistenceURL = persistenceURL
        self.state = Self.loadState(from: persistenceURL) ?? AIPMState()
    }

    func saveSettings(_ settings: AIPMAutomationSettings) {
        var nextState = state
        nextState.settings = sanitized(settings)
        nextState.nextRunAt = nextScheduledRunDate(for: nextState)
        nextState.updatedAt = .now
        state = nextState
        persist()
    }

    func recordRun(
        summary: String,
        proposals: [AIPMDecisionProposal],
        report: AIPMReportSnapshot?,
        intelligence: AIPMProjectIntelligenceSummary?
    ) {
        var nextState = state
        nextState.lastRunAt = .now
        nextState.lastRunSummary = summary
        nextState.lastRunError = nil
        nextState.latestIntelligence = intelligence
        nextState.proposals = Array((proposals + nextState.proposals).prefix(40))
        if let report {
            nextState.reports = Array(([report] + nextState.reports).prefix(20))
        }
        nextState.auditEvents = prependingAuditEvent(
            AIPMAuditEvent(
                kind: .runCompleted,
                summary: summary,
                resultMessage: "\(proposals.count) proposal\(proposals.count == 1 ? "" : "s") generated"
            ),
            to: nextState.auditEvents
        )
        nextState.nextRunAt = nextScheduledRunDate(for: nextState)
        nextState.updatedAt = .now
        state = nextState
        persist()
    }

    func recordRunFailure(_ message: String) {
        var nextState = state
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        nextState.lastRunError = trimmedMessage.isEmpty ? nil : trimmedMessage
        nextState.auditEvents = prependingAuditEvent(
            AIPMAuditEvent(
                kind: .runFailed,
                summary: "AI PM run failed",
                resultStatus: "failed",
                resultMessage: trimmedMessage
            ),
            to: nextState.auditEvents
        )
        nextState.nextRunAt = nextScheduledRunDate(for: nextState)
        nextState.updatedAt = .now
        state = nextState
        persist()
    }

    func refreshSchedule() {
        var nextState = state
        nextState.nextRunAt = nextScheduledRunDate(for: nextState)
        nextState.updatedAt = .now
        state = nextState
        persist()
    }

    func updateProposal(_ proposalID: AIPMDecisionProposal.ID, status: AIPMProposalStatus) {
        var nextState = state
        guard let index = nextState.proposals.firstIndex(where: { $0.id == proposalID }) else { return }
        nextState.proposals[index].status = status
        let proposal = nextState.proposals[index]
        nextState.auditEvents = prependingAuditEvent(
            AIPMAuditEvent(
                kind: .proposalStatusChanged,
                actor: "User",
                summary: "Marked \(proposal.title) \(status.rawValue)",
                proposalID: proposal.id,
                proposalTitle: proposal.title,
                resultStatus: status.rawValue
            ),
            to: nextState.auditEvents
        )
        nextState.updatedAt = .now
        state = nextState
        persist()
    }

    func recordActionApplication(
        proposal: AIPMDecisionProposal,
        change: BeadPlanReviewChange,
        resultStatus: String,
        resultMessage: String
    ) {
        var nextState = state
        nextState.auditEvents = prependingAuditEvent(
            AIPMAuditEvent(
                kind: .proposalActionApplied,
                actor: "User",
                summary: "\(change.kind.displayName): \(proposal.title)",
                proposalID: proposal.id,
                proposalTitle: proposal.title,
                change: change,
                resultStatus: resultStatus,
                resultMessage: resultMessage
            ),
            to: nextState.auditEvents
        )
        nextState.updatedAt = .now
        state = nextState
        persist()
    }

    private func sanitized(_ settings: AIPMAutomationSettings) -> AIPMAutomationSettings {
        var settings = settings
        settings.maximumProposals = min(max(settings.maximumProposals, 1), 20)
        return settings
    }

    private func nextScheduledRunDate(for state: AIPMState) -> Date? {
        guard state.settings.isEnabled, let interval = state.settings.cadence.intervalSeconds else { return nil }
        guard let lastRunAt = state.lastRunAt else { return Date().addingTimeInterval(15) }
        return max(lastRunAt.addingTimeInterval(interval), Date().addingTimeInterval(15))
    }

    private func prependingAuditEvent(_ event: AIPMAuditEvent, to events: [AIPMAuditEvent]) -> [AIPMAuditEvent] {
        Array(([event] + events).prefix(120))
    }

    private func persist() {
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try BeadsJSON.encoder.encode(state)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            // Keep the in-memory PM state active if disk persistence fails.
        }
    }

    private static func loadState(from url: URL) -> AIPMState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? BeadsJSON.decoder.decode(AIPMState.self, from: data)
    }

    private static var defaultPersistenceURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root
            .appendingPathComponent("Beads-Orchestrator", isDirectory: true)
            .appendingPathComponent("ai-pm-state.json")
    }
}
#endif
