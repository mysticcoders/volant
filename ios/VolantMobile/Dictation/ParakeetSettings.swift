import FluidAudio
import SwiftUI

/// Downloads the optional Parakeet model into the App Group and prepares it for the Neural Engine,
/// reporting progress for Settings. The download comes from Hugging Face (FluidInference's Core ML
/// build); nothing else leaves the device.
@MainActor
final class ParakeetDownloader: ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double, String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = ParakeetModel.isDownloaded ? .ready : .notDownloaded
    private var task: Task<Void, Never>?

    func download() {
        guard task == nil, let directory = ParakeetModel.directory else { return }
        state = .downloading(0, String(localized: "Starting…"))
        task = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try await AsrModels.download(to: directory, version: ParakeetModel.version) { progress in
                    Task { @MainActor in self?.report(progress) }
                }
                var url = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
                self?.state = ParakeetModel.isDownloaded ? .ready : .failed(String(localized: "The download finished incomplete."))
            } catch is CancellationError {
                self?.state = .notDownloaded
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    func delete() {
        task?.cancel()
        do {
            try ParakeetModel.delete()
            state = .notDownloaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func report(_ progress: DownloadProgress) {
        guard task != nil else { return }
        let detail: String
        switch progress.phase {
        case .listing: detail = String(localized: "Finding files…")
        case .downloading(let done, let total): detail = String(localized: "Downloading \(done) of \(total) files…")
        case .compiling: detail = String(localized: "Preparing for the Neural Engine…")
        }
        state = .downloading(progress.fractionCompleted, detail)
    }
}

/// Settings › Dictation Keyboard › Speech Model: Apple's engine by default, or the downloaded
/// Parakeet model for the final text.
struct ParakeetSettingsSection: View {
    @StateObject private var downloader = ParakeetDownloader()
    @AppStorage(ParakeetModel.enabledKey, store: KeyboardDictationSettings.defaults) private var usesParakeet = false

    var body: some View {
        Section {
            Toggle(isOn: $usesParakeet) {
                SettingsRow(symbol: "globe", title: "Parakeet (25 Languages)", value: nil)
            }
            if usesParakeet {
                switch downloader.state {
                case .notDownloaded:
                    Button { downloader.download() } label: {
                        SettingsRow(symbol: "arrow.down.circle", title: "Download Model", value: ParakeetModel.approximateSize)
                    }
                    .buttonStyle(.row)
                case .downloading(let fraction, let detail):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: fraction)
                        HStack {
                            Text(detail).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") { downloader.cancel() }.font(.footnote)
                        }
                    }
                case .ready:
                    SettingsRow(symbol: "checkmark.circle", title: "Model Ready", value: ParakeetModel.approximateSize)
                    Button(role: .destructive) { downloader.delete() } label: {
                        SettingsRow(symbol: "trash", title: "Delete Model", value: nil)
                    }
                    .buttonStyle(.row)
                case .failed(let reason):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Download failed").foregroundStyle(.red)
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { downloader.download() } label: {
                        SettingsRow(symbol: "arrow.clockwise", title: "Try Again", value: nil)
                    }
                    .buttonStyle(.row)
                }
            }
        } header: {
            Text("Speech Model")
        } footer: {
            Text("Apple's engine shows your words while you speak. With Parakeet on, Parakeet Ultra writes the final text: more accurate, and it recognizes 25 European languages. It downloads once from Hugging Face over the internet (Wi-Fi recommended); dictation then stays on this iPhone. The keyboard prepares it once, for about 15 seconds, and uses Apple's text until it's ready.")
        }
    }
}
