import Darwin
import Foundation
import Network
import Security

struct BrowserUploadHTTPRequest: Equatable {
    let method: String
    let target: String
    let version: String
    let headers: [String: String]
}

enum BrowserUploadHTTPError: LocalizedError, Equatable {
    case malformedRequest
    case headersTooLarge
    case unsupportedMethod
    case lengthRequired
    case invalidLength
    case bodyTooLarge
    case unsupportedMediaType
    case unsupportedTransferEncoding
    case invalidHost
    case invalidOrigin
    case unauthorized
    case tooManyRequests
    case tooManyTransfers
    case notFound

    var status: Int {
        switch self {
        case .malformedRequest, .invalidLength, .invalidHost, .invalidOrigin: return 400
        case .unauthorized: return 401
        case .notFound: return 404
        case .unsupportedMediaType: return 415
        case .unsupportedMethod: return 405
        case .lengthRequired: return 411
        case .bodyTooLarge: return 413
        case .tooManyRequests: return 429
        case .tooManyTransfers: return 503
        case .headersTooLarge: return 431
        case .unsupportedTransferEncoding: return 501
        }
    }

    var errorDescription: String? {
        switch self {
        case .malformedRequest: return "请求格式无效"
        case .headersTooLarge: return "请求头过大"
        case .unsupportedMethod: return "不支持此请求方法"
        case .lengthRequired: return "必须提供 Content-Length"
        case .invalidLength: return "Content-Length 无效"
        case .bodyTooLarge: return "文件超过 200 MB 限制"
        case .unsupportedMediaType: return "不支持此文件类型"
        case .unsupportedTransferEncoding: return "不支持分块传输"
        case .invalidHost: return "Host 无效"
        case .invalidOrigin: return "请求来源无效，请用页面显示的地址打开"
        case .unauthorized: return "验证码或会话已失效"
        case .tooManyRequests: return "尝试次数过多，请稍后重试"
        case .tooManyTransfers: return "已有文件正在上传，请稍后重试"
        case .notFound: return "页面不存在"
        }
    }
}

enum BrowserUploadHTTPParser {
    static let maximumHeaderBytes = 32 * 1024

    static func parseHeader(from data: Data) throws -> (BrowserUploadHTTPRequest, Data)? {
        guard data.count <= maximumHeaderBytes || data.range(of: Data("\r\n\r\n".utf8)) != nil else {
            throw BrowserUploadHTTPError.headersTooLarge
        }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard boundary.lowerBound <= maximumHeaderBytes,
              let text = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
            throw BrowserUploadHTTPError.headersTooLarge
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { throw BrowserUploadHTTPError.malformedRequest }
        let parts = first.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1",
              !parts[0].isEmpty, parts[1].hasPrefix("/") else {
            throw BrowserUploadHTTPError.malformedRequest
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw BrowserUploadHTTPError.malformedRequest }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil,
                  name.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).contains($0) }) else {
                throw BrowserUploadHTTPError.malformedRequest
            }
            headers[name] = value
        }
        let body = Data(data[boundary.upperBound...])
        return (BrowserUploadHTTPRequest(method: String(parts[0]), target: String(parts[1]), version: String(parts[2]), headers: headers), body)
    }

    static func contentLength(for request: BrowserUploadHTTPRequest, maximum: Int64) throws -> Int64 {
        if let transfer = request.headers["transfer-encoding"], !transfer.isEmpty {
            throw BrowserUploadHTTPError.unsupportedTransferEncoding
        }
        guard let raw = request.headers["content-length"] else { throw BrowserUploadHTTPError.lengthRequired }
        guard !raw.hasPrefix("+"), let value = Int64(raw), value >= 0 else { throw BrowserUploadHTTPError.invalidLength }
        guard value <= maximum else { throw BrowserUploadHTTPError.bodyTooLarge }
        return value
    }
}

final class BrowserUploadAuthorization {
    let code: String
    let expiresAt: Date
    private(set) var token: String?
    private var failedAttempts: [String: [Date]] = [:]
    private let now: () -> Date

    init(lifetime: TimeInterval = 10 * 60, now: @escaping () -> Date = Date.init, code: String? = nil) {
        self.now = now
        self.code = code ?? String(format: "%06d", Int.random(in: 0...999_999))
        expiresAt = now().addingTimeInterval(lifetime)
    }

    func exchange(code candidate: String, client: String) throws -> String {
        let current = now()
        guard current < expiresAt else { throw BrowserUploadHTTPError.unauthorized }
        let recent = (failedAttempts[client] ?? []).filter { current.timeIntervalSince($0) < 60 }
        guard recent.count < 5 else { throw BrowserUploadHTTPError.tooManyRequests }
        guard candidate == code else {
            failedAttempts[client] = recent + [current]
            throw BrowserUploadHTTPError.unauthorized
        }
        let newToken = Self.randomToken()
        token = newToken
        failedAttempts[client] = []
        return newToken
    }

    func authorizes(_ authorizationHeader: String?) -> Bool {
        guard now() < expiresAt, let token else { return false }
        return authorizationHeader == "Bearer \(token)"
    }

    func invalidate() {
        token = nil
        failedAttempts.removeAll()
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
    }
}

enum PrivateIPv4AddressProvider {
    static func isUsable(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168)
    }

    static func addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var values: [(String, String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let value = String(cString: host)
            guard isUsable(value) else { continue }
            values.append((String(cString: interface.pointee.ifa_name), value))
        }
        return Array(Set(values.map(\.1))).sorted { lhs, rhs in
            let leftWiFi = values.contains { $0.0 == "en0" && $0.1 == lhs }
            let rightWiFi = values.contains { $0.0 == "en0" && $0.1 == rhs }
            return leftWiFi == rightWiFi ? lhs.localizedStandardCompare(rhs) == .orderedAscending : leftWiFi
        }
    }
}

struct BrowserUploadResult: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let succeeded: Bool
    let detail: String
}

protocol BrowserUploadServing: AnyObject {
    var onStateChange: ((BrowserUploadServer.State) -> Void)? { get set }
    var onImport: ((ImportedBookRecord) -> Void)? { get set }
    var onResult: ((BrowserUploadResult) -> Void)? { get set }
    var authorization: BrowserUploadAuthorization { get }
    func start()
    func stop()
}

final class BrowserUploadServer: BrowserUploadServing, @unchecked Sendable {
    enum State: Equatable { case stopped, starting, ready(UInt16), failed(String) }

    var onStateChange: ((State) -> Void)?
    var onImport: ((ImportedBookRecord) -> Void)?
    var onResult: ((BrowserUploadResult) -> Void)?
    private(set) var authorization = BrowserUploadAuthorization()

    private let queue = DispatchQueue(label: "ice-reader.browser-upload")
    private let store: ImportedBookStore
    private let bundle: Bundle
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var activeUpload = false
    private var allowedHosts: Set<String> = []

    init(store: ImportedBookStore = .shared, bundle: Bundle = .main) {
        self.store = store
        self.bundle = bundle
    }

    func start() {
        queue.async {
            self.stopLocked(notify: false)
            self.authorization = BrowserUploadAuthorization()
            self.emit(.starting)
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.service = NWListener.Service(name: "Ice Reader 上传", type: "_icereader-upload._tcp")
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.emit(.failed("无法启动接收服务：\(error.localizedDescription)"))
            }
        }
    }

    func stop() { queue.async { self.stopLocked(notify: true) } }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            allowedHosts = Set(PrivateIPv4AddressProvider.addresses().map { "\($0):\(port)" })
            emit(.ready(port))
        case .failed(let error):
            stopLocked(notify: false)
            emit(.failed("本地网络接收失败：\(error.localizedDescription)"))
        case .cancelled: emit(.stopped)
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .failed = state { self.finish(connection) }
            if case .cancelled = state { self.finish(connection) }
        }
        connection.start(queue: queue)
        receiveHeader(connection, buffer: Data())
    }

    private func receiveHeader(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var combined = buffer
            if let data { combined.append(data) }
            do {
                if let (request, initialBody) = try BrowserUploadHTTPParser.parseHeader(from: combined) {
                    try self.route(request, initialBody: initialBody, connection: connection)
                } else if complete || error != nil {
                    throw BrowserUploadHTTPError.malformedRequest
                } else {
                    self.receiveHeader(connection, buffer: combined)
                }
            } catch {
                self.sendError(error, connection: connection)
            }
        }
    }

    private func route(_ request: BrowserUploadHTTPRequest, initialBody: Data, connection: NWConnection) throws {
        guard ["GET", "POST", "PUT"].contains(request.method) else { throw BrowserUploadHTTPError.unsupportedMethod }
        guard let host = request.headers["host"], allowedHosts.contains(host) else { throw BrowserUploadHTTPError.invalidHost }
        guard let components = URLComponents(string: "http://localhost\(request.target)"), let path = components.path.removingPercentEncoding else {
            throw BrowserUploadHTTPError.malformedRequest
        }
        if request.method == "GET" {
            guard initialBody.isEmpty else { throw BrowserUploadHTTPError.malformedRequest }
            switch path {
            case "/": sendAsset(name: "index", extension: "html", contentType: "text/html; charset=utf-8", connection: connection)
            case "/style.css": sendAsset(name: "style", extension: "css", contentType: "text/css; charset=utf-8", connection: connection)
            case "/app.js": sendAsset(name: "app", extension: "js", contentType: "application/javascript; charset=utf-8", connection: connection)
            case "/api/status": sendJSON(["ready": true], status: 200, connection: connection)
            default: throw BrowserUploadHTTPError.notFound
            }
            return
        }
        guard request.headers["origin"] == "http://\(host)" else { throw BrowserUploadHTTPError.invalidOrigin }
        if request.method == "POST", path == "/api/session" {
            let length = try BrowserUploadHTTPParser.contentLength(for: request, maximum: 256)
            receiveBody(connection, initial: initialBody, expected: length) { data in
                do {
                    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let code = object?["code"] as? String else { throw BrowserUploadHTTPError.malformedRequest }
                    let token = try self.authorization.exchange(code: code, client: self.clientKey(connection))
                    self.sendJSON(["token": token], status: 200, connection: connection)
                } catch { self.sendError(error, connection: connection) }
            }
            return
        }
        guard request.method == "PUT", path == "/api/upload" else { throw BrowserUploadHTTPError.notFound }
        guard authorization.authorizes(request.headers["authorization"]) else { throw BrowserUploadHTTPError.unauthorized }
        guard !activeUpload else { throw BrowserUploadHTTPError.tooManyTransfers }
        let contentType = request.headers["content-type"]?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard let contentType, ["application/octet-stream", "text/plain", "text/markdown", "text/html"].contains(contentType) else {
            throw BrowserUploadHTTPError.unsupportedMediaType
        }
        let length = try BrowserUploadHTTPParser.contentLength(for: request, maximum: ImportedBookStore.maximumUploadSize)
        guard length > 0 else { throw BrowserUploadHTTPError.invalidLength }
        guard store.hasAvailableSpace(for: length) else { throw ImportedBookStoreError.insufficientStorage }
        let query = components.queryItems ?? []
        guard let filename = query.first(where: { $0.name == "filename" })?.value else { throw ImportedBookStoreError.emptyFilename }
        let relativePath = query.first(where: { $0.name == "relativePath" })?.value
        _ = try ImportedBookStore.validatedFilename(filename)
        _ = try ImportedBookStore.validatedDisplayPath(relativePath)
        activeUpload = true
        streamUpload(connection, initial: initialBody, expected: length, filename: filename, relativePath: relativePath)
    }

    private func streamUpload(_ connection: NWConnection, initial: Data, expected: Int64, filename: String, relativePath: String?) {
        do {
            let stagedURL = try store.makeStagingURL()
            let handle = try FileHandle(forWritingTo: stagedURL)
            var received: Int64 = 0
            func consume(_ data: Data) throws {
                guard received + Int64(data.count) <= expected else { throw BrowserUploadHTTPError.invalidLength }
                try handle.write(contentsOf: data)
                received += Int64(data.count)
            }
            try consume(initial)
            func finishUpload() {
                do {
                    try handle.close()
                    guard received == expected else { throw ImportedBookStoreError.sizeMismatch }
                    let installation = try self.store.installStagedFile(
                        stagedURL: stagedURL,
                        filename: filename,
                        source: .browserUpload(relativePath: relativePath),
                        expectedSize: expected
                    )
                    let record = installation.record
                    self.activeUpload = false
                    self.onImport?(record)
                    self.onResult?(BrowserUploadResult(title: record.title, succeeded: true, detail: "已导入"))
                    self.sendJSON(["title": record.title, "id": record.id], status: 201, connection: connection)
                } catch {
                    self.activeUpload = false
                    try? handle.close()
                    self.store.removeTemporaryFile(stagedURL)
                    self.onResult?(BrowserUploadResult(title: filename, succeeded: false, detail: error.localizedDescription))
                    self.sendError(error, connection: connection)
                }
            }
            func receiveMore() {
                if received == expected { finishUpload(); return }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
                    do {
                        if let data { try consume(data) }
                        if received == expected { finishUpload() }
                        else if complete || error != nil { throw ImportedBookStoreError.sizeMismatch }
                        else { receiveMore() }
                    } catch {
                        self.activeUpload = false
                        try? handle.close()
                        self.store.removeTemporaryFile(stagedURL)
                        self.onResult?(BrowserUploadResult(title: filename, succeeded: false, detail: error.localizedDescription))
                        self.sendError(error, connection: connection)
                    }
                }
            }
            receiveMore()
        } catch {
            activeUpload = false
            sendError(error, connection: connection)
        }
    }

    private func receiveBody(_ connection: NWConnection, initial: Data, expected: Int64, completion: @escaping (Data) -> Void) {
        if Int64(initial.count) > expected { sendError(BrowserUploadHTTPError.invalidLength, connection: connection); return }
        if Int64(initial.count) == expected { completion(initial); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: Int(expected) - initial.count) { data, _, complete, error in
            var body = initial
            if let data { body.append(data) }
            if Int64(body.count) == expected { completion(body) }
            else if complete || error != nil { self.sendError(ImportedBookStoreError.sizeMismatch, connection: connection) }
            else { self.receiveBody(connection, initial: body, expected: expected, completion: completion) }
        }
    }

    private func sendAsset(name: String, extension ext: String, contentType: String, connection: NWConnection) {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "BrowserUploadWeb"),
              let data = try? Data(contentsOf: url) else {
            sendError(BrowserUploadHTTPError.notFound, connection: connection)
            return
        }
        send(data, status: 200, contentType: contentType, connection: connection)
    }

    private func sendJSON(_ object: [String: Any], status: Int, connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        send(data, status: status, contentType: "application/json; charset=utf-8", connection: connection)
    }

    private func sendError(_ error: Error, connection: NWConnection) {
        let status = (error as? BrowserUploadHTTPError)?.status ?? {
            switch error as? ImportedBookStoreError {
            case .fileTooLarge: return 413
            case .insufficientStorage: return 507
            case .unsupportedExtension: return 415
            default: return 400
            }
        }()
        sendJSON(["error": error.localizedDescription], status: status, connection: connection)
    }

    private func send(_ body: Data, status: Int, contentType: String, connection: NWConnection) {
        let reason = [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed", 411: "Length Required", 413: "Content Too Large", 415: "Unsupported Media Type", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 501: "Not Implemented", 503: "Service Unavailable", 507: "Insufficient Storage"][status] ?? "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in self.finish(connection) })
    }

    private func clientKey(_ connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint { return String(describing: host) }
        return String(describing: connection.endpoint)
    }

    private func finish(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = nil
        connection.cancel()
    }

    private func stopLocked(notify: Bool) {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        activeUpload = false
        allowedHosts.removeAll()
        authorization.invalidate()
        store.cleanupStaging()
        if notify { emit(.stopped) }
    }

    private func emit(_ state: State) { DispatchQueue.main.async { self.onStateChange?(state) } }
}
