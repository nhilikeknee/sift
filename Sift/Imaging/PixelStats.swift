import CoreGraphics
import Foundation

/// Luminance histogram and clipping, computed from a decoded image off the main actor.
struct Histogram: Sendable, Equatable {
    /// 64 bins across 0...255.
    let bins: [Int]
    /// Fraction of pixels at pure white / pure black (all channels >= 250 / <= 5).
    let white: Double
    let black: Double
    var peak: Int { bins.max() ?? 1 }
}

enum PixelStats {
    /// Reads 8-bit RGBA through a known-format context so every source layout comes out the same.
    private static func rgba(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (data, w, h) : nil
    }

    /// The histogram of part of an image, in normalized coordinates with the
    /// origin at the top left. A face's exposure judged from a whole-scene
    /// histogram is the sky's exposure (D-76).
    static func histogram(of image: CGImage, in rect: CGRect) -> Histogram? {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let px = CGRect(x: rect.minX * full.width, y: rect.minY * full.height,
                        width: rect.width * full.width, height: rect.height * full.height)
            .intersection(full).integral
        guard px.width >= 1, px.height >= 1 else { return histogram(of: image) }
        guard let cropped = image.cropping(to: px) else { return histogram(of: image) }
        return histogram(of: cropped)
    }

    static func histogram(of image: CGImage) -> Histogram? {
        guard let (px, w, h) = rgba(image), w * h > 0 else { return nil }
        var bins = [Int](repeating: 0, count: 64)
        var white = 0, black = 0
        var i = 0
        let n = w * h
        while i < n * 4 {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            // Rec. 601 luma, integer.
            let y = (r * 299 + g * 587 + b * 114) / 1000
            bins[y >> 2] += 1
            if r >= 250 && g >= 250 && b >= 250 { white += 1 }
            if r <= 5 && g <= 5 && b <= 5 { black += 1 }
            i += 4
        }
        return Histogram(bins: bins, white: Double(white) / Double(n), black: Double(black) / Double(n))
    }

    /// How sharp the frame is, as the variance of a Laplacian over its
    /// luminance (D-77). Not a number with units: it is only meaningful against
    /// the other frames of the same burst, which is exactly how a cull uses it.
    /// Scaled so a typical in-focus photo lands near 1.
    static func sharpness(of image: CGImage) -> Double? {
        guard let (px, w, h) = rgba(image), w > 2, h > 2 else { return nil }
        var luma = [Int32](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let o = i * 4
            luma[i] = Int32((Int(px[o]) * 299 + Int(px[o + 1]) * 587 + Int(px[o + 2]) * 114) / 1000)
        }
        var sum = 0.0, sumSq = 0.0
        var n = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                // The four-neighbor Laplacian. Cheap, and the only thing that
                // matters here is how much high-frequency detail survives.
                let lap = Double(4 * luma[i] - luma[i - 1] - luma[i + 1] - luma[i - w] - luma[i + w])
                sum += lap
                sumSq += lap * lap
                n += 1
            }
        }
        guard n > 0 else { return nil }
        let mean = sum / Double(n)
        return (sumSq / Double(n) - mean * mean) / 100
    }

    /// A mask over the edges the lens actually resolved (D-78). The same shape
    /// as the clipping mask, and for the same reason: the question "is this
    /// one sharp" is answered by looking at the photo, not at a number.
    ///
    /// Sobel over luminance, painted where the gradient clears a threshold set
    /// against the frame's own strongest edge — an absolute threshold calls a
    /// soft photo uniformly blurred and a contrasty one sharp everywhere.
    static func focusMask(of image: CGImage, color: (r: UInt8, g: UInt8, b: UInt8)) -> CGImage? {
        guard let (px, w, h) = rgba(image), w > 2, h > 2 else { return nil }
        var luma = [Int32](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let o = i * 4
            luma[i] = Int32((Int(px[o]) * 299 + Int(px[o + 1]) * 587 + Int(px[o + 2]) * 114) / 1000)
        }
        var grad = [Int32](repeating: 0, count: w * h)
        var strongest: Int32 = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let gx = (luma[i - w + 1] + 2 * luma[i + 1] + luma[i + w + 1])
                       - (luma[i - w - 1] + 2 * luma[i - 1] + luma[i + w - 1])
                let gy = (luma[i + w - 1] + 2 * luma[i + w] + luma[i + w + 1])
                       - (luma[i - w - 1] + 2 * luma[i - w] + luma[i - w + 1])
                let g = abs(gx) + abs(gy)
                grad[i] = g
                if g > strongest { strongest = g }
            }
        }
        guard strongest > 0 else { return nil }
        let cut = Int32(Double(strongest) * edgeFraction)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) where grad[i] >= cut {
            let o = i * 4
            out[o] = color.r; out[o + 1] = color.g; out[o + 2] = color.b; out[o + 3] = 255
        }
        return out.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    /// The share of the frame's strongest edge a pixel has to reach before it
    /// is painted. A third keeps the mask to what is actually resolved; lower
    /// and a soft photo lights up everywhere, which tells you nothing.
    private static let edgeFraction = 0.33

    /// A mask the size of `image`: opaque `color` where *any* channel is at or
    /// above `threshold`, transparent elsewhere. Drawn over the photo to show
    /// blown highlights.
    ///
    /// Any channel, not all three (D-166). Demanding all three meant only
    /// near-white pixels painted, so a blown sky — blue at 255, red and green
    /// well under it — and blown skin came back clean, and the overlay said a
    /// photograph was fine when a channel in it had nothing left to recover.
    /// That is the same rule every histogram in the category uses, and it is
    /// what the Highlights slider beside this switch is trying to pull back.
    static func clippingMask(of image: CGImage, threshold: UInt8 = 250, color: (r: UInt8, g: UInt8, b: UInt8)) -> CGImage? {
        guard let (px, w, h) = rgba(image) else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var i = 0
        while i < px.count {
            if px[i] >= threshold || px[i + 1] >= threshold || px[i + 2] >= threshold {
                out[i] = color.r; out[i + 1] = color.g; out[i + 2] = color.b; out[i + 3] = 255
            }
            i += 4
        }
        return out.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }
}
