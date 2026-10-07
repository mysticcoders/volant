import XCTest
import VolantCore
@testable import Volant

/// The row chosen last time for a query leads the results, whatever kind of row it is.
final class LearnedRankingTests: XCTestCase {
    private let app = ResultRow.app(AppEntry(id: "/Applications/Lockdown.app", name: "Lockdown", url: URL(fileURLWithPath: "/Applications/Lockdown.app"), lastUsed: nil))
    private var sections: [ResultSection] {
        [ResultSection(title: "Applications", rows: [app]),
         ResultSection(title: "System", rows: [.systemAction(.sleep), .systemAction(.lockScreen)]),
         ResultSection(title: "System Settings", rows: [.systemSettings(SystemSettingsDestination.search("lock screen")[0])])]
    }

    func testAChosenActionLeadsItsSectionAndTheResults() {
        let promoted = LauncherModel.promoting("system-action:lockScreen", in: sections)
        XCTAssertEqual(promoted.map(\.title), ["System", "Applications", "System Settings"])
        XCTAssertEqual(promoted[0].rows.map(\.id), ["system-action:lockScreen", "system-action:sleep"])
    }

    func testNoChoiceOrAMissingRowLeavesResultsAlone() {
        XCTAssertEqual(LauncherModel.promoting(nil, in: sections), sections)
        XCTAssertEqual(LauncherModel.promoting("core:gone", in: sections), sections)
    }
}
