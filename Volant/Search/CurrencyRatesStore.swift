import Foundation
import VolantCore

/// ECB exchange rates for the calculator. Nothing is fetched until the owner types something
/// shaped like a currency conversion; after that, rates refresh at most every twelve hours while
/// conversions are used, and a failed fetch waits an hour before trying again. Rates are cached
/// with their date in the support directory, so conversions keep working offline. Fetching goes
/// through the rates-only XPC helper, since the app itself has no network access.
final class CurrencyRatesStore {
    private struct Cache: Codable {
        let rates: CurrencyRates
        let fetchedAt: Date
    }

    static let refreshInterval: TimeInterval = 12 * 3600
    static let retryInterval: TimeInterval = 3600

    private let cacheURL: URL
    private let now: () -> Date
    private let fetch: (@escaping (Data?) -> Void) -> Void
    private var fetchedAt: Date?
    private var lastAttempt: Date?
    private(set) var fetching = false
    /// Called on the main queue when new rates arrive, so the launcher can redraw its answer.
    var onUpdate: () -> Void = {}

    init(cacheURL: URL = Preferences.supportDirectory.appendingPathComponent("currency-rates.json"),
         now: @escaping () -> Date = Date.init, fetch: ((@escaping (Data?) -> Void) -> Void)? = nil) {
        self.cacheURL = cacheURL
        self.now = now
        self.fetch = fetch ?? Self.fetchThroughHelper
    }

    /// Installs cached rates, if any. Never touches the network.
    func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        CurrencyRates.current = cache.rates
        fetchedAt = cache.fetchedAt
    }

    /// The launcher's hook for every calculator query; only currency conversions can start a fetch.
    func noteQuery(_ query: String) {
        guard CurrencyConverter.looksLikeConversion(query) else { return }
        refreshIfNeeded()
    }

    func refreshIfNeeded() {
        let time = now()
        guard !fetching else { return }
        if let fetchedAt, time.timeIntervalSince(fetchedAt) < Self.refreshInterval { return }
        if let lastAttempt, time.timeIntervalSince(lastAttempt) < Self.retryInterval { return }
        fetching = true
        lastAttempt = time
        fetch { [weak self] data in
            DispatchQueue.main.async { self?.finish(data) }
        }
    }

    private func finish(_ data: Data?) {
        fetching = false
        guard let data, let rates = CurrencyRates.parse(data) else { return }
        let cache = Cache(rates: rates, fetchedAt: now())
        fetchedAt = cache.fetchedAt
        CurrencyRates.current = rates
        try? JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        onUpdate()
    }

    /// One short-lived connection per fetch, answered once whether it replies, fails or times out.
    private static func fetchThroughHelper(_ completion: @escaping (Data?) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.RatesHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantRatesHostProtocol.self)
        connection.resume()
        let lock = NSLock()
        var done = false
        let finish: (Data?) -> Void = { data in
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            guard first else { return }
            connection.invalidate()
            completion(data)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 40) { finish(nil) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in finish(nil) } as? VolantRatesHostProtocol
        guard let proxy else { return finish(nil) }
        proxy.fetchRates { data, _ in finish(data) }
    }
}
