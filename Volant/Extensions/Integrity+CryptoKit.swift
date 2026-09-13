import CryptoKit
import Foundation

func import_CryptoKit_sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
