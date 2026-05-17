#if os(macOS)
import Darwin
import Foundation

@MainActor
final class BeadsHTTPServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Server stopped"
    @Published private(set) var listeningURLString = ""
    @Published private(set) var pairingToken = UUID().uuidString
    let llmConfiguration: LLMServerConfigurationStore

    private weak var store: BoardStore?
    private var socketFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.beadsorchestrator.http-server", qos: .userInitiated)
    private let port: UInt16 = 8787

    init(llmConfiguration: LLMServerConfigurationStore? = nil) {
        self.llmConfiguration = llmConfiguration ?? LLMServerConfigurationStore()
    }

    func configure(store: BoardStore) {
        self.store = store
    }

    var pairingPayload: BeadsPairingPayload? {
        guard !listeningURLString.isEmpty else { return nil }
        return BeadsPairingPayload(serverURLString: listeningURLString, pairingToken: pairingToken)
    }

    var pairingPayloadString: String {
        guard
            let pairingPayload,
            let data = try? BeadsJSON.encoder.encode(pairingPayload)
        else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    func regeneratePairingToken() {
        pairingToken = UUID().uuidString
        statusMessage = isRunning ? "Pairing token regenerated" : statusMessage
    }

    func start() {
        guard socketFD == -1 else { return }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            statusMessage = "Server failed: socket"
            return
        }

        var reuse: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            Darwin.close(fd)
            statusMessage = "Server failed: socket options"
            return
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(fd)
            statusMessage = "Server failed: bind port \(port)"
            return
        }

        guard Darwin.listen(fd, SOMAXCONN) == 0 else {
            Darwin.close(fd)
            statusMessage = "Server failed: listen"
            return
        }

        socketFD = fd
        isRunning = true
        listeningURLString = "http://\(localHostName):\(port)"
        statusMessage = "Server running on port \(port)"

        queue.async { [weak self] in
            self?.acceptLoop(socketFD: fd)
        }
    }

    func stop() {
        if socketFD >= 0 {
            Darwin.shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
        }
        socketFD = -1
        isRunning = false
        listeningURLString = ""
        statusMessage = "Server stopped"
    }

    private nonisolated func acceptLoop(socketFD: Int32) {
        while true {
            let clientFD = Darwin.accept(socketFD, nil, nil)
            guard clientFD >= 0 else { return }

            Task {
                await self.handle(clientFD)
            }
        }
    }

    private nonisolated func handle(_ clientFD: Int32) async {
        defer { Darwin.close(clientFD) }

        guard let requestData = receiveRequest(from: clientFD) else {
            send(httpResponse(status: 400, body: Data()), to: clientFD)
            return
        }

        let responseData = await route(requestData)
        send(responseData, to: clientFD)
    }

    private nonisolated func receiveRequest(from clientFD: Int32) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)

        while true {
            let count = Darwin.recv(clientFD, &chunk, chunk.count, 0)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk.prefix(count))

            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                continue
            }

            let headers = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let contentLength = contentLength(from: headers)
            let bodyStart = headerEnd.upperBound
            if buffer.count - bodyStart >= contentLength {
                return buffer
            }
        }
    }

    private nonisolated func send(_ data: Data, to clientFD: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0

            while sent < data.count {
                let result = Darwin.send(clientFD, baseAddress.advanced(by: sent), data.count - sent, 0)
                guard result > 0 else { return }
                sent += result
            }
        }
    }

    private nonisolated func contentLength(from headers: String) -> Int {
        headers
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
    }

    private func route(_ requestData: Data) async -> Data {
        guard
            let request = HTTPRequest(data: requestData),
            let store
        else {
            return httpResponse(status: 400, body: Data())
        }

        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return try jsonResponse(serverInfo(store: store))

            case ("GET", "/auth/verify"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                return try jsonResponse(serverInfo(store: store))

            case ("GET", "/boards"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                return try jsonResponse(store.boards)

            case ("GET", "/llm/status"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                return try jsonResponse(llmConfiguration.status)

            case ("POST", "/ai/bead-suggestions"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                let request = try BeadsJSON.decoder.decode(BeadFieldSuggestionRequest.self, from: request.body)
                let response = try await suggestBeadFields(request: request, store: store)
                return try jsonResponse(response)

            case ("PUT", "/boards"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                let boards = try BeadsJSON.decoder.decode([Board].self, from: request.body)
                store.replaceBoards(boards)
                return httpResponse(status: 204, body: Data())

            default:
                return httpResponse(status: 404, body: Data())
            }
        } catch {
            return httpResponse(status: 422, body: Data(error.localizedDescription.utf8))
        }
    }

    func suggestBeadFields(request: BeadFieldSuggestionRequest) async throws -> BeadFieldSuggestionResponse {
        guard let store else {
            throw LLMProviderError.unavailable("No board store is attached to the server.")
        }
        return try await suggestBeadFields(request: request, store: store)
    }

    private func suggestBeadFields(
        request: BeadFieldSuggestionRequest,
        store: BoardStore
    ) async throws -> BeadFieldSuggestionResponse {
        let status = llmConfiguration.status
        guard status.isAvailable else {
            throw LLMProviderError.unavailable(status.message)
        }

        let configuration = llmConfiguration.configuration
        guard let endpointURL = configuration.endpointURL else {
            throw LLMProviderError.unavailable("The LLM endpoint URL is invalid.")
        }

        let prompt = beadSuggestionPrompt(request: request, store: store)
        let llmResponse = try await requestLLMJSON(
            endpointURL: endpointURL.appending(path: "chat/completions"),
            configuration: configuration,
            userPrompt: prompt
        )

        do {
            let payload = try BeadsJSON.decoder.decode(LLMBeadSuggestionPayload.self, from: llmResponse)
            return BeadFieldSuggestionResponse(
                message: payload.message,
                suggestions: payload.suggestions,
                generatedAt: Date()
            )
        } catch {
            llmConfiguration.recordProviderFailure("The provider returned suggestions in an unreadable format.")
            throw LLMProviderError.invalidResponse
        }
    }

    private func requestLLMJSON(
        endpointURL: URL,
        configuration: LLMServerConfiguration,
        userPrompt: String
    ) async throws -> Data {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if configuration.provider.requiresAPIKey {
            request.setValue("Bearer \(configuration.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let chatRequest = OpenAIChatRequest(
            model: configuration.trimmedModelName,
            messages: [
                OpenAIChatMessage(
                    role: "system",
                    content: "You are an AI project manager for a software issue tracker. Return strict JSON only. Do not include markdown."
                ),
                OpenAIChatMessage(role: "user", content: userPrompt)
            ],
            temperature: 0.2,
            responseFormat: OpenAIResponseFormat(type: "json_object")
        )
        request.httpBody = try BeadsJSON.encoder.encode(chatRequest)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMProviderError.invalidResponse
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                throw LLMProviderError.providerStatus(httpResponse.statusCode)
            }

            let chatResponse = try BeadsJSON.decoder.decode(OpenAIChatResponse.self, from: data)
            guard let content = chatResponse.choices.first?.message.content else {
                throw LLMProviderError.invalidResponse
            }
            return Data(stripJSONCodeFence(from: content).utf8)
        } catch let error as LLMProviderError {
            llmConfiguration.recordProviderFailure(error.localizedDescription)
            throw error
        } catch {
            llmConfiguration.recordProviderFailure(error.localizedDescription)
            throw LLMProviderError.unavailable(error.localizedDescription)
        }
    }

    private func beadSuggestionPrompt(request: BeadFieldSuggestionRequest, store: BoardStore) -> String {
        let board = request.boardID.flatMap { boardID in
            store.boards.first { $0.id == boardID }
        } ?? store.selectedBoard

        let boardContext = board.map { board in
            let beads = board.columns
                .flatMap(\.beads)
                .filter { !$0.isArchived && $0.id != request.editingBeadID }
                .prefix(40)
                .map { bead in
                    [
                        "id=\(bead.relationshipID)",
                        "title=\(bead.title)",
                        "type=\(bead.issueType ?? bead.sourceType.displayName)",
                        "status=\(bead.status ?? store.columnName(for: bead) ?? "Unknown")",
                        "priority=\(bead.priority.rawValue)",
                        "parent=\(bead.parentBeadsID ?? "none")"
                    ].joined(separator: " | ")
                }
                .joined(separator: "\n")

            return """
            Board: \(board.name)
            Repository: \(board.repositoryName)
            Columns: \(board.columns.map(\.name).joined(separator: ", "))
            Existing beads:
            \(beads.isEmpty ? "No existing beads." : beads)
            """
        } ?? "No board context is available."

        let draft = request.draft
        return """
        Complete missing fields for a bead draft. Suggest only useful fields. It is acceptable to suggest replacing a user-entered field, but only when clearly helpful.

        Return JSON with exactly this shape:
        {
          "message": "short status message",
          "suggestions": [
            {
              "field": "summary|notes|labels|priority|issueType|parentBeadsID|dependencyBeadsIDs|title",
              "value": "field value as plain text; labels and dependency IDs are comma-separated",
              "rationale": "why this helps"
            }
          ]
        }

        Use "notes" for acceptance criteria and implementation guidance. Use "parentBeadsID" and "dependencyBeadsIDs" only when the ID exists in board context. Priority must be one of low, normal, high, urgent. Issue type should be a concise category such as task, bug, feature, epic, chore, or research.

        Current draft:
        Title: \(draft.title)
        Summary: \(draft.summary)
        Labels: \(draft.labelsText)
        Priority: \(draft.priority.rawValue)
        Issue Type: \(draft.issueType ?? "")
        Parent ID: \(draft.parentBeadsID ?? "")
        Dependencies: \(draft.dependencyBeadsIDs.joined(separator: ", "))
        Notes: \(draft.notes)

        \(boardContext)
        """
    }

    private func stripJSONCodeFence(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func serverInfo(store: BoardStore) -> BeadsServerInfo {
        BeadsServerInfo(
            name: "Beads-Orchestrator",
            version: "0.1.0",
            boardCount: store.activeBoards.count,
            updatedAt: Date(),
            authRequired: true,
            capabilities: [
                "canonical-board-store",
                "qr-pairing",
                "bearer-auth",
                "board-snapshot-read",
                "board-snapshot-replace",
                "beads-relationship-metadata",
                "server-side-llm-status"
            ] + (llmConfiguration.status.isAvailable ? ["ai-planning-assistance", "ai-bead-field-suggestions"] : []),
            llmStatus: llmConfiguration.status
        )
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        request.headerValue("authorization") == "Bearer \(pairingToken)"
    }

    private func jsonResponse<Value: Encodable>(_ value: Value) throws -> Data {
        try httpResponse(
            status: 200,
            body: BeadsJSON.encoder.encode(value),
            contentType: "application/json"
        )
    }

    private nonisolated func httpResponse(status: Int, body: Data, contentType: String = "text/plain") -> Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        return response
    }

    private nonisolated func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 422: "Unprocessable Content"
        default: "Error"
        }
    }

    private var localHostName: String {
        ProcessInfo.processInfo.hostName
    }
}

private struct LLMBeadSuggestionPayload: Decodable {
    var message: String
    var suggestions: [BeadFieldSuggestion]
}

private struct OpenAIChatRequest: Encodable {
    var model: String
    var messages: [OpenAIChatMessage]
    var temperature: Double
    var responseFormat: OpenAIResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIResponseFormat: Encodable {
    var type: String
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        var message: OpenAIChatMessage
    }

    var choices: [Choice]
}

private enum LLMProviderError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case providerStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            message
        case .invalidResponse:
            "The LLM provider returned an invalid response."
        case .providerStatus(let status):
            "The LLM provider returned HTTP \(status)."
        }
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init?(data: Data) {
        guard
            let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
            let requestLine = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
                .split(separator: "\r\n")
                .first
        else {
            return nil
        }

        let headerLines = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
            .split(separator: "\r\n")
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }

        method = String(requestParts[0])
        path = String(requestParts[1])
        headers = Dictionary(uniqueKeysWithValues: headerLines.dropFirst().compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, value)
        })
        body = Data(data[headerEnd.upperBound...])
    }

    func headerValue(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}
#endif
