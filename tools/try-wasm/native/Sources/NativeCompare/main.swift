import Foundation
import VolantCore

// Prints the native macOS answers for the spike's sample queries with the same clock, zone and
// locale as calc-test.mjs, so the WASI build's answers can be compared line by line.
var queries = Array(CommandLine.arguments.dropFirst())
if queries.isEmpty { while let line = readLine() { if !line.isEmpty { queries.append(line) } } }
let now = Date(timeIntervalSince1970: 1_794_040_200)
for query in queries {
    let answers = CalculationAnswer.answers(for: query, now: now, localZone: TimeZone(identifier: "America/Los_Angeles")!,
                                            locale: Locale(identifier: "en_US"))
    let text = answers.map { "\($0.result)\($0.resultDetail.map { " [\($0)]" } ?? "")" }.joined(separator: " | ")
    print("\(query): \(text.isEmpty ? "(no answer)" : text)")
}
