import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// The PRD's quality guarantees, one test each. These are the tests that say
/// "the file you put in is the file you get back".
@Suite struct QualityTests {
    init() { Preferences.useTestDefaults() }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-q-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func image(width: Int, height: Int, bitsPerComponent: Int = 8,
                       space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage {
        var info = CGImageAlphaInfo.noneSkipLast.rawValue
        if bitsPerComponent == 16 { info |= CGBitmapInfo.byteOrder16Little.rawValue }
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent,
                            bytesPerRow: 0, space: space, bitmapInfo: info)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func write(_ img: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:]) {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }

    /// Reads without the thumbnail path, which normalizes bit depth.
    private func exactly(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// The compressed image data of a JPEG: everything from the start-of-scan
    /// marker to the end. Re-encoding changes it; rewriting metadata does not.
    private func scan(of jpeg: Data) -> Data? {
        var i = 2
        while i + 4 < jpeg.count {
            guard jpeg[i] == 0xFF else { return nil }
            let marker = jpeg[i + 1]
            if marker == 0xDA { return jpeg[i...] }          // SOS: the picture starts here
            let length = Int(jpeg[i + 2]) << 8 | Int(jpeg[i + 3])
            i += 2 + length
        }
        return nil
    }

    private func properties(_ url: URL) -> [CFString: Any] {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return [:] }
        return p
    }

    // MARK: viewing

    @Test func viewingNeverWritesToTheFile() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg")
        write(image(width: 64, height: 48), to: f, type: .jpeg)
        let bytesBefore = try Data(contentsOf: f)
        let modifiedBefore = try f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        _ = await ImageLoader.shared.decode(f, maxPixels: nil)
        _ = await ImageLoader.shared.decode(f, maxPixels: Tokens.Layout.thumbnailPixels)
        _ = EXIFReader.read(f)
        _ = ImageLoader.pixelSize(of: f)

        #expect(try Data(contentsOf: f) == bytesBefore)
        #expect(try f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modifiedBefore)
    }

    @Test func viewingDecodesAtFullResolution() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg")
        write(image(width: 900, height: 600), to: f, type: .jpeg)
        let decoded = try #require(await ImageLoader.shared.decode(f, maxPixels: nil))
        #expect(decoded.width == 900 && decoded.height == 600)
    }

    // MARK: rotate

    @Test func rotateDoesNotDownscaleAVeryLongImage() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        // Longer than the 32768 cap that used to silently shrink the file.
        let f = dir.appendingPathComponent("wide.png")
        write(image(width: 40_000, height: 2), to: f, type: .png)

        let undo = try FileOps.rotate(f, clockwise: true)
        let turned = try #require(exactly(f))
        #expect(turned.width == 2 && turned.height == 40_000)

        try await undo.undo()
        let back = try #require(exactly(f))
        #expect(back.width == 40_000 && back.height == 2)
    }

    @Test func rotatingA16BitPNGKeeps16Bits() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("deep.png")
        write(image(width: 40, height: 20, bitsPerComponent: 16), to: f, type: .png)
        #expect(exactly(f)?.bitsPerComponent == 16, "fixture is actually 16-bit")

        _ = try FileOps.rotate(f, clockwise: true)
        let turned = try #require(exactly(f))
        #expect(turned.bitsPerComponent == 16)
        #expect(turned.width == 20 && turned.height == 40)
    }

    @Test func rotatingAJPEGLeavesThePixelsAlone() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg")
        write(image(width: 64, height: 48), to: f, type: .jpeg)
        let before = try Data(contentsOf: f)

        let undo = try FileOps.rotate(f, clockwise: true)
        let turned = try Data(contentsOf: f)
        try await undo.undo()
        let after = try Data(contentsOf: f)

        // Orientation went 1 -> 6 -> 1. Only the metadata block is rewritten, so the
        // entropy-coded scan — the actual picture — is byte-identical throughout.
        // The container itself grows, because the fixture had no metadata block to
        // begin with and now carries an orientation tag.
        #expect(scan(of: turned) == scan(of: before), "rotating does not re-encode")
        #expect(scan(of: after) == scan(of: before), "and neither does rotating back")
        #expect(properties(f)[kCGImagePropertyOrientation] as? UInt32 ?? 1 == 1)
    }

    // MARK: crop

    @Test func cropCarriesEXIFAndTheColorProfile() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg")
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        write(image(width: 100, height: 80, space: p3), to: f, type: .jpeg, properties: [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Sift",
                kCGImagePropertyTIFFModel: "Test Camera",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:13 10:30:00",
                kCGImagePropertyExifISOSpeedRatings: [400],
            ] as [CFString: Any],
        ])

        let (copy, undo) = try FileOps.cropCopy(f, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let exif = try #require(EXIFReader.read(copy))
        #expect(exif.camera == "Sift Test Camera")
        #expect(exif.iso == 400)
        #expect(exif.dateTaken != nil)
        #expect(exactly(copy)?.colorSpace?.name == p3.name, "ICC profile survives the crop")

        try await undo.undo()
    }

    @Test func cropIsFullResolutionAndExact() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.png")
        write(image(width: 1000, height: 400), to: f, type: .png)

        let (copy, undo) = try FileOps.cropCopy(f, normalized: CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
        let px = try #require(ImageLoader.pixelSize(of: copy))
        #expect(px.width == 500 && px.height == 400, "no resampling, no cap")
        try await undo.undo()
    }

    @Test func croppingA16BitPNGKeeps16Bits() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("deep.png")
        write(image(width: 40, height: 20, bitsPerComponent: 16), to: f, type: .png)

        let (copy, undo) = try FileOps.cropCopy(f, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(exactly(copy)?.bitsPerComponent == 16)
        try await undo.undo()
    }

    @Test func croppingLeavesTheOriginalByteIdentical() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg")
        write(image(width: 100, height: 80), to: f, type: .jpeg)
        let before = try Data(contentsOf: f)

        let (_, undo) = try FileOps.cropCopy(f, normalized: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        #expect(try Data(contentsOf: f) == before)
        try await undo.undo()
    }

    // MARK: non-pixel operations

    @Test func flaggingAndFavoritingLeaveTheBytesAlone() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg")
        write(image(width: 64, height: 48), to: f, type: .jpeg)
        let before = try Data(contentsOf: f)
        let ref = try #require(FolderScanner.ref(for: f))

        _ = try FileOps.setFlag(.keep, on: ref)
        _ = try FileOps.setFavorite(true, on: ref)

        #expect(try Data(contentsOf: f) == before)
    }

    @Test func renameAndMoveLeaveTheBytesAlone() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("a.jpg")
        write(image(width: 64, height: 48), to: f, type: .jpeg)
        let before = try Data(contentsOf: f)

        let (renamed, _) = try FileOps.rename(f, to: "b.jpg")
        let (moved, _) = try FileOps.move(renamed, into: sub)
        #expect(try Data(contentsOf: moved) == before)
    }
}
