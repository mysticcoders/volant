import Foundation

public struct Snippet: Codable, Hashable {
    public var name: String
    public var keyword: String
    public var body: String

    public init(name: String, keyword: String, body: String) {
        self.name = name
        self.keyword = keyword
        self.body = body
    }
}
