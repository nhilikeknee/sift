import Foundation

/// Keeps the ±N neighbors of the cursor decoded at full size (D-6).
@MainActor
final class Prefetcher {
    /// Keyed by content, like the caches: a rotated photo is a different thing
    /// to fetch, not the same one again.
    private var inFlight: [String: Task<Void, Never>] = [:]

    func warm(_ photos: [PhotoRef], around index: Int, radius: Int = Tokens.Layout.prefetchRadius) {
        let lo = max(0, index - radius), hi = min(photos.count - 1, index + radius)
        guard lo <= hi else { return }
        let wanted = Set(photos[lo...hi].map(\.contentID))

        for (key, task) in inFlight where !wanted.contains(key) {
            task.cancel()
            inFlight[key] = nil
        }
        // Nearest first: the cursor, then ±1, then ±2...
        let order = (lo...hi).sorted { abs($0 - index) < abs($1 - index) }
        for i in order {
            let url = photos[i].url
            let key = photos[i].contentID
            guard ImageCache.fulls[key] == nil, inFlight[key] == nil else { continue }
            inFlight[key] = Task { [weak self] in
                // `ahead`, not `shared`: this is the guess, and it must not
                // be in front of anything the reader has actually asked for
                // (D-217).
                let image = await ImageLoader.ahead.decode(url, maxPixels: nil)
                guard !Task.isCancelled else { return }
                if let image { ImageCache.fulls[key] = image }
                self?.inFlight[key] = nil
            }
        }
    }

    /// How many guesses are in flight. A readout, for the one test that can
    /// say what cancelling did: the tasks themselves are the outcome, and
    /// counting the call instead would pass over a `cancelAll` that cancelled
    /// nothing (D-254).
    var pending: Int { inFlight.count }

    func cancelAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}
