import AppKit

let app = NSApplication.shared
// A count-only installed-artifact check: never prints clipboard contents or key material.
if CommandLine.arguments.contains("--storage-check") {
    let store = ClipboardStore(retention: Preferences.load().clipboardRetention)
    print("Readable clipboard entries: \(store.recent(limit: Int(Int32.max)).count)")
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
