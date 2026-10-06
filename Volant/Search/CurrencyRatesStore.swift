import Foundation
import VolantCore

/// ECB exchange rates and, with the owner's CoinGecko key, crypto prices for the calculator.
/// Nothing is fetched until the owner types something shaped like a currency conversion; after
/// that, ECB rates refresh at most every twelve hours while conversions are used, and a failed
/// fetch waits an hour before trying again. Crypto prices are fetched only for conversions that
/// name a coin, only with a saved key, at most every ten minutes, five after a failure. Both are
/// cached in the support directory so conversions keep working offline. Fetching goes through the
/// rates-only XPC helper, since the app itself has no network access.
final class CurrencyRatesStore {
    private struct Cache: Codable {
        let rates: CurrencyRates
        let fetchedAt: Date
    }

    static let refreshInterval: TimeInterval = 12 * 3600
    static let retryInterval: TimeInterval = 3600
    static let cryptoRefreshInterval: TimeInterval = 600
    static let cryptoRetryInterval: TimeInterval = 300
    static let keyAccount = "coingecko"

    private let cacheURL: URL
    private let cryptoCacheURL: URL
    private let now: () -> Date
    private let fetch: (@escaping (Data?) -> Void) -> Void
    private let fetchCrypto: (String, @escaping (Data?) -> Void) -> Void
    private let cryptoKey: () -> String?
    private var fetchedAt: Date?
    private var lastAttempt: Date?
    private var lastCryptoAttempt: Date?
    private(set) var fetching = false
    private(set) var fetchingCrypto = false
    /// Called on the main queue when new rates arrive, so the launcher can redraw its answer.
    var onUpdate: () -> Void = {}

    init(cacheURL: URL = Preferences.supportDirectory.appendingPathComponent("currency-rates.json"),
         cryptoCacheURL: URL = Preferences.supportDirectory.appendingPathComponent("crypto-prices.json"),
         now: @escaping () -> Date = Date.init, fetch: ((@escaping (Data?) -> Void) -> Void)? = nil,
         fetchCrypto: ((String, @escaping (Data?) -> Void) -> Void)? = nil,
         cryptoKey: @escaping () -> String? = { (try? AICredentials.keychain.read(CurrencyRatesStore.keyAccount)) ?? nil }) {
        self.cacheURL = cacheURL
        self.cryptoCacheURL = cryptoCacheURL
        self.now = now
        self.fetch = fetch ?? Self.fetchThroughHelper
        self.fetchCrypto = fetchCrypto ?? Self.fetchCryptoThroughHelper
        self.cryptoKey = cryptoKey
    }

    /// Installs cached rates and prices, if any. Never touches the network.
    func loadCache() {
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            CurrencyRates.current = cache.rates
            fetchedAt = cache.fetchedAt
        }
        if cryptoKey() != nil, let data = try? Data(contentsOf: cryptoCacheURL), let prices = try? JSONDecoder().decode(CryptoPrices.self, from: data) {
            CryptoPrices.current = prices
        }
    }

    /// Drops crypto prices once the key is removed, so nothing from CoinGecko stays on screen or disk.
    func keyChanged() {
        guard cryptoKey() == nil else { return }
        CryptoPrices.current = nil
        lastCryptoAttempt = nil
        try? FileManager.default.removeItem(at: cryptoCacheURL)
    }

    /// The launcher's hook for every calculator query; only currency conversions can start a fetch,
    /// and only those naming a coin can fetch crypto prices.
    func noteQuery(_ query: String) {
        guard CurrencyConverter.looksLikeConversion(query) else { return }
        refreshIfNeeded()
        if CurrencyConverter.involvesCrypto(query) { refreshCryptoIfNeeded() }
    }

    func refreshCryptoIfNeeded() {
        let time = now()
        guard !fetchingCrypto, let key = cryptoKey() else { return }
        if let fetched = CryptoPrices.current?.fetchedAt, time.timeIntervalSince(fetched) < Self.cryptoRefreshInterval { return }
        if let lastCryptoAttempt, time.timeIntervalSince(lastCryptoAttempt) < Self.cryptoRetryInterval { return }
        fetchingCrypto = true
        lastCryptoAttempt = time
        fetchCrypto(key) { [weak self] data in
            DispatchQueue.main.async { self?.finishCrypto(data) }
        }
    }

    private func finishCrypto(_ data: Data?) {
        fetchingCrypto = false
        guard cryptoKey() != nil, let data, let prices = CryptoPrices.parse(data, at: now()) else { return }
        CryptoPrices.current = prices
        try? JSONEncoder().encode(prices).write(to: cryptoCacheURL, options: .atomic)
        onUpdate()
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

    private static func fetchThroughHelper(_ completion: @escaping (Data?) -> Void) {
        throughHelper(completion) { proxy, reply in proxy.fetchRates(reply: reply) }
    }

    private static func fetchCryptoThroughHelper(_ key: String, _ completion: @escaping (Data?) -> Void) {
        throughHelper(completion) { proxy, reply in proxy.fetchCrypto(key: key, reply: reply) }
    }

    /// One short-lived connection per fetch, answered once whether it replies, fails or times out.
    private static func throughHelper(_ completion: @escaping (Data?) -> Void,
                                      _ call: (VolantRatesHostProtocol, @escaping (Data?, String?) -> Void) -> Void) {
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
        call(proxy) { data, _ in finish(data) }
    }
}
