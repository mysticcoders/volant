import SwiftUI
import VolantCore

/// First-launch welcome: three pages, each a live preview built from the app's own views over a
/// headline, then Get Started. There is no sign-in, because Volant has no accounts.
struct OnboardingView: View {
    let finish: () -> Void
    @State private var page = UserDefaults.standard.integer(forKey: "fixtureOnboardingPage")

    private struct Page {
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
    }

    private let pages = [
        Page(title: "Your notes,\nwherever you are", subtitle: "Plain Markdown that syncs with Volant on your Mac through iCloud."),
        Page(title: "Your Mac’s toolkit,\nin your pocket", subtitle: "Snippets, quicklinks and the calculator you set up on your Mac come along."),
        Page(title: "Your tools.\nYour say.", subtitle: "No Volant account. No telemetry. Your notes stay in your own iCloud.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            VolantMark(size: 34).padding(.top, 24)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 28) {
                        Spacer(minLength: 0)
                        preview(index)
                            .frame(maxWidth: 340)
                            .padding(.horizontal, 24)
                        Spacer(minLength: 0)
                        VStack(spacing: 12) {
                            Text(pages[index].title)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                            Text(pages[index].subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 28)
                    }
                    .padding(.bottom, 12)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            PageDots(count: pages.count, current: page).padding(.vertical, 18)
            HStack(spacing: 12) {
                if page < pages.count - 1 {
                    Button("Skip", action: finish)
                        .buttonStyle(OnboardingButtonStyle(prominent: false))
                    Button("Continue") { withAnimation { page += 1 } }
                        .buttonStyle(OnboardingButtonStyle(prominent: true))
                } else {
                    Button("Get Started", action: finish)
                        .buttonStyle(OnboardingButtonStyle(prominent: true))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [Brand.rust.opacity(0.28), .clear], center: .top, startRadius: 10, endRadius: 420)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .tint(Brand.coral)
    }

    @ViewBuilder
    private func preview(_ index: Int) -> some View {
        switch index {
        case 0: NotePreviewCard()
        case 1: ToolkitPreview()
        default: HeroMark(size: 150)
        }
    }
}

/// A sample note drawn with the real Markdown preview, in a phone-like card.
private struct NotePreviewCard: View {
    private let sample = """
    # Weekend plan
    Pick up the bikes on Saturday morning.
    - [x] Book the campsite
    - [ ] Pack the stove
    - [ ] Check the trail map
    """

    var body: some View {
        MarkdownPreview(source: sample)
            .padding(20)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .overlay(alignment: .topTrailing) {
                Label("iCloud", systemImage: "checkmark.icloud")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .offset(x: 10, y: -14)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
    }
}

/// A sample of the tools: a snippet, a quicklink and a live calculator answer.
private struct ToolkitPreview: View {
    var body: some View {
        VStack(spacing: 10) {
            row(.snippets, "Email signature", "sig")
            row(.quicklinks, "Search GitHub", "github.com")
            if let answer = CalculationAnswer.answers(for: "5 km in mi").first {
                row(.calculator, answer.result, answer.input)
            }
        }
        .padding(14)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
    }

    private func row(_ tool: Tool, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            ToolIcon(tool: tool, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Page indicator: the current page as a wide pill, the others as short ones.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.white.opacity(0.2)))
                    .frame(width: index == current ? 28 : 14, height: 6)
            }
        }
        .animation(.spring(duration: 0.35), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Full-width rounded buttons: white for the main action, glass for the other.
struct OnboardingButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(prominent ? .black : .white)
            .background {
                if prominent {
                    Capsule().fill(.white)
                } else {
                    Capsule().fill(.white.opacity(0.1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
