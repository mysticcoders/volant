import SwiftUI

/// Shown over the app after the Volant keyboard opens it to listen: what was heard so far, and how
/// to get back to the app the owner was typing in, which iOS offers as the back link at the top
/// left. The owner can also stop or cancel here.
struct DictationScreen: View {
    @ObservedObject var service: DictationService
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Brand.gradient.opacity(0.25))
                    .frame(width: 168, height: 168)
                    .scaleEffect(pulse && service.state.phase == .listening ? 1.12 : 0.92)
                Circle()
                    .fill(Brand.gradient)
                    .frame(width: 120, height: 120)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title).font(.title2.weight(.semibold))
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            if !service.state.text.isEmpty {
                ScrollView {
                    Text(service.state.text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            }
            Spacer()

            VStack(spacing: 12) {
                if service.state.isActive {
                    Button {
                        Task { await service.stop() }
                    } label: {
                        Text("Stop").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Cancel", role: .cancel) {
                        service.cancel()
                        service.showingScreen = false
                    }
                } else {
                    Button {
                        service.showingScreen = false
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var symbol: String {
        switch service.state.phase {
        case .failed: "exclamationmark"
        case .done: "checkmark"
        default: "mic.fill"
        }
    }

    private var title: LocalizedStringKey {
        switch service.state.phase {
        case .preparing: "Getting Ready"
        case .listening: "Listening"
        case .finishing: "Finishing"
        case .done: "Done"
        case .failed: "Dictation Stopped"
        case .idle: "Not Listening"
        }
    }

    private var detail: String {
        switch service.state.phase {
        case .preparing:
            service.state.message ?? String(localized: "Opening the microphone.")
        case .listening, .finishing:
            String(localized: "Go back to the app you were typing in with the link at the top left, and keep talking. Tap Stop on the Volant keyboard when you're done.")
        case .done:
            String(localized: "Go back to the app you were typing in. The Volant keyboard types what you said.")
        case .failed:
            service.state.message ?? String(localized: "Dictation could not start.")
        case .idle:
            String(localized: "Tap the microphone on the Volant keyboard to dictate.")
        }
    }
}
