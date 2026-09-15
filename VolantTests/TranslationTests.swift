import XCTest
@testable import Volant

@MainActor final class TranslationTests: XCTestCase {
    private func ready(_ state: TranslationPairState = .installed) async -> TranslationModel {
        let model = TranslationModel()
        model.availability = { _ in state }
        model.text = "Hello\nHow are you?"
        model.target = "es"
        model.start()
        for _ in 0..<20 where model.request == nil && model.busy { await Task.yield() }
        return model
    }

    func testExplicitTranslationCopyAndSwap() async throws {
        let model = await ready(.downloadable)
        XCTAssertEqual(model.pairState, .downloadable)
        let request = try XCTUnwrap(model.request)
        XCTAssertEqual(request.source, "")
        XCTAssertEqual(request.text, "Hello\nHow are you?")
        var copies: [String] = []
        model.copy { copies.append($0) }
        XCTAssertTrue(copies.isEmpty)
        await model.perform(request) { _ in TranslationResult(text: "Hola\n¿Cómo estás?", source: "en") }
        XCTAssertEqual(model.pairState, .installed)
        XCTAssertFalse(model.busy)
        XCTAssertTrue(copies.isEmpty)
        model.copy { copies.append($0) }
        XCTAssertEqual(copies, ["Hola\n¿Cómo estás?"])
        model.swap()
        XCTAssertEqual(model.text, copies[0])
        XCTAssertEqual(model.source, "es")
        XCTAssertEqual(model.target, "en")
        XCTAssertTrue(model.output.isEmpty)
        XCTAssertNil(model.request)
    }

    func testLateResultCannotReplaceEditedDraftOrLanguage() async throws {
        for edit in 0..<3 {
            let model = await ready()
            let request = try XCTUnwrap(model.request)
            await model.perform(request) { _ in
                switch edit {
                case 0: model.text = "New text"
                case 1: model.target = "fr"
                default: model.cancel()
                }
                return TranslationResult(text: "Stale result", source: "en")
            }
            XCTAssertTrue(model.output.isEmpty)
            XCTAssertFalse(model.busy)
            XCTAssertNil(model.request)
            XCTAssertFalse(model.text.isEmpty)
        }
    }

    func testUnsupportedErrorsRetryAndLimits() async throws {
        let model = await ready(.unsupported)
        XCTAssertNil(model.request)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.pairState, .unsupported)
        model.availability = { _ in .installed }
        model.start()
        for _ in 0..<20 where model.request == nil { await Task.yield() }
        let request = try XCTUnwrap(model.request)
        await model.perform(request) { _ in throw NSError(domain: "sensitive fictional input", code: 1) }
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.message?.contains("sensitive") ?? true)
        XCTAssertTrue(model.canTranslate)
        model.text = String(repeating: "a", count: TranslationModel.textLimit + 1)
        model.start()
        XCTAssertNil(model.request)
        XCTAssertFalse(model.canTranslate)
        model.clear()
        XCTAssertFalse(model.hasDraft)
        XCTAssertNil(model.message)
    }

    func testStaleAvailabilityAndCatalogRetry() async {
        let model = TranslationModel()
        model.text = "Hello"
        model.availability = { _ in
            model.target = "fr"
            return .installed
        }
        model.start()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(model.request)
        XCTAssertFalse(model.busy)
        model.loadLanguages = { throw CancellationError() }
        await model.loadCatalog()
        XCTAssertTrue(model.catalogFailed)
        model.loadLanguages = { ["es", "en", "es"] }
        await model.loadCatalog()
        XCTAssertFalse(model.catalogFailed)
        XCTAssertEqual(Set(model.languages), Set(["es", "en"]))
        XCTAssertEqual(model.languages.count, 2)
    }
}
