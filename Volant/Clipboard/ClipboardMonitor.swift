import AppKit
import VolantCore

/// Polls the general pasteboard's change count and records plain text that passes the filter.
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount

    init(store: ClipboardStore) { self.store = store }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = (pb.types ?? []).map(\.rawValue)
        guard PasteboardFilter.shouldRecord(types: types) else { return }
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.utf8.count <= 256_000 else { return }
            store.record(text)
            return
        }
        if let png = pb.data(forType: .png) ?? pb.data(forType: .tiff).flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }),
           png.count <= 8_000_000 {
            store.recordImage(png)
        }
    }
}
