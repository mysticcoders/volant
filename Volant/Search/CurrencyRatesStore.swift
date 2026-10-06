import Foundation
import VolantCore

/// ECB exchange rates and CoinGecko crypto prices for the calculator. Nothing is fetched until the
/// owner types something shaped like a currency conversion; after that, ECB rates refresh at most
/// every twelve hours while conversions are used, and a failed fetch waits an hour before trying
/// again. Crypto prices are fetched only for conversions that name a coin, at most every ten
/// minutes, five after a failure and thirty after CoinGecko answers 429. They come from the keyless
/// public API, or with the owner's saved Demo key when there is one. Both are cached in the support
/// directory so conversions keep working offline. Fetching goes through the rates-only XPC helper,
/// since the app itself has no network access.
final class CurrencyRatesStore {
    private struct Cache: Codable {
        let rates: CurrencyRates
        let fetchedAt: Date
    }

    static let refreshInterval: TimeInterval = 12 * 3600
    static let retryInterval: TimeInterval = 3600
    static let cryptoRefreshInterval: TimeInterval = 600
    static let cryptoRetryInterval: TimeInterval = 300
    static let cryptoBusyInterval: TimeInterval = 1800
    static let keyAccount = "coingecko"

    private let cacheURL: URL
    private let cryptoCacheURL: URL
    private let now: () -> Date
    private let fetch: (@escaping (Data?) -> Void) -> Void
    private let fetchCrypto: (String?, @escaping (Data?, String?) -> Void) -> Void
    private let cryptoKey: () -> String?
    private var fetchedAt: Date?
    private var lastAttempt: Date?
    private var lastCryptoAttempt: Date?
    private var cryptoWait = CurrencyRatesStore.cryptoRetryInterval
    private var attemptedKey: String?
    private(set) var fetching = false
    private(set) var fetchingCrypto = false
    /// Called on the main queue when new rates arrive, so the launcher can redraw its answer.
    var onUpdate: () -> Void = {}

    init(cacheURL: URL = Preferences.supportDirectory.appendingPathComponent("currency-rates.json"),
         cryptoCacheURL: URL = Preferences.supportDirectory.appendingPathComponent("crypto-prices.json"),
         now: @escaping () -> Date = Date.init, fetch: ((@escaping (Data?) -> Void) -> Void)? = nil,
         fetchCrypto: ((String?, @escaping (Data?, String?) -> Void) -> Void)? = nil,
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
        if let data = try? Data(contentsOf: cryptoCacheURL), let prices = try? JSONDecoder().decode(CryptoPrices.self, from: data) {
            CryptoPrices.current = prices
        }
    }

    /// Lets the next coin query fetch right away when the saved key differs from the one last tried.
    /// Cached prices stay: they are the same public market data with or without a key, and keyless
    /// fetching continues. Other settings changes keep any wait in place.
    func keyChanged() {
        guard cryptoKey() != attemptedKey else { return }
        lastCryptoAttempt = nil
        cryptoWait = Self.cryptoRetryInterval
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
        guard !fetchingCrypto else { return }
        if let fetched = CryptoPrices.current?.fetchedAt, time.timeIntervalSince(fetched) < Self.cryptoRefreshInterval { return }
        if let lastCryptoAttempt, time.timeIntervalSince(lastCryptoAttempt) < cryptoWait { return }
        fetchingCrypto = true
        lastCryptoAttempt = time
        attemptedKey = cryptoKey()
        fetchCrypto(attemptedKey) { [weak self] data, message in
            DispatchQueue.main.async { self?.finishCrypto(data, message: message) }
        }
    }

    /// Installs and caches fetched prices, or sets how long to wait before the next attempt.
    private func finishCrypto(_ data: Data?, message: String?) {
        fetchingCrypto = false
        guard let data, let prices = CryptoPrices.parse(data, at: now()) else {
            cryptoWait = message == CryptoPrices.busyMessage ? Self.cryptoBusyInterval : Self.cryptoRetryInterval
            return
        }
        cryptoWait = Self.cryptoRetryInterval
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
        throughHelper({ data, _ in completion(data) }) { proxy, reply in proxy.fetchRates(reply: reply) }
    }

    private static func fetchCryptoThroughHelper(_ key: String?, _ completion: @escaping (Data?, String?) -> Void) {
        throughHelper(completion) { proxy, reply in proxy.fetchCrypto(key: key, reply: reply) }
    }

    /// One short-lived connection per fetch, answered once whether it replies, fails or times out.
    private static func throughHelper(_ completion: @escaping (Data?, String?) -> Void,
                                      _ call: (VolantRatesHostProtocol, @escaping (Data?, String?) -> Void) -> Void) {
        let connection = NSXPCConnection(serviceName: "com.mysticcoders.volant.RatesHost")
        connection.remoteObjectInterface = NSXPCInterface(with: VolantRatesHostProtocol.self)
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
        DispatchQueue.global().asyncAfter(deadline: .now() + 40) { finish(nil, nil) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in finish(nil, nil) } as? VolantRatesHostProtocol
        guard let proxy else { return finish(nil, nil) }
        call(proxy) { data, message in finish(data, message) }
    }
}
