import XCTest
import VolantCore

@testable import Volant

/// Apple Intelligence needs macOS 26 while Volant supports macOS 15, so the feature has to be
/// absent rather than broken on older systems. These assertions hold on either.
@MainActor
final class AppleFoundationModelTests: XCTestCase {
    func testAvailabilityAlwaysExplainsItselfWhenUnavailable() {
        let availability = AppleFoundationModel.availability
        if availability.isReady {
            XCTAssertNil(availability.reason)
        } else {
            let reason = try? XCTUnwrap(availability.reason)
            XCTAssertFalse((reason ?? "").isEmpty, "a disabled option must say why")
        }
    }

    func testOlderSystemsGetASystemVersionExplanationRatherThanASilentFailure() {
        guard #available(macOS 26.0, *) else {
            let reason = AppleFoundationModel.availability.reason ?? ""
            XCTAssertTrue(reason.contains("macOS"), "the reason names the requirement")
            XCTAssertFalse(AppleFoundationModel.availability.isReady)
            return
        }
        // On macOS 26+ the answer depends on the machine, so only the shape is asserted.
        XCTAssertNotNil(AppleFoundationModel.systemVersion)
    }

    func testAConversationIsSafeToCreateAndCancelOnAnySystem() {
        let conversation = AppleFoundationModel.Conversation()
        conversation.cancel()
        conversation.cancel()
    }

    func testUnavailableSystemsReportAnErrorInsteadOfHanging() {
        guard #unavailable(macOS 26.0) else { return }
        let finished = expectation(description: "finished")
        AppleFoundationModel.Conversation().send("hello", snapshot: { _ in
            XCTFail("no snapshot can arrive without the framework")
        }, finished: { error in
            XCTAssertNotNil(error)
            finished.fulfill()
        })
        wait(for: [finished], timeout: 2)
    }

    // MARK: Chat model wiring

    func testAppleUsesNeitherHelperPath() {
        let model = ACPModel()
        var config = AIConfiguration()
        config.connection = .apple
        model.configure(config)
        XCTAssertTrue(model.usesApple)
        XCTAssertFalse(model.usesAPI, "Apple must not be routed through the network helper")
        XCTAssertEqual(model.providerTitle, "Apple Intelligence")
    }

    func testTheHTTPKindsStillUseTheNetworkHelper() {
        for kind in [AIConnectionKind.byok, .local] {
            let model = ACPModel()
            var config = AIConfiguration()
            config.connection = kind
            model.configure(config)
            XCTAssertTrue(model.usesAPI, "\(kind) still uses the AI helper")
            XCTAssertFalse(model.usesApple)
        }
    }

    func testACPStillUsesTheAgentHelper() {
        let model = ACPModel()
        var config = AIConfiguration()
        config.connection = .acp
        config.provider = ACPProvider.allCases.first?.rawValue ?? ""
        model.configure(config)
        XCTAssertFalse(model.usesAPI)
        XCTAssertFalse(model.usesApple)
    }

    func testConfiguredTracksRuntimeAvailabilityRatherThanSettings() {
        let model = ACPModel()
        var config = AIConfiguration()
        config.connection = .apple
        model.configure(config)
        XCTAssertEqual(model.configured, AppleFoundationModel.availability.isReady,
                       "settings alone cannot make an unavailable model usable")
    }

    func testStartingWithoutAvailabilityFailsWithTheReason() {
        guard !AppleFoundationModel.availability.isReady else { return }
        let model = ACPModel()
        var config = AIConfiguration()
        config.connection = .apple
        model.configure(config)
        model.start()
        XCTAssertEqual(model.state.phase, "failed")
        XCTAssertEqual(model.error, AppleFoundationModel.availability.reason)
    }
}
