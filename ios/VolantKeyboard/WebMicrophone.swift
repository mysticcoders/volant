import AVFoundation
import UIKit
import WebKit

/// Microphone capture for the keyboard through a hidden web view. iOS gives a keyboard extension no
/// microphone, and audio code in the keyboard's own process tends to get it killed, but a web view's
/// `getUserMedia` captures in WebKit's processes. The page downsamples to 16 kHz 16-bit mono and
/// posts base64 chunks here, which become `AVAudioPCMBuffer`s for `onBuffer`.
///
/// This is the technique Raycast published in November 2026 (also in KeyboardKit 11.3 and
/// stephancill/ios-keyboard-dictation). Apple has not documented it and may close it, so every
/// failure is reported and the caller falls back to dictating in the Volant app. It needs Full
/// Access and the microphone permission the app already holds. The page stops the microphone on
/// its own when heartbeats stop, so a keyboard that is dismissed or killed never leaves it open.
@MainActor
final class WebMicrophone: NSObject {
    enum Failure: LocalizedError {
        case failed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .failed(let reason): String(localized: "The keyboard could not open the microphone (\(reason)).")
            case .timedOut: String(localized: "The keyboard's microphone did not start in time.")
            }
        }
    }

    static let sampleRate = 16_000.0
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    static let startTimeout: Duration = .seconds(3)

    /// Receives each captured buffer on the main thread.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Told when the page stopped capturing by itself, such as when the microphone was taken.
    var onStop: (() -> Void)?

    private var webView: WKWebView?
    private var isLoaded = false
    private var starting: CheckedContinuation<Void, Error>?
    private var heartbeat: Task<Void, Never>?
    private(set) var isCapturing = false

    /// Adds the web view to `view`, nearly invisible but inside the window: WebKit throttles a web
    /// view outside one.
    func attach(to view: UIView) {
        guard webView == nil else {
            if let webView, webView.superview !== view { view.addSubview(webView) }
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(WeakMessageHandler(self), name: "capture")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        webView.isAccessibilityElement = false
        webView.uiDelegate = self
        webView.navigationDelegate = self
        view.addSubview(webView)
        self.webView = webView
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://volant-keyboard.invalid/"))
    }

    /// Opens the microphone and starts streaming buffers, or throws when the page cannot.
    func start() async throws {
        guard !isCapturing else { return }
        guard let webView else { throw Failure.failed("no web view") }
        for _ in 0..<40 where !isLoaded { try? await Task.sleep(for: .milliseconds(50)) }
        guard isLoaded else { throw Failure.timedOut }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.startTimeout)
            guard !Task.isCancelled else { return }
            self?.finishStarting(with: Failure.timedOut)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            starting = continuation
            webView.evaluateJavaScript("startCapture()", completionHandler: nil)
        }
        isCapturing = true
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                _ = try? await self?.webView?.evaluateJavaScript("captureHeartbeat()")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Closes the microphone.
    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        finishStarting(with: CancellationError())
        guard isCapturing else { return }
        isCapturing = false
        webView?.evaluateJavaScript("stopCapture()", completionHandler: nil)
    }

    private func finishStarting(with error: Error?) {
        guard let starting else { return }
        self.starting = nil
        if let error { starting.resume(throwing: error) } else { starting.resume() }
    }

    fileprivate func received(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "audio":
            guard isCapturing, let encoded = message["data"] as? String, let buffer = Self.buffer(fromBase64: encoded) else { return }
            onBuffer?(buffer)
        case "started":
            finishStarting(with: nil)
        case "error":
            finishStarting(with: Failure.failed(message["message"] as? String ?? "unknown"))
        case "stopped":
            if isCapturing {
                isCapturing = false
                heartbeat?.cancel()
                heartbeat = nil
                onStop?()
            }
        default:
            break
        }
    }

    /// 16-bit little-endian samples at 16 kHz as a float buffer, or nil for empty or odd data.
    static func buffer(fromBase64 encoded: String) -> AVAudioPCMBuffer? {
        guard let data = Data(base64Encoded: encoded), data.count >= 2 else { return nil }
        let count = data.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        data.withUnsafeBytes { raw in
            for index in 0..<count {
                channel[index] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768
            }
        }
        buffer.frameLength = AVAudioFrameCount(count)
        return buffer
    }

    /// The capture page. The AudioContext is made only when capture starts, since making it earlier
    /// can take audio focus or change the Bluetooth route. Samples are averaged down to 16 kHz with
    /// the fractional position carried between buffers.
    private static let page = """
    <!doctype html><html><head><meta charset="utf-8"></head><body><script>
    let context = null, stream = null, source = null, node = null, watchdog = null, lastBeat = 0, carry = 0;
    function post(message) { window.webkit.messageHandlers.capture.postMessage(message); }
    function captureHeartbeat() { lastBeat = Date.now(); }
    function encode(samples) {
      const bytes = new Uint8Array(samples.buffer);
      let binary = '';
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      return btoa(binary);
    }
    function downsample(input, ratio) {
      const out = [];
      let position = carry;
      while (position + ratio <= input.length) {
        const start = Math.max(0, Math.floor(position)), end = Math.max(start + 1, Math.floor(position + ratio));
        let sum = 0;
        for (let j = start; j < end; j++) sum += input[j];
        out.push(sum / (end - start));
        position += ratio;
      }
      carry = position - input.length;
      const samples = new Int16Array(out.length);
      for (let i = 0; i < out.length; i++) samples[i] = Math.max(-32768, Math.min(32767, Math.round(out[i] * 32767)));
      return samples;
    }
    async function startCapture() {
      try {
        if (navigator.audioSession) navigator.audioSession.type = 'play-and-record';
        stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false, channelCount: 1 } });
        context = new AudioContext();
        if (context.state === 'suspended') await context.resume();
        source = context.createMediaStreamSource(stream);
        node = context.createScriptProcessor(2048, 1, 1);
        const ratio = context.sampleRate / 16000;
        carry = 0;
        node.onaudioprocess = (event) => {
          const samples = downsample(event.inputBuffer.getChannelData(0), ratio);
          if (samples.length) post({ type: 'audio', data: encode(samples) });
        };
        source.connect(node);
        node.connect(context.destination);
        stream.getAudioTracks().forEach((track) => track.addEventListener('ended', () => stopCapture()));
        lastBeat = Date.now();
        watchdog = setInterval(() => { if (Date.now() - lastBeat > 3000) stopCapture(); }, 1000);
        post({ type: 'started' });
      } catch (error) {
        stopCapture(true);
        post({ type: 'error', message: String((error && error.name) || error) });
      }
    }
    function stopCapture(quiet) {
      if (watchdog) clearInterval(watchdog);
      watchdog = null;
      try { if (node) node.disconnect(); if (source) source.disconnect(); } catch (e) {}
      if (stream) stream.getTracks().forEach((track) => track.stop());
      if (context) context.close();
      node = source = stream = context = null;
      if (navigator.audioSession) navigator.audioSession.type = 'auto';
      if (!quiet) post({ type: 'stopped' });
    }
    </script></body></html>
    """
}

extension WebMicrophone: WKUIDelegate, WKNavigationDelegate {
    /// Grants the page the microphone. This only skips WebKit's own per-site prompt; the system
    /// permission is still the one the Volant app holds.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
    }
}

/// Forwards script messages without the content controller retaining the microphone.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebMicrophone?

    init(_ target: WebMicrophone) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { target?.received(body) }
    }
}
