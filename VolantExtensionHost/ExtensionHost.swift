import Foundation
import JavaScriptCore

/// Runs one WebAssembly module inside JavaScriptCore. JavaScript is used only as glue to build the
/// import object; the module can reach nothing except the imports it is handed.
final class ExtensionHost: NSObject, VolantExtensionHostProtocol {
    private let connection: NSXPCConnection?

    init(connection: NSXPCConnection? = nil) { self.connection = connection }

    func prepare(reply: @escaping () -> Void) { reply() }

    func run(module: Data, capabilities: [String], input: String, timeout: Double, reply: @escaping (String?, String?) -> Void) {
        do { try ExtensionMemory.validate(module) }
        catch { reply(nil, error.localizedDescription); return }
        guard input.utf8.count <= 65_536, timeout.isFinite, (0.5...10).contains(timeout),
              Set(capabilities).isSubset(of: ExtensionManifest.knownCapabilities) else { reply(nil, "Invalid extension request."); return }
        let client = connection?.remoteObjectProxy as? VolantCapabilityClientProtocol
        let watchdog = DispatchWorkItem { exit(3) }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.5, timeout), execute: watchdog)
        defer { watchdog.cancel() }

        guard let ctx = JSContext() else { reply(nil, "Couldn’t create the extension runtime."); return }
        var failure: String? = nil
        ctx.exceptionHandler = { _, e in failure = e?.toString() }

        let allowed = Set(capabilities)
        var imports: [String: Any] = [:]
        var remainingCallbacks = 64
        if allowed.contains("log") {
            let f: @convention(block) (Int32, Int32) -> Void = { [weak ctx] ptr, len in
                guard let ctx, remainingCallbacks > 0 else { return }
                remainingCallbacks -= 1
                if let s = ExtensionHost.readString(ctx, ptr, len) { client?.log(s) }
            }
            imports["log"] = f
        }
        if allowed.contains("clipboard.write") {
            let f: @convention(block) (Int32, Int32) -> Void = { [weak ctx] ptr, len in
                guard let ctx, remainingCallbacks > 0 else { return }
                remainingCallbacks -= 1
                if let s = ExtensionHost.readString(ctx, ptr, len) { client?.clipboardWrite(s) }
            }
            imports["clipboard_write"] = f
        }
        ctx.setObject(imports, forKeyedSubscript: "veyImports" as NSString)
        ctx.setObject([UInt8](module), forKeyedSubscript: "moduleBytes" as NSString)
        ctx.setObject([UInt8](input.utf8), forKeyedSubscript: "inputBytes" as NSString)

        let script = """
        (function () {
          const mod = new WebAssembly.Module(new Uint8Array(moduleBytes));
          const declared = WebAssembly.Module.imports(mod);
          for (const imp of declared) {
            if (imp.kind !== 'function' || imp.module !== 'vey' || !(imp.name in veyImports)) {
              throw new Error('module wants import ' + imp.module + '.' + imp.name + ' which is not granted');
            }
          }
          const inst = new WebAssembly.Instance(mod, { vey: veyImports });
          const mem = inst.exports.memory;
          globalThis.__mem = mem;
          const bytes = inputBytes;
          const ptr = inst.exports.alloc(bytes.length);
          new Uint8Array(mem.buffer, ptr, bytes.length).set(bytes);
          const out = inst.exports.run(ptr, bytes.length);
          const view = new DataView(mem.buffer);
          const len = view.getUint32(out, true);
          if (len > 65536) throw new Error('Extension output exceeds 64 KiB');
          return Array.from(new Uint8Array(mem.buffer, out + 4, len));
        })()
        """
        let result = ctx.evaluateScript(script)
        if let failure { reply(nil, failure); return }
        let bytes = (result?.toArray() as? [NSNumber])?.map { UInt8(truncatingIfNeeded: $0.intValue) } ?? []
        guard let text = String(bytes: bytes, encoding: .utf8) else { reply(nil, "Extension output is not UTF-8."); return }
        reply(text, nil)
    }

    /// Reads a UTF-8 string out of the module's linear memory. The module cannot address anything else.
    private static func readString(_ ctx: JSContext, _ ptr: Int32, _ len: Int32) -> String? {
        guard ptr >= 0, len >= 0, len <= 65_536 else { return nil }
        let js = "Array.from(new Uint8Array(globalThis.__mem.buffer, \(ptr), \(len)))"
        guard let arr = ctx.evaluateScript(js)?.toArray() as? [NSNumber] else { return nil }
        return String(decoding: arr.map { UInt8(truncatingIfNeeded: $0.intValue) }, as: UTF8.self)
    }
}
