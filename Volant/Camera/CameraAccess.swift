import AVFoundation

/// Camera authorization as the launcher needs it, apart from AVFoundation so tests can supply
/// every state without a camera or a consent prompt.
enum CameraAuthorization: Equatable {
    case authorized, notDetermined, denied, restricted
}

protocol CameraAccess {
    /// Whether macOS reports any video capture device; checked before asking for permission.
    var hasCamera: Bool { get }
    var authorization: CameraAuthorization { get }
    /// Shows macOS's camera consent prompt; the completion runs on the main thread.
    func requestAccess(_ completion: @escaping (Bool) -> Void)
}

/// AVFoundation's camera authorization. Reading the status never prompts; only `requestAccess`
/// does, and the launcher calls it only when the owner chooses Open Camera.
struct SystemCameraAccess: CameraAccess {
    var hasCamera: Bool { CameraPreviewSession.defaultDevice() != nil }

    var authorization: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied
        }
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
