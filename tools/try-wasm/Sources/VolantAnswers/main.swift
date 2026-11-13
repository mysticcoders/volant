import Foundation
import VolantCalc

/// The request the browser sends: the typed query, the visitor's clock as Unix seconds, their IANA
/// time zone and locale identifier, and, for currency, the raw feed bodies the site fetched.
/// `mode: "feeds"` asks only which feeds the query needs, so nothing is fetched otherwise.
struct Request: Decodable {
    let mode: String?
    let query: String
    let now: Double
    let zone: String?
    let locale: String?
    let ecb: String?
    let world: String?
    let crypto: String?
    let cryptoFetchedAt: Double?
}

/// Which rate feeds a query needs, decided by VolantCore's own `CurrencyConverter.feedsNeeded`.
struct Feeds: Encodable {
    let rates: Bool
    let world: Bool
    let crypto: Bool
}

/// One answer, as the launcher's calculator card shows it.
struct Answer: Encodable {
    let input: String
    let inputDetail: String?
    let result: String
    let resultDetail: String?
    let copyText: String
}

/// Reads one request from standard input and writes JSON: the feeds a query needs, or its answers.
/// Feed bodies are parsed by VolantCore's own parsers and installed as the current rates first.
/// A malformed request writes an empty list rather than failing the command.
func main() {
    var text = ""
    while let line = readLine(strippingNewline: false) { text += line }
    let encoder = JSONEncoder()
    guard let request = try? JSONDecoder().decode(Request.self, from: Data(text.utf8)) else {
        print("[]", terminator: "")
        return
    }
    let locale = Locale(identifier: request.locale ?? "en_US")
    if request.mode == "feeds" {
        let needed = CurrencyConverter.feedsNeeded(request.query, locale: locale)
        let output = (try? encoder.encode(Feeds(rates: needed.rates, world: needed.world, crypto: needed.crypto))) ?? Data("{}".utf8)
        print(String(decoding: output, as: UTF8.self), terminator: "")
        return
    }
    CurrencyRates.current = request.ecb.flatMap { CurrencyRates.parse(Data($0.utf8)) }
    WorldRates.current = request.world.flatMap { WorldRates.parse(Data($0.utf8)) }
    CryptoPrices.current = request.crypto.flatMap {
        CryptoPrices.parse(Data($0.utf8), at: Date(timeIntervalSince1970: request.cryptoFetchedAt ?? request.now))
    }
    let zone = request.zone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
    let answers = CalculationAnswer.answers(for: request.query, now: Date(timeIntervalSince1970: request.now),
                                            localZone: zone, locale: locale).map {
        Answer(input: $0.input, inputDetail: $0.inputDetail, result: $0.result, resultDetail: $0.resultDetail, copyText: $0.copyText)
    }
    let output = (try? encoder.encode(answers)) ?? Data("[]".utf8)
    print(String(decoding: output, as: UTF8.self), terminator: "")
}

main()
