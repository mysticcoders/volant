import Foundation
import VolantCore

/// Hands SVG markup the fetch helper downloaded and checked to VolantExtensionHost, the sandboxed helper
/// with no network access, which checks it again and draws it (`rasterizeSVG`). Volant never parses or
/// draws the markup; it accepts only the PNG that comes back, under the same checks as any row image
/// (`ExtensionRowImages.thumbnail`). One short-lived connection per preview, completing exactly once on
/// the main queue.
enum ExtensionSVGRendering {
    /// How a preview ended: the helper's PNG, markup the helper refused, no answer within
    /// `ExtensionSVGPreview.replyTimeout` of sending it (the helper stops itself at
    /// `ExtensionSVGPreview.renderTimeout`), or any other failure, including the helper going away.
    enum Reply: Equatable {
        case png(Data)
        case refused, timedOut, failed
    }

    /// How long the helper may take to start before the preview fails; launchd can throttle a helper
    /// that just stopped itself.
    static let startTimeout: TimeInterval = 10

    /// Draws `markup` at most `ExtensionItemImage.thumbnailPixels` on a side in the extension helper.
    static func rasterize(_ markup: Data, completion: @escaping (Reply) -> Void) {
        guard markup.count <= ExtensionSVGPreview.maximumBytes else { completion(.refused); return }
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.ExtensionHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantExtensionHostProtocol.self)
        let call = Call(timeout: ExtensionSVGPreview.replyTimeout, startTimeout: startTimeout, close: { connection.invalidate() }, completion: completion)
        connection.invalidationHandler = { call.finish(.failed) }
        connection.interruptionHandler = { call.finish(.failed) }
        connection.resume()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in call.finish(.failed) }) as? VolantExtensionHostProtocol else {
            call.finish(.failed); return
        }
        call.armStart()
        proxy.prepare {
            call.sent()
            proxy.rasterizeSVG(data: markup, maximumPixels: ExtensionItemImage.thumbnailPixels) { png, code in
                call.finish(Self.reply(png: png, code: code))
            }
        }
    }

    /// The reply for what the helper sent back: its PNG, a refusal code, or anything else as a failure.
    static func reply(png: Data?, code: String?) -> Reply {
        if let png, code == nil { return .png(png) }
        return code?.hasPrefix("refused.") == true ? .refused : .failed
    }

    /// One preview request: a deadline to start the helper, a stricter one once the markup is sent, and a
    /// single completion. The connection is closed when it ends, so a helper still drawing is abandoned.
    final class Call: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var generation = 0
        private let timeout: TimeInterval
        private let startTimeout: TimeInterval
        private let close: () -> Void
        private let completion: (Reply) -> Void

        init(timeout: TimeInterval, startTimeout: TimeInterval, close: @escaping () -> Void, completion: @escaping (Reply) -> Void) {
            self.timeout = timeout; self.startTimeout = startTimeout; self.close = close; self.completion = completion
        }

        /// Fails the call if the helper has not answered `prepare` within `startTimeout`.
        func armStart() { arm(after: startTimeout, as: .failed) }

        /// Starts the reply deadline once the markup is on its way.
        func sent() { arm(after: timeout, as: .timedOut) }

        private func arm(after seconds: TimeInterval, as reply: Reply) {
            lock.lock(); generation += 1; let token = generation; lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
                lock.lock(); let current = generation == token; lock.unlock()
                if current { finish(reply) }
            }
        }

        /// Completes once, on the main queue, and closes the connection.
        func finish(_ reply: Reply) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            close()
            DispatchQueue.main.async { self.completion(reply) }
        }
    }
}
