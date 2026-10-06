import SwiftUI
import VolantCore

/// A calculator answer drawn as two halves, the query and its result, each with a detail tag,
/// separated by an arrow; color answers show a swatch beside the query. Selection lightens the card rather than tinting it, and only semantic
/// colors are used so it follows light and dark appearances.
struct CalculatorCard: View {
    let answer: CalculationAnswer
    let rowID: String
    /// Lazy rows observe selection themselves; parent closure updates can retain stale styling.
    @ObservedObject var model: LauncherModel
    private var selected: Bool { model.selectedRow?.id == rowID }

    var body: some View {
        HStack(spacing: 0) {
            side(answer.input, detail: answer.inputDetail, swatch: answer.swatch)
            divider
            side(answer.result, detail: answer.resultDetail)
        }
        .frame(height: 118)
        .background(Color.primary.opacity(selected ? 0.10 : 0.05),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(answer.input + " equals " + answer.result)
        .accessibilityValue([answer.inputDetail, answer.resultDetail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// One half: the large text centered, with its tag below. The tag space is kept when there is
    /// no tag so both halves line up.
    private func side(_ text: String, detail: String?, swatch: CalculationAnswer.Swatch? = nil) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                if let swatch {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(.sRGB, red: swatch.red, green: swatch.green, blue: swatch.blue, opacity: swatch.alpha))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                        .frame(width: 30, height: 30)
                }
                Text(dimmedColons(text))
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }
            .padding(.horizontal, 18)
            Spacer(minLength: 10)
            Text(detail ?? " ")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(detail == nil ? 0 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(detail == nil ? 0 : 1)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
        }
        .frame(width: 32)
    }

    /// Colons in clock times read lighter, so "7:30" scans as one number.
    private func dimmedColons(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        var search = attributed.startIndex
        while let range = attributed[search...].range(of: ":") {
            attributed[range].foregroundColor = .secondary
            search = range.upperBound
        }
        return attributed
    }
}
