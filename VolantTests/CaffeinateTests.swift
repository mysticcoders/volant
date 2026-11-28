import XCTest
import VolantCore
@testable import Volant

final class CaffeinateTests: XCTestCase {
    final class Assertions: CaffeinateAssertions {
        var created: [(Bool, TimeInterval)] = []
        var released: [UInt32] = []
        var failCreate = false
        var failRelease = false
        func create(display: Bool, timeout: TimeInterval) throws -> UInt32 {
            if failCreate { throw CocoaError(.featureUnsupported) }
            created.append((display, timeout)); return 42
        }
        func release(_ id: UInt32) throws {
            if failRelease { throw CocoaError(.featureUnsupported) }
            released.append(id)
        }
    }
    func testTimedSessionExpiresAndDoesNotRestart() {
        let assertions = Assertions()
        var time = 10.0
        let service = CaffeinateService(assertions: assertions, now: { time }, automaticTimer: false)
        XCTAssertFalse(service.isActive)
        XCTAssertTrue(assertions.created.isEmpty)
        XCTAssertTrue(service.perform(CaffeinateCommand.parse("caffeinate 1h")[0]))
        XCTAssertEqual(assertions.created.first?.1, 3600)
        time = 70; service.tick(); XCTAssertEqual(service.remaining, 3540)
        time = 3610; service.tick()
        XCTAssertFalse(service.isActive)
        XCTAssertEqual(assertions.released, [42])
        service.tick(); service.stop(); XCTAssertEqual(assertions.released, [42])
    }
    func testIndefiniteDisplaySessionAndDuplicateStart() {
        let assertions = Assertions()
        let service = CaffeinateService(assertions: assertions, automaticTimer: false)
        XCTAssertTrue(service.perform(CaffeinateCommand.parse("caffeinate on display")[0]))
        XCTAssertEqual(assertions.created.first?.0, true)
        XCTAssertEqual(assertions.created.first?.1, 0)
        XCTAssertNil(service.remaining)
        XCTAssertFalse(service.perform(CaffeinateCommand.parse("caffeinate 30m")[0]))
        XCTAssertEqual(assertions.created.count, 1)
        XCTAssertTrue(service.perform(.off))
        XCTAssertFalse(service.isActive)
    }
    func testFailuresPreserveOwnershipForRetry() {
        let assertions = Assertions()
        let service = CaffeinateService(assertions: assertions, automaticTimer: false)
        assertions.failCreate = true
        XCTAssertFalse(service.perform(CaffeinateCommand.parse("caffeinate 30m")[0]))
        XCTAssertFalse(service.isActive); XCTAssertNotNil(service.error)
        assertions.failCreate = false
        XCTAssertTrue(service.perform(CaffeinateCommand.parse("caffeinate 30m")[0]))
        assertions.failRelease = true
        XCTAssertFalse(service.stop()); XCTAssertTrue(service.isActive)
        assertions.failRelease = false
        XCTAssertTrue(service.stop()); XCTAssertFalse(service.isActive)
    }
    func testDeinitializationReleasesOwnedAssertion() {
        let assertions = Assertions()
        var service: CaffeinateService? = CaffeinateService(assertions: assertions, automaticTimer: false)
        service?.perform(CaffeinateCommand.parse("caffeinate on")[0])
        service = nil
        XCTAssertEqual(assertions.released, [42])
    }
    func testCommandGrammar() {
        XCTAssertEqual(CaffeinateCommand.parse("CAFFEINATE 3h display").first?.minutes, 180)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate").count, 8)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate").prefix(4).map(\.display), [true, true, true, true])
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate").suffix(4).map(\.display), [false, false, false, false])
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m").first?.display, true)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate on").first?.display, true)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m display").first?.display, true)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m system").first?.display, false)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate on mac").first?.display, false)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate system").map(\.display), [false, false, false, false])
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m").first?.title, "Caffeinate")
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m system").first?.title, "Caffeinate · Display May Sleep")
        let systemFirst = CaffeinateCommand.parse("caffeinate", keepsDisplayAwake: false)
        XCTAssertEqual(systemFirst.map(\.display), [false, false, false, false, true, true, true, true])
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m", keepsDisplayAwake: false).first?.display, false)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate on", keepsDisplayAwake: false).first?.display, false)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m display", keepsDisplayAwake: false).first?.display, true)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate 30m system", keepsDisplayAwake: true).first?.display, false)
        XCTAssertEqual(CaffeinateCommand.parse("caffeinate off"), [.off])
        for query in ["caffeinate 0m", "caffeinate -1h", "caffeinate 25h", "caffeinate 9999999999999999999999h", "caffeinate 1h garbage", "caffeinate off display", "caffeinate off system", "caffeinate 30m system display", "Safari"] {
            XCTAssertTrue(CaffeinateCommand.parse(query).isEmpty, query)
        }
        XCTAssertTrue(LauncherRouting.isReserved("caffeinate"))
        XCTAssertTrue(LauncherRouting.isReserved("emoji"))
    }

    func testTheWhileRunningSettingKeepsAnUntilStoppedSessionAndEndsOnlyItsOwn() {
        let assertions = Assertions()
        let service = CaffeinateService(assertions: assertions, automaticTimer: false)
        service.keepAwakeWhileRunning(false, display: true)
        XCTAssertFalse(service.isActive, "Off by default: nothing starts at launch")
        service.keepAwakeWhileRunning(true, display: true)
        XCTAssertTrue(service.isActive && service.isAutomatic)
        XCTAssertEqual(assertions.created.count, 1)
        XCTAssertEqual(assertions.created.first?.1, 0, "Until stopped, not timed")
        XCTAssertEqual(service.summary, "Mac & display awake · while Volant runs")
        service.keepAwakeWhileRunning(true, display: true)
        XCTAssertEqual(assertions.created.count, 1, "Reapplying an unchanged setting doesn't start a second session")
        service.keepAwakeWhileRunning(true, display: false)
        XCTAssertEqual(assertions.created.map(\.0), [true, false], "A changed display mode moves the automatic session")
        XCTAssertEqual(assertions.released, [42])
        service.keepAwakeWhileRunning(false, display: false)
        XCTAssertFalse(service.isActive)

        XCTAssertTrue(service.perform(CaffeinateCommand.parse("caffeinate 30m")[0]))
        service.keepAwakeWhileRunning(false, display: true)
        XCTAssertTrue(service.isActive, "Turning the setting off leaves a session the owner started")
        XCTAssertFalse(service.isAutomatic)
    }

    func testStoppingByHandPausesTheSettingUntilItIsTurnedOnAgain() {
        let assertions = Assertions()
        let service = CaffeinateService(assertions: assertions, automaticTimer: false)
        service.keepAwakeWhileRunning(true, display: true)
        XCTAssertTrue(service.perform(.off))
        XCTAssertFalse(service.isActive)
        service.keepAwakeWhileRunning(true, display: true)
        XCTAssertFalse(service.isActive, "A config reload doesn't undo caffeinate off")
        service.keepAwakeWhileRunning(false, display: true)
        service.keepAwakeWhileRunning(true, display: true)
        XCTAssertTrue(service.isAutomatic, "Turning the setting on again resumes it")
    }

    func testATimedSessionHandsBackToTheSettingWhenItEnds() {
        let assertions = Assertions()
        var time = 0.0
        let service = CaffeinateService(assertions: assertions, now: { time }, automaticTimer: false)
        XCTAssertTrue(service.perform(CaffeinateCommand.parse("caffeinate 1m")[0]))
        service.keepAwakeWhileRunning(true, display: true)
        XCTAssertFalse(service.isAutomatic, "A running timed session is left alone")
        time = 61; service.tick()
        XCTAssertTrue(service.isActive && service.isAutomatic, "The setting takes over once the timed session ends")
        XCTAssertEqual(assertions.created.map(\.1), [60, 0])
    }
}
