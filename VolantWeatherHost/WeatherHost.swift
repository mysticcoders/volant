import CoreLocation
import Foundation
import VolantCore
import WeatherKit

/// Answers Volant's weather command with Apple's WeatherKit. Its inputs are coordinates the app has
/// already rounded to 0.1 degrees, or a place name `WeatherQuery` accepts; Apple's geocoder turns either
/// into a place and its time zone. Replies carry only a `WeatherReport`, never raw service responses, and
/// failures are `HostMessage` codes the app words in the owner's language.
/// The Apple Weather marks are fetched once, from the attribution URLs WeatherKit names, and only from
/// apple.com.
final class WeatherHost: NSObject, VolantWeatherHostProtocol {
    private static let hours = ExtensionItemForecast.maximumHours
    private static let days = ExtensionItemForecast.maximumDays
    private let attribution = AttributionCache()

    func weather(latitude: Double, longitude: Double, reply: @escaping (Data?, String?) -> Void) {
        guard let rounded = ExtensionLocation(latitude: latitude, longitude: longitude) else { return reply(nil, HostMessage(.weatherUnavailable).wire) }
        let location = CLLocation(latitude: rounded.latitude, longitude: rounded.longitude)
        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let coordinates = String(format: "%.1f, %.1f", rounded.latitude, rounded.longitude)
            await self.answer(location: location, placemark: placemark, fallbackName: coordinates, reply: reply)
        }
    }

    func weather(place: String, reply: @escaping (Data?, String?) -> Void) {
        guard WeatherQuery.validPlace(place) else { return reply(nil, HostMessage(.weatherNoPlace, place).wire) }
        Task {
            guard let placemark = try? await CLGeocoder().geocodeAddressString(place).first, let location = placemark.location else {
                return reply(nil, HostMessage(.weatherNoPlace, place).wire)
            }
            await self.answer(location: location, placemark: placemark, fallbackName: place, reply: reply)
        }
    }

    private func answer(location: CLLocation, placemark: CLPlacemark?, fallbackName: String, reply: @escaping (Data?, String?) -> Void) async {
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let zone = placemark?.timeZone ?? .current
            let label = placemark.map(Self.label) ?? ""
            let forecast = Self.forecast(weather, place: label.isEmpty ? fallbackName : label, zone: zone)
            let marks = await attribution.marks()
            let report = WeatherReport(forecast: forecast, legalURL: marks.legal, markLight: marks.light, markDark: marks.dark)
            reply(try JSONEncoder().encode(report), nil)
        } catch {
            reply(nil, HostMessage(.weatherUnavailable).wire)
        }
    }

    /// The card's data: current conditions, today's range, the hours from the current one on, and each
    /// day, in Celsius and the place's own wall-clock times.
    static func forecast(_ weather: Weather, place: String, zone: TimeZone) -> ExtensionItemForecast {
        let current = weather.currentWeather
        let hourStart = Calendar(identifier: .gregorian).dateInterval(of: .hour, for: current.date)?.start ?? current.date
        let hours = weather.hourlyForecast.forecast.filter { $0.date >= hourStart }.prefix(Self.hours).map { hour in
            ExtensionItemForecast.Hour(time: wallClock(hour.date, zone: zone, format: "yyyy-MM-dd'T'HH:mm"),
                                       temperature: celsius(hour.temperature), symbol: symbol(hour.condition, daylight: hour.isDaylight)?.rawValue)
        }
        let days = weather.dailyForecast.forecast.prefix(Self.days).map { day in
            ExtensionItemForecast.Day(date: wallClock(day.date, zone: zone, format: "yyyy-MM-dd"), high: celsius(day.highTemperature),
                                      low: celsius(day.lowTemperature), symbol: symbol(day.condition, daylight: true)?.rawValue)
        }
        return ExtensionItemForecast(place: place, condition: current.condition.description,
                                     symbol: symbol(current.condition, daylight: current.isDaylight)?.rawValue,
                                     temperature: celsius(current.temperature), high: days.first?.high, low: days.first?.low,
                                     hours: Array(hours), days: Array(days))
    }

    /// "Tokyo, Japan" or "Portland, Oregon": the locality and the region or country, without repeats.
    static func label(_ placemark: CLPlacemark) -> String {
        var parts: [String] = []
        for part in [placemark.locality ?? placemark.name, placemark.administrativeArea ?? placemark.country].compactMap({ $0 }) where !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: ", ")
    }

    /// The Volant row symbol for a WeatherKit condition, by day or by night.
    static func symbol(_ condition: WeatherCondition, daylight: Bool) -> ExtensionItemSymbol? {
        switch condition {
        case .clear, .mostlyClear: return daylight ? .sun : .moon
        case .partlyCloudy: return daylight ? .cloudSun : .cloudMoon
        case .mostlyCloudy, .cloudy: return .cloud
        case .foggy, .haze, .smoky, .blowingDust: return .fog
        case .drizzle, .sunShowers: return .drizzle
        case .rain: return .rain
        case .heavyRain, .tropicalStorm, .hurricane: return .heavyRain
        case .freezingDrizzle, .freezingRain, .sleet, .wintryMix, .hail: return .sleet
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow: return .snow
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms: return .thunderstorm
        case .breezy, .windy: return .wind
        case .hot: return .hot
        case .frigid: return .cold
        @unknown default: return nil
        }
    }

    private static func celsius(_ temperature: Measurement<UnitTemperature>) -> Double { temperature.converted(to: .celsius).value }

    private static func wallClock(_ date: Date, zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

}

/// The Apple Weather marks and legal link, fetched once per helper process from the URLs WeatherKit's
/// attribution names. Only https URLs on apple.com are read, each capped at 128 KB and kept only when it
/// is a PNG; a failure leaves the mark out and the card shows the legal link alone.
actor AttributionCache {
    private var loaded: (legal: String?, light: Data?, dark: Data?)?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func marks() async -> (legal: String?, light: Data?, dark: Data?) {
        if let loaded { return loaded }
        guard let attribution = try? await WeatherService.shared.attribution else { return (nil, nil, nil) }
        let legal = WeatherReport.isApple(attribution.legalPageURL) ? attribution.legalPageURL.absoluteString : nil
        async let light = mark(attribution.combinedMarkLightURL)
        async let dark = mark(attribution.combinedMarkDarkURL)
        let result = (legal, await light, await dark)
        loaded = result
        return result
    }

    private func mark(_ url: URL) async -> Data? {
        guard WeatherReport.isApple(url), let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= WeatherReport.maximumMarkBytes else { return nil }
        return data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? data : nil
    }
}
