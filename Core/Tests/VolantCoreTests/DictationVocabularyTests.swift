import XCTest

@testable import VolantCore

/// The dictation vocabulary: corrections inside a phrase, recognizer hints, import parsing, limits,
/// and the config patch that keeps other fields and refuses a stale list.
final class DictationVocabularyTests: XCTestCase {
    private let kubernetes = DictationVocabularyEntry(term: "Kubernetes", soundsLike: ["cooper netties", "cuber nettis"])

    func testMishearingsAndCapitalizationAreCorrectedAsWholeWords() {
        let list = [kubernetes, DictationVocabularyEntry(term: "PostgreSQL", soundsLike: ["post gress"])]
        XCTAssertEqual(DictationVocabulary.applying(list, to: " Deploy it on cooper netties."), " Deploy it on Kubernetes.")
        XCTAssertEqual(DictationVocabulary.applying(list, to: "Cuber  Nettis and kubernetes, then post gress"), "Kubernetes and Kubernetes, then PostgreSQL")
        XCTAssertEqual(DictationVocabulary.applying(list, to: "postgresql is fine"), "PostgreSQL is fine")
        XCTAssertEqual(DictationVocabulary.applying(list, to: "kubernetesish and cooper nettiesx"), "kubernetesish and cooper nettiesx", "Only whole words change")
        XCTAssertEqual(DictationVocabulary.applying([], to: "cooper netties"), "cooper netties")
    }

    func testLongestMatchWinsAndSpecialCharactersAreLiteral() {
        let list = [DictationVocabularyEntry(term: "Go", soundsLike: []),
                    DictationVocabularyEntry(term: "Go modules", soundsLike: ["go modules"]),
                    DictationVocabularyEntry(term: "C++", soundsLike: ["see plus plus"])]
        XCTAssertEqual(DictationVocabulary.applying(list, to: "go modules in go"), "Go modules in Go")
        XCTAssertEqual(DictationVocabulary.applying(list, to: "I write see plus plus"), "I write C++")
        XCTAssertEqual(DictationVocabulary.applying([DictationVocabularyEntry(term: "a.b")], to: "axb a.b"), "axb a.b")
    }

    func testNormalizingTrimsMergesAndBounds() {
        let messy = [DictationVocabularyEntry(term: "  Kubernetes ", soundsLike: ["cooper  netties", "kubernetes", "", "Cooper Netties"]),
                     DictationVocabularyEntry(term: "kubernetes", soundsLike: ["koobernetes"]),
                     DictationVocabularyEntry(term: " ", soundsLike: ["x"]),
                     DictationVocabularyEntry(term: String(repeating: "x", count: 65)),
                     DictationVocabularyEntry(term: "tab\u{7}bell")]
        XCTAssertEqual(DictationVocabulary.normalized(messy), [DictationVocabularyEntry(term: "Kubernetes", soundsLike: ["cooper netties", "koobernetes"])])
        let many = (0..<600).map { DictationVocabularyEntry(term: "term\($0)", soundsLike: (0..<12).map { "heard\($0)" }) }
        let bounded = DictationVocabulary.normalized(many)
        XCTAssertEqual(bounded.count, DictationVocabulary.maximumEntries)
        XCTAssertEqual(bounded[0].soundsLike.count, DictationVocabulary.maximumSoundsLike)
        XCTAssertEqual(DictationVocabulary.hints(many).count, DictationVocabulary.maximumHints)
    }

    func testImportReadsTermsAndHeardWrittenPairs() {
        let text = """
        # my words
        heard,written
        Kubernetes
        cooper netties,Kubernetes
        "post gress","PostgreSQL"
        see plus plus\tC++

        a,b,c
        ,Empty
        """
        let (entries, skipped) = DictationVocabulary.parse(importing: text)
        XCTAssertEqual(entries, [DictationVocabularyEntry(term: "Kubernetes", soundsLike: ["cooper netties"]),
                                 DictationVocabularyEntry(term: "PostgreSQL", soundsLike: ["post gress"]),
                                 DictationVocabularyEntry(term: "C++", soundsLike: ["see plus plus"])])
        XCTAssertEqual(skipped, 2)
        let merged = DictationVocabulary.merging([DictationVocabularyEntry(term: "kubernetes", soundsLike: ["koober"])], into: entries)
        XCTAssertEqual(merged.first, DictationVocabularyEntry(term: "Kubernetes", soundsLike: ["cooper netties", "koober"]))
    }

    func testConfigKeepsOtherFieldsAndRefusesAStaleList() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"future":{"enabled":true},"summonHotKey":"cmd+space"}"#.utf8).write(to: url)
        try Preferences.updateDictationVocabulary([kubernetes], expected: [], at: url)
        let saved = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.dictationVocabulary, [kubernetes])
        XCTAssertEqual(saved.summonHotKey, "cmd+space")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNotNil(object?["future"])
        XCTAssertThrowsError(try Preferences.updateDictationVocabulary([], expected: [], at: url), "An edit from a stale list is refused")
        try Preferences.updateDictationVocabulary([], expected: [kubernetes], at: url)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).dictationVocabulary, [])
        XCTAssertTrue(SettingsSync.keys.contains("dictationVocabulary"))
        XCTAssertThrowsError(try JSONDecoder().decode(Preferences.self, from: Data(#"{"dictationVocabulary":[{"soundsLike":["x"]}]}"#.utf8)),
                             "A malformed list is not decoded, so sync never applies it")
    }

    func testCorrectsWhatTheRecognizerActuallyProduced() {
        let list = [DictationVocabularyEntry(term: "Kubernetes", soundsLike: ["Kubernitz", "Gubanits"]),
                    DictationVocabularyEntry(term: "PostgreSQL", soundsLike: ["post-Ger SQL", "post-garesqL"]),
                    DictationVocabularyEntry(term: "Herdr", soundsLike: ["herder"]),
                    DictationVocabularyEntry(term: "Tailscale", soundsLike: ["tail scale"]),
                    DictationVocabularyEntry(term: "Homebrew"), DictationVocabularyEntry(term: "Keychain"), DictationVocabularyEntry(term: "Sparkle")]
        let heard = ["Deploy the service to Kubernitz before lunch.": "Deploy the service to Kubernetes before lunch.",
                     "Deploy the service to Gubanits before lunch.": "Deploy the service to Kubernetes before lunch.",
                     "The query runs slowly on post-Ger SQL with a big join.": "The query runs slowly on PostgreSQL with a big join.",
                     "I pushed the fix to the Volant repo and pinged herder.": "I pushed the fix to the Volant repo and pinged Herdr.",
                     "Install it with homebrew, then restart tail scale.": "Install it with Homebrew, then restart Tailscale.",
                     "We store the tokens in keychain and sign with sparkle.": "We store the tokens in Keychain and sign with Sparkle."]
        for (transcript, expected) in heard { XCTAssertEqual(DictationVocabulary.applying(list, to: transcript), expected) }
    }
}
