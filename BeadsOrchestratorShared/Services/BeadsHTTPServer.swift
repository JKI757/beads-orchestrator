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
    let aiPMState: AIPMStateStore

    private weak var store: BoardStore?
    private var automationTask: Task<Void, Never>?
    private var socketFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.beadsorchestrator.http-server", qos: .userInitiated)
    private let port: UInt16 = 8787

    init(llmConfiguration: LLMServerConfigurationStore? = nil, aiPMState: AIPMStateStore? = nil) {
        self.llmConfiguration = llmConfiguration ?? LLMServerConfigurationStore()
        self.aiPMState = aiPMState ?? AIPMStateStore()
    }

    func configure(store: BoardStore) {
        self.store = store
        aiPMState.refreshSchedule()
        restartAutomationLoop()
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
        automationTask?.cancel()
        automationTask = nil
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

            case ("POST", "/ai/plan-review"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                let request = try BeadsJSON.decoder.decode(BeadPlanReviewRequest.self, from: request.body)
                let response = try await reviewPlan(request: request, store: store)
                return try jsonResponse(response)

            case ("POST", "/ai/status-report"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                let request = try BeadsJSON.decoder.decode(BeadStatusReportRequest.self, from: request.body)
                let response = try await statusReport(request: request, store: store)
                return try jsonResponse(response)

            case ("GET", "/ai/pm/state"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                return try jsonResponse(aiPMState.state)

            case ("PUT", "/ai/pm/settings"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                let settings = try BeadsJSON.decoder.decode(AIPMAutomationSettings.self, from: request.body)
                saveAIPMSettings(settings)
                return try jsonResponse(aiPMState.state)

            case ("POST", "/ai/pm/run"):
                guard isAuthorized(request) else {
                    return httpResponse(status: 401, body: Data())
                }
                let runRequest = request.body.isEmpty
                    ? AIPMRunRequest(boardID: nil)
                    : try BeadsJSON.decoder.decode(AIPMRunRequest.self, from: request.body)
                let response = try await runAIPM(request: runRequest)
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

    func reviewPlan(request: BeadPlanReviewRequest) async throws -> BeadPlanReviewResponse {
        guard let store else {
            throw LLMProviderError.unavailable("No board store is attached to the server.")
        }
        return try await reviewPlan(request: request, store: store)
    }

    func statusReport(request: BeadStatusReportRequest) async throws -> BeadStatusReportResponse {
        guard let store else {
            throw LLMProviderError.unavailable("No board store is attached to the server.")
        }
        return try await statusReport(request: request, store: store)
    }

    func saveAIPMSettings(_ settings: AIPMAutomationSettings) {
        aiPMState.saveSettings(settings)
        restartAutomationLoop()
    }

    func runAIPM(request: AIPMRunRequest = AIPMRunRequest(boardID: nil)) async throws -> AIPMState {
        guard let store else {
            let error = LLMProviderError.unavailable("No board store is attached to the server.")
            aiPMState.recordRunFailure(error.localizedDescription)
            throw error
        }
        do {
            return try await runAIPM(request: request, store: store)
        } catch {
            aiPMState.recordRunFailure(error.localizedDescription)
            throw error
        }
    }

    func evaluateAIPMProjectIntelligence(
        request: AIPMRunRequest = AIPMRunRequest(boardID: nil)
    ) throws -> AIPMProjectIntelligenceSummary {
        guard let store else {
            throw LLMProviderError.unavailable("No board store is attached to the server.")
        }
        return try projectIntelligenceSummary(request: request, store: store)
    }

    private func restartAutomationLoop() {
        automationTask?.cancel()
        automationTask = nil

        let settings = aiPMState.state.settings
        guard settings.isEnabled, settings.cadence != .manual else { return }

        automationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.automationDelaySeconds()
                guard delay > 0 else { return }

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                _ = try? await self.runAIPM()
            }
        }
    }

    private func automationDelaySeconds() -> TimeInterval {
        let settings = aiPMState.state.settings
        let interval = settings.cadence.intervalSeconds ?? 0
        guard interval > 0 else { return 0 }
        guard llmConfiguration.status.isAvailable else { return interval }
        if let nextRunAt = aiPMState.state.nextRunAt {
            return max(nextRunAt.timeIntervalSinceNow, 15)
        }
        guard let lastRunAt = aiPMState.state.lastRunAt else { return 15 }
        return max(lastRunAt.addingTimeInterval(interval).timeIntervalSinceNow, 15)
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

    private func reviewPlan(
        request: BeadPlanReviewRequest,
        store: BoardStore
    ) async throws -> BeadPlanReviewResponse {
        let status = llmConfiguration.status
        guard status.isAvailable else {
            throw LLMProviderError.unavailable(status.message)
        }

        let configuration = llmConfiguration.configuration
        guard let endpointURL = configuration.endpointURL else {
            throw LLMProviderError.unavailable("The LLM endpoint URL is invalid.")
        }

        let prompt = try planReviewPrompt(request: request, store: store)
        let llmResponse = try await requestLLMJSON(
            endpointURL: endpointURL.appending(path: "chat/completions"),
            configuration: configuration,
            userPrompt: prompt
        )

        do {
            let payload = try BeadsJSON.decoder.decode(LLMPlanReviewPayload.self, from: llmResponse)
            return BeadPlanReviewResponse(
                message: payload.message,
                findings: payload.findings,
                changes: payload.changes,
                generatedAt: Date()
            )
        } catch {
            llmConfiguration.recordProviderFailure("The provider returned a plan review in an unreadable format.")
            throw LLMProviderError.invalidResponse
        }
    }

    private func statusReport(
        request: BeadStatusReportRequest,
        store: BoardStore
    ) async throws -> BeadStatusReportResponse {
        let status = llmConfiguration.status
        guard status.isAvailable else {
            throw LLMProviderError.unavailable(status.message)
        }

        let configuration = llmConfiguration.configuration
        guard let endpointURL = configuration.endpointURL else {
            throw LLMProviderError.unavailable("The LLM endpoint URL is invalid.")
        }

        let prompt = try statusReportPrompt(request: request, store: store)
        let llmResponse = try await requestLLMJSON(
            endpointURL: endpointURL.appending(path: "chat/completions"),
            configuration: configuration,
            userPrompt: prompt
        )

        do {
            let payload = try BeadsJSON.decoder.decode(LLMStatusReportPayload.self, from: llmResponse)
            return BeadStatusReportResponse(
                title: payload.title,
                summary: payload.summary,
                sections: payload.sections,
                generatedAt: Date()
            )
        } catch {
            llmConfiguration.recordProviderFailure("The provider returned a status report in an unreadable format.")
            throw LLMProviderError.invalidResponse
        }
    }

    private func runAIPM(request: AIPMRunRequest, store: BoardStore) async throws -> AIPMState {
        let status = llmConfiguration.status
        guard status.isAvailable else {
            throw LLMProviderError.unavailable(status.message)
        }

        let settings = aiPMState.state.settings
        guard settings.isEnabled else {
            throw LLMProviderError.unavailable("AI PM automation is disabled.")
        }

        let configuration = llmConfiguration.configuration
        guard let endpointURL = configuration.endpointURL else {
            throw LLMProviderError.unavailable("The LLM endpoint URL is invalid.")
        }

        let intelligence = try projectIntelligenceSummary(request: request, store: store)
        let prompt = try aiPMPrompt(request: request, settings: settings, store: store, intelligence: intelligence)
        let llmResponse = try await requestLLMJSON(
            endpointURL: endpointURL.appending(path: "chat/completions"),
            configuration: configuration,
            userPrompt: prompt
        )

        do {
            let payload = try BeadsJSON.decoder.decode(LLMAIPMRunPayload.self, from: llmResponse)
            let proposals = payload.proposals
                .prefix(settings.maximumProposals)
                .map { proposal in
                    AIPMDecisionProposal(
                        title: proposal.title,
                        summary: proposal.summary,
                        category: proposal.category,
                        risk: proposal.risk,
                        rationale: proposal.rationale,
                        changes: proposal.changes ?? []
                    )
                }
            let report = payload.report.map { report in
                AIPMReportSnapshot(
                    title: report.title,
                    summary: report.summary,
                    sections: report.sections
                )
            }
            aiPMState.recordRun(
                summary: payload.summary,
                proposals: proposals,
                report: report,
                intelligence: intelligence
            )
            return aiPMState.state
        } catch {
            llmConfiguration.recordProviderFailure("The provider returned an AI PM run in an unreadable format.")
            throw LLMProviderError.invalidResponse
        }
    }

    private func requestLLMJSON(
        endpointURL: URL,
        configuration: LLMServerConfiguration,
        userPrompt: String
    ) async throws -> Data {
        let attemptCount = configuration.sanitizedRetryLimit + 1
        var lastError: Error?

        for attempt in 1...attemptCount {
            let startedAt = Date()
            do {
                var request = URLRequest(url: endpointURL)
                request.httpMethod = "POST"
                request.timeoutInterval = configuration.sanitizedTimeoutSeconds
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !configuration.trimmedAPIKey.isEmpty {
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

                let (data, response) = try await URLSession.shared.data(for: request)
                let latency = Date().timeIntervalSince(startedAt)
                guard data.count <= configuration.sanitizedMaximumResponseBytes else {
                    throw LLMProviderError.responseTooLarge(data.count, configuration.sanitizedMaximumResponseBytes)
                }
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
                llmConfiguration.recordProviderSuccess(latency: latency)
                return Data(stripJSONCodeFence(from: content).utf8)
            } catch {
                lastError = error
                guard attempt < attemptCount, isRetryableLLMError(error) else {
                    let providerError = normalizedLLMError(error)
                    llmConfiguration.recordProviderFailure(providerError.localizedDescription)
                    throw providerError
                }

                try? await Task.sleep(nanoseconds: UInt64(attempt) * 250_000_000)
            }
        }

        let providerError = normalizedLLMError(lastError ?? LLMProviderError.invalidResponse)
        llmConfiguration.recordProviderFailure(providerError.localizedDescription)
        throw providerError
    }

    private func isRetryableLLMError(_ error: Error) -> Bool {
        if let providerError = error as? LLMProviderError {
            switch providerError {
            case let .providerStatus(status):
                return status == 408 || status == 409 || status == 425 || status == 429 || (500...599).contains(status)
            case .unavailable:
                return true
            case .invalidResponse, .responseTooLarge:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func normalizedLLMError(_ error: Error) -> LLMProviderError {
        if let providerError = error as? LLMProviderError {
            return providerError
        }
        return LLMProviderError.unavailable(error.localizedDescription)
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
              "field": "summary|notes|labels|priority|issueType|status|isBlocked|isStale|parentBeadsID|dependencyBeadsIDs|title",
              "value": "field value as plain text; labels and dependency IDs are comma-separated",
              "rationale": "why this helps"
            }
          ]
        }

        Use "notes" for acceptance criteria and implementation guidance. Use "parentBeadsID" and "dependencyBeadsIDs" only when the ID exists in board context. Use "status", "isBlocked", and "isStale" only when they clarify current PM state. Priority must be one of low, normal, high, urgent. Issue type should be a concise category such as task, bug, feature, epic, chore, or research.

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

    private func planReviewPrompt(request: BeadPlanReviewRequest, store: BoardStore) throws -> String {
        let board = request.boardID.flatMap { boardID in
            store.boards.first { $0.id == boardID }
        } ?? store.selectedBoard
        guard let board else {
            throw LLMProviderError.unavailable("No board context is available.")
        }
        guard let root = board.columns.flatMap(\.beads).first(where: { $0.id == request.beadID }) else {
            throw LLMProviderError.unavailable("The selected bead no longer exists.")
        }

        let reviewBeads = reviewBeads(root: root, board: board, scope: request.scope)
        let statusByBeadID = Dictionary(
            uniqueKeysWithValues: board.columns.flatMap { column in
                column.beads.map { bead in (bead.id, bead.status ?? column.name) }
            }
        )
        let context = reviewBeads.map { bead in
            """
            id=\(bead.relationshipID)
            title=\(bead.title)
            type=\(bead.issueType ?? bead.sourceType.displayName)
            status=\(statusByBeadID[bead.id] ?? "Unknown")
            priority=\(bead.priority.rawValue)
            parent=\(bead.parentBeadsID ?? "none")
            children=\(bead.childBeadsIDs.joined(separator: ", "))
            dependencies=\(bead.dependencyBeadsIDs.joined(separator: ", "))
            summary=\(bead.summary)
            notes=\(bead.notes)
            """
        }.joined(separator: "\n---\n")

        let boardIDs = board.columns
            .flatMap(\.beads)
            .filter { !$0.isArchived }
            .map { "\($0.relationshipID): \($0.title)" }
            .joined(separator: "\n")

        return """
        Review this software project plan like a senior AI project manager. Find missing steps, unclear acceptance criteria, unrealistic scope, dependency mistakes, sequencing risks, and places where the work should be decomposed.

        Return JSON with exactly this shape:
        {
          "message": "short review summary",
          "findings": [
            {
              "severity": "info|warning|critical",
              "category": "scope|acceptanceCriteria|dependencies|sequencing|risk|decomposition",
              "title": "short finding",
              "detail": "specific, actionable detail"
            }
          ],
          "changes": [
            {
              "kind": "updateField|createBead|createChildBead|addDependency|setParent|setStatus|setBlocked|setStale",
              "targetBeadsID": "existing bead id or null",
              "field": "summary|notes|labels|priority|issueType|status|isBlocked|isStale|parentBeadsID|dependencyBeadsIDs|title or null",
              "value": "new field value, dependency id, parent id, status, or true/false when relevant",
              "title": "bead title when creating a bead",
              "summary": "bead or replacement summary",
              "notes": "acceptance criteria and implementation guidance",
              "labels": ["label"],
              "priority": "low|normal|high|urgent or null",
              "issueType": "task|bug|feature|epic|chore|research or null",
              "rationale": "why this change improves execution"
            }
          ]
        }

        Use updateField for improvements to the selected bead or an included subtree bead. Use createBead for missing top-level work and createChildBead for missing child work that should remain independently movable. Use setStatus, setBlocked, and setStale for explicit PM state changes. Use addDependency or setParent only when the referenced ID appears in Available bead IDs. Do not invent external IDs. Keep changes reviewable and small.

        Board: \(board.name)
        Repository: \(board.repositoryName)
        Columns: \(board.columns.map(\.name).joined(separator: ", "))
        Review scope: \(request.scope.rawValue)
        Root bead ID: \(root.relationshipID)

        Available bead IDs:
        \(boardIDs)

        Reviewed plan:
        \(context)
        """
    }

    private func statusReportPrompt(request: BeadStatusReportRequest, store: BoardStore) throws -> String {
        let board = request.boardID.flatMap { boardID in
            store.boards.first { $0.id == boardID }
        } ?? store.selectedBoard
        guard let board else {
            throw LLMProviderError.unavailable("No board context is available.")
        }

        let root = request.beadID.flatMap { beadID in
            board.columns.flatMap(\.beads).first { $0.id == beadID }
        }
        if request.scope == .subtree && root == nil {
            throw LLMProviderError.unavailable("The selected parent bead no longer exists.")
        }

        let reportBeads: [Bead]
        switch request.scope {
        case .board:
            reportBeads = board.columns.flatMap(\.beads).filter { !$0.isArchived }
        case .subtree:
            reportBeads = root.map { reviewBeads(root: $0, board: board, scope: .subtree) } ?? []
        }

        let statusByBeadID = Dictionary(
            uniqueKeysWithValues: board.columns.flatMap { column in
                column.beads.map { bead in (bead.id, bead.status ?? column.name) }
            }
        )
        let context = reportBeads.map { bead in
            [
                "id=\(bead.relationshipID)",
                "title=\(bead.title)",
                "type=\(bead.issueType ?? bead.sourceType.displayName)",
                "status=\(statusByBeadID[bead.id] ?? "Unknown")",
                "priority=\(bead.priority.rawValue)",
                "blocked=\(bead.isBlocked)",
                "stale=\(bead.isStale)",
                "parent=\(bead.parentBeadsID ?? "none")",
                "children=\(bead.childBeadsIDs.joined(separator: ", "))",
                "dependencies=\(bead.dependencyBeadsIDs.joined(separator: ", "))",
                "summary=\(bead.summary)"
            ].joined(separator: " | ")
        }.joined(separator: "\n")

        return """
        Generate a terse operational project status report from canonical beads state. Distinguish completed, active, blocked, stale, and unplanned or missing work. Focus on decisions, risks, likely next actions, and work sequencing.

        Return JSON with exactly this shape:
        {
          "title": "short report title",
          "summary": "2-4 sentence executive summary",
          "sections": [
            {
              "title": "Completed|Active|Blocked|Stale|Unplanned Work|Risks|Next Actions",
              "items": ["terse bullet without markdown"]
            }
          ]
        }

        Include sections only when useful. Keep every item specific and tied to a bead or decision when possible. Do not propose state changes.

        Board: \(board.name)
        Repository: \(board.repositoryName)
        Scope: \(request.scope.rawValue)
        Root: \(root.map(\.relationshipID) ?? "board")
        Columns: \(board.columns.map(\.name).joined(separator: ", "))

        Beads:
        \(context.isEmpty ? "No active beads." : context)
        """
    }

    private func aiPMPrompt(
        request: AIPMRunRequest,
        settings: AIPMAutomationSettings,
        store: BoardStore,
        intelligence: AIPMProjectIntelligenceSummary
    ) throws -> String {
        let board = request.boardID.flatMap { boardID in
            store.boards.first { $0.id == boardID }
        } ?? store.selectedBoard
        guard let board else {
            throw LLMProviderError.unavailable("No board context is available.")
        }

        let statusByBeadID = Dictionary(
            uniqueKeysWithValues: board.columns.flatMap { column in
                column.beads.map { bead in (bead.id, bead.status ?? column.name) }
            }
        )
        let activeBeads = board.columns
            .flatMap(\.beads)
            .filter { !$0.isArchived }
        let context = activeBeads.map { bead in
            [
                "id=\(bead.relationshipID)",
                "title=\(bead.title)",
                "type=\(bead.issueType ?? bead.sourceType.displayName)",
                "status=\(statusByBeadID[bead.id] ?? "Unknown")",
                "priority=\(bead.priority.rawValue)",
                "blocked=\(bead.isBlocked)",
                "stale=\(bead.isStale)",
                "parent=\(bead.parentBeadsID ?? "none")",
                "children=\(bead.childBeadsIDs.joined(separator: ", "))",
                "dependencies=\(bead.dependencyBeadsIDs.joined(separator: ", "))",
                "summary=\(bead.summary)",
                "notes=\(bead.notes.prefix(280))"
            ].joined(separator: " | ")
        }.joined(separator: "\n")

        let pendingDecisions = aiPMState.state.pendingProposals
            .prefix(12)
            .map { proposal in
                "\(proposal.category.rawValue) / \(proposal.risk.rawValue): \(proposal.title) - \(proposal.summary)"
            }
            .joined(separator: "\n")

        return """
        Act as an autonomous AI project manager for a software project. Inspect the canonical board state and decide what needs PM attention without asking the user to write prompts.

        Autonomy policy:
        - You may autonomously analyze backlog, sequencing, risk, stale work, missing work, handoff quality, and reporting.
        - You must surface decisions as reviewable proposals.
        - Do not silently mutate project state.
        - When autonomy is surfaceDecisions, focus on decisions and risks with minimal proposed changes.
        - When autonomy is autonomousProposals, include concrete draft changes that could be applied after review.
        - Prefer a small number of high-signal proposals over a large backlog of noise.
        - Every proposal should be specific enough for a user to accept, dismiss, or turn into child beads later.

        Return JSON with exactly this shape:
        {
          "summary": "short PM run summary",
          "proposals": [
            {
              "title": "decision or PM action",
              "summary": "what should happen",
              "category": "backlog|planning|risk|milestone|decision|handoff",
              "risk": "low|medium|high",
              "rationale": "why this matters now",
              "changes": [
                {
                  "kind": "updateField|createBead|createChildBead|addDependency|setParent|setStatus|setBlocked|setStale",
                  "targetBeadsID": "existing bead id or null",
                  "field": "summary|notes|labels|priority|issueType|status|isBlocked|isStale|parentBeadsID|dependencyBeadsIDs|title or null",
                  "value": "field value, dependency id, parent id, status, or true/false when relevant",
                  "title": "bead title when creating a bead",
                  "summary": "bead or replacement summary",
                  "notes": "acceptance criteria and implementation guidance",
                  "labels": ["label"],
                  "priority": "low|normal|high|urgent or null",
                  "issueType": "task|bug|feature|epic|chore|research or null",
                  "rationale": "why this change improves execution"
                }
              ]
            }
          ],
          "report": {
            "title": "short operational report title",
            "summary": "2-4 sentence status summary",
            "sections": [
              { "title": "Risks|Decisions|Next Actions|Blocked|Stale|Completed|Active", "items": ["terse bullet"] }
            ]
          }
        }

        Use createBead for missing top-level work, createChildBead for work under a known parent, updateField for text and metadata corrections, setStatus for moving work between board phases, setBlocked for blocker state, and setStale for stale/active state. Use addDependency or setParent only when the referenced ID appears in the board context. Keep each proposed action independently reviewable.

        Settings:
        cadence=\(settings.cadence.rawValue)
        autonomy=\(settings.autonomyLevel.rawValue)
        reviewsBacklog=\(settings.reviewsBacklog) \(settings.reviewsBacklog ? "" : "(do not propose backlog expansion unless it blocks active work)")
        generatesReports=\(settings.generatesReports) \(settings.generatesReports ? "" : "(return report as null)")
        maximumProposals=\(settings.maximumProposals)

        Board:
        name=\(board.name)
        repository=\(board.repositoryName)
        columns=\(board.columns.map(\.name).joined(separator: ", "))

        Pending decisions already surfaced:
        \(pendingDecisions.isEmpty ? "None" : pendingDecisions)

        Deterministic project intelligence:
        \(projectIntelligencePromptContext(intelligence))

        Beads:
        \(context.isEmpty ? "No active beads." : context)
        """
    }

    private func projectIntelligenceSummary(request: AIPMRunRequest, store: BoardStore) throws -> AIPMProjectIntelligenceSummary {
        let board = request.boardID.flatMap { boardID in
            store.boards.first { $0.id == boardID }
        } ?? store.selectedBoard
        guard let board else {
            throw LLMProviderError.unavailable("No board context is available.")
        }

        let activeBeads = board.columns.flatMap(\.beads).filter { !$0.isArchived }
        let beadsByRelationshipID = Dictionary(
            activeBeads.map { ($0.relationshipID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let blocked = activeBeads.filter(\.isBlocked)
        let stale = activeBeads.filter(\.isStale)
        let urgent = activeBeads.filter { $0.priority == .urgent }
        let orphanedChildren = activeBeads.filter { bead in
            bead.parentBeadsID.map { beadsByRelationshipID[$0] == nil } ?? false
        }
        let dependencyIssueBeads = activeBeads.filter { bead in
            bead.dependencyBeadsIDs.contains { beadsByRelationshipID[$0] == nil || $0 == bead.relationshipID }
        }

        var signals: [AIPMProjectSignal] = []
        if activeBeads.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: .info,
                category: .health,
                title: "Board has no active beads",
                detail: "There is no active work for the AI PM to analyze."
            ))
        }
        if !blocked.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: blocked.contains { $0.priority == .urgent || $0.priority == .high } ? .critical : .warning,
                category: .blocked,
                title: "\(blocked.count) blocked bead\(blocked.count == 1 ? "" : "s")",
                detail: "Blocked work needs an owner decision or dependency resolution.",
                beadIDs: blocked.map(\.relationshipID)
            ))
        }
        if !stale.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: stale.count >= 3 ? .warning : .info,
                category: .stale,
                title: "\(stale.count) stale bead\(stale.count == 1 ? "" : "s")",
                detail: "Stale work should be refreshed, closed, or moved out of active planning.",
                beadIDs: stale.map(\.relationshipID)
            ))
        }
        if !urgent.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: urgent.count >= 3 ? .warning : .info,
                category: .workload,
                title: "\(urgent.count) urgent bead\(urgent.count == 1 ? "" : "s")",
                detail: "Too many urgent items can hide the real priority order.",
                beadIDs: urgent.map(\.relationshipID)
            ))
        }
        if !orphanedChildren.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: .warning,
                category: .hierarchy,
                title: "\(orphanedChildren.count) bead\(orphanedChildren.count == 1 ? "" : "s") with missing parent",
                detail: "Parent references should point to active beads so hierarchy views and planning prompts stay accurate.",
                beadIDs: orphanedChildren.map(\.relationshipID)
            ))
        }
        if !dependencyIssueBeads.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: .warning,
                category: .dependency,
                title: "\(dependencyIssueBeads.count) bead\(dependencyIssueBeads.count == 1 ? "" : "s") with dependency issues",
                detail: "Dependencies should point to active beads and should not point back to the same bead.",
                beadIDs: dependencyIssueBeads.map(\.relationshipID)
            ))
        }
        if signals.isEmpty {
            signals.append(AIPMProjectSignal(
                severity: .info,
                category: .health,
                title: "No deterministic PM risks detected",
                detail: "The board has active work and no blocked, stale, orphaned, or invalid dependency signals."
            ))
        }

        return AIPMProjectIntelligenceSummary(
            boardID: board.id,
            boardName: board.name,
            totalActiveBeads: activeBeads.count,
            blockedBeads: blocked.count,
            staleBeads: stale.count,
            urgentBeads: urgent.count,
            orphanedChildren: orphanedChildren.count,
            dependencyIssues: dependencyIssueBeads.count,
            signals: signals,
            generatedAt: .now
        )
    }

    private func projectIntelligencePromptContext(_ intelligence: AIPMProjectIntelligenceSummary) -> String {
        let metrics = [
            "active=\(intelligence.totalActiveBeads)",
            "blocked=\(intelligence.blockedBeads)",
            "stale=\(intelligence.staleBeads)",
            "urgent=\(intelligence.urgentBeads)",
            "orphanedChildren=\(intelligence.orphanedChildren)",
            "dependencyIssues=\(intelligence.dependencyIssues)"
        ].joined(separator: " | ")
        let signals = intelligence.signals.map { signal in
            var parts = [
                "\(signal.severity.rawValue)/\(signal.category.rawValue)",
                signal.title,
                signal.detail
            ]
            if !signal.beadIDs.isEmpty {
                parts.append("beads=\(signal.beadIDs.joined(separator: ", "))")
            }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
        return """
        board=\(intelligence.boardName)
        metrics=\(metrics)
        signals:
        \(signals)
        """
    }

    private func reviewBeads(root: Bead, board: Board, scope: BeadPlanReviewScope) -> [Bead] {
        guard scope == .subtree else { return [root] }

        let beadsByRelationshipID = Dictionary(
            board.columns.flatMap(\.beads).map { ($0.relationshipID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        var result: [Bead] = []
        var visited: Set<String> = []

        func visit(_ bead: Bead) {
            guard !visited.contains(bead.relationshipID) else { return }
            visited.insert(bead.relationshipID)
            result.append(bead)
            for childID in bead.childBeadsIDs {
                if let child = beadsByRelationshipID[childID] {
                    visit(child)
                }
            }
        }

        visit(root)
        return result
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
            ] + (llmConfiguration.status.isAvailable ? ["ai-planning-assistance", "ai-bead-field-suggestions", "ai-plan-review", "ai-status-report", "ai-pm-automation"] : []),
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

private struct LLMPlanReviewPayload: Decodable {
    var message: String
    var findings: [BeadPlanReviewFinding]
    var changes: [BeadPlanReviewChange]
}

private struct LLMStatusReportPayload: Decodable {
    var title: String
    var summary: String
    var sections: [BeadStatusReportSection]
}

private struct LLMAIPMRunPayload: Decodable {
    var summary: String
    var proposals: [LLMAIPMProposalPayload]
    var report: LLMAIPMReportPayload?
}

private struct LLMAIPMProposalPayload: Decodable {
    var title: String
    var summary: String
    var category: AIPMProposalCategory
    var risk: AIPMProposalRisk
    var rationale: String
    var changes: [BeadPlanReviewChange]?
}

private struct LLMAIPMReportPayload: Decodable {
    var title: String
    var summary: String
    var sections: [BeadStatusReportSection]
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
    case responseTooLarge(Int, Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            message
        case .invalidResponse:
            "The LLM provider returned an invalid response."
        case .providerStatus(let status):
            "The LLM provider returned HTTP \(status)."
        case let .responseTooLarge(actual, limit):
            "The LLM provider returned \(actual) bytes, above the configured \(limit) byte limit."
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
