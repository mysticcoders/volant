import AppKit
import CryptoKit
import SwiftUI
import VolantCore

/// Renders the launcher, a calculator card, the actions popover and the notes window in every color
/// theme with fictional data, for visual inspection. Palette themes render in their own appearance;
/// System and Volant render light and dark. Images go to /tmp/volant-theme-<id>-<mode>-<surface>.png.
/// System and Catppuccin Mocha also render a scrolled list (edge fade), the open Volant menu, and
/// the footer's Herdr status while agents wait, while loading, and with a machine unavailable.
setbuf(stdout, nil)
let app = NSApplication.shared
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
    .appendingPathComponent("volant-themes-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let clipboard = ClipboardStore(retention: 10, storageURL: root.appendingPathComponent("clipboard.sqlite"), encryptionKey: SymmetricKey(size: .bits256))
let usage = UsageStore(url: root.appendingPathComponent("usage.sqlite"))
let notesDirectory = root.appendingPathComponent("Notes")
try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
try "# Trip checklist\n\n## Before Friday\n\n- Pack the **blue** bag\n- Check the [route](https://example.com/route)\n- Bring `charger` and cards\n\n> Leave by 7:30.\n\n```swift\nlet bags = 2\nlet note = \"Window seat\"\n```\n"
    .write(to: notesDirectory.appendingPathComponent("Trip checklist.md"), atomically: true, encoding: .utf8)
let notes = NotesStore(directory: notesDirectory)
let model = LauncherModel(index: AppIndex(), clipboard: clipboard, notes: notes, config: Preferences(), usage: usage) { _ in }
model.searchesSecondarySources = false
var config = Preferences()
config.snippets = [Snippet(name: "Standup notes", keyword: "", body: "Fictional"), Snippet(name: "Status update", keyword: "", body: "Fictional"),
                   Snippet(name: "Support reply", keyword: "", body: "Fictional")]
model.config = config

let host = NSHostingView(rootView: ThemedRoot { ThemedLauncher(model: model) })
let window = NSWindow(contentRect: NSRect(origin: .zero, size: LauncherPanel.size), styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = host
window.makeKeyAndOrderFront(nil)
let notesModel = NotesModel(store: notes)
let notesHost = NSHostingView(rootView: ThemedRoot { NotesView(model: notesModel) })
let notesWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
notesWindow.contentView = notesHost
notesWindow.orderFront(nil)

/// Native scroll views under a view, so a render can scroll to a position that cuts rows in half.
func scrollViews(_ view: NSView) -> [NSScrollView] {
    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
}

typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let windowImage = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: WindowImage.self) }

/// Captures a window through the window server, which composites effects an offscreen
/// `cacheDisplay` render leaves out, such as scroll transitions. Falls back to `capture` and says so.
func captureWindow(_ window: NSWindow, _ name: String) throws {
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    if let windowImage, let image = windowImage(.null, 1 << 3, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "/tmp/volant-theme-\(name).png"))
    } else {
        print("Window-server capture unavailable for \(name); using an offscreen render")
        try capture(window.contentView!, name)
    }
}

/// The footer's look-through measurement for one capture: luminance spread inside the footer,
/// left of its action label and right of the Volant mark, plus the region's average color.
struct FooterSample {
    var stddev: Double
    var range: Double
    var average: (Double, Double, Double)
}

/// Captures the window through the window server and samples the footer, since the blur is
/// composited there and an offscreen render does not show it.
func sampleFooter(_ window: NSWindow) -> FooterSample? {
    guard let windowImage, let image = windowImage(.null, 1 << 3, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    let scale = Double(rep.pixelsWide) / window.frame.width
    let xs = Int(36 * scale)..<Int(window.frame.width * 0.55 * scale)
    let ys = (rep.pixelsHigh - Int(30 * scale))..<(rep.pixelsHigh - Int(8 * scale))
    var values: [Double] = []
    var sum = (0.0, 0.0, 0.0)
    for y in ys { for x in xs {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let (r, g, b) = (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
        values.append(255 * (0.2126 * r + 0.7152 * g + 0.0722 * b))
        sum = (sum.0 + r, sum.1 + g, sum.2 + b)
    } }
    guard !values.isEmpty else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    let n = Double(values.count)
    return FooterSample(stddev: deviation, range: values.max()! - values.min()!, average: (sum.0 / n, sum.1 / n, sum.2 / n))
}

/// WCAG relative luminance of an sRGB color with components in 0...1.
func relativeLuminance(_ c: (Double, Double, Double)) -> Double {
    func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
}

/// The footer label's color: the palette's text, or the system label color in this appearance.
func footerLabelColor(_ theme: ColorTheme) -> (Double, Double, Double) {
    var color = NSColor.labelColor
    if let hex = theme.palette?.text, let value = Int(hex.dropFirst(), radix: 16) {
        color = NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var resolved = color
    NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) ?? color }
    return (Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent))
}

/// Writes a view's current drawing to a PNG.
func capture(_ view: NSView, _ name: String) throws {
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/volant-theme-\(name).png"))
}

/// Renders the footer's Herdr status in its waiting, loading and unavailable states with fictional
/// panes and machines, through the window server so the translucent footer composites as on screen.
func renderHerdrFooter(_ name: String) throws {
    let agents = model.agents
    func pane(_ status: String, _ id: String, _ project: String) -> AgentSession {
        AgentSession(agent: "claude", agentStatus: status, paneID: "w1:p" + id, terminalID: "fixture-" + id, cwd: "/fictional/" + project)
    }
    let local = HerdrMachineStatus(id: "local", label: "Local", state: "connected", detail: "4 panes")
    agents.connected = true
    model.promotedHarness = "all"
    model.query = ""
    let states: [(String, [AgentSession], Bool, [HerdrMachineStatus], String)] = [
        ("waiting", [pane("blocked", "1", "orbit"), pane("blocked", "2", "comet"), pane("blocked", "3", "atlas"), pane("working", "4", "nova")], false, [local], "Herdr: 3 waiting"),
        ("loading", [], true, [HerdrMachineStatus(id: "local", label: "Local", state: "loading", detail: "Loading panes…")], "Herdr: loading…"),
        ("unavailable", [pane("working", "4", "nova")], false, [local, HerdrMachineStatus(id: "remote:studio", label: "Studio", state: "unavailable", detail: "Connection timed out")], "Herdr: Studio unavailable")
    ]
    for (state, sessions, busy, machines, expected) in states {
        agents.sessions = sessions; agents.busy = busy; agents.machines = machines
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let text = HerdrStatusSummary(sessions: sessions, connected: true, busy: busy, machines: machines).text
        precondition(text == expected, "\(name) Herdr \(state): footer reads \(text), expected \(expected)")
        try captureWindow(window, name + "-herdr-" + state)
    }
    agents.sessions = []; agents.machines = []; agents.busy = false; agents.connected = false
    model.promotedHarness = nil
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
}

for theme in ColorTheme.catalog {
    for mode in theme.mode.map({ [$0] }) ?? [ColorTheme.Mode.light, .dark] {
        let setting: Appearance.Theme = mode == .dark ? .dark : .light
        MainActor.assumeIsolated { ThemeStore.shared.apply(Appearance(theme: setting, colorTheme: theme.id)) }
        window.appearance = NSApp.appearance
        notesWindow.appearance = NSApp.appearance
        let name = "\(theme.id)-\(mode.rawValue)"
        model.actionTarget = nil
        model.query = "snip s"
        model.selection = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(host, name + "-rows")
        model.actionTarget = model.selectedRow
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(host, name + "-actions")
        model.actionTarget = nil
        model.query = "#3a7bd5 in oklch"
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(host, name + "-card")
        notesModel.selectIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try capture(notesHost, name + "-notes")
        if [ColorTheme.systemID, "catppuccin-mocha"].contains(theme.id) {
            model.query = ""
            model.selection = 0
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let scroll = scrollViews(host).max(by: { $0.frame.height < $1.frame.height }) {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            try captureWindow(window, name + "-scrolled")
            let under = sampleFooter(window)
            model.query = "zzqx nothing matches this"
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            try captureWindow(window, name + "-empty")
            let empty = sampleFooter(window)
            if let under, let empty {
                let label = relativeLuminance(footerLabelColor(theme)), background = relativeLuminance(under.average)
                let contrast = (max(label, background) + 0.05) / (min(label, background) + 0.05)
                print(String(format: "Footer %@: rows beneath stddev %.1f range %.0f; empty stddev %.1f range %.0f; label contrast %.2f:1",
                             name, under.stddev, under.range, empty.stddev, empty.range, contrast))
                precondition(under.stddev >= 2 * max(empty.stddev, 1), "\(name): rows beneath the footer do not show through")
                precondition(contrast >= 4.5, "\(name): footer label contrast \(contrast) is below 4.5:1")
            } else {
                print("Footer \(name): window-server capture unavailable, no measurement")
            }
            model.query = ""
            model.selection = 0
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let scroll = scrollViews(host).max(by: { $0.frame.height < $1.frame.height }) {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            model.showingAppMenu = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            try capture(host, name + "-app-menu")
            model.showingAppMenu = false
            try renderHerdrFooter(name)
        }
        print("Rendered \(name)")
    }
}
let imported = try RaycastTheme.parse("raycast://theme?name=Harbor%20Night&appearance=dark&colors=%23101418,%230C1014,%23E8ECF0,%232A3440,%237A8490,%23F06060,%23F09050,%23E8C860,%2370C080,%236CA8F0,%23A890F0,%23E080C8")
MainActor.assumeIsolated {
    ThemeStore.shared.apply(Appearance(colorTheme: imported.customTheme.id, customThemes: [imported.customTheme]))
}
window.appearance = NSApp.appearance
model.query = "snip s"
model.selection = 1
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
try capture(host, "imported-dark-rows")
model.query = "#3a7bd5 in oklch"
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
try capture(host, "imported-dark-card")
print("PASS: rendered \(ColorTheme.catalog.count) color themes and an imported Raycast theme")
exit(0)
