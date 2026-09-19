import Foundation

/// No redirects, cookies, URL cache, background sessions or provider error-body logging.
final class AIRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct AIStreamDecoder {
    var provider: AIAPIProvider
    private var line = Data()
    private var fields: [String] = []
    private var eventBytes = 0
    private var total = 0
    private(set) var finished = false
    init(provider: AIAPIProvider) { self.provider = provider }
    mutating func feed(_ byte: UInt8) throws -> String {
        total += 1
        guard total <= 2_097_152, line.count < 65_536 else { throw AIHTTPError.limit }
        if byte != 10 { line.append(byte); return "" }
        guard let text = String(data: line, encoding: .utf8) else { throw AIHTTPError.response }
        line.removeAll(keepingCapacity: true)
        let clean = text.hasSuffix("\r") ? String(text.dropLast()) : text
        if clean.hasPrefix("data:") {
            let value = clean.dropFirst(5).drop(while: { $0 == " " })
            eventBytes += value.utf8.count
            guard eventBytes <= 65_536 else { throw AIHTTPError.limit }
            fields.append(String(value)); return ""
        }
        guard clean.isEmpty, !fields.isEmpty else { return "" }
        let data = fields.joined(separator: "\n"); fields = []; eventBytes = 0
        if data == "[DONE]" { guard provider == .compatible else { throw AIHTTPError.response }; finished = true; return "" }
        guard let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { throw AIHTTPError.response }
        if object["error"] != nil || object["type"] as? String == "error" { throw AIHTTPError.response }
        switch provider {
        case .openAI:
            switch object["type"] as? String {
            case "response.output_text.delta", "response.refusal.delta": return object["delta"] as? String ?? ""
            case "response.completed": finished = true
            case "response.failed", "response.incomplete": throw AIHTTPError.incomplete
            case "response.function_call_arguments.delta": throw AIHTTPError.unsupported
            default: break
            }
        case .anthropic:
            if object["type"] as? String == "message_stop" { finished = true }
            if let block = object["content_block"] as? [String: Any], block["type"] as? String == "tool_use" { throw AIHTTPError.unsupported }
            if let delta = object["delta"] as? [String: Any] {
                if delta["stop_reason"] as? String == "max_tokens" { throw AIHTTPError.incomplete }
                if delta["type"] as? String == "text_delta" { return delta["text"] as? String ?? "" }
            }
        case .compatible:
            if let choice = (object["choices"] as? [[String: Any]])?.first {
                if let reason = choice["finish_reason"] as? String, reason != "stop" { throw AIHTTPError.incomplete }
                if let delta = choice["delta"] as? [String: Any] {
                    if delta["tool_calls"] != nil || delta["function_call"] != nil { throw AIHTTPError.unsupported }
                    return delta["content"] as? String ?? ""
                }
            }
        }
        return ""
    }
}
final class AIHTTPTransport {
    let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 180
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config, delegate: AIRedirectGuard(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func request(_ config: AIHTTPConfiguration, key: String, path: String) throws -> URLRequest {
        try config.validate(requireModel: false)
        guard key.utf8.count <= 8192, !key.contains(where: { $0.isWhitespace }) else { throw AIHTTPError.key }
        if !config.local && key.isEmpty { throw AIHTTPError.key }
        var request = URLRequest(url: try config.baseURL().appendingPathComponent(path))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }
    func chatRequest(_ config: AIHTTPConfiguration, key: String, messages: [ACPMessage]) throws -> URLRequest {
        try config.validate()
        guard messages.count <= 100, messages.reduce(0, { $0 + $1.text.utf8.count }) <= 262_144 else { throw AIHTTPError.limit }
        let history = messages.map { ["role": $0.role == "You" ? "user" : "assistant", "content": $0.text] }
        var body: [String: Any] = ["model": config.model, "stream": true]
        let path: String
        switch config.provider {
        case .openAI: path = "responses"; body["input"] = history; body["store"] = false
        case .anthropic: path = "messages"; body["messages"] = history; body["max_tokens"] = 4096
        case .compatible: path = "chat/completions"; body["messages"] = history
        }
        var request = try request(config, key: key, path: path)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }
    func stream(_ config: AIHTTPConfiguration, key: String, messages: [ACPMessage], delta: @escaping (String) async throws -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: chatRequest(config, key: key, messages: messages))
        guard let http = response as? HTTPURLResponse else { throw AIHTTPError.response }
        guard (200...299).contains(http.statusCode) else { throw AIHTTPError.http(http.statusCode) }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw AIHTTPError.response }
        var parser = AIStreamDecoder(provider: config.provider)
        var pending = "", lastDelivery = Date()
        for try await byte in bytes {
            try Task.checkCancellation()
            pending += try parser.feed(byte)
            if !pending.isEmpty && (pending.utf8.count >= 256 || Date().timeIntervalSince(lastDelivery) >= 0.05 || parser.finished) {
                try await delta(pending); pending = ""; lastDelivery = Date()
            }
            if parser.finished { break }
        }
        if !pending.isEmpty { try await delta(pending) }
        guard parser.finished else { throw AIHTTPError.incomplete }
    }
    func models(_ config: AIHTTPConfiguration, key: String) async throws -> [String] {
        var request = try request(config, key: key, path: "models")
        request.timeoutInterval = config.local ? 2 : 15
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIHTTPError.response }
        guard (200...299).contains(http.statusCode) else { throw AIHTTPError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { throw AIHTTPError.limit }
            data.append(byte)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = json["data"] as? [[String: Any]], rows.count <= 1000 else { throw AIHTTPError.response }
        return Array(Set(rows.compactMap { $0["id"] as? String }.filter { !$0.isEmpty && $0.utf8.count <= 256 && !$0.contains(where: { $0.isNewline }) })).sorted()
    }
}
