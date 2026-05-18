import Foundation
import Combine
#if os(macOS)
import UserNotifications
#endif

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
    var lastLatencyMilliseconds: Int?
    var lastFailureMessage: String?
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
    var maximumActionsPerProposal: Int
    var maximumConsecutiveFailures: Int
    var requiresHighRiskApproval: Bool
    var sendsNotifications: Bool
    var notifiesHighRiskProposals: Bool
    var notifiesRunFailures: Bool

    init(
        isEnabled: Bool = true,
        cadence: AIPMCadence = .manual,
        autonomyLevel: AIPMAutonomyLevel = .surfaceDecisions,
        reviewsBacklog: Bool = true,
        generatesReports: Bool = true,
        maximumProposals: Int = 8,
        maximumActionsPerProposal: Int = 5,
        maximumConsecutiveFailures: Int = 3,
        requiresHighRiskApproval: Bool = true,
        sendsNotifications: Bool = false,
        notifiesHighRiskProposals: Bool = true,
        notifiesRunFailures: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.cadence = cadence
        self.autonomyLevel = autonomyLevel
        self.reviewsBacklog = reviewsBacklog
        self.generatesReports = generatesReports
        self.maximumProposals = maximumProposals
        self.maximumActionsPerProposal = maximumActionsPerProposal
        self.maximumConsecutiveFailures = maximumConsecutiveFailures
        self.requiresHighRiskApproval = requiresHighRiskApproval
        self.sendsNotifications = sendsNotifications
        self.notifiesHighRiskProposals = notifiesHighRiskProposals
        self.notifiesRunFailures = notifiesRunFailures
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case cadence
        case autonomyLevel
        case reviewsBacklog
        case generatesReports
        case maximumProposals
        case maximumActionsPerProposal
        case maximumConsecutiveFailures
        case requiresHighRiskApproval
        case sendsNotifications
        case notifiesHighRiskProposals
        case notifiesRunFailures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        cadence = try container.decodeIfPresent(AIPMCadence.self, forKey: .cadence) ?? .manual
        autonomyLevel = try container.decodeIfPresent(AIPMAutonomyLevel.self, forKey: .autonomyLevel) ?? .surfaceDecisions
        reviewsBacklog = try container.decodeIfPresent(Bool.self, forKey: .reviewsBacklog) ?? true
        generatesReports = try container.decodeIfPresent(Bool.self, forKey: .generatesReports) ?? true
        maximumProposals = try container.decodeIfPresent(Int.self, forKey: .maximumProposals) ?? 8
        maximumActionsPerProposal = try container.decodeIfPresent(Int.self, forKey: .maximumActionsPerProposal) ?? 5
        maximumConsecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .maximumConsecutiveFailures) ?? 3
        requiresHighRiskApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresHighRiskApproval) ?? true
        sendsNotifications = try container.decodeIfPresent(Bool.self, forKey: .sendsNotifications) ?? false
        notifiesHighRiskProposals = try container.decodeIfPresent(Bool.self, forKey: .notifiesHighRiskProposals) ?? true
        notifiesRunFailures = try container.decodeIfPresent(Bool.self, forKey: .notifiesRunFailures) ?? true
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

    var permitsDraftChanges: Bool {
        self == .autonomousProposals
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
    var consecutiveRunFailures: Int
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
        consecutiveRunFailures: Int = 0,
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
        self.consecutiveRunFailures = consecutiveRunFailures
        self.updatedAt = updatedAt
    }

    var pendingProposals: [AIPMDecisionProposal] {
        proposals.filter { $0.status == .pending }
    }

    var highRiskPendingProposals: [AIPMDecisionProposal] {
        pendingProposals.filter { $0.risk == .high }
    }

    var unreadDecisionCount: Int {
        pendingProposals.count
    }

    var needsAttention: Bool {
        unreadDecisionCount > 0 || lastRunError?.isEmpty == false
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
        case consecutiveRunFailures
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
        consecutiveRunFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveRunFailures) ?? 0
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
    case deferred

    var id: String {
        rawValue
    }
}

struct AIPMReportSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var deltas: AIPMReportDeltas
    var sections: [BeadStatusReportSection]
    var boardSnapshot: AIPMBoardSnapshot?
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        deltas: AIPMReportDeltas = AIPMReportDeltas(),
        sections: [BeadStatusReportSection],
        boardSnapshot: AIPMBoardSnapshot? = nil,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.deltas = deltas
        self.sections = sections
        self.boardSnapshot = boardSnapshot
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case deltas
        case sections
        case boardSnapshot
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        deltas = try container.decodeIfPresent(AIPMReportDeltas.self, forKey: .deltas) ?? AIPMReportDeltas()
        sections = try container.decodeIfPresent([BeadStatusReportSection].self, forKey: .sections) ?? []
        boardSnapshot = try container.decodeIfPresent(AIPMBoardSnapshot.self, forKey: .boardSnapshot)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
    }
}

struct AIPMReportDeltas: Codable, Equatable {
    var progress: [String]
    var risks: [String]
    var blockers: [String]
    var decisions: [String]

    init(
        progress: [String] = [],
        risks: [String] = [],
        blockers: [String] = [],
        decisions: [String] = []
    ) {
        self.progress = progress
        self.risks = risks
        self.blockers = blockers
        self.decisions = decisions
    }

    var isEmpty: Bool {
        progress.isEmpty && risks.isEmpty && blockers.isEmpty && decisions.isEmpty
    }
}

struct AIPMBoardSnapshot: Codable, Equatable {
    var boardID: Board.ID
    var boardName: String
    var beads: [AIPMBoardSnapshotBead]
    var generatedAt: Date

    init(
        boardID: Board.ID,
        boardName: String,
        beads: [AIPMBoardSnapshotBead],
        generatedAt: Date = .now
    ) {
        self.boardID = boardID
        self.boardName = boardName
        self.beads = beads
        self.generatedAt = generatedAt
    }
}

struct AIPMBoardSnapshotBead: Codable, Equatable {
    var relationshipID: String
    var title: String
    var status: String
    var priority: BeadPriority
    var isBlocked: Bool
    var isStale: Bool
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
        false
    }
}

struct LLMServerConfiguration: Codable, Equatable {
    var provider: LLMProviderKind
    var endpointURLString: String
    var modelName: String
    var apiKey: String
    var timeoutSeconds: Double
    var maximumResponseBytes: Int
    var retryLimit: Int

    init(
        provider: LLMProviderKind = .disabled,
        endpointURLString: String = "http://127.0.0.1:11434/v1",
        modelName: String = "",
        apiKey: String = "",
        timeoutSeconds: Double = 60,
        maximumResponseBytes: Int = 1_000_000,
        retryLimit: Int = 1
    ) {
        self.provider = provider
        self.endpointURLString = endpointURLString
        self.modelName = modelName
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
        self.maximumResponseBytes = maximumResponseBytes
        self.retryLimit = retryLimit
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case endpointURLString
        case modelName
        case apiKey
        case timeoutSeconds
        case maximumResponseBytes
        case retryLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(LLMProviderKind.self, forKey: .provider) ?? .disabled
        endpointURLString = try container.decodeIfPresent(String.self, forKey: .endpointURLString) ?? "http://127.0.0.1:11434/v1"
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 60
        maximumResponseBytes = try container.decodeIfPresent(Int.self, forKey: .maximumResponseBytes) ?? 1_000_000
        retryLimit = try container.decodeIfPresent(Int.self, forKey: .retryLimit) ?? 1
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
        endpointCandidates.first
    }

    var endpointCandidates: [URL] {
        Self.endpointCandidates(from: trimmedEndpointURLString)
    }

    var sanitizedTimeoutSeconds: Double {
        min(max(timeoutSeconds, 5), 300)
    }

    var sanitizedMaximumResponseBytes: Int {
        min(max(maximumResponseBytes, 65_536), 10_000_000)
    }

    var sanitizedRetryLimit: Int {
        min(max(retryLimit, 0), 5)
    }

    static func endpointCandidates(from rawValue: String) -> [URL] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let valuesWithScheme = trimmed.contains("://") ? [trimmed] : ["http://\(trimmed)", "https://\(trimmed)"]
        var candidates: [URL] = []

        for valueWithScheme in valuesWithScheme {
            guard let components = URLComponents(string: valueWithScheme) else { continue }
            guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return [] }
            guard let host = components.host, !host.isEmpty else { continue }

            let originalPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let suffixes = ["", "v1", "api/v1", "api", "vx"]
            let candidatePaths = ([originalPath] + suffixes)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                .reduce(into: [String]()) { result, path in
                    guard !result.contains(path) else { return }
                    result.append(path)
                }

            candidates.append(contentsOf: candidatePaths.compactMap { path in
                var candidate = components
                candidate.path = path.isEmpty ? "" : "/\(path)"
                return candidate.url
            })
        }

        return candidates.reduce(into: [URL]()) { result, url in
            guard !result.contains(url) else { return }
            result.append(url)
        }
    }
}

#if os(macOS)
@MainActor
final class LLMServerConfigurationStore: ObservableObject {
    @Published private(set) var configuration: LLMServerConfiguration
    @Published private var lastFailureMessage: String?
    @Published private var lastLatencyMilliseconds: Int?

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
        self.configuration = sanitized(configuration)
        lastFailureMessage = nil
        persist()
    }

    func recordProviderFailure(_ message: String) {
        lastFailureMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recordProviderSuccess(latency: TimeInterval) {
        lastLatencyMilliseconds = max(0, Int((latency * 1000).rounded()))
        lastFailureMessage = nil
    }

    func discoverModels(for configuration: LLMServerConfiguration) async throws -> [String] {
        try await discoverEndpoint(for: configuration).models
    }

    func discoverEndpoint(for configuration: LLMServerConfiguration) async throws -> LLMEndpointDiscoveryResult {
        let sanitizedConfiguration = sanitized(configuration)
        guard sanitizedConfiguration.provider.requiresEndpoint else {
            throw LLMEndpointDiscoveryError.unavailable("Choose an LLM provider before discovering models.")
        }
        let endpointURLs = sanitizedConfiguration.endpointCandidates
        guard !endpointURLs.isEmpty else {
            throw LLMEndpointDiscoveryError.unavailable("Enter a valid HTTP endpoint before discovering models.")
        }

        var lastError: Error?
        for endpointURL in endpointURLs {
            do {
                let models = try await models(at: endpointURL, configuration: sanitizedConfiguration)
                return LLMEndpointDiscoveryResult(endpointURLString: endpointURL.absoluteString, models: models)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? LLMEndpointDiscoveryError.invalidResponse
    }

    private func models(at endpointURL: URL, configuration: LLMServerConfiguration) async throws -> [String] {
        var request = URLRequest(url: endpointURL.appending(path: "models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        if !configuration.trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(configuration.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMEndpointDiscoveryError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw LLMEndpointDiscoveryError.providerStatus(httpResponse.statusCode)
        }

        let payload = try BeadsJSON.decoder.decode(OpenAIModelsResponse.self, from: data)
        return payload.data.map(\.id).filter { !$0.isEmpty }.sorted()
    }

    func testEndpoint(_ configuration: LLMServerConfiguration) async -> LLMEndpointTestResult {
        do {
            let discovery = try await discoverEndpoint(for: configuration)
            let models = discovery.models
            if models.isEmpty {
                return LLMEndpointTestResult(
                    isSuccessful: false,
                    message: "Endpoint responded, but returned no models.",
                    endpointURLString: discovery.endpointURLString,
                    models: []
                )
            }
            return LLMEndpointTestResult(
                isSuccessful: true,
                message: "Endpoint returned \(models.count) model\(models.count == 1 ? "" : "s") at \(discovery.endpointURLString).",
                endpointURLString: discovery.endpointURLString,
                models: models
            )
        } catch {
            recordProviderFailure(error.localizedDescription)
            return LLMEndpointTestResult(
                isSuccessful: false,
                message: error.localizedDescription,
                endpointURLString: nil,
                models: []
            )
        }
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
                lastLatencyMilliseconds: lastLatencyMilliseconds,
                lastFailureMessage: lastFailureMessage,
                updatedAt: Date()
            )
        }

        guard isValidEndpoint(configuration.endpointURL) else {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: modelName.isEmpty ? nil : modelName,
                message: "Enter a valid HTTP endpoint for the LLM provider.",
                lastLatencyMilliseconds: lastLatencyMilliseconds,
                lastFailureMessage: lastFailureMessage,
                updatedAt: Date()
            )
        }

        guard !modelName.isEmpty else {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: nil,
                message: "Discover and choose a model before enabling planning assistance.",
                lastLatencyMilliseconds: lastLatencyMilliseconds,
                lastFailureMessage: lastFailureMessage,
                updatedAt: Date()
            )
        }

        if let lastFailureMessage, !lastFailureMessage.isEmpty {
            return BeadsLLMStatus(
                isAvailable: false,
                provider: providerName,
                model: modelName,
                message: "LLM provider failed safely: \(lastFailureMessage)",
                lastLatencyMilliseconds: lastLatencyMilliseconds,
                lastFailureMessage: lastFailureMessage,
                updatedAt: Date()
            )
        }

        return BeadsLLMStatus(
            isAvailable: true,
            provider: providerName,
            model: modelName,
            message: "Planning assistance is configured on the Mac server.",
            lastLatencyMilliseconds: lastLatencyMilliseconds,
            lastFailureMessage: lastFailureMessage,
            updatedAt: Date()
        )
    }

    private func isValidEndpoint(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func sanitized(_ configuration: LLMServerConfiguration) -> LLMServerConfiguration {
        var sanitizedConfiguration = configuration
        sanitizedConfiguration.endpointURLString = configuration.trimmedEndpointURLString
        sanitizedConfiguration.modelName = configuration.trimmedModelName
        sanitizedConfiguration.apiKey = configuration.trimmedAPIKey
        sanitizedConfiguration.timeoutSeconds = configuration.sanitizedTimeoutSeconds
        sanitizedConfiguration.maximumResponseBytes = configuration.sanitizedMaximumResponseBytes
        sanitizedConfiguration.retryLimit = configuration.sanitizedRetryLimit
        return sanitizedConfiguration
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

struct LLMEndpointTestResult: Equatable {
    var isSuccessful: Bool
    var message: String
    var endpointURLString: String?
    var models: [String]
}

struct LLMEndpointDiscoveryResult: Equatable {
    var endpointURLString: String
    var models: [String]
}

struct OpenAIModelsResponse: Decodable, Equatable {
    struct Model: Decodable, Equatable {
        var id: String
    }

    var data: [Model]
}

private enum LLMEndpointDiscoveryError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case providerStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        case .invalidResponse:
            "The LLM endpoint returned an invalid response."
        case let .providerStatus(status):
            "The LLM endpoint returned HTTP \(status)."
        }
    }
}

private final class AIPMLocalNotifier {
    static let shared = AIPMLocalNotifier()

    private init() {}

    func deliver(identifier: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.enqueue(identifier: identifier, title: title, body: body, center: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.enqueue(identifier: identifier, title: title, body: body, center: center)
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    private func enqueue(identifier: String, title: String, body: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
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
        nextState.consecutiveRunFailures = 0
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
        notifyForRun(settings: nextState.settings, proposals: proposals)
    }

    func recordRunFailure(_ message: String) {
        var nextState = state
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        nextState.lastRunError = trimmedMessage.isEmpty ? nil : trimmedMessage
        nextState.consecutiveRunFailures += 1
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
        notifyForRunFailure(settings: nextState.settings, message: trimmedMessage)
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
        settings.maximumActionsPerProposal = min(max(settings.maximumActionsPerProposal, 1), 12)
        settings.maximumConsecutiveFailures = min(max(settings.maximumConsecutiveFailures, 1), 10)
        if !settings.sendsNotifications {
            settings.notifiesHighRiskProposals = false
            settings.notifiesRunFailures = false
        }
        return settings
    }

    private func notifyForRun(settings: AIPMAutomationSettings, proposals: [AIPMDecisionProposal]) {
        guard settings.sendsNotifications, settings.notifiesHighRiskProposals else { return }
        let highRiskProposals = proposals.filter { $0.risk == .high && $0.status == .pending }
        guard !highRiskProposals.isEmpty else { return }

        let proposalCount = highRiskProposals.count
        AIPMLocalNotifier.shared.deliver(
            identifier: "ai-pm-high-risk-\(UUID().uuidString)",
            title: "AI PM needs review",
            body: "\(proposalCount) high-risk proposal\(proposalCount == 1 ? "" : "s") need a decision. Open the AI PM dashboard to review."
        )
    }

    private func notifyForRunFailure(settings: AIPMAutomationSettings, message: String) {
        guard settings.sendsNotifications, settings.notifiesRunFailures else { return }
        AIPMLocalNotifier.shared.deliver(
            identifier: "ai-pm-run-failed-\(UUID().uuidString)",
            title: "AI PM run failed",
            body: "Open the AI PM dashboard to review the provider error and retry. \(message)"
        )
    }

    private func nextScheduledRunDate(for state: AIPMState) -> Date? {
        guard state.settings.isEnabled, let interval = state.settings.cadence.intervalSeconds else { return nil }
        guard state.consecutiveRunFailures < state.settings.maximumConsecutiveFailures else { return nil }
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
