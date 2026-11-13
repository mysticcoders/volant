import AppKit
import ImageIO
import VolantCore

/// Image previews for list extension rows that carry an `image` (see `ExtensionItemImage`). A row asks
/// for its image only when it appears on screen. Each list starts at most
/// `ExtensionItemImage.maximumFetchesPerList` fetches, at most `maximumConcurrentFetches` run at once,
/// and a result that arrives after the launcher moved on to another list, or left it, is dropped.
///
/// The fetch helper decodes downloads; this class accepts only the helper's small PNG thumbnails
/// (`thumbnail`). Thumbnails, and fetches that failed, are kept in memory for the session by extension
/// and URL, at most `maximumCachedImages` entries and `maximumCachedBytes` of pixels, least recently
/// used first out, and are never written to disk. A cached image is shown again only after the
/// extension and host pass the same checks as a fetch.
final class ExtensionRowImages: ObservableObject {
    /// The images the rows of the current list show, by `key`.
    @Published private(set) var shown: [String: NSImage] = [:]
    /// Loads one image through `ExtensionManager.loadRowImage`; the launcher supplies it.
    var load: (InstalledExtension, String, @escaping (ExtensionManager.RowImageOutcome) -> Void) -> Void = { _, _, done in done(.refused) }
    /// Whether the extension may show an image from this URL right now (`ExtensionManager.rowImageURL`).
    var authorize: (InstalledExtension, String) -> Bool = { _, _ in false }

    private struct Entry { let image: NSImage?; let bytes: Int }
    private var cache: [String: Entry] = [:]
    private var recency: [String] = []
    private(set) var cachedBytes = 0
    /// Changes with every new list, so rows that stay on screen across lists ask for their image again.
    @Published private(set) var list = 0
    private var startedInList = 0
    private var requested: Set<String> = []
    private var queue: [(key: String, ext: InstalledExtension, url: String)] = []
    private(set) var inFlight = 0

    var cachedCount: Int { cache.count }

    static func key(_ url: String, _ ext: InstalledExtension) -> String { ext.id + "\u{0}" + url }

    /// The loaded image for a row of the current list, or nil while it loads, when it failed, or when it
    /// was never requested.
    func image(_ url: String, for ext: InstalledExtension) -> NSImage? { shown[Self.key(url, ext)] }

    /// Starts a new list, or leaves the current one: forgets what it requested and showed, cancels its
    /// queued fetches, and makes the results of fetches still running be dropped when they arrive.
    func reset() {
        list += 1
        startedInList = 0
        requested = []
        queue = []
        if !shown.isEmpty { shown = [:] }
    }

    /// Called when a row with this image appears. Shows a cached image after checking the extension and
    /// host again, or queues a fetch while the list has fetches left. A row asks once per list.
    func request(_ url: String, for ext: InstalledExtension) {
        let key = Self.key(url, ext)
        guard requested.insert(key).inserted else { return }
        if let entry = cache[key] {
            touch(key)
            if let image = entry.image, authorize(ext, url) { shown[key] = image }
            return
        }
        guard startedInList < ExtensionItemImage.maximumFetchesPerList else { return }
        startedInList += 1
        queue.append((key, ext, url))
        pump()
    }

    /// Starts queued fetches while fewer than the concurrent limit run.
    private func pump() {
        while inFlight < ExtensionItemImage.maximumConcurrentFetches, !queue.isEmpty {
            let next = queue.removeFirst(), list = self.list
            inFlight += 1
            load(next.ext, next.url) { [weak self] outcome in
                guard let self else { return }
                self.inFlight -= 1
                defer { self.pump() }
                guard list == self.list else { return }
                switch outcome {
                case .image(let image):
                    self.store(next.key, image)
                    self.shown[next.key] = image
                case .failed: self.store(next.key, nil)
                case .refused, .stopped: self.requested.remove(next.key)
                }
            }
        }
    }

    /// Caches a thumbnail, or a failure as nil, then evicts the least recently used entries past the bounds.
    private func store(_ key: String, _ image: NSImage?) {
        if let old = cache.removeValue(forKey: key) { cachedBytes -= old.bytes; recency.removeAll { $0 == key } }
        let bytes = image.map { Int($0.size.width) * Int($0.size.height) * 4 } ?? 0
        cache[key] = Entry(image: image, bytes: bytes)
        recency.append(key)
        cachedBytes += bytes
        while cache.count > ExtensionItemImage.maximumCachedImages || cachedBytes > ExtensionItemImage.maximumCachedBytes, let oldest = recency.first {
            recency.removeFirst()
            cachedBytes -= cache.removeValue(forKey: oldest)?.bytes ?? 0
        }
    }

    /// Marks a cached entry as just used.
    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    /// The image for a thumbnail the fetch helper returned, or nil. Only a single-frame PNG of at most
    /// `ExtensionItemImage.maximumThumbnailBytes` and at most `thumbnailPixels` on each side is decoded;
    /// anything else, even from the helper, is refused.
    static func thumbnail(_ data: Data) -> NSImage? {
        let limit = ExtensionItemImage.thumbnailPixels
        guard ExtensionItemImage.looksLikeThumbnail(data),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...limit).contains(width), (1...limit).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == width, image.height == height else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
