import SwiftUI
import UIKit
import VolantCore

/// The Volant keyboard's layout, drawn from plain values so the keyboard and the app's setup preview
/// show the same thing: a dictation bar (Dictate and the style while idle; cancel, the live
/// transcript and finish while listening), snippet tiles or the style choices below it, and a row of
/// globe, space, delete and return keys.
struct KeyboardPanel: View {
    enum Bar: Equatable {
        case idle
        case starting(String)
        case listening(String)
        case finishing
    }

    let bar: Bar
    /// Shown in place of the snippets, for Full Access and other problems.
    let message: String?
    let snippets: [KeyboardSnippet]
    let style: DictationStyle
    let returnTitle: String?
    /// Recent microphone levels from 0 to 1, oldest first, drawn as the waveform while listening.
    var levels: [Double] = []
    /// When listening began, for the timer.
    var listeningSince: Date?
    /// The globe key, which must come from the input view controller; nil hides it.
    let globe: AnyView?
    var onDictate: () -> Void = {}
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}
    var onStyle: (DictationStyle) -> Void = { _ in }
    var onSnippet: (KeyboardSnippet) -> Void = { _ in }
    var onSpace: () -> Void = {}
    var onDelete: () -> Void = {}
    var onReturn: () -> Void = {}

    @State private var choosingStyle = false

    static let height: CGFloat = 262

    var body: some View {
        VStack(spacing: 10) {
            if bar == .idle {
                idleBar.frame(height: 64)
                Group {
                    if choosingStyle {
                        styleChoices
                    } else if let message {
                        MessageCard(text: message)
                    } else if snippets.isEmpty {
                        MessageCard(text: String(localized: "Snippets from Volant on your Mac appear here."))
                    } else {
                        snippetTiles
                    }
                }
                .frame(height: 112)
            } else {
                activeCard.frame(height: 186)
            }
            keyRow.frame(height: 44)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.2), value: bar == .idle)
        .onChange(of: bar) { _, new in if new != .idle { choosingStyle = false } }
    }

    /// Dictate and the style, the keyboard's resting state.
    private var idleBar: some View {
        HStack(spacing: 0) {
            Button(action: onDictate) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Brand.gradient)
                    Text("Dictate").font(.system(size: 21, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.leading, 22)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Dictate"))
            Button { choosingStyle.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: style.symbol).font(.system(size: 14))
                    Text(style.name).font(.system(size: 16))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Dictation Style, \(style.name)"))
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(Color.keyboardKey).shadow(color: .keyboardKeyShadow, radius: 0, y: 1))
    }

    /// The dictation in progress: cancel, what is happening with a timer, finish, the waveform, and
    /// the transcript so far.
    private var activeCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if bar == .finishing {
                    Color.clear.frame(width: 44, height: 44)
                } else {
                    CircleButton(symbol: "xmark", label: "Cancel Dictation", action: onCancel)
                }
                Spacer(minLength: 0)
                statusLine
                Spacer(minLength: 0)
                if case .listening = bar {
                    Button(action: onFinish) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Brand.gradient))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Finish Dictation"))
                } else {
                    ProgressView().frame(width: 52, height: 52)
                }
            }
            Waveform(levels: levels, live: { if case .listening = bar { return true }; return false }())
                .frame(height: 50)
                .accessibilityHidden(true)
            Text(transcript.isEmpty ? " " : transcript)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 42, alignment: .topLeading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.keyboardKey).shadow(color: .keyboardKeyShadow, radius: 0, y: 1))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch bar {
        case .listening:
            HStack(spacing: 8) {
                ListeningDot()
                Text("Listening").font(.system(size: 17, weight: .semibold))
                if let listeningSince {
                    TimelineView(.periodic(from: listeningSince, by: 1)) { context in
                        Text(Self.elapsed(from: listeningSince, to: context.date))
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .starting(let text):
            Text(text).font(.system(size: 16)).foregroundStyle(.secondary).lineLimit(1)
        case .finishing:
            Text("Finishing…").font(.system(size: 16)).foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var transcript: String {
        if case .listening(let text) = bar { return text }
        return ""
    }

    /// Minutes and seconds, such as 0:07.
    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var styleChoices: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(DictationStyle.allCases) { choice in
                Button {
                    onStyle(choice)
                    choosingStyle = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: choice.symbol).font(.system(size: 17)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(choice.name).font(.system(size: 15, weight: .medium))
                            Text(choice.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.keyboardKey))
                    .overlay {
                        if choice == style { RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.gradient, lineWidth: 2) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == style ? .isSelected : [])
            }
        }
    }

    /// Snippet tiles in two rows: two columns fill the width, and more scroll sideways with the
    /// next column peeking in.
    private var snippetTiles: some View {
        GeometryReader { geometry in
            let columns = snippets.count > 4 ? 2.4 : 2
            let width = (geometry.size.width - 8 * (columns.rounded(.up) - 1)) / columns
            tiles(width: max(120, width))
        }
    }

    private func tiles(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(52), spacing: 8), GridItem(.fixed(52), spacing: 8)], spacing: 8) {
                ForEach(snippets) { snippet in
                    Button { onSnippet(snippet) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "text.quote").font(.system(size: 14)).foregroundStyle(Brand.gradient)
                            Text(snippet.name).font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(width: width, height: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.keyboardKey))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Types this snippet"))
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var keyRow: some View {
        HStack(spacing: 6) {
            if let globe {
                globe
                    .frame(width: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.keyboardSpecialKey).shadow(color: .keyboardKeyShadow, radius: 0, y: 1))
            }
            PanelKey(fill: .keyboardKey, action: onSpace) { Text("space").font(.system(size: 16)) }
                .accessibilityLabel(Text("Space"))
            RepeatingKey(action: onDelete) { Image(systemName: "delete.left").font(.system(size: 19)) }
                .frame(width: 56)
                .accessibilityLabel(Text("Delete"))
            PanelKey(fill: .keyboardSpecialKey, action: onReturn) {
                if let returnTitle {
                    Text(returnTitle).font(.system(size: 16))
                } else {
                    Image(systemName: "return").font(.system(size: 19))
                }
            }
            .frame(width: 88)
            .accessibilityLabel(Text(returnTitle ?? String(localized: "Return")))
        }
    }
}

/// The microphone level over the last couple of seconds as rounded bars, newest on the right.
/// While not live it lies flat and faint, as a placeholder.
private struct Waveform: View {
    let levels: [Double]
    let live: Bool

    var body: some View {
        GeometryReader { geometry in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 3
            let width = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Brand.gradient)
                        .frame(width: width, height: max(width, CGFloat(live ? level : 0) * geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(live ? 1 : 0.35)
            .animation(.linear(duration: 0.08), value: levels)
        }
    }
}

/// A notice in the middle of the keyboard.
private struct MessageCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.keyboardKey.opacity(0.5)))
    }
}

/// A round button inside the dictation bar.
private struct CircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.keyboardSpecialKey))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// A pulsing dot that shows the microphone is live.
private struct ListeningDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Brand.gradient)
            .frame(width: 10, height: 10)
            .scaleEffect(pulse ? 1.3 : 0.8)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

/// A key that acts once when tapped.
private struct PanelKey<Label: View>: View {
    let fill: Color
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill).shadow(color: .keyboardKeyShadow, radius: 0, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .foregroundStyle(.primary)
    }
}

/// A key that acts once when pressed, then repeats while held, like delete on the system keyboard.
private struct RepeatingKey<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        label()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(repeater == nil ? Color.keyboardSpecialKey : Color.keyboardKey)
                .shadow(color: .keyboardKeyShadow, radius: 0, y: 1))
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard repeater == nil else { return }
                    action()
                    repeater = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        while !Task.isCancelled {
                            action()
                            try? await Task.sleep(for: .milliseconds(80))
                        }
                    }
                }
                .onEnded { _ in
                    repeater?.cancel()
                    repeater = nil
                })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Dims a key while it is pressed.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

extension Color {
    static let keyboardKey = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22) : .white })
    static let keyboardSpecialKey = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1) })
    static let keyboardKeyShadow = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.4) : UIColor(white: 0, alpha: 0.3) })
}

/// How each dictation style is named and drawn on iPhone. The layout rules live in VolantCore; the
/// names stay here because only the iPhone shows them.
extension DictationStyle {
    var name: String {
        switch self {
        case .plain: String(localized: "Plain", comment: "Dictation style: the transcript as spoken")
        case .message: String(localized: "Message", comment: "Dictation style: a chat message")
        case .email: String(localized: "Email", comment: "Dictation style: an email with greeting and paragraphs")
        case .notes: String(localized: "Notes", comment: "Dictation style: one bullet per sentence")
        }
    }

    var detail: String {
        switch self {
        case .plain: String(localized: "Exactly as you said it", comment: "Dictation style description")
        case .message: String(localized: "No closing period", comment: "Dictation style description")
        case .email: String(localized: "Greeting, paragraphs and sign-off on their own lines", comment: "Dictation style description")
        case .notes: String(localized: "One bullet per sentence", comment: "Dictation style description")
        }
    }

    var symbol: String {
        switch self {
        case .plain: "text.alignleft"
        case .message: "bubble.left"
        case .email: "envelope"
        case .notes: "list.bullet"
        }
    }
}
