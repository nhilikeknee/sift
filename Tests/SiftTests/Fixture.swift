import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A temporary folder and a photograph to put in it.
///
/// Five suites had grown their own `tempDir()` and five their own `writeJPEG`,
/// each a few lines and each subtly its own: different default sizes, some
/// taking an orientation, one writing PNG. The copies are not the cost — the
/// cost is that a fixture quirk found in one of them is fixed in one of them.
/// This is the shared pair; the older suites still carry theirs, which is
/// tech debt rather than a bug (D-332).
enum Fixture {
    /// A folder of its own, tagged with the suite that asked for it. The tag
    /// is why the copies were not identical and is worth keeping: a directory
    /// left behind by a failing run says `sift-crop-…` rather than `sift-…`,
    /// and which suite dropped it is the first thing you want to know. The
    /// caller removes it; nothing here does, because a test that fails is
    /// easier to read with its files still on disk.
    static func tempDir(_ tag: String = "") throws -> URL {
        let prefix = tag.isEmpty ? "sift-" : "sift-\(tag)-"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A flat gray JPEG, wider than tall so a rotation is observable, and
    /// written by ImageIO — which is the same library that reads it, so this
    /// exercises none of the paths a camera file takes (D-43). Anything about
    /// vendor metadata needs a real photograph, not this.
    static func writeJPEG(_ url: URL, width: Int = 40, height: Int = 20,
                          orientation: Int? = nil,
                          gps: (latitude: Double, longitude: Double)? = nil) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // `#require` rather than `!`: a name the filesystem will not hold
        // returns nil here, and a force unwrap takes the whole run down with
        // a signal instead of failing the one test that asked for it.
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.jpeg.identifier as CFString, 1, nil),
                                "no JPEG writer for \(url.lastPathComponent)")
        var props: [CFString: Any] = [:]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        // Signed degrees in, ref-and-magnitude out, which is how a camera
        // writes the IFD and how `CGImageSourceCopyProperties` reads it back.
        if let gps {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(gps.latitude),
                kCGImagePropertyGPSLatitudeRef: gps.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(gps.longitude),
                kCGImagePropertyGPSLongitudeRef: gps.longitude >= 0 ? "E" : "W",
            ] as CFDictionary
        }
        CGImageDestinationAddImage(dest, ctx.makeImage()!,
                                   props.isEmpty ? nil : props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }
}
