import XCTest

@testable import VolantCore

/// Apple Intelligence is a connection kind with nothing to configure, so the rules that apply to
/// the HTTP kinds must not be applied to it, and old configurations must keep decoding.
final class AppleConnectionKindTests: XCTestCase {
    private func configuration(_ json: String) throws -> AIConfiguration {
        try JSONDecoder().decode(AIConfiguration.self, from: Data(json.utf8))
    }

    func testAppleNeedsNoEndpointOrKeyToBeConfigured() throws {
        var config = AIConfiguration()
        config.connection = .apple
        XCTAssertTrue(config.isConfigured, "availability is a runtime question, not a settings one")
        XCTAssertFalse(config.connection.usesHTTP, "no helper and no endpoint")
    }

    func testTheHTTPKindsStillRequireAValidEndpoint() {
        for kind in [AIConnectionKind.byok, .local] {
            var config = AIConfiguration()
            config.connection = kind
            config.api.model = ""
            config.localAPI.model = ""
            XCTAssertFalse(config.isConfigured, "\(kind) still needs a model")
            XCTAssertTrue(kind.usesHTTP)
        }
    }

    func testACPIsUnaffected() {
        var config = AIConfiguration()
        config.connection = .acp
        XCTAssertFalse(config.isConfigured)
        config.provider = ACPProvider.allCases.first?.rawValue ?? ""
        XCTAssertTrue(config.isConfigured)
        XCTAssertFalse(config.connection.usesHTTP)
    }

    func testAppleRoundTripsThroughConfiguration() throws {
        var config = AIConfiguration()
        config.connection = .apple
        let restored = try JSONDecoder().decode(AIConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored.connection, .apple)
    }

    func testConfigurationsWrittenBeforeAppleExistedStillLoad() throws {
        XCTAssertEqual(try configuration(#"{"connection":"byok"}"#).connection, .byok)
        XCTAssertEqual(try configuration(#"{}"#).connection, .acp, "a missing connection still defaults to ACP")
    }

    func testAppleIsOfferedInTheConnectionPicker() {
        XCTAssertTrue(AIConnectionKind.allCases.contains(.apple))
        XCTAssertEqual(AIConnectionKind.apple.title, "Apple Intelligence")
    }
}
