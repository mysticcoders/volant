import XCTest
@testable import VolantCore

final class ExtensionItemBadgeTests: XCTestCase {
    func testBadgesAreTrimmedCappedAndKeepOnlyKnownSymbols() throws {
        let items = try ExtensionNetwork.items(from: #"""
        {"items":[
          {"title":"A fictional story","url":"https://news.example.com/1","badges":[
            {"symbol":"points","text":"312"},
            {"symbol":"comments","text":" 88 "},
            {"symbol":"../../icon.png","text":"example.com"},
            {"symbol":"time","text":"3h"}
          ]},
          {"title":"Empty badges","url":"https://news.example.com/2","badges":[{"symbol":"points","text":"  "}]},
          {"title":"Long badge","url":"https://news.example.com/3","badges":[{"text":"a\nvery long badge text that goes on and on"}]}
        ]}
        """#)
        XCTAssertEqual(items[0].badges, [ExtensionItemBadge(symbol: "points", text: "312"), ExtensionItemBadge(symbol: "comments", text: "88"),
                                         ExtensionItemBadge(symbol: nil, text: "example.com")], "At most three; an unknown symbol keeps its text")
        XCTAssertNil(items[1].badges, "Blank badges are dropped")
        XCTAssertEqual(items[2].badges?.first?.text.count, ExtensionItemBadge.maximumTextLength)
        XCTAssertFalse(items[2].badges?.first?.text.contains("\n") ?? true, "Badges stay on one line")
    }

    func testSymbolNamesAreStableLowercaseIdentifiers() {
        let names = ExtensionItemBadge.Symbol.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { $0.allSatisfy(\.isLowercase) })
    }
}
