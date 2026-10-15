import CoreLocation
import VolantCore

/// Finds the owner's approximate location for list extensions they allowed to receive it. Location
/// Services is asked only when such an extension first runs, never at startup. Each fix is rounded to
/// 0.1 degrees before anything else sees it, kept in memory for at most 15 minutes so repeated runs stay
/// fast, and never written or logged. A refused or failed lookup answers nil and the extension runs
/// without a location.
@MainActor
final class ExtensionLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = ExtensionLocationProvider()
    private static let lifetime: TimeInterval = 15 * 60
    private static let timeout: TimeInterval = 10

    private var manager: CLLocationManager?
    private var cached: (location: ExtensionLocation, at: Date)?
    private var waiting: [(ExtensionLocation?) -> Void] = []
    private var deadline: DispatchWorkItem?

    /// Calls `completion` on the main queue with the rounded location, or nil when Location Services is
    /// off, Volant is not allowed, or no fix arrives within ten seconds.
    func locate(_ completion: @escaping (ExtensionLocation?) -> Void) {
        if let cached, Date().timeIntervalSince(cached.at) < Self.lifetime { completion(cached.location); return }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        let manager = self.manager ?? CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        let deadline = DispatchWorkItem { [weak self] in self?.finish(nil) }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: deadline)
        request(manager)
    }

    private func request(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: finish(nil)
        }
    }

    private func finish(_ location: ExtensionLocation?) {
        deadline?.cancel(); deadline = nil
        if let location { cached = (location, Date()) }
        let callbacks = waiting; waiting = []
        callbacks.forEach { $0(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard !waiting.isEmpty, manager.authorizationStatus != .notDetermined else { return }
            request(manager)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let rounded = locations.last.flatMap { ExtensionLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        MainActor.assumeIsolated { finish(rounded) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}
