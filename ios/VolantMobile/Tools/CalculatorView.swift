import SwiftUI
import VolantCore

/// The Mac launcher's calculator: VolantCore answers math, units, dates, time zones, colors,
/// percentages and cooking measures as you type. Tapping an answer copies it.
struct CalculatorView: View {
    @Environment(\.volantTheme) private var theme
    @State private var query = UserDefaults.standard.string(forKey: "fixtureQuery") ?? ""
    @State private var toast: String?
    @FocusState private var focused: Bool

    private static let examples = ["15% tip on 42", "5 km in mi", "3pm Tokyo in London", "days until Dec 25", "350f in c", "#ff7a5f"]

    var body: some View {
        let answers = CalculationAnswer.answers(for: query)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Type a calculation", text: $query, axis: .vertical)
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .focused($focused)
                    .padding(16)
                    .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Try").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.examples, id: \.self) { example in
                            Button(example) { query = example }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                } else if answers.isEmpty {
                    Text("No answer yet").foregroundStyle(.secondary).padding(.horizontal, 4)
                } else {
                    ForEach(answers, id: \.self) { answer in
                        AnswerCard(answer: answer) {
                            UIPasteboard.general.string = answer.copyText
                            toast = String(localized: "Copied \(answer.copyText)")
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = query.isEmpty }
        .toast($toast)
    }
}

/// One answer: the question as understood on the left, the result large on the right.
struct AnswerCard: View {
    let answer: CalculationAnswer
    let copy: () -> Void
    @Environment(\.volantTheme) private var theme

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let swatch = answer.swatch {
                        Circle().fill(Color(.sRGB, red: swatch.red, green: swatch.green, blue: swatch.blue, opacity: swatch.alpha))
                            .frame(width: 16, height: 16)
                    }
                    Text(answer.input).font(.subheadline).foregroundStyle(.secondary)
                    if let detail = answer.inputDetail { Text(detail).font(.caption).foregroundStyle(.tertiary) }
                }
                Text(answer.result)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                HStack {
                    if let detail = answer.resultDetail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Label("Copy", systemImage: "doc.on.doc").font(.caption.weight(.medium)).foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Lays out views left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
