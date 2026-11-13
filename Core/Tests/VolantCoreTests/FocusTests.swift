import XCTest

@testable import VolantCore

final class FocusHostTests: XCTestCase {
    func testRulesComeFromWhatTheOwnerTypes() {
        XCTAssertEqual(FocusHost.rule(from: "X.com"), "x.com")
        XCTAssertEqual(FocusHost.rule(from: " https://www.youtube.com/watch?v=1 "), "youtube.com")
        XCTAssertEqual(FocusHost.rule(from: "*.reddit.com"), "reddit.com")
        XCTAssertEqual(FocusHost.rule(from: "user@news.ycombinator.com:443/item"), "news.ycombinator.com")
        XCTAssertEqual(FocusHost.rule(from: "x.com."), "x.com")
        XCTAssertEqual(FocusHost.rule(from: "www.com"), "www.com")
    }

    func testRejectsTextThatIsNotAHost() {
        for input in ["", "localhost", "not a site", "x..com", "-x.com", "x-.com", "a_b.com", String(repeating: "a", count: 64) + ".com"] {
            XCTAssertNil(FocusHost.rule(from: input), input)
        }
    }

    func testInternationalNamesUseTheirASCIIForm() {
        XCTAssertEqual(Punycode.encode("bücher"), "bcher-kva")
        XCTAssertEqual(Punycode.encode("münchen"), "mnchen-3ya")
        XCTAssertEqual(Punycode.encode("例え"), "r8jz45g")
        XCTAssertEqual(FocusHost.rule(from: "Bücher.de"), "xn--bcher-kva.de")
        XCTAssertEqual(FocusHost.host(ofPageAddress: "https://xn--bcher-kva.de/"), "xn--bcher-kva.de")
    }

    func testMatchesTheHostAndItsSubdomainsOnly() {
        XCTAssertTrue(FocusHost.matches("x.com", rule: "x.com"))
        XCTAssertTrue(FocusHost.matches("mobile.x.com", rule: "x.com"))
        XCTAssertFalse(FocusHost.matches("notx.com", rule: "x.com"))
        XCTAssertFalse(FocusHost.matches("x.com.example.test", rule: "x.com"))
        XCTAssertFalse(FocusHost.matches("aws.amazon.com", rule: "www.amazon.com"))
    }

    func testOnlyWebPagesHaveHosts() {
        XCTAssertEqual(FocusHost.host(ofPageAddress: "https://WWW.X.com./home"), "www.x.com")
        XCTAssertEqual(FocusHost.host(ofPageAddress: "http://reddit.com:8080/r/swift"), "reddit.com")
        XCTAssertNil(FocusHost.host(ofPageAddress: "file:///Users/me/x.com.html"))
        XCTAssertNil(FocusHost.host(ofPageAddress: "about:blank"))
        XCTAssertNil(FocusHost.host(ofPageAddress: "chrome://settings"))
    }
}

final class FocusSetupTests: XCTestCase {
    func testNormalizesWhatItIsGiven() {
        let setup = FocusSetup(goal: "  Write  ", minutes: 5000, apps: ["com.a", " com.a ", ""], websites: ["X.com", "x.com", "nonsense"], categories: [.social, .social])
        XCTAssertEqual(setup.goal, "Write")
        XCTAssertEqual(setup.minutes, FocusSetup.maximumMinutes)
        XCTAssertEqual(setup.apps, ["com.a"])
        XCTAssertEqual(setup.websites, ["x.com"])
        XCTAssertEqual(setup.categories, [.social])
    }

    func testCombinesItsOwnRulesWithItsCategories() {
        let setup = FocusSetup(apps: ["com.tinyspeck.slackmacgap"], websites: ["x.com", "example.org"], categories: [.social, .messaging])
        XCTAssertEqual(setup.blockedWebsites.first, "x.com")
        XCTAssertEqual(setup.blockedWebsites.filter { $0 == "x.com" }.count, 1)
        XCTAssertTrue(setup.blockedWebsites.contains("example.org"))
        XCTAssertTrue(setup.blockedWebsites.contains("reddit.com"))
        XCTAssertEqual(setup.blockedApps.filter { $0 == "com.tinyspeck.slackmacgap" }.count, 1)
        XCTAssertTrue(setup.blockedApps.contains("com.apple.MobileSMS"))
        XCTAssertFalse(FocusSetup(categories: []).blocksAnything)
    }

    func testCategoryRulesAreValidRules() {
        for category in FocusCategory.allCases {
            for website in category.websites { XCTAssertEqual(FocusHost.normalized(website), website, website) }
            XCTAssertFalse(category.websites.isEmpty && category.apps.isEmpty, category.rawValue)
        }
    }

    func testDecodingDropsUnknownValuesInsteadOfFailing() throws {
        let json = #"{"goal":"Read","categories":["social","gaming"],"websites":["x.com","??"],"minutes":0}"#
        let setup = try JSONDecoder().decode(FocusSetup.self, from: Data(json.utf8))
        XCTAssertEqual(setup.categories, [.social])
        XCTAssertEqual(setup.websites, ["x.com"])
        XCTAssertEqual(setup.minutes, 1)
        let untimed = try JSONDecoder().decode(FocusSetup.self, from: Data(#"{"goal":"Read"}"#.utf8))
        XCTAssertNil(untimed.minutes)
        XCTAssertEqual(try JSONDecoder().decode(FocusPreferences.self, from: Data(#"{"snoozeMinutes":99}"#.utf8)).snoozeMinutes, 30)
    }
}

final class FocusSessionTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    func session(minutes: Int? = 30) -> FocusSession {
        FocusSession(setup: FocusSetup(goal: "Write", minutes: minutes, apps: ["com.tinyspeck.slackmacgap", "com.apple.finder"], websites: ["x.com"], categories: []), at: start)
    }

    func testRunsForItsLengthAndThenFinishes() {
        let s = session()
        XCTAssertEqual(s.remaining(at: at(10)), 20 * 60)
        XCTAssertFalse(s.isFinished(at: at(29.9)))
        XCTAssertTrue(s.isFinished(at: at(30)))
        XCTAssertEqual(s.remaining(at: at(45)), 0)
        XCTAssertFalse(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(30)))
    }

    func testUntimedSessionsRunUntilEnded() {
        let s = session(minutes: nil)
        XCTAssertNil(s.remaining(at: at(600)))
        XCTAssertFalse(s.isFinished(at: at(6000)))
        XCTAssertTrue(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(6000)))
    }

    func testPauseKeepsTheTimeLeftAndStopsBlocking() {
        var s = session()
        s.pause(at: at(10))
        XCTAssertTrue(s.isPaused)
        XCTAssertEqual(s.remaining(at: at(500)), 20 * 60)
        XCTAssertFalse(s.isFinished(at: at(500)))
        XCTAssertFalse(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(20)))
        XCTAssertNil(s.blockingRule(forPageAddress: "https://x.com", at: at(20)))
        XCTAssertNil(s.nextChange(after: at(20)))
        s.resume(at: at(40))
        XCTAssertEqual(s.remaining(at: at(40)), 20 * 60)
        XCTAssertEqual(s.endsAt, at(60))
        XCTAssertTrue(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(41)))
        s.pause(at: at(50))
        s.pause(at: at(55))
        s.resume(at: at(70))
        XCTAssertEqual(s.endsAt, at(80))
    }

    func testBlocksListedAppsButNeverProtectedOnes() {
        let s = session()
        XCTAssertTrue(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(1)))
        XCTAssertFalse(s.blocks(app: "com.apple.finder", at: at(1)))
        XCTAssertFalse(s.blocks(app: "com.apple.Safari", at: at(1)))
    }

    func testBlocksMatchingPagesOnly() {
        let s = session()
        XCTAssertEqual(s.blockingRule(forPageAddress: "https://mobile.x.com/home", at: at(1)), "x.com")
        XCTAssertNil(s.blockingRule(forPageAddress: "https://notx.com", at: at(1)))
        XCTAssertNil(s.blockingRule(forPageAddress: "about:blank", at: at(1)))
    }

    func testSnoozeLetsOneThingThroughForAWhile() {
        var s = session()
        s.snooze(.app("com.tinyspeck.slackmacgap"), minutes: 3, at: at(5))
        XCTAssertFalse(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(7)))
        XCTAssertEqual(s.blockingRule(forPageAddress: "https://x.com", at: at(7)), "x.com")
        XCTAssertEqual(s.nextChange(after: at(7)), at(8))
        XCTAssertTrue(s.blocks(app: "com.tinyspeck.slackmacgap", at: at(8)))
        s.snooze(.website("x.com"), minutes: 3, at: at(9))
        s.snooze(.website("x.com"), minutes: 5, at: at(10))
        XCTAssertEqual(s.snoozes.count, 1)
        XCTAssertNil(s.blockingRule(forPageAddress: "https://x.com", at: at(14)))
        XCTAssertNotNil(s.blockingRule(forPageAddress: "https://x.com", at: at(15)))
        XCTAssertEqual(s.nextChange(after: at(16)), at(30))
    }

    func testEditingCountsTheNewLengthFromTheStart() {
        var s = session()
        s.snooze(.website("x.com"), minutes: 3, at: at(5))
        s.pause(at: at(10))
        s.resume(at: at(15))
        s.edit(FocusSetup(goal: "Read", minutes: 60, apps: ["com.tinyspeck.slackmacgap"], categories: []), at: at(16))
        XCTAssertEqual(s.setup.goal, "Read")
        XCTAssertEqual(s.endsAt, at(65))
        XCTAssertTrue(s.snoozes.isEmpty)
        XCTAssertNil(s.blockingRule(forPageAddress: "https://x.com", at: at(17)))
        s.edit(FocusSetup(goal: "Read", minutes: 5, categories: []), at: at(20))
        XCTAssertTrue(s.isFinished(at: at(20)))
    }

    func testEditingWhilePausedWaitsForResume() {
        var s = session()
        s.pause(at: at(10))
        s.edit(FocusSetup(goal: "Write", minutes: 45, categories: []), at: at(12))
        XCTAssertNil(s.endsAt)
        XCTAssertEqual(s.remaining(at: at(20)), 35 * 60)
        s.resume(at: at(20))
        XCTAssertEqual(s.endsAt, at(55))
    }

    func testSurvivesEncoding() throws {
        var s = session()
        s.snooze(.app("com.tinyspeck.slackmacgap"), minutes: 3, at: at(1))
        s.pause(at: at(2))
        let decoded = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}

final class FocusCommandTests: XCTestCase {
    func testParsesLauncherQueries() {
        XCTAssertNil(FocusCommand.parse("focused"))
        XCTAssertNil(FocusCommand.parse("caffeinate"))
        XCTAssertEqual(FocusCommand.parse("focus"), .menu)
        XCTAssertEqual(FocusCommand.parse("Focus  "), .menu)
        XCTAssertEqual(FocusCommand.parse("focus pause"), .pause)
        XCTAssertEqual(FocusCommand.parse("focus Done"), .complete)
        XCTAssertEqual(FocusCommand.parse("focus stop"), .end)
        XCTAssertEqual(FocusCommand.parse("focus edit"), .edit)
        XCTAssertEqual(FocusCommand.parse("focus 25m Write the Newsletter"), .start(.minutes(25), goal: "Write the Newsletter"))
        XCTAssertEqual(FocusCommand.parse("focus 1h"), .start(.minutes(60), goal: nil))
        XCTAssertEqual(FocusCommand.parse("focus pause the podcast edit"), .start(.remembered, goal: "pause the podcast edit"))
    }

    func testReadsLengths() {
        XCTAssertEqual(FocusCommand.minutes("25"), 25)
        XCTAssertEqual(FocusCommand.minutes("25m"), 25)
        XCTAssertEqual(FocusCommand.minutes("45min"), 45)
        XCTAssertEqual(FocusCommand.minutes("1h30m"), 90)
        XCTAssertEqual(FocusCommand.minutes("1h30"), 90)
        XCTAssertEqual(FocusCommand.minutes("2H"), 120)
        for token in ["0", "0m", "h", "m", "13h", "25x", "1.5h", "-5", "twenty"] { XCTAssertNil(FocusCommand.minutes(token), token) }
    }
}

final class FocusPreferencesPatchTests: XCTestCase {
    func testPatchKeepsUnknownFieldsAndRefusesStaleEdits() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"summonHotKey":"cmd+space","future":1,"focus":{"later":true,"snoozeMinutes":5}}"#.utf8).write(to: url)
        let current = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).focus
        XCTAssertEqual(current.snoozeMinutes, 5)
        let updated = FocusPreferences(lastSetup: FocusSetup(goal: "Read", minutes: nil, websites: ["x.com"], categories: []), snoozeMinutes: 4)
        try Preferences.updateFocus(updated, expected: current, at: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["future"] as? Int, 1)
        XCTAssertEqual(object["summonHotKey"] as? String, "cmd+space")
        XCTAssertEqual((object["focus"] as? [String: Any])?["later"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).focus, updated)
        XCTAssertThrowsError(try Preferences.updateFocus(FocusPreferences(), expected: current, at: url))
    }
}
