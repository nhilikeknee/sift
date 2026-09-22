import Foundation
import ImageIO
import CoreGraphics

/// An immutable decoded bitmap. CGImage is immutable, so crossing actors is safe.
struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    var width: Int { cgImage.width }
    var height: Int { cgImage.height }
    var byteCost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// Decodes off the main actor (D-6). Thumbnails and full frames both go through
/// CGImageSourceCreateThumbnailAtIndex so EXIF orientation is applied — but only
/// after the metadata has been read (D-46).
///
/// **There are two of these, and the axis is not size — it is whether anybody
/// is waiting** (D-217). `shared` decodes what the reader has asked to see:
/// the thumbnail under the cursor, the frame in the preview, the pixels a
/// panel is about to measure. `ahead` decodes what the app is guessing they
/// will want next.
///
/// An actor runs one call at a time, so with one of them a cursor move put
/// seven full-size decodes in front of every thumbnail the grid then asked
/// for. Measured on a 24MP JPEG: a thumbnail that takes 9ms took 482ms behind
/// that window. Two actors means the guess and the ask do not queue against
/// each other; they still compete for the machine, which is a much smaller
/// number than waiting for a mutex.
actor ImageLoader {
    /// What the reader is waiting for.
    static let shared = ImageLoader()
    /// What the app is guessing they will want. `Prefetcher` and nothing else.
    static let ahead = ImageLoader()

    func decode(_ url: URL, maxPixels: Int?) -> DecodedImage? {
        // Before ImageIO, not after. `CGImageSourceCreateThumbnailAtIndex` is
        // one C call that runs to completion, so a task cancelled while its
        // turn on this actor was still queued used to decode anyway and throw
        // the result away — which is how arrowing through ten photographs
        // built a queue nothing could drain (D-217).
        guard !Task.isCancelled else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        // Read the properties first, always. `kCGImageSourceCreateThumbnailWithTransform`
        // only applies the EXIF orientation if ImageIO has already parsed the
        // metadata, and on files whose orientation sits behind vendor blocks it
        // parses lazily. Asking for the natural size is what forces that parse.
        // Skipping it — which the thumbnail path used to do, since it passes its
        // own `maxPixels` — returned every frame in its stored orientation, so a
        // rotated photo kept its old thumbnail while the full-size preview, which
        // does ask, turned correctly (D-46).
        let natural = Self.longestEdge(of: source)

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        // Omitting the max size means full resolution. Never guess a ceiling:
        // a wrong guess shows the viewer a downscaled photo.
        if let maxPixel = maxPixels ?? natural {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(cgImage: cg)
    }

    /// Synchronous decode for tests and one-off tooling. Views use the actor path.
    nonisolated func decodeSync(_ url: URL) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let maxPixel = Self.longestEdge(of: source) {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(DecodedImage.init)
    }

    /// The size the photograph is *drawn* at, which is not the size it is
    /// stored at: a frame shot vertically is stored landscape with an EXIF
    /// orientation that turns it (D-167).
    ///
    /// Every caller is laying something out over the decoded image — the fitted
    /// rect, the 1:1 scale, the percentage readout, the clipping and focus
    /// masks — and the decode applies orientation. Handing those callers the
    /// stored size put a portrait photograph inside a landscape rectangle, and
    /// the masks painted the whole rectangle.
    nonisolated static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // 5 through 8 are the four orientations that involve a quarter turn.
        let turned = (props[kCGImagePropertyOrientation] as? Int).map { (5...8).contains($0) } ?? false
        return turned ? (h, w) : (w, h)
    }

    nonisolated private static func longestEdge(of source: CGImageSource) -> Int? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(w, h)
    }
}
