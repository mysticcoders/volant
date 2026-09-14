import Foundation
import CryptoKit
import CommonCrypto
import zlib

enum RaycastImportFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

/// Independent RAYCFG3 reader. No shell, Keychain lookup, or decrypted temporary file.
enum RaycastArchive {
    static let fileLimit = 64 * 1024 * 1024
    static func decode(_ bytes: Data, password: String) throws -> Data {
        let raw = [UInt8](bytes)
        guard raw.count <= fileLimit else { throw failure("This export exceeds the 64 MB import limit.") }
        guard raw.count >= 12, raw.prefix(8) == Array("RAYCFG3\n".utf8)[...] else {
            throw failure("Choose a Raycast schema 3 export. Older Raycast exports aren’t supported yet.")
        }
        let size = (0..<4).reduce(0) { $0 | Int(raw[8 + $1]) << (8 * $1) }
        guard size > 0, size <= 1024 * 1024, 12 + size + 16 < raw.count else { throw failure("The export header is damaged.") }
        let header = try gunzip(Data(raw[12..<(12 + size)]), limit: 1024 * 1024)
        guard let object = try JSONSerialization.jsonObject(with: header) as? [String: Any],
              object["schemaVersion"] as? Int == 3,
              let encryption = object["encryption"] as? [String: Any],
              let iv = hex(encryption["iv"]), iv.count == 16,
              let salt = hex(encryption["salt"]), salt.count == 16 else { throw failure("The export uses an unsupported encryption header.") }
        var key = try RaycastScrypt.derive(password: Array(password.utf8), salt: salt)
        defer { _ = key.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let compressed: Data
        do {
            let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: raw[(12 + size)..<(raw.count - 16)], tag: raw.suffix(16))
            compressed = try AES.GCM.open(sealed, using: SymmetricKey(data: key))
        } catch { throw failure("Couldn’t unlock the export. Check the password, or choose a fresh export if the file is damaged.") }
        return try gunzip(compressed, limit: 128 * 1024 * 1024)
    }
    static func failure(_ text: String) -> RaycastImportFailure { .message(text) }
    private static func hex(_ value: Any?) -> [UInt8]? {
        guard let value = value as? String, value.utf8.count == 32 else { return nil }
        let chars = Array(value.utf8)
        var result: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard chars[i] < 128, chars[i + 1] < 128, let byte = UInt8(String(decoding: chars[i...i+1], as: UTF8.self), radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }
    static func gunzip(_ data: Data, limit: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw failure("Couldn’t initialize the export reader.") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { source in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 32768)
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { target -> Int32 in
                    stream.next_out = target.baseAddress
                    stream.avail_out = uInt(target.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = buffer.count - Int(stream.avail_out)
                guard output.count + count <= limit else { throw failure("The expanded export exceeds the import memory limit.") }
                output.append(contentsOf: buffer.prefix(count))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw failure("Unexpected trailing data in the export.") }
                    return output
                }
                guard status == Z_OK, count > 0 else { throw failure("The export’s compressed data is damaged.") }
            }
        }
    }
}

/// scrypt with p=1, as specified by RFC 7914. Fixed production parameters; tests may reduce N/r.
/// Uses system PBKDF2-HMAC-SHA256 and CryptoKit AES-GCM; no dependency on another launcher's code.
enum RaycastScrypt {
    static func derive(password: [UInt8], salt: [UInt8], n: Int = 16384, r: Int = 8, length: Int = 32) throws -> [UInt8] {
        guard n > 1, n <= 16384, n & (n - 1) == 0, r > 0, r <= 8, length > 0, length <= 64 else { throw RaycastArchive.failure("Invalid key derivation parameters.") }
        let initial = try pbkdf(password, salt, 128 * r)
        var x = stride(from: 0, to: initial.count, by: 4).map { i in
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(initial[i + $1]) << (8 * $1) }
        }
        let width = x.count
        var memory = [UInt32](repeating: 0, count: n * width)
        defer { _ = memory.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        for i in 0..<n {
            for j in 0..<width { memory[i * width + j] = x[j] }
            x = mix(x, r: r)
        }
        for _ in 0..<n {
            let index = Int(x[width - 16] & UInt32(n - 1)) * width
            for j in 0..<width { x[j] ^= memory[index + j] }
            x = mix(x, r: r)
        }
        let mixed = x.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
        return try pbkdf(password, mixed, length)
    }
    private static func pbkdf(_ password: [UInt8], _ salt: [UInt8], _ count: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count)
        let status = password.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress?.assumingMemoryBound(to: Int8.self), password.count, s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 1, &result, count)
        } }
        guard status == kCCSuccess else { throw RaycastArchive.failure("Couldn’t derive the export key.") }
        return result
    }
    private static func mix(_ input: [UInt32], r: Int) -> [UInt32] {
        var state = Array(input.suffix(16))
        var output = [UInt32](repeating: 0, count: input.count)
        for block in 0..<(2 * r) {
            for j in 0..<16 { state[j] ^= input[block * 16 + j] }
            state = salsa(state)
            let destination = (block / 2 + (block % 2) * r) * 16
            for j in 0..<16 { output[destination + j] = state[j] }
        }
        return output
    }
    private static func salsa(_ input: [UInt32]) -> [UInt32] {
        var words = input
        func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 { (value << amount) | (value >> (32 - amount)) }
        func quarter(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            words[b] ^= rotate(words[a] &+ words[d], 7)
            words[c] ^= rotate(words[b] &+ words[a], 9)
            words[d] ^= rotate(words[c] &+ words[b], 13)
            words[a] ^= rotate(words[d] &+ words[c], 18)
        }
        for _ in 0..<4 {
            for i in 0..<4 { quarter(i * 5, (i * 5 + 4) % 16, (i * 5 + 8) % 16, (i * 5 + 12) % 16) }
            for row in 0..<4 { let base = row * 4; quarter(base + row, base + (row + 1) % 4, base + (row + 2) % 4, base + (row + 3) % 4) }
        }
        return zip(words, input).map { $0 &+ $1 }
    }
}
