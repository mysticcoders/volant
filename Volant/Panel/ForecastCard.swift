import SwiftUI
import VolantCore

/// A forecast drawn as a weather card, for the built-in weather command or a list extension row that
/// carries an `ExtensionItemForecast`: the current temperature, conditions, place and the day's range on
/// the leading side, and an hourly or daily strip beside it. Today and This Week switch the strip, by
/// clicking or with Tab while the card is selected. The built-in card adds the Apple Weather mark and
/// legal link that WeatherKit requires.
struct ForecastCard: View {
    let rowID: String
    let fallback: ExtensionItemForecast
    var attribution: WeatherReport?
    @ObservedObject var state: LauncherRowState
    @Environment(\.volantTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    private static let hourColumns = 8
    private static let dayColumns = 7

    private var forecast: ExtensionItemForecast {
        switch state.rowsByID[rowID] {
        case .extensionItem(let item, _)?: return item.forecast ?? fallback
        case .weather(_, .report(let report))?: return report.forecast
        default: return fallback
        }
    }
    private var selected: Bool { state.selectedID == rowID }
    private var hours: [ExtensionItemForecast.Hour] { Array((forecast.hours ?? []).prefix(Self.hourColumns)) }
    private var days: [ExtensionItemForecast.Day] { Array((forecast.days ?? []).prefix(Self.dayColumns)) }
    private var showsWeek: Bool { hours.isEmpty || (state.forecastShowsWeek && !days.isEmpty) }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            summary.frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                if !hours.isEmpty && !days.isEmpty { tabs }
                if showsWeek { dayStrip } else { hourStrip }
                if let attribution { attributionLine(attribution) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(height: attribution == nil ? 132 : 156, alignment: .top)
        .background(theme.card(selected: selected), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let temperature = forecast.temperature {
                    Text(ExtensionItemForecast.degrees(temperature)).font(.system(size: 34, weight: .semibold)).monospacedDigit()
                }
                if let symbol = forecast.symbol.flatMap(ExtensionItemSymbol.init(rawValue:)) {
                    ForecastSymbol(symbol: symbol, size: 24)
                }
            }
            Text(forecast.place).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            if let condition = forecast.condition {
                Text(condition).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let range { Text(range).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
        }
    }

    /// The day's high and low, from the forecast or else from today's entry in the week.
    private var range: String? {
        guard let high = forecast.high ?? forecast.days?.first?.high, let low = forecast.low ?? forecast.days?.first?.low else { return nil }
        let highText = ExtensionItemForecast.degrees(high), lowText = ExtensionItemForecast.degrees(low)
        return String(localized: "H: \(highText, format: .verbatim)  L: \(lowText, format: .verbatim)",
                      comment: "Weather card: today's high and low temperatures, such as H: 19° L: 9°")
    }

    /// The Apple Weather mark for this appearance and the link to Apple's data sources, as WeatherKit's
    /// terms require wherever its data shows.
    private func attributionLine(_ report: WeatherReport) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let data = colorScheme == .dark ? report.markDark : report.markLight, let mark = NSImage(data: data) {
                Image(nsImage: mark).resizable().scaledToFit().frame(height: 12)
                    .accessibilityLabel(String(localized: "Apple Weather", comment: "Accessibility label for the Apple Weather mark on the weather card"))
            }
            if let legal = report.legalURL.flatMap(URL.init(string:)) {
                Button(String(localized: "Data Sources", comment: "Weather card link to Apple Weather's legal attribution page")) { NSWorkspace.shared.open(legal) }
                    .buttonStyle(.link).font(.system(size: 11))
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab(String(localized: "Today", comment: "Weather card tab showing the hourly forecast"), week: false)
            tab(String(localized: "This Week", comment: "Weather card tab showing the daily forecast"), week: true)
        }
    }

    private func tab(_ title: String, week: Bool) -> some View {
        let chosen = showsWeek == week
        return Button { state.setForecastShowsWeek(week) } label: {
            Text(title)
                .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.primary.opacity(chosen ? 0.1 : 0), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var hourStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                column(ExtensionItemForecast.hourLabel(hour, index: index), emphasized: index == 0, symbol: hour.symbol) {
                    Text(ExtensionItemForecast.degrees(hour.temperature)).font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var dayStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                column(ExtensionItemForecast.dayLabel(day, index: index), emphasized: index == 0, symbol: day.symbol) {
                    HStack(spacing: 4) {
                        Text(ExtensionItemForecast.degrees(day.high)).font(.system(size: 14, weight: .semibold))
                        Text(ExtensionItemForecast.degrees(day.low)).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func column<Value: View>(_ label: String, emphasized: Bool, symbol: String?, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.system(size: 12, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)).lineLimit(1)
            Group {
                if let symbol = symbol.flatMap(ExtensionItemSymbol.init(rawValue:)) { ForecastSymbol(symbol: symbol, size: 18) }
                else { Color.clear }
            }
            .frame(height: 22)
            value().monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityLabel: String {
        let now = [forecast.temperature.map { ExtensionItemForecast.degrees($0) }, forecast.condition, range].compactMap { $0 }
        return ([forecast.place] + now).joined(separator: ", ")
    }
}

/// A weather symbol in full color, with the same soft edge row symbols use so white clouds stay
/// visible on a light card.
private struct ForecastSymbol: View {
    let symbol: ExtensionItemSymbol
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: symbol.systemName)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.45), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}
