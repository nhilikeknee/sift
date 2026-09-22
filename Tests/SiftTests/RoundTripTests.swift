import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// An inverse that exists, applied, landing back at the start (D-328).
///
/// D-5 has held since the first commit because `FileOps` returns the way back
/// from every call, and the compiler will not let you write an operation
/// without one. That proves an inverse *exists*. It does not prove the inverse
/// is the right one, and the gap is where an original went missing: crop a
/// photograph, revert it, take back the revert, and the pixels came home while
/// the kept original did not, so there was no way back to it a second time.
/// Four separate reports of this shape — a revert with no way back, a copy
/// reverting to the edit it was made from, a favorite whose way back re-applied
/// it — and every one of them was a single operation the suite already tested
/// in one direction.
///
/// These go the other way, as a sweep rather than one test per feature.
/// `CropTests.undoingARevertPutsRevertBackOnOffer` is the shape, written the day
/// that bug was fixed; it covers crop and revert and nothing else, and the next
/// editing operation will arrive with the same gap. What the sweep cannot see:
/// an inverse that restores the photograph and loses something beside it, which
/// is what the crop suite checks by hand.
@Suite struct RoundTripTests {
    init() { FileOps.useTestBackups(); Preferences.useTestDefaults() }

    /// What a reader would see, per visible file: the orientation the frame is
    /// stood up by, and the pixels it decodes to.
    ///
    /// Not the bytes on disk. A rotate rewrites the orientation tag and leaves
    /// the pixels alone (D-16), so ImageIO re-serializes the metadata and the
    /// file comes back a different size having come back to the same
    /// photograph. Comparing bytes would fail on the one operation that is
    /// most careful not to touch them. Hidden files are left out: the kept
    /// original is one, and an edit is allowed to add or remove it.
    private func appearance(_ dir: URL) throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasPrefix(".") }
        return names.reduce(into: [:]) { out, name in
            let url = dir.appendingPathComponent(name)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (props?[kCGImagePropertyOrientation] as? Int) ?? 1
            var bytes = Data([UInt8(orientation)])
            if let pixels = image.dataProvider?.data as Data? { bytes.append(pixels) }
            out[name] = bytes
        }
    }

    /// The operations that rewrite pixels, each one applied and taken back.
    ///
    /// Named rather than discovered: a scan of `FileOps` for everything
    /// returning an `UndoableOp` would be the stronger test and cannot be
    /// written, because each call needs its own arguments. A new editing
    /// operation therefore needs a line here, which is the trade-off.
    @Test(arguments: ["rotate", "crop", "adjust"])
    func everyEditsInverseRestoresThePhotographItStartedFrom(_ edit: String) async throws {
        let dir = try Fixture.tempDir("roundtrip"); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try Fixture.writeJPEG(photo)
        let before = try appearance(dir)

        let undo: UndoableOp
        switch edit {
        case "rotate": undo = try FileOps.rotate(photo, clockwise: true)
        case "crop": undo = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        default:
            var recipe = Adjustments.neutral
            recipe[.exposure] = 100
            undo = try FileOps.adjustInPlace(photo, recipe)
        }
        #expect(try appearance(dir) != before, "\(edit) did not write anything")

        try await undo.undo()
        #expect(try appearance(dir) == before, "undoing \(edit) did not restore the photograph")
    }

    /// The way back is read off the stack, never captured when the offer is
    /// made (D-283). Favorite a photograph and unfavorite it quickly, and a
    /// pill built from the first operation was still on screen offering to undo
    /// something that had already been undone — pressing it favorited the
    /// photograph again.
    @MainActor
    @Test func theUndoOfferIsAlwaysTheTopOfTheStack() throws {
        let stack = UndoStack()
        #expect(stack.topLabel == nil)
        #expect(!stack.canUndo)

        stack.push(UndoableOp(label: "Favorite", inverse: .all([])))
        #expect(stack.topLabel == "Favorite")

        stack.push(UndoableOp(label: "Unfavorite", inverse: .all([])))
        #expect(stack.topLabel == "Unfavorite", "the offer named an operation that is no longer on top")

        _ = stack.pop()
        #expect(stack.topLabel == "Favorite")
        _ = stack.pop()
        #expect(stack.topLabel == nil, "an offer outlived the stack it came from")
        #expect(!stack.canUndo)
    }
}
