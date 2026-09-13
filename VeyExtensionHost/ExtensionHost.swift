import Foundation
import JavaScriptCore

/// Runs one WebAssembly module inside JavaScriptCore. JavaScript is used only as glue to build the
/// import object; the module can reach nothing except the imports it is handed.
final class ExtensionHost: NSObject, VeyExtensionHostProtocol {
    private let connection: NSXPCConnection

    init(connection: NSXPCConnection) { self.connection = connection }

    func run(module: Data, capabilities: [String], input: String, timeout: Double, reply: @escaping (String?, String?) -> Void) {
        let client = connection.remoteObjectProxy as? VeyCapabilityClientProtocol
        let watchdog = DispatchWorkItem { exit(3) }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.5, timeout), execute: watchdog)
        defer { watchdog.cancel() }

        let ctx = JSContext()!
        var failure: String? = nil
        ctx.exceptionHandler = { _, e in failure = e?.toString() }

        let allowed = Set(capabilities)
        var imports: [String: Any] = [:]
        if allowed.contains("log") {
            let f: @convention(block) (Int32, Int32) -> Void = { ptr, len in
                if let s = ExtensionHost.readString(ctx, ptr, len) { client?.log(s) }
            }
            imports["log"] = f
        }
        if allowed.contains("clipboard.write") {
            let f: @convention(block) (Int32, Int32) -> Void = { ptr, len in
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
            if (imp.module !== 'vey' || !(imp.name in veyImports)) {
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
          return Array.from(new Uint8Array(mem.buffer, out + 4, len));
        })()
        """
        let result = ctx.evaluateScript(script)
        if let failure { reply(nil, failure); return }
        let bytes = (result?.toArray() as? [NSNumber])?.map { UInt8(truncatingIfNeeded: $0.intValue) } ?? []
        reply(String(decoding: bytes, as: UTF8.self), nil)
    }

    /// Reads a UTF-8 string out of the module's linear memory. The module cannot address anything else.
    private static func readString(_ ctx: JSContext, _ ptr: Int32, _ len: Int32) -> String? {
        guard ptr >= 0, len >= 0, len <= 1_000_000 else { return nil }
        let js = "Array.from(new Uint8Array(globalThis.__mem.buffer, \(ptr), \(len)))"
        guard let arr = ctx.evaluateScript(js)?.toArray() as? [NSNumber] else { return nil }
        return String(decoding: arr.map { UInt8(truncatingIfNeeded: $0.intValue) }, as: UTF8.self)
    }
}
