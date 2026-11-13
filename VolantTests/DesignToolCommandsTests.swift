import CryptoKit
import VolantCore
import XCTest
@testable import Volant

/// Pick Color, Open Camera and the System Events toggles, against fakes: no loupe appears, no
/// camera is touched, no consent prompt is raised and no Apple Event is sent from a test host.
@MainActor
final class DesignToolCommandsTests: XCTestCase {
    private var root: URL!
    private var actions: [LauncherAction] = []
    private var dismissals = 0
    private var reopenings = 0
    private var copied: [String] = []
    private var opened: [URL] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("design-tools-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        actions = []; dismissals = 0; reopenings = 0; copied = []; opened = []
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A launcher over fictional, isolated stores whose side effects are all recorded.
    private func model() -> LauncherModel {
        let clipboard = ClipboardStore(retention: 2, storageURL: root.appendingPathComponent("clips.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
        let model = LauncherModel(index: AppIndex(entries: []), clipboard: clipboard,
                                  notes: NotesStore(directory: root.appendingPathComponent("Notes")), config: Preferences(),
                                  usage: UsageStore(url: root.appendingPathComponent("usage.sqlite"))) { [weak self] in self?.actions.append($0) }
        model.searchesSecondarySources = false
        model.appleShortcuts.loadOverride = { $0([], nil) }
        model.dismiss = { [weak self] in self?.dismissals += 1 }
        model.reopen = { [weak self] in self?.reopenings += 1 }
        model.copyText = { [weak self] in self?.copied.append($0) }
        model.openURL = { [weak self] in self?.opened.append($0) }
        model.globalDefaults = { ["AppleInterfaceStyle": "Dark", "_HIHideMenuBar": false] }
        return model
    }

    private var cameraRequests: Int { actions.filter { if case .camera = $0 { return true }; return false }.count }

    // MARK: Pick Color

    func testPickColorHidesSamplesOnceAndReturnsWithFormatsAndHexSelected() {
        let model = model(), sampler = FakeColorSampler()
        model.colorSampler = sampler
        model.query = "pick color"
        XCTAssertEqual(model.selectedRow?.id, "core:colorPicker")
        model.activateSelection()
        model.activateSelection()
        XCTAssertEqual(sampler.requests, 1, "a second Return while the loupe is up does not start another")
        XCTAssertEqual(dismissals, 1, "the launcher hides while sampling")
        sampler.finish(PickedColor(red: 1, green: 99.0 / 255, blue: 99.0 / 255))
        XCTAssertEqual(reopenings, 1)
        XCTAssertEqual(model.query, "pick color", "the typed phrase is kept")
        XCTAssertEqual(model.selectedRow?.id, "picked-color:hex")
        XCTAssertEqual(model.rows.filter { $0.id.hasPrefix("picked-color:") }.compactMap { row -> String? in
            if case .pickedColor(let color, let format) = row { return color.value(format) }; return nil
        }, ["#ff6363", "rgb(255 99 99)", "hsl(0 100% 69.4%)", "oklch(70% 0.1907 23.4)"])
        model.activateSelection()
        XCTAssertEqual(copied, ["#ff6363"], "Return copies the selected format")
        XCTAssertEqual(dismissals, 2)
    }

    func testPickAnotherColorFollowsTheFormatsAndOpensTheLoupeAgain() {
        let model = model(), sampler = FakeColorSampler()
        model.colorSampler = sampler
        model.query = "color picker"
        model.activateSelection()
        sampler.finish(PickedColor(red: 1, green: 99.0 / 255, blue: 99.0 / 255))
        XCTAssertEqual(model.rows.map(\.id).filter { $0.hasPrefix("picked-color:") || $0 == "core:colorPicker" },
                       ["picked-color:hex", "picked-color:rgb", "picked-color:hsl", "picked-color:oklch", "picked-color:another"],
                       "Pick Another Color follows the formats and replaces the Pick Color command")
        XCTAssertEqual(model.selectedRow?.id, "picked-color:hex", "HEX stays selected")
        model.activate(rowID: "picked-color:another")
        XCTAssertEqual(sampler.requests, 2, "the loupe opens again")
        sampler.finish(PickedColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(model.selectedRow?.id, "picked-color:hex")
        model.activateSelection()
        XCTAssertEqual(copied, ["#0000ff"], "the new color replaces the old one")
    }

    func testEscapeInTheLoupeReturnsWithoutAColorOrACopy() {
        let model = model(), sampler = FakeColorSampler()
        model.colorSampler = sampler
        model.query = "eyedropper"
        model.activate(rowID: "core:colorPicker")
        sampler.finish(nil)
        XCTAssertEqual(reopenings, 1, "cancelling brings the launcher back")
        XCTAssertEqual(model.query, LauncherModel.colorPickerQuery)
        XCTAssertNil(model.pickedColor)
        XCTAssertFalse(model.rows.contains { $0.id.hasPrefix("picked-color:") })
        XCTAssertTrue(copied.isEmpty)
        XCTAssertFalse(model.samplingColor, "a new pick may start")
    }

    func testPickedColorShowsOnlyUnderPickColorPhrases() {
        let model = model(), sampler = FakeColorSampler()
        model.colorSampler = sampler
        model.query = "color picker"
        model.activate(rowID: "core:colorPicker")
        sampler.finish(PickedColor(red: 0, green: 0, blue: 0))
        model.query = "color"
        XCTAssertFalse(model.rows.contains { $0.id.hasPrefix("picked-color:") })
        model.query = "Colour Picker"
        XCTAssertEqual(model.rows.filter { $0.id.hasPrefix("picked-color:") }.count, 5, "four formats and Pick Another Color")
        XCTAssertTrue(model.rows.contains { $0.id == "picked-color:another" }, "picking another stays available")
    }

    // MARK: Open Camera

    func testAuthorizedCameraOpensWithoutAsking() {
        let model = model(), camera = FakeCameraAccess(authorization: .authorized)
        model.cameraAccess = camera
        model.query = "camera"
        model.activate(rowID: "core:camera")
        XCTAssertEqual(camera.requests, 0)
        XCTAssertEqual(cameraRequests, 1)
        XCTAssertEqual(dismissals, 1)
    }

    func testFirstUseAsksOnceAndOpensOnlyWhenGranted() {
        let model = model(), camera = FakeCameraAccess(authorization: .notDetermined)
        model.cameraAccess = camera
        model.query = "open camera"
        model.activate(rowID: "core:camera")
        XCTAssertEqual(camera.requests, 1)
        XCTAssertTrue(PermissionGate.isPrompting, "the launcher stays up while macOS asks")
        XCTAssertEqual(cameraRequests, 0, "nothing opens before the answer")
        camera.answer?(true)
        XCTAssertFalse(PermissionGate.isPrompting)
        XCTAssertEqual(cameraRequests, 1)

        let refused = FakeCameraAccess(authorization: .notDetermined)
        model.cameraAccess = refused
        model.query = "camera"
        model.activate(rowID: "core:camera")
        refused.answer?(false)
        XCTAssertEqual(cameraRequests, 1, "a refusal opens nothing")
        XCTAssertEqual(model.rows.map(\.id), ["privacy:camera"])
        XCTAssertEqual(model.actionFeedback, LauncherModel.cameraDeniedMessage)
    }

    func testDeniedAndRestrictedCameraOfferThePrivacyPaneWithoutAsking() {
        for state in [CameraAuthorization.denied, .restricted] {
            let model = model(), camera = FakeCameraAccess(authorization: state)
            model.cameraAccess = camera
            model.query = "camera"
            model.activate(rowID: "core:camera")
            XCTAssertEqual(camera.requests, 0, "\(state)")
            XCTAssertEqual(model.selectedRow?.id, "privacy:camera", "\(state)")
            XCTAssertNotNil(model.actionFeedback)
            XCTAssertEqual(model.selectedRow?.primaryAction, "Open Settings")
            model.activateSelection()
            XCTAssertEqual(opened.last?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        }
        XCTAssertEqual(cameraRequests, 0)
    }

    func testNoCameraExplainsAndNeverAsks() {
        let model = model(), camera = FakeCameraAccess(authorization: .notDetermined)
        camera.hasCamera = false
        model.cameraAccess = camera
        model.query = "camera"
        model.activate(rowID: "core:camera")
        XCTAssertEqual(camera.requests, 0)
        XCTAssertEqual(cameraRequests, 0)
        XCTAssertEqual(model.actionFeedback, "No camera is connected to this Mac.")
    }

    // MARK: System Events toggles

    func testToggleRowsShowTheStateReadFromPreferences() {
        let model = model()
        model.query = "dark mode"
        guard case .systemToggle(.appearance, let on)? = model.rows.first(where: { $0.id == "system-toggle:appearance" }) else { return XCTFail("no appearance row") }
        XCTAssertEqual(on, true)
        model.query = "hide menu bar"
        guard case .systemToggle(.menuBar, let hidden)? = model.rows.first(where: { $0.id == "system-toggle:menuBar" }) else { return XCTFail("no menu bar row") }
        XCTAssertEqual(hidden, false)
        model.globalDefaults = { nil }
        model.query = "light mode"
        guard case .systemToggle(.appearance, let unknown)? = model.rows.first(where: { $0.id == "system-toggle:appearance" }) else { return XCTFail("no appearance row") }
        XCTAssertNil(unknown)
    }

    func testReturnTogglesThroughSystemEventsAndKeepsTheLauncherOpen() {
        let model = model(), events = FakeSystemEvents(values: ["aprp/thme": true])
        model.systemToggles = SystemToggleService(runner: events, queue: nil)
        model.query = "dark mode"
        model.activate(rowID: "system-toggle:appearance")
        XCTAssertEqual(events.values["aprp/thme"], false)
        XCTAssertEqual(events.writes, ["aprp/thme=false"])
        XCTAssertEqual(dismissals, 0)
        guard case .systemToggle(_, let on)? = model.selectedRow else { return XCTFail("selection moved") }
        XCTAssertEqual(on, false, "the row shows the new state")
        XCTAssertEqual(model.actionFeedback, SystemToggle.appearance.confirmation(on: false))
    }

    func testRefusedAutomationOffersThePrivacyPane() {
        let model = model(), events = FakeSystemEvents(values: [:])
        events.prepareError = SystemEventsFailure(status: SystemEventsFailure.notPermitted)
        model.systemToggles = SystemToggleService(runner: events, queue: nil)
        model.query = "menu bar"
        model.activate(rowID: "system-toggle:menuBar")
        XCTAssertTrue(events.writes.isEmpty)
        XCTAssertEqual(model.rows.map(\.id), ["privacy:automation"])
        XCTAssertEqual(model.actionFeedback, SystemEventsFailure.denied.message)
        model.activateSelection()
        XCTAssertEqual(opened.last?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    func testOtherFailuresKeepTheRowAndExplain() {
        let model = model(), events = FakeSystemEvents(values: ["dpas/dahm": false])
        events.writeError = NSError(domain: NSOSStatusErrorDomain, code: SystemEventsFailure.timedOut)
        model.systemToggles = SystemToggleService(runner: events, queue: nil)
        model.query = "menu bar"
        model.activate(rowID: "system-toggle:menuBar")
        XCTAssertEqual(model.selectedRow?.id, "system-toggle:menuBar")
        XCTAssertEqual(model.actionFeedback, SystemEventsFailure.noAnswer.message)
    }

    func testServiceConfirmsTheChangeByReadingItBack() {
        let events = FakeSystemEvents(values: ["dpas/dahm": false])
        XCTAssertEqual(SystemToggleService.perform(.menuBar, runner: events), .success(true))
        XCTAssertEqual(SystemToggleService.perform(.menuBar, runner: events), .success(false))
        events.ignoresWrites = true
        XCTAssertEqual(SystemToggleService.perform(.menuBar, runner: events), .failure(.notApplied), "an ignored write is not reported as done")
        let missing = FakeSystemEvents(values: [:])
        missing.prepareError = SystemEventsFailure(status: SystemEventsFailure.processNotFound)
        XCTAssertEqual(SystemToggleService.perform(.appearance, runner: missing), .failure(.unavailable))
        XCTAssertEqual(SystemEventsFailure(status: -1708), .failed(-1708))
    }

    func testEventsAddressOnlyTheToggleProperty() {
        XCTAssertEqual(AppleEventSystemEvents.code("thme"), 0x7468_6D65)
        let specifier = AppleEventSystemEvents.specifier("thme", in: "aprp")
        XCTAssertEqual(specifier.descriptorType, DescType(typeObjectSpecifier))
        XCTAssertEqual(specifier.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, AppleEventSystemEvents.code("thme"))
        let container = specifier.forKeyword(AEKeyword(keyAEContainer))
        XCTAssertEqual(container?.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, AppleEventSystemEvents.code("aprp"))
        XCTAssertEqual(container?.forKeyword(AEKeyword(keyAEContainer))?.descriptorType, DescType(typeNull))
        XCTAssertEqual(AppleEventSystemEvents.bundleIdentifier, "com.apple.systemevents")
    }
}

/// Records sample requests and finishes them when the test says.
private final class FakeColorSampler: ColorSampling {
    private(set) var requests = 0
    private var pending: ((PickedColor?) -> Void)?
    func sample(_ completion: @escaping (PickedColor?) -> Void) { requests += 1; pending = completion }
    func finish(_ color: PickedColor?) { pending?(color); pending = nil }
}

/// A camera whose authorization and consent answer the test controls.
private final class FakeCameraAccess: CameraAccess {
    var hasCamera = true
    var authorization: CameraAuthorization
    private(set) var requests = 0
    var answer: ((Bool) -> Void)?
    init(authorization: CameraAuthorization) { self.authorization = authorization }
    func requestAccess(_ completion: @escaping (Bool) -> Void) { requests += 1; answer = completion }
}

/// System Events as a dictionary of properties keyed `container/property`.
private final class FakeSystemEvents: SystemEventsRunning {
    var values: [String: Bool]
    var prepareError: Error?
    var writeError: Error?
    var ignoresWrites = false
    private(set) var writes: [String] = []
    init(values: [String: Bool]) { self.values = values }
    func prepare() throws { if let prepareError { throw prepareError } }
    func readBoolean(container: String, property: String) throws -> Bool { values[container + "/" + property] ?? false }
    func writeBoolean(container: String, property: String, value: Bool) throws {
        if let writeError { throw writeError }
        writes.append("\(container)/\(property)=\(value)")
        if !ignoresWrites { values[container + "/" + property] = value }
    }
}
