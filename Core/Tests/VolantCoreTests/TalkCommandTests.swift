import XCTest

@testable import VolantCore

/// Dictation is reachable as a command and as its own hotkey. These are the parts that do not need
/// the Speech framework, so they hold on macOS 15 as well as 26.
final class TalkCommandTests: XCTestCase {
    func testTalkIsADiscoverableCommand() {
        XCTAssertTrue(CoreCommand.allCases.contains(.talk))
        XCTAssertEqual(CoreCommand.talk.title, "Dictate Text")
        XCTAssertEqual(CoreCommand.talk.query, "talk")
        XCTAssertEqual(CoreCommand.talk.symbol, "mic")
    }

    func testTalkIsReservedSoAUserShortcutCannotShadowIt() {
        XCTAssertTrue(LauncherRouting.isReserved("talk"))
        XCTAssertTrue(LauncherRouting.isReserved("Talk"))
        XCTAssertTrue(LauncherRouting.isReserved("talk something"))
        XCTAssertFalse(LauncherRouting.isReserved("talkie"), "only the whole first word is reserved")
    }

    func testTheDictationHotkeyDefaultsToUnsetAndRoundTrips() throws {
        XCTAssertEqual(Preferences().talkHotKey, "", "no default binding is taken from the owner")
        var preferences = Preferences()
        preferences.talkHotKey = "option+d"
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.talkHotKey, "option+d")
    }

    func testConfigurationsWrittenBeforeDictationStillLoad() throws {
        let legacy = Data(#"{"summonHotKey":"option+space"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(preferences.talkHotKey, "")
        XCTAssertEqual(preferences.summonHotKey, "option+space")
    }

    func testTheOtherCommandsAreUnchanged() {
        XCTAssertEqual(CoreCommand.emoji.query, ":")
        XCTAssertEqual(CoreCommand.clipboard.query, "clip")
        XCTAssertEqual(CoreCommand.ai.title, "AI Chat")
    }
}
