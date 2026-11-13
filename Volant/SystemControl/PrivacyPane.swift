import Foundation

/// The Privacy & Security panes a launcher command may need the owner to visit after macOS
/// refused it: Camera for Open Camera, Automation for the System Events toggles, Accessibility for
/// Search Menu Items.
enum PrivacyPane: String, Hashable {
    case camera, automation, accessibility

    /// The anchor System Settings opens to, under its Privacy & Security pane.
    private static let paneURL = "x-apple.systempreferences:com.apple.preference.security?"

    var url: URL {
        switch self {
        case .camera: return URL(string: Self.paneURL + "Privacy_Camera")!
        case .automation: return URL(string: Self.paneURL + "Privacy_Automation")!
        case .accessibility: return URL(string: Self.paneURL + "Privacy_Accessibility")!
        }
    }

    var title: String {
        switch self {
        case .camera: return String(localized: "Open Camera Privacy Settings", comment: "Launcher row title: opens Privacy & Security › Camera")
        case .automation: return String(localized: "Open Automation Privacy Settings", comment: "Launcher row title: opens Privacy & Security › Automation")
        case .accessibility: return String(localized: "Open Accessibility Privacy Settings", comment: "Launcher row title: opens Privacy & Security › Accessibility")
        }
    }

    var detail: String {
        switch self {
        case .camera: return String(localized: "Privacy & Security › Camera", comment: "Launcher row subtitle for the Camera privacy settings row: where to turn on Volant")
        case .automation: return String(localized: "Privacy & Security › Automation", comment: "Launcher row subtitle for the Automation privacy settings row: where to turn on System Events for Volant")
        case .accessibility: return String(localized: "Privacy & Security › Accessibility", comment: "Launcher row subtitle for the Accessibility privacy settings row: where to turn on Volant")
        }
    }

    var sectionTitle: String {
        switch self {
        case .camera: return String(localized: "Camera", comment: "Launcher section title when camera access needs attention")
        case .automation: return String(localized: "Automation", comment: "Launcher section title when Automation access needs attention")
        case .accessibility: return String(localized: "Accessibility")
        }
    }

    var symbol: String {
        switch self {
        case .camera: return "camera"
        case .automation: return "gearshape.2"
        case .accessibility: return "accessibility"
        }
    }
}
