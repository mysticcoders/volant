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

/// Settings › Dictation Keyboard › Speech Model: Apple's engine, or Parakeet once downloaded.
struct SpeechModelView: View {
    @StateObject private var downloader = ParakeetDownloader()
    @AppStorage(ParakeetModel.enabledKey, store: KeyboardDictationSettings.defaults) private var usesParakeet = false

    var body: some View {
        List {
            Section {
                choice(title: "Apple", detail: "Built in, your device's language", selected: !usesParakeet) { usesParakeet = false }
                choice(title: "Parakeet", detail: "More accurate, 25 languages", selected: usesParakeet) { usesParakeet = true }
            } footer: {
                Text("Both run on this iPhone.")
            }

            if usesParakeet {
                Section {
                    switch downloader.state {
                    case .notDownloaded:
                        Button { downloader.download() } label: {
                            SettingsRow(symbol: "arrow.down.circle", title: "Download", value: ParakeetModel.approximateSize)
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
                        SettingsRow(symbol: "checkmark.circle", title: "Downloaded", value: ParakeetModel.approximateSize)
                        Button(role: .destructive) { downloader.delete() } label: {
                            SettingsRow(symbol: "trash", title: "Delete", value: nil)
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
                } footer: {
                    Text(downloader.state == .ready
                         ? "Words appear as you speak; Parakeet writes the final text."
                         : "One-time download. Wi-Fi recommended.")
                }
            }
        }
        .navigationTitle("Speech Model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice(title: LocalizedStringKey, detail: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .buttonStyle(.row)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
