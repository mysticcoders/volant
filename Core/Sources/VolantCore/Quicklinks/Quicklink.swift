import Foundation

public struct Quicklink: Codable, Hashable {
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}
