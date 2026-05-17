#if os(macOS)
import Darwin
import Foundation

@MainActor
final class BeadsHTTPServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Server stopped"
    @Published private(set) var listeningURLString = ""
    @Published private(set) var pairingToken = UUID().uuidString

    private weak var store: BoardStore?
    private var socketFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.beadsorchestrator.http-server", qos: .userInitiated)
    private let port: UInt16 = 8787

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
            return httpResponse(status: 422, body: Data())
        }
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
                "beads-relationship-metadata"
            ]
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
