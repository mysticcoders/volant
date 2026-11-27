import SwiftUI
import VolantCore

/// A short walkthrough for adding the Volant keyboard: what it does, with a live preview of the
/// keyboard itself; how to turn it on with Full Access; and a field to try it in, which confirms
/// once the keyboard shows up with Full Access and once text has been dictated into it.
struct KeyboardSetupFlow: View {
    enum Page: Int { case intro, enable, tryIt }

    @State var page: Page
    @ObservedObject private var service = DictationService.shared
    @State private var trial = ""
    @State private var started = Date()
    @FocusState private var trialFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(page: Page = .intro) {
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch page {
                case .intro: intro
                case .enable: enable
                case .tryIt: tryIt
                }
            }
            .padding(.horizontal, 24)
            .animation(.default, value: page)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                if page != .intro {
                    ToolbarItem(placement: .navigation) {
                        Button { page = Page(rawValue: page.rawValue - 1) ?? .intro } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel(Text("Back"))
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 24) {
            KeyboardPreview()
                .padding(.top, 8)
            Text("Dictate in any app with Volant")
                .font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "waveform", text: "Speech is transcribed on device, with your vocabulary from Volant on your Mac.")
                Feature(symbol: "envelope", text: "Pick a style to lay it out as a message, an email or notes.")
                Feature(symbol: "text.quote", text: "Your Mac snippets are one tap away.")
            }
            Spacer(minLength: 0)
            PrimaryButton(title: "Set Up Keyboard") { page = .enable }
        }
    }

    private var enable: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Turn on the Volant keyboard")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 16) {
                NumberedStep(number: 1, text: "Open Settings")
                NumberedStep(number: 2, text: "Tap Keyboards")
                NumberedStep(number: 3, text: "Turn on Volant")
                NumberedStep(number: 4, text: "Turn on Allow Full Access")
            }
            Text("Full Access lets the keyboard open Volant to listen and read back what you said, because iOS never lets a keyboard use the microphone itself. iOS warns that a keyboard with Full Access could send what you type; Volant's keyboard sends nothing over the network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                PrimaryButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("I've Turned It On") { page = .tryIt }
                    .font(.body.weight(.medium))
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Try it")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 8)
            Text(tryStatus.text)
                .font(.body)
                .foregroundStyle(tryStatus.done ? .primary : .secondary)
                .contentTransition(.opacity)
            HStack(spacing: 8) {
                Image(systemName: tryStatus.done ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(tryStatus.done ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.tertiary))
                Text(tryStatus.done ? "Volant keyboard is working" : tryStatus.needsFullAccess ? "Full Access is off" : "Waiting for the Volant keyboard")
                    .font(.subheadline.weight(.medium))
            }
            TextField("Dictate here", text: $trial, axis: .vertical)
                .lineLimit(4...8)
                .focused($trialFocused)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
            if tryStatus.done {
                PrimaryButton(title: "Done") { dismiss() }
            }
            Spacer(minLength: 0)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            trialFocused = true
        }
    }

    /// Where the trial stands: the keyboard not seen yet, seen without Full Access, seen and ready,
    /// or text typed with it.
    private var tryStatus: (text: String, done: Bool, needsFullAccess: Bool) {
        let shown = service.keyboardLastShown.flatMap { $0.date >= started ? $0 : nil }
        let ready = shown?.fullAccess ?? ((KeyboardPresence.lastSeen ?? .distantPast) >= started)
        if ready && !trial.isEmpty {
            return (String(localized: "You're all set. Switch to the Volant keyboard whenever you want to dictate."), true, false)
        }
        if let shown, !shown.fullAccess {
            return (String(localized: "The keyboard is on, but Allow Full Access is off. Turn it on in Settings › Apps › Volant › Keyboards."), false, true)
        }
        if ready {
            return (String(localized: "Tap Dictate on the keyboard, say something, then tap the checkmark."), false, false)
        }
        return (String(localized: "Touch and hold the globe key below the keyboard and choose Volant."), false, false)
    }
}

/// The real keyboard layout with sample snippets, drawn on a keyboard-colored panel.
/// `-fixtureKeyboardListening YES` draws it listening, with a sample waveform and transcript.
struct KeyboardPreview: View {
    private static let listening = UserDefaults.standard.bool(forKey: "fixtureKeyboardListening")
    private static let sampleLevels: [Double] = (0..<40).map { index in
        let x = Double(index)
        return max(0.08, min(1, 0.45 + 0.35 * sin(x * 0.7) * cos(x * 0.23) + 0.15 * sin(x * 2.1)))
    }

    private static let samples = [
        KeyboardSnippet(name: String(localized: "Home address"), body: ""),
        KeyboardSnippet(name: String(localized: "Meeting link"), body: ""),
        KeyboardSnippet(name: String(localized: "Sign-off"), body: ""),
        KeyboardSnippet(name: String(localized: "Running late"), body: ""),
    ]

    var body: some View {
        KeyboardPanel(bar: Self.listening ? .listening(String(localized: "Hi Sam, I looked at the draft and it reads well")) : .idle,
                      message: nil, snippets: Self.samples, style: .email, returnTitle: nil,
                      levels: Self.listening ? Self.sampleLevels : [], listeningSince: Self.listening ? Date().addingTimeInterval(-7) : nil,
                      globe: AnyView(Image(systemName: "globe").font(.system(size: 19)).frame(maxHeight: .infinity)))
            .frame(height: KeyboardPanel.height)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 28).fill(Color(uiColor: .systemGray5)))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Preview of the Volant keyboard: a Dictate bar with the Email style, snippet tiles, and space, delete and return keys."))
    }
}

private struct Feature: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Brand.gradient).frame(width: 24)
            Text(text)
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
            Text(text).font(.title3)
        }
    }
}

private struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
