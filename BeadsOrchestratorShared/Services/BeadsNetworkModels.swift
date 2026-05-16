import Foundation

struct BeadsServerInfo: Codable, Equatable {
    var name: String
    var version: String
    var boardCount: Int
    var updatedAt: Date
    var authRequired: Bool
    var capabilities: [String]
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
