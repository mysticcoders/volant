import Foundation

/// The icons a list extension may give a row. The extension names one; Volant maps it to an SF Symbol
/// it draws itself, so a module never supplies images for rows. The set covers weather conditions and
/// temperature; anything else is dropped and the row shows the extension's icon.
public enum ExtensionItemSymbol: String, CaseIterable, Sendable {
    case sun, moon
    case cloudSun = "cloud-sun", cloudMoon = "cloud-moon", cloud
    case fog, drizzle, rain
    case heavyRain = "heavy-rain"
    case sleet, snow, thunderstorm, wind, hot, cold

    /// The SF Symbol Volant draws, in full color where the symbol has a multicolor variant.
    public var systemName: String {
        switch self {
        case .sun: "sun.max.fill"
        case .moon: "moon.stars.fill"
        case .cloudSun: "cloud.sun.fill"
        case .cloudMoon: "cloud.moon.fill"
        case .cloud: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .sleet: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .wind: "wind"
        case .hot: "thermometer.sun.fill"
        case .cold: "thermometer.snowflake"
        }
    }
}
