import Foundation

/// Cost-bounded, keyed by `PhotoRef.contentID`. Two instances: one for grid
/// thumbnails, one for full frames. Derived state only; can be emptied at any
/// time without losing anything.
///
/// The key is content rather than URL on purpose (D-45). A decode that started
/// before a rotate can finish after it, and under a URL key it would put the
/// pre-rotation frame back into the cache after the rotation cleared it. Under
/// a content key that late write lands on a key nothing will ask for again, and
/// the reader misses and decodes the file as it now is.
final class ImageCache: @unchecked Sendable {
    /// The two caches the app runs on, as one value so they are swapped
    /// together. Global mutable state is a dependency, so it is injectable
    /// (D-149), the way the caps-lock read and the pasteboard are (D-54).
    struct Pair: Sendable {
        let thumbnails: ImageCache
        let fulls: ImageCache

        init(thumbnailBytes: Int = 256 << 20, fullBytes: Int = 1 << 30) {
            thumbnails = ImageCache(limitBytes: thumbnailBytes)
            fulls = ImageCache(limitBytes: fullBytes)
        }

        /// What the app itself uses. Nothing binds `caches`, so every read in a
        /// running Sift resolves here.
        static let shared = Pair()
    }

    /// Task-local rather than a settable global: a test binds its own pair for
    /// the length of its own task tree, which is what makes a suite running in
    /// parallel with other suites deterministic. A settable static would still
    /// be one cache shared by every test running at that moment.
    @TaskLocal static var caches: Pair = .shared

    static var thumbnails: ImageCache { caches.thumbnails }
    static var fulls: ImageCache { caches.fulls }

    private final class Box { let image: DecodedImage; init(_ i: DecodedImage) { image = i } }
    private let cache = NSCache<NSString, Box>()

    init(limitBytes: Int) { cache.totalCostLimit = limitBytes }

    subscript(key: String) -> DecodedImage? {
        get { cache.object(forKey: key as NSString)?.image }
        set {
            if let newValue { cache.setObject(Box(newValue), forKey: key as NSString, cost: newValue.byteCost) }
            else { cache.removeObject(forKey: key as NSString) }
        }
    }

    func removeAll() { cache.removeAllObjects() }
}
