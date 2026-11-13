import AppKit
import AVFoundation

/// One capture session from the default camera to a preview layer. Nothing is recorded, saved or
/// sent: there is no output besides the on-screen layer. Starting and stopping run on a private
/// serial queue because `startRunning` blocks until the camera is on.
final class CameraPreviewSession {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.mysticcoders.volant.camera-preview")
    private var configured = false

    /// The built-in camera when there is one, otherwise the system's default video device.
    static func defaultDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                         mediaType: .video, position: .unspecified)
        return discovery.devices.first { $0.deviceType == .builtInWideAngleCamera } ?? AVCaptureDevice.default(for: .video) ?? discovery.devices.first
    }

    /// Adds the default camera once, then starts the session; reports false on the main thread
    /// when no camera input could be added.
    func start(_ completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .high
                if let device = Self.defaultDevice(), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                    session.addInput(input)
                    configured = true
                }
                session.commitConfiguration()
            }
            guard configured else { DispatchQueue.main.async { completion(false) }; return }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { completion(true) }
        }
    }

    /// Turns the camera off; its indicator light goes out once the session stops.
    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// A small floating window with a mirrored live preview of the default camera, like a mirror
/// before a call. Escape or the close button closes it, and the camera stops whenever the window
/// closes or is hidden, so the camera is never on without the window on screen.
final class CameraPreviewWindow: NSPanel, NSWindowDelegate {
    static let contentSize = NSSize(width: 360, height: 270)
    private let preview = CameraPreviewSession()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let message = NSTextField(labelWithString: "")
    /// Called when starting the camera fails, so the launcher can explain it.
    var onFailure: (String) -> Void = { _ in }

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: preview.session)
        super.init(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                   backing: .buffered, defer: false)
        title = String(localized: "Camera", comment: "Camera preview window title")
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = Self.contentSize
        contentMinSize = NSSize(width: 240, height: 180)
        delegate = self
        let view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(previewLayer)
        message.textColor = .white
        message.alignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32)
        ])
        contentView = view
        setAccessibilityLabel(String(localized: "Camera preview", comment: "Accessibility label of the camera preview window"))
    }

    override var canBecomeKey: Bool { true }

    /// Places the window near the top right of the screen with the pointer, brings it forward and
    /// starts the camera. Showing it again while open only brings it forward.
    func present() {
        if !isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 24, y: visible.maxY - frame.height - 24))
            }
        }
        message.stringValue = String(localized: "Starting camera…", comment: "Camera preview placeholder while the camera turns on")
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        preview.start { [weak self] started in
            guard let self, self.isVisible else { self?.preview.stop(); return }
            guard started else {
                self.close()
                self.onFailure(String(localized: "Couldn’t start the camera. Another app may be using it.", comment: "Launcher message when the camera fails to start"))
                return
            }
            self.message.stringValue = ""
            if let connection = self.previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    /// Escape closes the preview, like the launcher.
    override func cancelOperation(_ sender: Any?) { close() }

    override func orderOut(_ sender: Any?) {
        preview.stop()
        super.orderOut(sender)
    }

    func windowWillClose(_ notification: Notification) { preview.stop() }
}
