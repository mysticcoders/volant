import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Talks to an fsearch daemon the owner already runs (github.com/noahdunnagan/fsearch), over its
/// JSON-lines Unix socket at `~/Library/Application Support/FSearch/fsearch.sock`. Volant never
/// installs, starts or runs fsearch: when no daemon is listening, it reports that and file search
/// falls back to Spotlight. Replies are size-capped and validated; only a hit's path, kind,
/// modification time, size and score are kept.
public enum FSearch {
    public static let maximumQueryLength = 256
    public static let maximumHits = 50
    public static let maximumReplyBytes = 1 << 20
    public static let timeout: TimeInterval = 2

    /// The daemon's socket for a home folder.
    public static func socketPath(home: String) -> String {
        (home as NSString).appendingPathComponent("Library/Application Support/FSearch/fsearch.sock")
    }

    /// One file or folder fsearch found.
    public struct Hit: Codable, Equatable {
        public var path: String
        public var kind: String
        public var mtime: Int?
        public var size: Int?
        public var score: Int?
        public init(path: String, kind: String, mtime: Int? = nil, size: Int? = nil, score: Int? = nil) {
            self.path = path; self.kind = kind; self.mtime = mtime; self.size = size; self.score = score
        }
        public var isFolder: Bool { kind == "dir" }
    }

    /// What the daemon reports about its index.
    public struct Status: Codable, Equatable {
        public var entries: Int
        public var fullDiskAccess: Bool?
        enum CodingKeys: String, CodingKey { case entries, fullDiskAccess = "full_disk_access" }
        public init(entries: Int, fullDiskAccess: Bool? = nil) { self.entries = entries; self.fullDiskAccess = fullDiskAccess }
    }

    /// A search request for a filename query, or nil when the query cannot be sent.
    public static func searchRequest(_ query: String, limit: Int) -> Data? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maximumQueryLength, !text.contains(where: \.isNewline) else { return nil }
        return line(["op": "search", "q": text, "limit": max(1, min(limit, maximumHits))])
    }

    public static let statusRequest = line(["op": "status"])

    /// Tells fsearch the owner opened a file, so it ranks higher for a while.
    public static func openedRequest(_ path: String) -> Data? {
        guard isUsablePath(path) else { return nil }
        return line(["op": "open", "path": path])
    }

    /// The hits in a search reply. Paths that are not absolute, too long or contain a NUL are dropped,
    /// and at most `maximumHits` are kept. A reply with `"ok": false` becomes `.daemon` with its message.
    public static func hits(from reply: Data) throws -> [Hit] {
        let object = try decode(reply)
        guard let raw = object["hits"] as? [[String: Any]] else { throw FSearchError.malformed }
        return raw.prefix(maximumHits).compactMap { item in
            guard let path = item["path"] as? String, isUsablePath(path) else { return nil }
            return Hit(path: path, kind: (item["kind"] as? String).map { String($0.prefix(16)) } ?? "file",
                       mtime: item["mtime"] as? Int, size: item["size"] as? Int, score: item["score"] as? Int)
        }
    }

    public static func status(from reply: Data) throws -> Status {
        let object = try decode(reply)
        guard let entries = object["entries"] as? Int else { throw FSearchError.malformed }
        return Status(entries: entries, fullDiskAccess: object["full_disk_access"] as? Bool)
    }

    static func isUsablePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count <= 4096 && !path.contains("\0")
    }

    private static func line(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        data.append(0x0A)
        return data
    }

    private static func decode(_ reply: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else { throw FSearchError.malformed }
        if object["ok"] as? Bool == false {
            throw FSearchError.daemon(String(((object["error"] as? String) ?? "fsearch could not answer.").prefix(300)))
        }
        return object
    }

    /// Sends one request line and reads one reply line from the socket, within `timeout` and
    /// `maximumReplyBytes`. A missing or refused socket is `.notRunning`.
    public static func exchange(socket path: String, request: Data, timeout: TimeInterval = timeout,
                                maximumBytes: Int = maximumReplyBytes) throws -> Data {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { throw FSearchError.notRunning }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        #if canImport(Darwin)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let descriptor = Glibc.socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { throw FSearchError.notRunning }
        defer { close(descriptor) }
        var wait = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        #if canImport(Darwin)
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw FSearchError.notRunning }
        let sent = request.withUnsafeBytes { send(descriptor, $0.baseAddress, request.count, 0) }
        guard sent == request.count else { throw FSearchError.timedOut }
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = recv(descriptor, &chunk, chunk.count, 0)
            if count < 0 { throw FSearchError.timedOut }
            if count == 0 { break }
            reply.append(contentsOf: chunk[0..<count])
            if reply.count > maximumBytes { throw FSearchError.tooLarge }
            if let newline = reply.firstIndex(of: 0x0A) { reply = reply[..<newline]; break }
        }
        guard !reply.isEmpty else { throw FSearchError.malformed }
        return Data(reply)
    }
}

public enum FSearchError: Error, LocalizedError, Equatable {
    case notRunning, timedOut, tooLarge, malformed, daemon(String)
    public var errorDescription: String? {
        switch self {
        case .notRunning: return "fsearch isn’t running. Run fsearch once in Terminal, or start it at login with fsearch install --login."
        case .timedOut: return "fsearch didn’t answer in time."
        case .tooLarge: return "fsearch sent more than Volant reads."
        case .malformed: return "fsearch sent a reply Volant couldn’t read."
        case .daemon(let message): return "fsearch: " + message
        }
    }
}
