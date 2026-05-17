import Foundation

struct BeadsServerClient {
    var baseURL: URL
    var pairingToken: String
    var session: URLSession = .shared

    func health() async throws -> BeadsServerInfo {
        try await get("health", as: BeadsServerInfo.self, requiresAuth: false)
    }

    func verifyPairing() async throws -> BeadsServerInfo {
        try await get("auth/verify", as: BeadsServerInfo.self)
    }

    func boards() async throws -> [Board] {
        try await get("boards", as: [Board].self)
    }

    func replaceBoards(_ boards: [Board]) async throws {
        var request = URLRequest(url: endpoint("boards"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)
        request.httpBody = try BeadsJSON.encoder.encode(boards)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func llmStatus() async throws -> BeadsLLMStatus {
        try await get("llm/status", as: BeadsLLMStatus.self)
    }

    private func get<Value: Decodable>(_ path: String, as type: Value.Type, requiresAuth: Bool = true) async throws -> Value {
        var request = URLRequest(url: endpoint(path))
        if requiresAuth {
            try authorize(&request)
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try BeadsJSON.decoder.decode(type, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private func authorize(_ request: inout URLRequest) throws {
        let token = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw BeadsNetworkError.missingPairingToken
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BeadsNetworkError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw BeadsNetworkError.httpStatus(httpResponse.statusCode)
        }
    }
}
