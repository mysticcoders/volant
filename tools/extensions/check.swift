import AppKit
import Foundation
import Network
import VolantCore
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let module = try Data(contentsOf: root.appendingPathComponent("extensions/hello-rust/hello.wasm"))
let engine = ExtensionHost()
func evaluate(_ data: Data, input: String = "", capabilities: [String] = [], timeout: Double = 2) -> (String?, String?) {
    var result: (String?, String?) = (nil, "No reply")
    engine.run(module: data, capabilities: capabilities, input: input, timeout: timeout) { result = ($0, $1) }
    return result
}
if CommandLine.arguments.contains("--spin") {
    let spin = try Data(contentsOf: root.appendingPathComponent("extensions/spin-rust/spin.wasm"))
    _ = evaluate(spin, timeout: 0.5)
    fatalError("Watchdog failed to terminate looping WASM")
}
if CommandLine.arguments.contains("--command-spin") {
    let spin = try Data(contentsOf: root.appendingPathComponent("tools/extensions/wasi-fixtures/spin.wasm"))
    engine.runCommand(module: spin, input: "", timeout: 0.5) { _, _ in fatalError("Command watchdog failed") }
    fatalError("Command watchdog failed to terminate")
}
/// Draws `svg` through the production helper's `rasterizeSVG`, waiting up to `wait` seconds for its reply.
func rasterize(_ svg: String, wait: TimeInterval = 10) -> (Data?, String?) {
    var result: (Data?, String?) = (nil, "No reply")
    let done = DispatchSemaphore(value: 0)
    engine.rasterizeSVG(data: Data(svg.utf8), maximumPixels: ExtensionItemImage.thumbnailPixels) { result = ($0, $1); done.signal() }
    _ = done.wait(timeout: .now() + wait)
    return result
}
/// A file the SVG check accepts that the renderer needs seconds for: one evenodd path of 3,000 long,
/// crossing segments.
func slowSVG() -> String {
    var path = "M0 0"
    for index in 0..<3000 { path += "L\((index * 7919) % 16384) \((index * 104729) % 16384)" }
    return #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16384 16384"><path fill-rule="evenodd" d=""# + path + #""/></svg>"#
}
/// Draws markup full of external references with the check bypassed (`ExtensionSVGRasterizer.draw`) in
/// this unsandboxed process while a loopback listener counts connections, then proves the listener
/// works with one real request. A local PNG referenced by path must not appear in the drawing either.
func checkRendererFetchesNothing() throws {
    let lock = NSLock()
    var connections = 0
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    let ready = DispatchSemaphore(value: 0)
    listener.newConnectionHandler = { connection in lock.lock(); connections += 1; lock.unlock(); connection.cancel() }
    listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
    listener.start(queue: .global())
    defer { listener.cancel() }
    check(ready.wait(timeout: .now() + 5) == .success, "Loopback listener starts")
    let base = "http://127.0.0.1:\(listener.port!.rawValue)"
    let png = FileManager.default.temporaryDirectory.appendingPathComponent("volant-svg-green-\(UUID().uuidString).png")
    let pixels = ExtensionImageDecoding.redrawnPNG(width: 24, height: 24) { $0.setFillColor(red: 0, green: 1, blue: 0, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 24, height: 24)) }
    try pixels!.write(to: png)
    defer { try? FileManager.default.removeItem(at: png) }
    let open = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24" width="24" height="24">"#
    let documents = [
        open + #"<image href="\#(base)/image.png" width="24" height="24"/><image xlink:href="\#(base)/xlink.png" width="24" height="24"/></svg>"#,
        open + #"<use href="\#(base)/sprite.svg#a"/><use xlink:href="\#(base)/sprite-xlink.svg#a"/></svg>"#,
        open + #"<style>@import url(\#(base)/import.css); rect { fill: url(\#(base)/paint.svg#g) }</style><rect width="24" height="24"/></svg>"#,
        open + #"<style>@font-face { font-family: f; src: url(\#(base)/font.woff) }</style><text font-family="f" y="20">A</text></svg>"#,
        open + #"<filter id="f"><feImage href="\#(base)/feimage.png"/></filter><rect width="24" height="24" filter="url(#f)"/></svg>"#,
        #"<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY x SYSTEM "\#(base)/xxe.txt"><!ENTITY y SYSTEM "\#(png.absoluteString)">]>"# + open + "<text y=\"20\">&x;&y;</text></svg>",
        #"<?xml version="1.0"?><!DOCTYPE svg SYSTEM "\#(base)/svg.dtd">"# + open + "</svg>",
        open + #"<xi:include xmlns:xi="http://www.w3.org/2001/XInclude" href="\#(base)/include.svg"/></svg>"#,
        open + #"<script>fetch('\#(base)/script')</script><rect width="24" height="24" onload="fetch('\#(base)/onload')"/></svg>"#,
        open + #"<foreignObject width="24" height="24"><img xmlns="http://www.w3.org/1999/xhtml" src="\#(base)/fo.png"/></foreignObject></svg>"#
    ]
    for svg in documents {
        check(ExtensionSVGPreview.check(Data(svg.utf8)) != nil, "The check refuses \(svg)")
        _ = ExtensionSVGRasterizer.draw(Data(svg.utf8), maximumPixels: 64)
    }
    for href in [png.absoluteString, png.path] {
        let svg = open + #"<image href="\#(href)" width="24" height="24"/><image xlink:href="\#(href)" width="24" height="24"/></svg>"#
        if case .png(let drawn) = ExtensionSVGRasterizer.draw(Data(svg.utf8), maximumPixels: 64), let image = NSBitmapImageRep(data: drawn),
           let center = image.colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB) {
            check(!(center.greenComponent > 0.8 && center.redComponent < 0.2), "The renderer drew a local file referenced by \(href)")
        }
    }
    Thread.sleep(forTimeInterval: 1)
    lock.lock(); let seen = connections; lock.unlock()
    check(seen == 0, "The renderer opened \(seen) connections")
    let probe = DispatchSemaphore(value: 0)
    URLSession(configuration: .ephemeral).dataTask(with: URL(string: base + "/probe")!) { _, _, _ in probe.signal() }.resume()
    _ = probe.wait(timeout: .now() + 10)
    lock.lock(); let probed = connections; lock.unlock()
    check(probed > 0, "The listener sees a real request, so zero connections above is meaningful")
}
if CommandLine.arguments.contains("--svg-spin") {
    guard ExtensionSVGRasterizer.representationClass != nil else { print("SKIP: this macOS has no SVG image representation"); exit(4) }
    guard ExtensionSVGPreview.check(Data(slowSVG().utf8)) == nil else { fatalError("The slow SVG must pass the check") }
    _ = rasterize(slowSVG(), wait: 30)
    fatalError("SVG watchdog failed to terminate a slow render")
}
func check(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) } }
if ExtensionSVGRasterizer.representationClass != nil {
    let logo = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 222" width="256" height="222"><path fill="#000" d="m128 0 128 221.705H0z"/></svg>"##
    let drawn = rasterize(logo)
    check(drawn.1 == nil && drawn.0.map(ExtensionItemImage.looksLikeThumbnail) == true, "The helper draws a checked SVG into a small PNG: \(String(describing: drawn.1))")
    let hostile = rasterize(#"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>"#)
    check(hostile.0 == nil && hostile.1 == "refused.forbiddenElement", "The helper checks the markup again: \(String(describing: hostile.1))")
    check(rasterize("<html></html>").1 == "refused.notSVG", "The helper draws only SVG")
    print("PASS: the extension helper checks SVG again and draws it into a PNG")
    try checkRendererFetchesNothing()
    print("PASS: the SVG renderer opened no connection and read no file for external references, with the check bypassed and no sandbox")
} else {
    print("SKIP: this macOS has no SVG image representation; SVG previews show the placeholder")
}
let hello = evaluate(module, input: "Andrew")
check(hello.0 == "Hello, Andrew!" && hello.1 == nil, "WASM returns real greeting: \(String(describing: hello))")
check(evaluate(module).0 == "Hello, world!", "Empty input")
check(evaluate(module, input: "世界 👋").0 == "Hello, 世界 👋!", "UTF-8 round trip")
check(evaluate(module, input: String(repeating: "x", count: ExtensionLimits.maximumInputBytes + 1)).1 != nil, "Input limit")
check(evaluate(module, input: String(repeating: "x", count: ExtensionLimits.maximumOutputBytes - 9)).1 == nil, "Output just under the limit succeeds")
check(evaluate(module, input: String(repeating: "x", count: ExtensionLimits.maximumOutputBytes)).1 != nil, "Output limit")
check(evaluate(module, timeout: .infinity).1 != nil, "Finite watchdog")
check(evaluate(Data([0])).1 != nil, "Malformed module")
// Valid bounded module importing volant.log; denied before any missing-export checks.
let imported = Data([0,97,115,109,1,0,0,0, 1,6,1,96,2,127,127,0, 2,14,1,6,118,111,108,97,110,116,3,108,111,103,0,0, 5,4,1,1,1,1])
check(evaluate(imported).1?.contains("not granted") == true, "Undeclared capability denied")
let clipboard = try Data(contentsOf: root.appendingPathComponent("extensions/clipboard-test/clipboard.wasm"))
let granted = evaluate(clipboard, input: "note", capabilities: ["clipboard.write"])
check(granted.0 == "Copied “Volant clipboard test v1: note”" && granted.1 == nil, "Clipboard test runs with clipboard.write: \(granted)")
check(evaluate(clipboard, capabilities: ["log"]).1?.contains("not granted") == true, "Clipboard test refused without clipboard.write")
// The ABI 1 namespace is volant; a module still importing the pre-rename vey namespace is refused.
let legacyNamespace = Data([0,97,115,109,1,0,0,0, 1,6,1,96,2,127,127,0, 2,11,1,3,118,101,121,3,108,111,103,0,0, 5,4,1,1,1,1])
check(evaluate(legacyNamespace, capabilities: ["log"]).1?.contains("not granted") == true, "Legacy vey namespace refused")
check(evaluate(imported, capabilities: ["log"]).1?.contains("not granted") != true, "volant.log accepted when granted")
let base64 = try Data(contentsOf: root.appendingPathComponent("extensions/raycast-base64/encode.wasm"))
let legacyRejection = evaluate(base64)
check(legacyRejection.0 == nil && legacyRejection.1?.contains("not granted") == true, "ABI 1 never silently accepts WASI imports: \(legacyRejection.1 ?? "no error")")
for input in ["", "Hello, Volant!", "café ☕ 日本語", String(repeating: "a", count: 4096)] {
    var output: String?, failure: String?
    engine.runCommand(module: base64, input: input, timeout: 2) { output = $0; failure = $1 }
    check(output == Data(input.utf8).base64EncodedString() && failure == nil, "Production WASI adapter executes real TypeScript: \(failure ?? "wrong output")")
}
var overLimit = false
var exactLimit = false
engine.runCommand(module: base64, input: String(repeating: "a", count: 49152), timeout: 2) { exactLimit = $0?.utf8.count == 65536 && $1 == nil }
check(exactLimit, "The Base64 sample encodes the most its 64 KiB input buffer holds")
engine.runCommand(module: base64, input: String(repeating: "a", count: 65536), timeout: 2) { overLimit = $0 == nil && $1 != nil }
check(overLimit, "Input past the sample's own buffer fails without truncated success")
func commandProbe(_ name: String, input: String = "OK") throws -> (String?, String?) {
    let bytes = try Data(contentsOf: root.appendingPathComponent("tools/extensions/wasi-fixtures/\(name).wasm"))
    var result: (String?, String?) = (nil, "No reply")
    engine.runCommand(module: bytes, input: input, timeout: 2) { result = ($0, $1) }
    return result
}
check(try commandProbe("streams").0 == "OK", "Bounded streams, partial reads, EOF, fd rights, closed fds, empty environment and frozen clock")
check(try commandProbe("zeroExit").0 == "OK", "proc_exit(0) terminates only this command")
check(try commandProbe("exactOutput").0?.utf8.count == ExtensionLimits.maximumOutputBytes, "Exactly \(ExtensionLimits.outputDescription) of command output succeeds")
check(try commandProbe("caughtExit").0 == "OK", "Caught exit cannot resume command I/O")
for name in ["failedExit", "bounds", "vectorLimit", "outputLimit", "stderrLimit", "invalidUTF8", "callLimit", "filesystem", "network", "prototype"] {
    let result = try commandProbe(name)
    check(result.0 == nil && result.1 != nil, "Command rejects \(name) without partial output")
}
check(try commandProbe("streams").0 == "OK", "Fresh command recovers after rejected calls")
// List extensions: a dependency-free fixture plans only its host and renders rows the launcher
// accepts. The real readers live in github.com/mysticcoders/volant-extensions. No network is used.
let fixture = try Data(contentsOf: root.appendingPathComponent("tools/extensions/list-fixture/list-fixture.wasm"))
check((try? ExtensionMemory.validate(fixture)) != nil, "List fixture declares bounded memory")
let fixturePlan = evaluate(fixture, input: try ExtensionNetwork.request(phase: "plan", query: "", now: Date()))
let fixtureURLs = try ExtensionNetwork.plannedURLs(from: fixturePlan.0 ?? "", hosts: ["fixture.example.com"])
check(fixtureURLs.map(\.host) == ["fixture.example.com"], "List fixture plans its one host: \(fixturePlan)")
check((try? ExtensionNetwork.plannedURLs(from: fixturePlan.0 ?? "", hosts: ["other.example.com"])) == nil, "A plan outside the approved hosts is refused")
let explained = evaluate(fixture, input: try ExtensionNetwork.request(phase: "plan", query: "explain", now: Date()))
check((try? ExtensionNetwork.items(from: explained.0 ?? ""))?.first?.title == "Fixture explains its query", "A plan may return rows instead of URLs")
for (status, title) in [(200, "Fixture fetched"), (0, "Fixture nothing fetched")] {
    let response = ExtensionNetwork.Response(url: fixtureURLs[0].absoluteString, status: status, body: status == 200 ? "{}" : "")
    let rendered = evaluate(fixture, input: try ExtensionNetwork.request(phase: "render", query: "", now: Date(), responses: [response]))
    let items = try ExtensionNetwork.items(from: rendered.0 ?? "")
    check(items.first?.title == title && items.first?.secondaryTitle == "Open Comments", "List fixture renders responses with status \(status): \(rendered)")
}
print("PASS: production ABI 2 executes Raycast TypeScript and enforces stream, import, pointer, output and host-call boundaries")
print("PASS: actual WASM greeting, UTF-8, input/output limits, malformed modules and denied imports")
