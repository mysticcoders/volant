import AppKit
import ServiceManagement
import VolantCore

// Renders every page of the Welcome window in light and dark from fictional data: a temporary
// config.json, fake permissions and login item, invented agents and the bundled Hello World. Nothing
// prompts, connects, registers a login item or reads the owner's files. Images go to
// /tmp/volant-welcome-<appearance>-<page>.png, which tools/render-vm.py collects.

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let root = FileManager.default.temporaryDirectory.appendingPathComponent("volant-welcome-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let configURL = root.appendingPathComponent("config.json")
try Data(#"{"summonHotKey":"option+space","statusBar":{"sources":["rex"],"herdrFilter":"all"}}"#.utf8).write(to: configURL)

/// Contacts allowed, Calendars denied and the microphone not asked yet, so all three states render.
final class FixturePermissions: WelcomePermissionProvider {
    func status(_ permission: WelcomePermission) -> WelcomePermissionStatus {
        switch permission {
        case .contacts: return .allowed
        case .calendars: return .denied
        case .microphone: return .notDetermined
        }
    }
    func request(_ permission: WelcomePermission, completion: @escaping (WelcomePermissionStatus) -> Void) { completion(.allowed) }
}

final class FixtureLoginItem: WelcomeLoginItem {
    var status: SMAppService.Status = .enabled
    func setEnabled(_ enabled: Bool) throws { status = enabled ? .enabled : .notRegistered }
}

/// Builds a model whose agents and running apps are invented; `competing` adds a running Raycast.
func makeModel(competing: Bool, registered: Bool) -> WelcomeModel {
    let config = try! JSONDecoder().decode(Preferences.self, from: Data(contentsOf: configURL))
    let hello = Bundle.main.url(forResource: "HelloWorld", withExtension: nil).map { [$0] } ?? []
    let agents = [ACPAgentAvailability(provider: "claude", state: .ready, detail: "", path: "/fictional/bin/claude"),
                  ACPAgentAvailability(provider: "codex", state: .needsAdapter, detail: "Needs the codex-acp adapter", path: nil)]
    return WelcomeModel(configURL: configURL, config: config, summonRegistered: registered,
                        permissions: FixturePermissions(), loginItem: FixtureLoginItem(), dictationAvailable: true,
                        runningBundleIDs: { competing ? ["com.raycast.macos"] : [] },
                        detectChatAgents: { reply in reply(agents) }, rexInstalled: { true }, herdrInstalled: { false },
                        makeExtensionManager: { ExtensionManager(configURL: configURL, roots: hello, dataDirectory: root.appendingPathComponent("ExtensionData")) })
}

typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let windowImage = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: WindowImage.self) }

/// Saves the window as a PNG, from the window server when it can, otherwise by caching the view.
func capture(_ controller: WelcomeWindowController, _ name: String) {
    let window = controller.window!
    window.contentView!.layoutSubtreeIfNeeded()
    let url = URL(fileURLWithPath: "/tmp/volant-welcome-\(name).png")
    if let windowImage, let image = windowImage(.null, 1 << 3, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
    } else {
        let view = window.contentView!
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
    }
    print("Rendered Welcome \(name)")
    fflush(stdout)
}

func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

DispatchQueue.main.async {
    var failures = 0
    for theme in ["light", "dark"] {
        app.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        let model = makeModel(competing: false, registered: true)
        let controller = WelcomeWindowController(model: model) {}
        controller.present()
        controller.window!.orderFrontRegardless()
        settle()
        if model.steps != [.shortcut, .typing, .access, .agents, .extensions] { print("FAIL: \(theme) agents page missing: \(model.steps)"); failures += 1 }
        if model.extensions.isEmpty { print("FAIL: \(theme) bundled Hello World missing from the extensions page"); failures += 1 }
        for step in model.steps {
            model.step = step
            settle()
            capture(controller, "\(theme)-\(step.rawValue)")
        }
        controller.window!.orderOut(nil)

        let warned = makeModel(competing: true, registered: true)
        let competing = WelcomeWindowController(model: warned) {}
        competing.present()
        competing.window!.orderFrontRegardless()
        settle()
        capture(competing, "\(theme)-shortcut-raycast")
        competing.window!.orderOut(nil)

        let blocked = makeModel(competing: false, registered: false)
        let unavailable = WelcomeWindowController(model: blocked) {}
        unavailable.present()
        unavailable.window!.orderFrontRegardless()
        settle()
        capture(unavailable, "\(theme)-shortcut-unavailable")
        unavailable.window!.orderOut(nil)
    }
    try? FileManager.default.removeItem(at: root)
    exit(failures == 0 ? 0 : 1)
}
app.run()
