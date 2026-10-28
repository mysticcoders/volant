import XCTest
import VolantCore

private final class RatesFixtureProtocol: URLProtocol {
    static var respond: ((RatesFixtureProtocol) -> Void)?
    static var cancelled: (() -> Void)?
    private var onCancel: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        onCancel = Self.cancelled
        Self.respond?(self)
    }
    override func stopLoading() { onCancel?() }

    func send(_ chunks: [Data], status: Int = 200, length: Int? = nil, finish: Bool = true) {
        var headers = ["Content-Type": "application/json"]
        if let length { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
}

final class RatesHostTests: XCTestCase {
    private var host: RatesHost!
    private let crypto = Data(#"{"bitcoin":{"eur":50000},"ethereum":{"eur":2000},"solana":{"eur":100},"ripple":{"eur":0.5},"binancecoin":{"eur":400},"cardano":{"eur":0.25}}"#.utf8)

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RatesFixtureProtocol.self]
        host = RatesHost(configuration: config)
    }

    override func tearDown() {
        host.stop()
        host = nil
        RatesFixtureProtocol.respond = nil
        RatesFixtureProtocol.cancelled = nil
        super.tearDown()
    }

    func testChunkedCryptoExactlyAtLimitParsesAndRepliesOnce() {
        var body = crypto
        body.append(Data(repeating: 32, count: CryptoPrices.maximumBytes - body.count))
        RatesFixtureProtocol.respond = { fixture in
            XCTAssertEqual(fixture.request.url, CryptoPrices.request)
            XCTAssertNil(fixture.request.value(forHTTPHeaderField: CryptoPrices.keyHeader))
            fixture.send([body.prefix(100), body.dropFirst(100)])
        }
        let done = expectation(description: "Parsed bounded response")
        host.fetchCrypto(key: nil) { data, error in
            XCTAssertEqual(data, body)
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testUnknownLengthOverflowCancelsBeforeServerFinishes() {
        let cancelled = expectation(description: "Cancelled oversized transfer")
        RatesFixtureProtocol.cancelled = { cancelled.fulfill() }
        RatesFixtureProtocol.respond = { fixture in
            fixture.send([Data(repeating: 32, count: CryptoPrices.maximumBytes), Data([32])], finish: false)
        }
        let done = expectation(description: "Rejected before end of stream")
        host.fetchCrypto(key: nil) { data, error in
            XCTAssertNil(data)
            XCTAssertEqual(error, "Couldn’t get crypto prices.")
            done.fulfill()
        }
        wait(for: [done, cancelled], timeout: 3)
    }

    func testAdvertisedOversizeRejectsWithoutReceivingBody() {
        RatesFixtureProtocol.respond = { $0.send([], length: CurrencyRates.maximumBytes + 1, finish: false) }
        let done = expectation(description: "Reject length header")
        host.fetchRates { data, error in
            XCTAssertNil(data)
            XCTAssertEqual(error, "Couldn’t get exchange rates.")
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testSingleOversizedWorldRatesChunkRejectsBeforeCompletion() {
        RatesFixtureProtocol.respond = { fixture in
            XCTAssertEqual(fixture.request.url, WorldRates.feed)
            fixture.send([Data(repeating: 32, count: WorldRates.maximumBytes + 1)], finish: false)
        }
        let done = expectation(description: "Reject one oversized chunk")
        host.fetchWorldRates { data, error in
            XCTAssertNil(data)
            XCTAssertEqual(error, "Couldn’t get exchange rates.")
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testCryptoStatusMessagesDoNotDependOnReceivingABody() {
        for (status, key, message) in [(429, nil as String?, CryptoPrices.busyMessage), (401, "fixture-key", "CoinGecko didn’t accept the key.")] {
            RatesFixtureProtocol.respond = { fixture in
                XCTAssertEqual(fixture.request.value(forHTTPHeaderField: CryptoPrices.keyHeader), key)
                fixture.send([], status: status, finish: false)
            }
            let done = expectation(description: "Status-specific error")
            host.fetchCrypto(key: key) { data, error in
                XCTAssertNil(data)
                XCTAssertEqual(error, message)
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
    }

    func testMalformedSuccessBodyNeverCrossesXPC() {
        RatesFixtureProtocol.respond = { $0.send([Data("fictional invalid feed".utf8)]) }
        let done = expectation(description: "Parse before reply")
        host.fetchRates { data, error in
            XCTAssertNil(data)
            XCTAssertNotNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
}
