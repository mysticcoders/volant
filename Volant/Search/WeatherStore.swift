import AppKit
import VolantCore

/// The weather command's forecasts. A weather query asks after typing pauses, so each keystroke never
/// becomes a WeatherKit request; each place's forecast is kept in memory for ten minutes and nothing is
/// written to disk. `weather` alone uses the owner's location through `ExtensionLocationProvider`, which
/// asks Location Services on first use only and rounds to 0.1 degrees before anything else sees it.
/// Requests go through the weather-only XPC helper, and a reply for a query the owner has since changed
/// is kept for that query's next use but never shown in place of the current one.
/// Used on the main thread only, like the launcher model that owns it.
final class WeatherStore {
    static let lifetime: TimeInterval = 10 * 60
    static let pause: TimeInterval = 0.45
    /// A failure is shown for half a minute, then asked again, so a refused location or an outage clears.
    static let messageLifetime: TimeInterval = 30
    private static let timeout: TimeInterval = 20

    /// A forecast ready to draw, or why there is none.
    enum Answer: Hashable {
        case report(WeatherReport)
        case message(String)
        /// `weather` alone, while Location Services is off or Volant is not allowed.
        case needsLocation
    }

    var onUpdate: () -> Void = {}
    private var answers: [String: (answer: Answer, expires: Date)] = [:]
    private var wanted: WeatherQuery?
    private var pending: DispatchWorkItem?
    private var inFlight: Set<String> = []
    private let fetch: (WeatherQuery, ExtensionLocation?, @escaping (Data?, String?) -> Void) -> Void
    private let locate: (@escaping (ExtensionLocation?) -> Void) -> Void
    private let now: () -> Date

    init(fetch: @escaping (WeatherQuery, ExtensionLocation?, @escaping (Data?, String?) -> Void) -> Void = WeatherStore.throughHelper,
         locate: @escaping (@escaping (ExtensionLocation?) -> Void) -> Void = { completion in MainActor.assumeIsolated { ExtensionLocationProvider.shared.locate(completion) } },
         now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.locate = locate
        self.now = now
    }

    /// The answer for `query` if one is still fresh, otherwise nil while it is asked for. Asking waits
    /// for typing to pause, and a later call for another query replaces the wait.
    func answer(for query: WeatherQuery) -> Answer? {
        if let entry = answers[query.key], now() < entry.expires { return entry.answer }
        guard wanted != query else { return nil }
        wanted = query
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start(query) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pause, execute: work)
        return nil
    }

    /// Forgets which query is wanted, so nothing arrives for a launcher that was dismissed or moved on.
    func cancel() {
        pending?.cancel()
        pending = nil
        wanted = nil
    }

    private func start(_ query: WeatherQuery) {
        guard wanted == query, !inFlight.contains(query.key) else { return }
        inFlight.insert(query.key)
        switch query {
        case .place: request(query, location: nil)
        case .here:
            locate { [weak self] location in
                guard let self else { return }
                guard let location else { return self.finish(query, .needsLocation) }
                self.request(query, location: location)
            }
        }
    }

    private func request(_ query: WeatherQuery, location: ExtensionLocation?) {
        fetch(query, location) { data, message in
            DispatchQueue.main.async { [weak self] in
                let answer: Answer = data.flatMap(WeatherReport.decode).map(Answer.report)
                    ?? .message(HostMessage.display(message) ?? HostMessage(.weatherUnavailable).text)
                self?.finish(query, answer)
            }
        }
    }

    private func finish(_ query: WeatherQuery, _ answer: Answer) {
        inFlight.remove(query.key)
        let lifetime = if case .report = answer { Self.lifetime } else { Self.messageLifetime }
        answers[query.key] = (answer, now().addingTimeInterval(lifetime))
        guard wanted == query else { return }
        wanted = nil
        onUpdate()
    }

    /// One short-lived connection per forecast, answered once whether it replies, fails or times out.
    static func throughHelper(_ query: WeatherQuery, _ location: ExtensionLocation?, _ completion: @escaping (Data?, String?) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.WeatherHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantWeatherHostProtocol.self)
        connection.resume()
        let lock = NSLock()
        var done = false
        let finish: (Data?, String?) -> Void = { data, message in
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            guard first else { return }
            connection.invalidate()
            completion(data, message)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil, nil) }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(nil, nil) }) as? VolantWeatherHostProtocol else {
            return finish(nil, nil)
        }
        switch query {
        case .here:
            guard let location else { return finish(nil, nil) }
            proxy.weather(latitude: location.latitude, longitude: location.longitude, reply: finish)
        case .place(let place):
            proxy.weather(place: place, reply: finish)
        }
    }
}
