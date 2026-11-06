import XCTest
@testable import VolantCore

final class WelcomeTests: XCTestCase {
    func testFreshInstallShowsAndExistingInstallIsMarkedDone() {
        XCTAssertEqual(WelcomeLaunch.decide(configExisted: false, completed: nil), .show)
        XCTAssertEqual(WelcomeLaunch.decide(configExisted: true, completed: nil), .markDone, "an install from before Welcome never sees it")
        XCTAssertEqual(WelcomeLaunch.decide(configExisted: true, completed: false), .show, "a Welcome that never closed shows again")
        XCTAssertEqual(WelcomeLaunch.decide(configExisted: true, completed: true), .skip)
        XCTAssertEqual(WelcomeLaunch.decide(configExisted: false, completed: true), .skip)
    }

    func testAgentsPageAppearsOnlyWhenSomethingWasFound() {
        XCTAssertEqual(WelcomeStep.steps(showingAgents: false), [.shortcut, .typing, .access, .extensions])
        XCTAssertEqual(WelcomeStep.steps(showingAgents: true), [.shortcut, .typing, .access, .agents, .extensions])
        XCTAssertEqual(WelcomeStep.next(after: .access, showingAgents: false), .extensions)
        XCTAssertEqual(WelcomeStep.next(after: .access, showingAgents: true), .agents)
        XCTAssertNil(WelcomeStep.next(after: .extensions, showingAgents: true))
        XCTAssertNil(WelcomeStep.previous(before: .shortcut, showingAgents: true))
        XCTAssertEqual(WelcomeStep.previous(before: .extensions, showingAgents: false), .access)
        XCTAssertEqual(WelcomeStep.next(after: .agents, showingAgents: false), .shortcut, "a page that disappeared restarts from the first")
    }

    func testTipsAreDistinctAndTryRealQueries() {
        let tips = WelcomeTip.all
        XCTAssertEqual(Set(tips.map(\.id)).count, tips.count)
        XCTAssertTrue(tips.allSatisfy { !$0.tryQuery.isEmpty && !$0.detail.isEmpty })
        for word in ["contacts", "files", "clipboard", "notes", "translate", "servers", "today"] {
            XCTAssertTrue(tips.contains { $0.tryQuery == word }, word)
            XCTAssertTrue(LauncherRouting.isReserved(word), word)
        }
    }

    func testCompetingLaunchersAreNamedOnceAndSorted() {
        XCTAssertEqual(WelcomeCompetingLaunchers.names(running: ["com.apple.finder", "com.runningwithcrayons.Alfred", "com.raycast.macos", "com.runningwithcrayons.Alfred-3"]), ["Alfred", "Raycast"])
        XCTAssertEqual(WelcomeCompetingLaunchers.names(running: ["com.apple.finder"]), [])
    }

    func testWelcomeWordsAreReservedAndFindTheCommand() {
        for word in ["welcome", "Welcome", "onboarding", "getting started"] {
            XCTAssertTrue(LauncherRouting.isReserved(word), word)
        }
        XCTAssertFalse(LauncherRouting.isReserved("welcomes"), "only the whole first word is reserved")
        XCTAssertFalse(LauncherRouting.isReserved("getting"))
        XCTAssertEqual(CoreCommand.search("welcome").first, .welcome)
        XCTAssertTrue(CoreCommand.search("getting started").contains(.welcome))
        XCTAssertTrue(CoreCommand.search("onboarding").contains(.welcome))
    }

    func testCompletionIsPerMacAndPatchedWithoutLosingOtherFields() throws {
        XCTAssertFalse(SettingsSync.keys.contains("welcomeCompleted"), "every Mac needs its own shortcut and access")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("welcome-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"summonHotKey":"cmd+space","futureSetting":{"kept":true}}"#.utf8).write(to: url)
        XCTAssertNil(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).welcomeCompleted)
        try Preferences.updateBoolean("welcomeCompleted", value: false, at: url)
        try Preferences.updateBoolean("welcomeCompleted", value: true, at: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["welcomeCompleted"] as? Bool, true)
        XCTAssertEqual(object["summonHotKey"] as? String, "cmd+space")
        XCTAssertEqual((object["futureSetting"] as? [String: Bool])?["kept"], true)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).welcomeCompleted, true)
    }

    func testFreshDefaultsLeaveCompletionUnset() throws {
        let data = try JSONEncoder().encode(Preferences())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["welcomeCompleted"], "a fresh file has no key, so the launch decision reads it as new")
    }
}
