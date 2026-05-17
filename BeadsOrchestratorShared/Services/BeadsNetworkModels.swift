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
    case createChildBead
    case addDependency
    case setParent

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .updateField:
            "Update Field"
        case .createChildBead:
            "Create Child"
        case .addDependency:
            "Add Dependency"
        case .setParent:
            "Set Parent"
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

enum BeadSuggestionField: String, Codable, CaseIterable, Identifiable {
    case title
    case summary
    case notes
    case labels
    case priority
    case issueType
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
