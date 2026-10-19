import XCTest

@testable import VolantCore

/// Close matches by sound: mishearings the recognizer actually produced are caught without being
/// listed, while known words, short terms and unrelated unknown words are left alone.
final class DictationCloseMatchTests: XCTestCase {
    private let vocabulary = ["Kubernetes", "PostgreSQL", "Volant", "Herdr", "Tailscale", "Sparkle"].map { DictationVocabularyEntry(term: $0) }
    /// A tiny stand-in for the spell checker: these are the only known words.
    private let dictionary: Set<String> = ["deploy", "the", "service", "to", "before", "lunch", "query", "runs", "slowly", "on", "post", "with",
                                           "a", "big", "join", "i", "pushed", "push", "fix", "repo", "and", "pinged", "herder", "tail", "scale",
                                           "install", "it", "then", "restart", "cuban", "needs", "go", "kubectl", "is", "great"]
    private func correct(_ text: String) -> String {
        DictationCloseMatch.correcting(vocabulary, in: text, isKnownWord: { dictionary.contains($0.lowercased()) })
    }

    func testPhoneticKeysMatchTheRecognizersMishearings() {
        let key = DictationCloseMatch.phoneticKey
        XCTAssertEqual(key("Kubernetes"), key("Kubernitz"))
        XCTAssertEqual(key("Kubernetes"), key("Gubanits"))
        XCTAssertEqual(DictationCloseMatch.distance(key("PostgreSQL"), key("postgersql")), 1, "Long skeletons may be one sound off")
        XCTAssertEqual(key("Volant"), key("Villand"))
    }

    func testUnlistedMishearingsAreCorrected() {
        XCTAssertEqual(correct("Deploy the service to Kubernitz before lunch."), "Deploy the service to Kubernetes before lunch.")
        XCTAssertEqual(correct("Deploy the service to Gubanits before lunch."), "Deploy the service to Kubernetes before lunch.")
        XCTAssertEqual(correct("The query runs slowly on post-Ger SQL with a big join."), "The query runs slowly on PostgreSQL with a big join.")
        XCTAssertEqual(correct("The query runs slowly on post-garesqL with a big join."), "The query runs slowly on PostgreSQL with a big join.")
        XCTAssertEqual(correct("I push the fix to the Villand repo and pinged herder."), "I push the fix to the Volant repo and pinged herder.")
    }

    func testKnownWordsShortTermsAndUnrelatedWordsStay() {
        XCTAssertEqual(correct("pinged herder, then restart tail scale"), "pinged herder, then restart tail scale", "Real words need an explicit mishearing")
        XCTAssertEqual(correct("Deploy the service to Cuban needs"), "Deploy the service to Cuban needs")
        XCTAssertEqual(correct("kubectl is great and Zanzibar too"), "kubectl is great and Zanzibar too")
        XCTAssertEqual(DictationCloseMatch.correcting([DictationVocabularyEntry(term: "Herdr")], in: "Hurdur", isKnownWord: { _ in false }), "Hurdur",
                       "A term with too little sound to compare is only corrected exactly")
        XCTAssertEqual(DictationCloseMatch.correcting([DictationVocabularyEntry(term: "Gos")], in: "Goss", isKnownWord: { _ in false }), "Goss",
                       "Terms under five letters are only corrected exactly")
        XCTAssertEqual(correct("Kubernetes, Volant."), "Kubernetes, Volant.")
        XCTAssertEqual(DictationCloseMatch.correcting([DictationVocabularyEntry(term: "Obsidian")], in: "100 usd in eur", isKnownWord: { $0 == "in" }),
                       "100 usd in eur", "Short skeletons must match exactly: usd in is one sound from Obsidian")
        XCTAssertEqual(correct("before Kubernitz. Deploy"), "before Kubernetes. Deploy", "A span never crosses punctuation")
    }
}
