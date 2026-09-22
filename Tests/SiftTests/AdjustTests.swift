import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// The adjust panel, held to what comes out the other end (D-161).
///
/// Every one of these reads pixels back rather than checking that a filter was
/// asked for: Core Image accepts any parameter you hand it and a sign error
/// costs nothing at the call site. The warmth direction in `Adjustments.render`
/// is the one this suite actually decided.
@Suite struct AdjustTests {
    init() { FileOps.useTestBackups() }


    /// A flat patch at one value, the smallest fixture that answers "did this
    /// get brighter".
    private func patch(_ r: Double, _ g: Double, _ b: Double, side: Int = 8) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    /// What is actually in the top-left pixel, 0-255 per channel.
    private func pixel(_ image: CGImage) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func rendered(_ adjustments: Adjustments, _ image: CGImage) throws -> (r: Int, g: Int, b: Int) {
        let out = try #require(adjustments.render(image), "Core Image refused the render")
        return pixel(out)
    }

    // MARK: the recipe as a value

    @Test func neutralIsTheOnlyRecipeWithNothingSet() {
        #expect(Adjustments.neutral.isNeutral)
        for knob in Adjustments.Knob.allCases {
            var a = Adjustments.neutral
            a[knob] = 1
            #expect(!a.isNeutral, "\(knob) moved and the recipe still says neutral")
        }
    }

    @Test func aKnobClampsToItsOwnRange() {
        var a = Adjustments.neutral
        a[.exposure] = 4000
        #expect(a.exposure == 100)
        a[.shadows] = -4000
        #expect(a.shadows == -100)
    }

    /// The cache key names the content, not the address: two different recipes
    /// must never answer to one key, or a photograph wears the previous
    /// frame's exposure.
    @Test func everyKnobChangesTheKey() {
        var seen: Set<String> = [Adjustments.neutral.key]
        for knob in Adjustments.Knob.allCases {
            var a = Adjustments.neutral
            a[knob] = 25
            #expect(seen.insert(a.key).inserted, "\(knob) does not reach the key")
        }
    }

    @Test func aNeutralRecipeHandsTheImageStraightBack() {
        let image = patch(0.5, 0.5, 0.5)
        #expect(Adjustments.neutral.render(image) === image)
    }

    @Test func theSummaryNamesWhatIsSetAndNothingElse() {
        #expect(Adjustments.neutral.summary == "No adjustment")
        var a = Adjustments.neutral
        a[.exposure] = 30
        a[.shadows] = -10
        #expect(a.summary == "Exposure +30  ·  Shadows -10")
    }

    // MARK: what the pixels do

    @Test func exposureBrightensAndDarkens() throws {
        let gray = patch(0.5, 0.5, 0.5)
        let flat = pixel(gray).r
        var up = Adjustments.neutral; up[.exposure] = 100
        var down = Adjustments.neutral; down[.exposure] = -100
        #expect(try rendered(up, gray).r > flat + 20)
        #expect(try rendered(down, gray).r < flat - 20)
    }

    @Test func saturationAllTheWayOutLeavesGray() throws {
        let red = patch(0.8, 0.2, 0.2)
        var out = Adjustments.neutral; out[.saturation] = -100
        let p = try rendered(out, red)
        #expect(abs(p.r - p.g) <= 2 && abs(p.g - p.b) <= 2, "still colored: \(p)")
    }

    @Test func saturationUpPushesTheChannelsApart() throws {
        let red = patch(0.6, 0.4, 0.4)
        let before = pixel(red)
        var up = Adjustments.neutral; up[.saturation] = 100
        let after = try rendered(up, red)
        #expect(after.r - after.g > before.r - before.g)
    }

    /// The one the sign was decided by. Warmth up has to put red in and take
    /// blue out; the filter's two neutrals can be read either way round, and
    /// this is what says which.
    @Test func warmthUpAddsRedAndTakesBlue() throws {
        let gray = patch(0.5, 0.5, 0.5)
        var warm = Adjustments.neutral; warm[.warmth] = 100
        var cool = Adjustments.neutral; cool[.warmth] = -100
        let w = try rendered(warm, gray)
        let c = try rendered(cool, gray)
        #expect(w.r > w.b, "warmth up came out cool: \(w)")
        #expect(c.b > c.r, "warmth down came out warm: \(c)")
    }

    /// The tone curve's promise: each end moves and the other one does not.
    /// `CIHighlightShadowAdjust` could not do this — its highlight input only
    /// darkens — which is why `render` builds a curve instead.
    @Test func highlightsMoveTheBrightEndAndLeaveTheDarkEndAlone() throws {
        let bright = patch(0.8, 0.8, 0.8), dark = patch(0.15, 0.15, 0.15)
        var down = Adjustments.neutral; down[.highlights] = -100
        #expect(try rendered(down, bright).r < pixel(bright).r - 5)
        #expect(abs(try rendered(down, dark).r - pixel(dark).r) <= 2)
    }

    @Test func shadowsLiftTheDarkEndAndLeaveTheBrightEndAlone() throws {
        let bright = patch(0.85, 0.85, 0.85), dark = patch(0.12, 0.12, 0.12)
        var up = Adjustments.neutral; up[.shadows] = 100
        #expect(try rendered(up, dark).r > pixel(dark).r + 5)
        #expect(abs(try rendered(up, bright).r - pixel(bright).r) <= 2)
    }

    @Test func contrastPushesTheEndsApart() throws {
        let bright = patch(0.8, 0.8, 0.8), dark = patch(0.2, 0.2, 0.2)
        var up = Adjustments.neutral; up[.contrast] = 100
        #expect(try rendered(up, bright).r > pixel(bright).r)
        #expect(try rendered(up, dark).r < pixel(dark).r)
    }

    /// The pair that is easy to confuse with Highlights and Shadows, held to
    /// what makes them a different knob: Whites and Blacks move where white and
    /// black *start*, so they act past the quarter tones and leave the middle
    /// of the frame where it was. A Whites slider that darkens a midtone is the
    /// defect this test exists for — an earlier version slid the curve's end
    /// point sideways and cost the midtone twenty levels (D-230).
    @Test func whitesMoveTheBrightestEndAndLeaveTheMidtoneAlone() throws {
        let brightest = patch(0.96, 0.96, 0.96), mid = patch(0.5, 0.5, 0.5)
        var up = Adjustments.neutral; up[.whites] = 100
        var down = Adjustments.neutral; down[.whites] = -100
        #expect(try rendered(up, brightest).r > pixel(brightest).r + 5)
        #expect(try rendered(down, brightest).r < pixel(brightest).r - 5)
        #expect(abs(try rendered(up, mid).r - pixel(mid).r) <= 2)
        #expect(abs(try rendered(down, mid).r - pixel(mid).r) <= 2)
    }

    @Test func blacksMoveTheDarkestEndAndLeaveTheMidtoneAlone() throws {
        let darkest = patch(0.03, 0.03, 0.03), mid = patch(0.5, 0.5, 0.5)
        var up = Adjustments.neutral; up[.blacks] = 100
        var down = Adjustments.neutral; down[.blacks] = -100
        #expect(try rendered(up, darkest).r > pixel(darkest).r + 5)
        #expect(try rendered(down, darkest).r < pixel(darkest).r)
        #expect(abs(try rendered(up, mid).r - pixel(mid).r) <= 2)
        #expect(abs(try rendered(down, mid).r - pixel(mid).r) <= 2)
    }

    /// Four knobs act on one range and two of the pairs can be driven at each
    /// other: shadows all the way down meets blacks all the way up. A curve
    /// that ran backwards would invert the bottom of the frame, and an earlier
    /// version of this did — one five-point curve carrying all four dipped
    /// eight levels there, whatever the two points were clamped apart to,
    /// because a spline dips *inside* a flat segment next to a steep one. The
    /// fix was two curves, and this is the measurement that says it worked.
    ///
    /// A 256-step ramp rather than a handful of patches: the dip was inside a
    /// segment, so sampling seven points found it by luck. One level backwards
    /// is the 8-bit quantization and is allowed; two is a curve going the
    /// wrong way.
    @Test func noSettingOfTheFourToneKnobsInvertsTheFrame() throws {
        let ramp = Self.grayRamp
        for h in [-100.0, -50, 0, 50, 100] {
            for sh in [-100.0, -50, 0, 50, 100] {
                for w in [-100.0, -50, 0, 50, 100] {
                    for b in [-100.0, -50, 0, 50, 100] {
                        let a = Adjustments([.highlights: h, .shadows: sh, .whites: w, .blacks: b])
                        let out = Self.readRow(try #require(a.render(ramp)))
                        let worst = zip(out, out.dropFirst()).map { $1 - $0 }.min() ?? 0
                        #expect(worst >= -1, "h\(h) s\(sh) w\(w) b\(b) stepped back \(worst) levels")
                    }
                }
            }
        }
    }

    /// 256 grays, one pixel each, so a whole transfer curve comes back from a
    /// single render instead of 256 of them.
    private static let grayRamp: CGImage = {
        let ctx = CGContext(data: nil, width: 256, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<256 {
            let v = CGFloat(x) / 255
            ctx.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: 1))
        }
        return ctx.makeImage()!
    }()

    private static func readRow(_ image: CGImage) -> [Int] {
        var bytes = [UInt8](repeating: 0, count: 256 * 4)
        let ctx = CGContext(data: &bytes, width: 256, height: 1, bitsPerComponent: 8, bytesPerRow: 256 * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 1))
        return (0..<256).map { Int(bytes[$0 * 4]) }
    }

    /// The other half of the white balance, and the sign settled the same way
    /// warmth's was: a gray patch rendered both ways and the bytes read back.
    /// Up is magenta and down is green, which is the direction Lightroom's own
    /// Tint runs.
    @Test func tintUpGoesMagentaAndDownGoesGreen() throws {
        let gray = patch(0.5, 0.5, 0.5)
        var magenta = Adjustments.neutral; magenta[.tint] = 100
        var green = Adjustments.neutral; green[.tint] = -100
        let m = try rendered(magenta, gray)
        let g = try rendered(green, gray)
        #expect(m.r > m.g && m.b > m.g, "tint up came out green: \(m)")
        #expect(g.g > g.r && g.g > g.b, "tint down came out magenta: \(g)")
    }

    /// Tint and warmth are two axes of one filter and one call. Setting either
    /// alone has to still reach the pixels, which a `warmth != 0` guard left
    /// over from when there was one axis would quietly stop.
    @Test func tintReachesThePixelsWithWarmthAtZero() throws {
        let gray = patch(0.5, 0.5, 0.5)
        var a = Adjustments.neutral; a[.tint] = 100
        #expect(try rendered(a, gray) != pixel(gray))
    }

    /// What makes vibrance a second color knob rather than a copy of the
    /// first: the same push moves a color that has little to start with much
    /// further than it moves skin. Saturation moves both by the same factor.
    @Test func vibranceMovesAFlatColorFurtherThanItMovesSkin() throws {
        let skin = patch(0.8, 0.62, 0.53), flat = patch(0.25, 0.55, 0.85)
        var up = Adjustments.neutral; up[.vibrance] = 100
        func spread(_ p: (r: Int, g: Int, b: Int)) -> Int { max(p.r, max(p.g, p.b)) - min(p.r, min(p.g, p.b)) }
        let skinGain = spread(try rendered(up, skin)) - spread(pixel(skin))
        let flatGain = spread(try rendered(up, flat)) - spread(pixel(flat))
        #expect(flatGain > skinGain, "vibrance treated skin like everything else: skin \(skinGain), flat \(flatGain)")
        #expect(skinGain < 12, "vibrance pushed skin as hard as saturation would: \(skinGain)")
    }

    @Test func vibranceDownTakesColorOut() throws {
        let flat = patch(0.25, 0.55, 0.85)
        var down = Adjustments.neutral; down[.vibrance] = -100
        let after = try rendered(down, flat)
        #expect(max(after.r, max(after.g, after.b)) - min(after.r, min(after.g, after.b))
                    < pixel(flat).b - pixel(flat).r)
    }

    /// Every knob has to be somewhere in the panel, or a case added to the
    /// enum ships a number that nothing on screen can set. A capability with
    /// no way in is missing.
    @Test func everyKnobIsInAGroupAndEveryGroupHasKnobs() {
        let grouped = Adjustments.Knob.Group.allCases.flatMap(\.knobs)
        #expect(grouped.count == Adjustments.Knob.allCases.count)
        #expect(Set(grouped) == Set(Adjustments.Knob.allCases))
        #expect(Adjustments.Knob.Group.allCases.allSatisfy { !$0.knobs.isEmpty })
        // And in the enum's order within each group, so the panel reads the
        // way the list is written rather than in whatever order a filter fell.
        #expect(grouped == Adjustments.Knob.allCases.sorted {
            let g = Adjustments.Knob.Group.allCases
            let a = g.firstIndex(of: $0.group)!, b = g.firstIndex(of: $1.group)!
            if a != b { return a < b }
            return Adjustments.Knob.allCases.firstIndex(of: $0)! < Adjustments.Knob.allCases.firstIndex(of: $1)!
        })
    }

    /// A recipe written by a version with fewer knobs still has to read back.
    /// The synthesised decoder throws on a missing key even where the property
    /// has a default, which would put the sliders at zero over pixels that
    /// already carry the edit — the one thing D-165 exists to prevent.
    @Test func aRecipeStoredBeforeAKnobExistedStillDecodes() throws {
        let old = Data(#"{"exposure":35,"contrast":15,"highlights":-40,"shadows":25,"saturation":10,"warmth":20}"#.utf8)
        let recipe = try JSONDecoder().decode(Adjustments.self, from: old)
        #expect(recipe.exposure == 35)
        #expect(recipe.warmth == 20)
        #expect(recipe.whites == 0 && recipe.blacks == 0 && recipe.tint == 0 && recipe.vibrance == 0)
    }

    @Test func aRecipeRoundTripsThroughItsOwnCoding() throws {
        let recipe = Adjustments([.exposure: 35, .whites: -20, .tint: 15, .vibrance: 60])
        let back = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(recipe))
        #expect(back == recipe)
    }

    @Test func theRenderKeepsTheShapeOfTheFrame() throws {
        let image = patch(0.5, 0.4, 0.3, side: 40)
        var a = Adjustments.neutral; a[.exposure] = 20
        let out = try #require(a.render(image))
        #expect(out.width == 40 && out.height == 40)
    }

    // MARK: the file it writes

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-adjust-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeJPEG(_ url: URL) throws {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, patch(0.45, 0.45, 0.45, side: 24), nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func adjustWritesASiblingAndLeavesTheOriginalAlone() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        let before = try Data(contentsOf: original)

        var recipe = Adjustments.neutral
        recipe[.exposure] = 100
        let (dest, undo) = try FileOps.adjustCopy(original, recipe)

        #expect(dest.lastPathComponent == "a.adjust.jpg")
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(try Data(contentsOf: original) == before, "the original was rewritten")

        // And it is the adjusted frame rather than a copy of the source.
        let source = CGImageSourceCreateWithURL(dest as CFURL, nil)!
        let written = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(pixel(written).r > pixel(patch(0.45, 0.45, 0.45)).r + 20)

        try await undo.undo()
        #expect(!FileManager.default.fileExists(atPath: dest.path), "undo left the copy behind")
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    /// The second copy takes a number, the way a crop's does. The naming lives
    /// in one place now, so this is the check that the one place still works
    /// for both callers.
    @Test func aSecondAdjustedCopyTakesANumber() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.contrast] = 40
        let first = try FileOps.adjustCopy(original, recipe).0
        let second = try FileOps.adjustCopy(original, recipe).0
        #expect(first.lastPathComponent == "a.adjust.jpg")
        #expect(second.lastPathComponent == "a.adjust2.jpg")
    }

    /// The one operation in the app that changes a photograph in place, so the
    /// thing to hold it to is the inverse: the original comes back, byte for
    /// byte, and the adjusted version goes to the Trash rather than being
    /// deleted (D-163).
    ///
    /// Rewritten for D-165, deliberately: this used to assert the folder held
    /// nothing but `a.jpg` afterwards. An overwrite now leaves the original in
    /// a hidden file so the edit can be taken back or taken further next week,
    /// so what is checked is that nothing a *scan* can see was added, which is
    /// the thing the old assertion was protecting.
    /// Rewritten for D-240, deliberately. It read the toast D-233 added — the
    /// sentence naming the hidden original the first save-over leaves — and
    /// that toast is gone at the owner's word, so the wording half of this test
    /// went with it. What it was really protecting stays and is the whole test
    /// now: the first overwrite keeps the original, a scan of the folder still
    /// sees one file, and the second overwrite leaves the first original alone.
    @Test func theFirstOverwriteKeepsTheOriginalOutOfSight() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("DSC_0001.jpg")
        try writeJPEG(photo)
        var recipe = Adjustments.neutral
        recipe[.exposure] = 100

        #expect(!AdjustRecord.isRevertable(photo), "nothing is kept before the first write")
        _ = try FileOps.adjustInPlace(photo, recipe)

        #expect(FileManager.default.fileExists(atPath: AdjustRecord.originalURL(for: photo).path),
                "the first overwrite kept no original")
        #expect(AdjustRecord.isRevertable(photo), "Revert has nothing to offer after a write")
        let kept = try Data(contentsOf: AdjustRecord.originalURL(for: photo))

        _ = try FileOps.adjustInPlace(photo, recipe)
        #expect(try Data(contentsOf: AdjustRecord.originalURL(for: photo)) == kept,
                "the second overwrite replaced the original with an already-adjusted frame")
        #expect(try FolderScanner.scan(dir).map(\.name) == ["DSC_0001.jpg"],
                "the kept original became visible to a scan")
    }

    @Test func overwritingKeepsTheNameAndUndoBringsTheOriginalBack() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        let before = try Data(contentsOf: original)

        var recipe = Adjustments.neutral
        recipe[.exposure] = 100
        let undo = try FileOps.adjustInPlace(original, recipe)

        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(try Data(contentsOf: original) != before, "the file was not written")
        #expect(try FolderScanner.scan(dir).map(\.name) == ["a.jpg"],
                "an overwrite left something else in the folder")
        #expect(FileManager.default.fileExists(atPath: AdjustRecord.originalURL(for: original).path),
                "the original was not kept")
        let source = CGImageSourceCreateWithURL(original as CFURL, nil)!
        let written = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(pixel(written).r > pixel(patch(0.45, 0.45, 0.45)).r + 20)

        try await undo.undo()
        #expect(try Data(contentsOf: original) == before, "undo did not restore the original bytes")
        #expect(AdjustRecord.original(for: original) == nil, "undo left a kept original behind")
        #expect(AdjustRecord.recipe(for: original) == nil, "undo left the recipe on the file")
    }

    // MARK: the record an overwrite leaves (D-165)

    /// The point of keeping the original: the second overwrite develops it
    /// again rather than adjusting the file the first one wrote. Two +50s in a
    /// row land where one +50 lands, not two stops further up.
    @Test func asecondOverwriteDevelopsTheKeptOriginalRatherThanTheAdjustedFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let twice = dir.appendingPathComponent("twice.jpg")
        let once = dir.appendingPathComponent("once.jpg")
        try writeJPEG(twice)
        try writeJPEG(once)

        var recipe = Adjustments.neutral
        recipe[.exposure] = 50
        _ = try FileOps.adjustInPlace(twice, recipe)
        _ = try FileOps.adjustInPlace(twice, recipe)
        _ = try FileOps.adjustInPlace(once, recipe)

        func value(_ url: URL) throws -> Int {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return pixel(image).r
        }
        // JPEG round-trips twice on one side and once on the other, so within a
        // couple of levels rather than equal.
        #expect(abs(try value(twice) - (try value(once))) <= 3,
                "the second overwrite stacked on the first")
    }

    /// The six numbers come back off the file, which is what puts the sliders
    /// where they were left.
    @Test func theRecipeIsReadableBackOffTheFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.exposure] = 30
        recipe[.warmth] = -20
        _ = try FileOps.adjustInPlace(original, recipe)
        #expect(AdjustRecord.recipe(for: original) == recipe)
        #expect(AdjustRecord.editable(for: original) == recipe)
        #expect(AdjustRecord.isRevertable(original))
    }

    /// A recipe whose original has gone — the photograph was renamed by
    /// something that is not this app — is history rather than a starting
    /// point. Put back on the sliders it would be applied a second time.
    @Test func aRecipeWithoutItsOriginalIsNotEditable() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.contrast] = 40
        _ = try FileOps.adjustInPlace(original, recipe)
        try FileManager.default.removeItem(at: AdjustRecord.originalURL(for: original))
        #expect(AdjustRecord.recipe(for: original) == recipe, "the numbers are still what was done")
        #expect(AdjustRecord.editable(for: original) == nil)
        #expect(!AdjustRecord.isRevertable(original))
    }

    /// The kept original is invisible to every count, grid and filmstrip in the
    /// app, because every scan skips hidden files and it is named to be one.
    @Test func theKeptOriginalIsInvisibleToAScan() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.shadows] = 40
        _ = try FileOps.adjustInPlace(original, recipe)
        #expect(try FolderScanner.scan(dir).count == 1)
        #expect(FolderScanner.count(dir, recursive: true) == 1)
    }

    /// The undo that outlives the session: the bytes come back, the record goes
    /// away, and undoing *that* puts the adjusted version and its recipe back.
    @Test func revertPutsTheOriginalBackAndUndoingItPutsTheAdjustmentBack() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        let before = try Data(contentsOf: original)
        var recipe = Adjustments.neutral
        recipe[.exposure] = 60
        _ = try FileOps.adjustInPlace(original, recipe)
        let adjusted = try Data(contentsOf: original)

        let undo = try FileOps.revertAdjust(original)
        #expect(try Data(contentsOf: original) == before, "revert did not restore the original bytes")
        #expect(AdjustRecord.recipe(for: original) == nil, "revert left the recipe on the file")
        #expect(AdjustRecord.original(for: original) == nil, "revert left the kept original behind")

        try await undo.undo()
        #expect(try Data(contentsOf: original) == adjusted, "undoing the revert lost the adjusted file")
        #expect(AdjustRecord.recipe(for: original) == recipe, "undoing the revert lost the recipe")
        #expect(AdjustRecord.isRevertable(original), "undoing the revert lost the kept original")
    }

    /// A photograph flagged after it was adjusted keeps that flag through the
    /// revert: the marks belong to the file as it is now, not to the copy that
    /// was put aside before they were set (D-3).
    @Test func revertKeepsAFlagSetAfterTheOverwrite() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.contrast] = 30
        _ = try FileOps.adjustInPlace(original, recipe)
        _ = try FileOps.setFlag(.keep, on: FolderScanner.ref(for: original)!)

        _ = try FileOps.revertAdjust(original)
        #expect(FolderScanner.ref(for: original)?.flag == .keep, "the revert dropped the flag")
    }

    /// A cull renames and moves constantly, so the record has to travel. The
    /// photograph keeps its recipe through a rename because `moveItem` carries
    /// extended attributes; the kept original has to be carried on purpose.
    @Test func theRecordFollowsARenameAndComesBackWithTheUndo() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.exposure] = 35
        _ = try FileOps.adjustInPlace(original, recipe)

        let (renamed, undo) = try FileOps.rename(original, to: "b.jpg")
        #expect(AdjustRecord.editable(for: renamed) == recipe, "the rename orphaned the kept original")
        #expect(AdjustRecord.original(for: original) == nil, "the kept original stayed under the old name")

        try await undo.undo()
        #expect(AdjustRecord.editable(for: original) == recipe, "undoing the rename left the record behind")
    }

    /// Trashing a photograph takes its kept original with it, or the folder
    /// keeps a hidden copy of something that is not there any more.
    @Test func trashingTakesTheKeptOriginalWithIt() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        var recipe = Adjustments.neutral
        recipe[.saturation] = -40
        _ = try FileOps.adjustInPlace(original, recipe)

        let undo = try FileOps.trash(original)
        #expect(AdjustRecord.original(for: original) == nil, "the kept original was left in the folder")
        try await undo.undo()
        #expect(AdjustRecord.isRevertable(original), "undoing the trash left the kept original in the Trash")
    }

    @Test func revertRefusesWhenNoOriginalWasKept() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        #expect(throws: FileOps.Failure.self) { _ = try FileOps.revertAdjust(original) }
    }

    /// The flag, the favorite and the color label are extended attributes on
    /// the file (D-3), and an overwrite that dropped them would quietly undo a
    /// cull decision. `replaceItemAt` is what carries them.
    @Test func overwritingKeepsTheFlagOnTheFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        _ = try FileOps.setFlag(.keep, on: FolderScanner.ref(for: original)!)
        #expect(FolderScanner.ref(for: original)?.flag == .keep)

        var recipe = Adjustments.neutral
        recipe[.contrast] = 50
        _ = try FileOps.adjustInPlace(original, recipe)
        #expect(FolderScanner.ref(for: original)?.flag == .keep, "the overwrite dropped the flag")
    }

    @Test func overwritingRefusesAContainerItWouldHaveToChange() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let gif = dir.appendingPathComponent("a.gif")
        try Data([0x47, 0x49, 0x46]).write(to: gif)
        var recipe = Adjustments.neutral
        recipe[.exposure] = 20
        #expect(throws: FileOps.Failure.self) { _ = try FileOps.adjustInPlace(gif, recipe) }
        // A copy is still on offer, which is what the refusal tells you to do.
        #expect(FileManager.default.fileExists(atPath: gif.path))
    }

    @Test func overwritingRefusesToWriteNothing() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        #expect(throws: FileOps.Failure.self) { _ = try FileOps.adjustInPlace(original, .neutral) }
    }

    @Test func adjustRefusesToWriteNothing() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.jpg")
        try writeJPEG(original)
        #expect(throws: FileOps.Failure.self) {
            _ = try FileOps.adjustCopy(original, .neutral)
        }
    }
}

/// Where the panel and the numbers in it live, which is not the same place
/// (D-161). The panel is posture: it is where somebody is working. The numbers
/// are about one photograph and go when that photograph does.
@Suite @MainActor struct AdjustStateTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int = 3) -> LibraryStore {
        let s = LibraryStore()
        for i in 0..<count {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    @Test func movingTheCursorClearsTheSlidersAndLeavesThePanelUp() {
        let s = store()
        s.adjusting = true
        s.adjustments[.exposure] = 40
        s.move(by: 1)
        #expect(s.adjusting, "the panel is where you are working, not a property of the photo")
        #expect(s.adjustments.isNeutral, "the next photograph inherited an exposure nobody set for it")
    }

    @Test func cropAndAdjustAreNeverBothRunning() {
        let s = store()
        s.adjusting = true
        s.adjustments[.contrast] = 20
        s.cropping = true
        #expect(!s.adjusting)
        #expect(s.adjustments.isNeutral)

        s.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        s.adjusting = true
        #expect(!s.cropping)
        #expect(s.cropRect == nil)
    }

    @Test func switchingTheFeatureOffTakesThePanelAndTheNumbers() {
        let s = store()
        s.adjusting = true
        s.adjustments[.warmth] = 60
        s.standDown(FeatureSet(off: [.adjust]))
        #expect(!s.adjusting)
        #expect(s.adjustments.isNeutral)
    }

    @Test func escLeavesAdjustBeforeItClosesTheWindow() {
        let s = store()
        let router = CommandRouter(store: s)
        s.previewOpen = true
        s.focus = .preview
        s.adjusting = true
        s.adjustments[.shadows] = 30
        router.perform(.cancel)
        #expect(!s.adjusting)
        #expect(s.adjustments.isNeutral)
        #expect(s.previewOpen, "Esc closed the window with a mode still running")
    }

    @Test func overwriteNeedsASliderToHaveMoved() {
        let s = store()
        let router = CommandRouter(store: s)
        s.adjusting = true
        router.perform(.saveOverOriginal)
        #expect(s.adjusting, "it saved nothing and closed the panel anyway")
        #expect(s.toast?.message == "Move a slider first")
    }

    // MARK: what the photograph itself carries (D-165)

    private func photoWithRecipe(_ recipe: Adjustments) throws -> (LibraryStore, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-adjust-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.jpg")
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        if !recipe.isNeutral { _ = try FileOps.adjustInPlace(url, recipe) }

        let s = LibraryStore()
        s.insert(FolderScanner.ref(for: url)!)
        s.cursor = 0
        return (s, url, dir)
    }

    /// Opening the panel on a photograph that was overwritten puts the sliders
    /// back where they were left, rather than at zero over pixels that already
    /// carry the edit.
    @Test func thePanelOpensAtWhatTheOverwriteLeftOnTheFile() throws {
        var recipe = Adjustments.neutral
        recipe[.exposure] = 40
        let (s, _, dir) = try photoWithRecipe(recipe)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: s)
        router.perform(.adjust)
        #expect(s.adjustments == recipe, "the sliders came up at zero over an adjusted file")
        #expect(s.adjustBaseline == recipe)
        #expect(s.adjustRevertable)
    }

    /// Reopening one and pressing ⇧Return without moving anything would write
    /// the same six numbers over the same file for nothing, so it says so.
    @Test func overwritingWhatIsAlreadyOnTheFileIsRefused() throws {
        var recipe = Adjustments.neutral
        recipe[.contrast] = 25
        let (s, _, dir) = try photoWithRecipe(recipe)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: s)
        router.perform(.adjust)
        router.perform(.saveOverOriginal)
        #expect(s.adjusting, "it closed the panel over a write it did not make")
        #expect(s.toast?.message == "That is already what is on the file")
    }

    /// ⇧R on a photograph with nothing kept says so rather than closing the
    /// panel over an operation it did not perform.
    @Test func revertingWithNothingKeptSaysSo() throws {
        let (s, _, dir) = try photoWithRecipe(.neutral)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: s)
        router.perform(.adjust)
        router.perform(.revertToOriginal)
        #expect(s.adjusting)
        #expect(s.toast?.message == "No original is kept for this photo")
    }

    /// The whole way through the router. Rewritten for D-240, deliberately:
    /// ⇧R used to write immediately, and it now shows the original and waits.
    /// So the first half is the preview — the panel closes, the mode is on, and
    /// nothing on disk has moved — and the write is what Return does next.
    @Test func revertingThroughTheRouterShowsTheOriginalAndThenPutsTheFileBack() async throws {
        var recipe = Adjustments.neutral
        recipe[.exposure] = 45
        let (s, url, dir) = try photoWithRecipe(recipe)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: s)
        router.perform(.adjust)
        #expect(s.adjustRevertable)
        router.perform(.revertToOriginal)
        #expect(s.reverting, "the original is not on screen")
        #expect(!s.adjusting, "the panel stayed up over the photograph it is no longer about")
        #expect(AdjustRecord.recipe(for: url) != nil, "the preview wrote to the file")
        #expect(AdjustRecord.isRevertable(url), "the preview consumed the kept original")

        router.perform(.confirm)
        #expect(!s.reverting, "the mode outlived the write it was asking about")
        for _ in 0..<100 where s.adjustRevertable {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(AdjustRecord.recipe(for: url) == nil, "the revert never landed")
        #expect(AdjustRecord.original(for: url) == nil)
        #expect(!s.adjustRevertable, "the panel would still offer to revert a photo with nothing kept")
    }

    /// Esc out of the preview and the photograph is exactly as it was: the
    /// point of a preview is that it can be turned down (D-240).
    @Test func leavingTheRevertPreviewChangesNothing() throws {
        var recipe = Adjustments.neutral
        recipe[.exposure] = 45
        let (s, url, dir) = try photoWithRecipe(recipe)
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = try Data(contentsOf: url)
        let router = CommandRouter(store: s)
        router.perform(.revertToOriginal)
        #expect(s.reverting)
        router.perform(.cancel)
        #expect(!s.reverting)
        #expect(try Data(contentsOf: url) == before, "cancelling the preview still wrote")
        #expect(AdjustRecord.isRevertable(url), "cancelling the preview took the original away")
    }

    /// Asking for the panel from the gallery opens the window it draws in. The
    /// same defect the filmstrip had: a command that reports success and puts
    /// nothing on screen (D-118).
    @Test func askingForThePanelFromTheGalleryOpensThePreview() {
        let s = store()
        let router = CommandRouter(store: s)
        s.focus = .gallery
        router.perform(.adjust)
        #expect(s.adjusting)
        #expect(s.previewOpen)
    }
}
