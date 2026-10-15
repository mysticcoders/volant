import XCTest
@testable import VolantCore

final class ExtensionItemSymbolTests: XCTestCase {
    func testRowsKeepKnownSymbolsAndDropUnknownOnes() throws {
        let items = try ExtensionNetwork.items(from: #"""
        {"items":[
          {"title":"Sunny, 24°","url":"https://weather.example.com/1","symbol":"sun"},
          {"title":"Showers","url":"https://weather.example.com/2","symbol":"heavy-rain"},
          {"title":"Bad name","url":"https://weather.example.com/3","symbol":"../../icon.png"},
          {"title":"No symbol","url":"https://weather.example.com/4"}
        ]}
        """#)
        XCTAssertEqual(items.map(\.symbol), ["sun", "heavy-rain", nil, nil])
    }

    func testSymbolNamesAreStableLowercaseIdentifiers() {
        let names = ExtensionItemSymbol.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "-" } })
        XCTAssertEqual(Set(ExtensionItemSymbol.allCases.map(\.systemName)).count, names.count)
    }
}
