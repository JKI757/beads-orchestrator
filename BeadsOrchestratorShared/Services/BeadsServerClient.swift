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

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    func llmStatus() async throws -> BeadsLLMStatus {
        try await get("llm/status", as: BeadsLLMStatus.self)
    }

    func suggestBeadFields(_ suggestionRequest: BeadFieldSuggestionRequest) async throws -> BeadFieldSuggestionResponse {
        try await post("ai/bead-suggestions", body: suggestionRequest, as: BeadFieldSuggestionResponse.self)
    }

    func reviewPlan(_ reviewRequest: BeadPlanReviewRequest) async throws -> BeadPlanReviewResponse {
        try await post("ai/plan-review", body: reviewRequest, as: BeadPlanReviewResponse.self)
    }

    func statusReport(_ reportRequest: BeadStatusReportRequest) async throws -> BeadStatusReportResponse {
        try await post("ai/status-report", body: reportRequest, as: BeadStatusReportResponse.self)
    }

    func aiPMState() async throws -> AIPMState {
        try await get("ai/pm/state", as: AIPMState.self)
    }

    func updateAIPMSettings(_ settings: AIPMAutomationSettings) async throws -> AIPMState {
        try await put("ai/pm/settings", body: settings, as: AIPMState.self)
    }

    func runAIPM(_ runRequest: AIPMRunRequest = AIPMRunRequest(boardID: nil)) async throws -> AIPMState {
        try await post("ai/pm/run", body: runRequest, as: AIPMState.self)
    }

    private func get<Value: Decodable>(_ path: String, as type: Value.Type, requiresAuth: Bool = true) async throws -> Value {
        var request = URLRequest(url: endpoint(path))
        if requiresAuth {
            try authorize(&request)
        }

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try BeadsJSON.decoder.decode(type, from: data)
    }

    private func post<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        as type: Value.Type
    ) async throws -> Value {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)
        request.httpBody = try BeadsJSON.encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try BeadsJSON.decoder.decode(type, from: data)
    }

    private func put<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        as type: Value.Type
    ) async throws -> Value {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)
        request.httpBody = try BeadsJSON.encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
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

    private func validate(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BeadsNetworkError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                throw BeadsNetworkError.httpMessage(httpResponse.statusCode, message)
            }
            throw BeadsNetworkError.httpStatus(httpResponse.statusCode)
        }
    }
}
