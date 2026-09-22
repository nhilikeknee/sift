import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// The shape a crop is held to (D-238).
///
/// Every one of these is arithmetic the gesture cannot be driven to prove: a
/// drag is a pointer, and a pointer is the one thing this suite has no way to
/// move. What it can hold is the rule — a box that comes out of `shaped` is the
/// ratio it was asked for, it is inside the photograph, and the point the drag
/// was not moving has not moved.
@Suite struct CropRatioTests {
    private let frame = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func ratio(_ r: CGRect) -> CGFloat { r.width / r.height }

    @Test func eachShapeIsTheNumbersOnItsOwnLabel() {
        let photo: CGFloat = 3.0 / 2.0
        #expect(CropRatio.free.aspect(photo: photo, turned: false) == nil)
        #expect(CropRatio.original.aspect(photo: photo, turned: false) == photo)
        #expect(CropRatio.square.aspect(photo: photo, turned: false) == 1)
        #expect(CropRatio.fourThree.aspect(photo: photo, turned: false) == 4.0 / 3.0)
        #expect(CropRatio.threeTwo.aspect(photo: photo, turned: false) == 3.0 / 2.0)
        #expect(CropRatio.sixteenNine.aspect(photo: photo, turned: false) == 16.0 / 9.0)
    }

    /// The turn is a transpose, including on `Original`: a portrait crop of a
    /// landscape frame is the whole point of the control.
    @Test func turningAShapeStandsItUp() {
        let photo: CGFloat = 3.0 / 2.0
        #expect(CropRatio.fourThree.aspect(photo: photo, turned: true) == 3.0 / 4.0)
        #expect(CropRatio.original.aspect(photo: photo, turned: true) == 2.0 / 3.0)
        // Nothing to turn, so nothing turns: the control is not drawn for
        // these two at all.
        #expect(CropRatio.square.aspect(photo: photo, turned: true) == 1)
        #expect(CropRatio.free.aspect(photo: photo, turned: true) == nil)
        #expect(!CropRatio.square.canTurn && !CropRatio.free.canTurn)
        #expect(CropRatio.original.canTurn && CropRatio.sixteenNine.canTurn)
    }

    @Test func everyShapeHasALabelAndTheyAreAllDifferent() {
        let labels = CropRatio.allCases.map(\.label)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
    }

    // MARK: the box the ratio makes

    @Test func aShapedBoxIsTheRatioItWasAskedFor() throws {
        for aspect in [1.0, 4.0 / 3.0, 16.0 / 9.0, 9.0 / 16.0] as [CGFloat] {
            let box = try #require(CropGrip.shaped(CGSize(width: 300, height: 90), aspect: aspect,
                                                   driven: .larger, unit: CGPoint(x: 0, y: 0),
                                                   pin: CGPoint(x: 100, y: 100), within: frame))
            #expect(abs(ratio(box) - aspect) < 0.001, "\(aspect) came out \(ratio(box))")
            #expect(frame.contains(box.insetBy(dx: -0.5, dy: -0.5).intersection(frame)))
        }
    }

    /// The pin is the corner the drag is not holding, and it stays exactly
    /// where it was however much the box has to shrink to fit.
    @Test func theCornerTheDragIsNotHoldingStaysPut() throws {
        let pin = CGPoint(x: 700, y: 550)
        let box = try #require(CropGrip.shaped(CGSize(width: 400, height: 400), aspect: 16.0 / 9.0,
                                               driven: .larger, unit: CGPoint(x: 1, y: 1),
                                               pin: pin, within: frame))
        #expect(abs(box.maxX - pin.x) < 0.001)
        #expect(abs(box.maxY - pin.y) < 0.001)
        #expect(abs(ratio(box) - 16.0 / 9.0) < 0.001)
    }

    /// A single edge opens the other axis out from the middle, so pulling the
    /// left edge of a 16:9 box does not walk the box down the frame.
    @Test func pullingOneEdgeGrowsTheOtherAxisAboutItsMiddle() throws {
        let start = CGRect(x: 200, y: 200, width: 160, height: 90)
        let box = try #require(CropGrip.shaped(CGSize(width: 320, height: start.height),
                                               aspect: 16.0 / 9.0, driven: .width,
                                               unit: CGPoint(x: 1, y: 0.5),
                                               pin: CGPoint(x: start.maxX, y: start.midY),
                                               within: frame))
        #expect(abs(box.maxX - start.maxX) < 0.001, "the fixed edge moved")
        #expect(abs(box.midY - start.midY) < 0.001, "the box slid up or down the frame")
        #expect(abs(box.width - 320) < 0.001)
        #expect(abs(ratio(box) - 16.0 / 9.0) < 0.001)
    }

    @Test func aBoxIsShrunkToFitRatherThanAllowedOffTheFrame() throws {
        let box = try #require(CropGrip.shaped(CGSize(width: 4000, height: 4000), aspect: 1,
                                               driven: .larger, unit: CGPoint(x: 0.5, y: 0.5),
                                               pin: CGPoint(x: 400, y: 300), within: frame))
        #expect(box.height <= frame.height + 0.001)
        #expect(box.minX >= frame.minX - 0.001 && box.maxX <= frame.maxX + 0.001)
        #expect(box.minY >= frame.minY - 0.001 && box.maxY <= frame.maxY + 0.001)
    }

    /// The floor the free crop already had, kept: a shape chosen in a corner
    /// with two pixels of room gives nothing back rather than a box too small
    /// to see, and the caller keeps what it had.
    @Test func aBoxTooSmallToSaveIsRefused() {
        #expect(CropGrip.shaped(CGSize(width: 4, height: 4), aspect: 1, driven: .larger,
                                unit: CGPoint(x: 0, y: 0), pin: CGPoint(x: 799, y: 599),
                                within: frame) == nil)
    }

    /// Choosing a ratio takes the box in rather than pushing it out, which is
    /// what the panel does with `.smaller` and the only behavior that cannot
    /// put an edge off the photograph.
    @Test func snappingAWideBoxToSquareTakesItIn() throws {
        let wide = CGRect(x: 100, y: 200, width: 600, height: 200)
        let box = try #require(CropGrip.shaped(wide.size, aspect: 1, driven: .smaller,
                                               unit: CGPoint(x: 0.5, y: 0.5),
                                               pin: CGPoint(x: wide.midX, y: wide.midY), within: frame))
        #expect(abs(box.width - 200) < 0.001 && abs(box.height - 200) < 0.001)
        #expect(abs(box.midX - wide.midX) < 0.001 && abs(box.midY - wide.midY) < 0.001)
    }

    /// In the normalized square the rectangle is actually kept in, the ratio
    /// means the ratio divided by the photograph's own shape. Getting this
    /// wrong is invisible on screen and wrong in the file: a 16:9 box on a 4:3
    /// frame came out 1.94:1 (D-238).
    @Test func aRatioInNormalizedSpaceIsDividedByThePhotographsShape() throws {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let photo: CGFloat = 4.0 / 3.0
        let target: CGFloat = 16.0 / 9.0
        let box = try #require(CropGrip.shaped(unit.size, aspect: target / photo, driven: .smaller,
                                               unit: CGPoint(x: 0.5, y: 0.5),
                                               pin: CGPoint(x: 0.5, y: 0.5),
                                               within: unit, least: 0.02))
        let pixels = CGSize(width: box.width * 1600, height: box.height * 1200)
        #expect(abs(pixels.width / pixels.height - target) < 0.001,
                "\(pixels.width) × \(pixels.height) is not 16:9")
    }

    /// A drag with a ratio on it goes through the same `apply` a free one does,
    /// so the branch that reads the grip is the branch that is tested.
    @Test func aDragWithARatioOnItComesBackShaped() {
        let grip = CropGrip(at: CGPoint(x: 100, y: 100), in: nil)
        let box = grip.apply(translation: CGSize(width: 300, height: 40),
                             to: CGPoint(x: 100, y: 100), at: CGPoint(x: 400, y: 140),
                             within: frame, aspect: 1)
        #expect(abs(box.width - box.height) < 0.001, "a square drag came out \(box.size)")
        #expect(abs(box.minX - 100) < 0.001 && abs(box.minY - 100) < 0.001)
    }

    @Test func afreeDragIsStillWhateverItDraws() {
        let grip = CropGrip(at: CGPoint(x: 100, y: 100), in: nil)
        let box = grip.apply(translation: CGSize(width: 300, height: 40),
                             to: CGPoint(x: 100, y: 100), at: CGPoint(x: 400, y: 140),
                             within: frame)
        #expect(box == CGRect(x: 100, y: 100, width: 300, height: 40))
    }
}

/// A crop written into the photograph, and taken back off it (D-239).
@Suite struct CropInPlaceTests {
    init() { FileOps.useTestBackups() }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-crop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeJPEG(_ url: URL, width: Int = 80, height: Int = 60) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func size(of url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    @Test func theCropIsWrittenIntoThePhotographAndTheOriginalIsKept() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))

        #expect(try size(of: photo) == CGSize(width: 40, height: 30), "the file was not cropped")
        let kept = try #require(AdjustRecord.original(for: photo), "no original was kept")
        #expect(try size(of: kept) == CGSize(width: 80, height: 60), "the kept original is not the whole frame")
        #expect(try FolderScanner.scan(dir).map(\.name) == ["a.jpg"],
                "the crop left something else in the folder, or the kept original is not hidden")
    }

    @Test func undoPutsTheWholeFrameBack() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)
        let before = try Data(contentsOf: photo)

        let undo = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        try await undo.undo()

        #expect(try Data(contentsOf: photo) == before, "undo did not restore the original bytes")
        #expect(AdjustRecord.original(for: photo) == nil, "undo left a kept original behind")
        #expect(!AdjustRecord.isDerived(photo), "undo left the derived mark on the file")
    }

    /// The undo that outlives the session: the hidden original is what Revert
    /// reads, and it works on a crop for the same reason it works on an
    /// adjustment.
    @Test func revertPutsACroppedPhotographBack() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(AdjustRecord.isRevertable(photo))
        _ = try FileOps.revertAdjust(photo)

        #expect(try size(of: photo) == CGSize(width: 80, height: 60), "Revert did not put the frame back")
        #expect(!AdjustRecord.isDerived(photo), "Revert left the derived mark on a photograph it uncropped")
        #expect(AdjustRecord.original(for: photo) == nil, "Revert left the kept original behind")
    }

    /// The interaction that would lose the crop without saying anything: a
    /// photograph adjusted last week and cropped today must develop the
    /// *cropped* pixels next time, or the next save over it puts the
    /// cropped-out corner back (D-239).
    @Test func anAdjustmentAfterACropDevelopsTheCroppedFrame() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        var recipe = Adjustments.neutral
        recipe[.exposure] = 40
        _ = try FileOps.adjustInPlace(photo, recipe)
        #expect(AdjustRecord.base(for: photo) == AdjustRecord.originalURL(for: photo),
                "an adjusted photograph develops its kept original")

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(AdjustRecord.base(for: photo) == photo,
                "the crop was about to be developed away")
        #expect(AdjustRecord.recipe(for: photo) == nil,
                "the recipe stayed on a file the crop had already baked it into")
        #expect(AdjustRecord.editable(for: photo) == nil,
                "the panel would open at numbers that are already in these pixels")
        #expect(AdjustRecord.isRevertable(photo),
                "the original is still there, so Revert is still on offer")

        _ = try FileOps.adjustInPlace(photo, recipe)
        #expect(try size(of: photo) == CGSize(width: 40, height: 30),
                "saving an adjustment over the photograph undid the crop")
    }

    /// The same rule the adjust overwrite keeps: a second write does not
    /// replace the kept original, because the original is the frame as it
    /// arrived rather than the frame as it was a minute ago.
    @Test func asecondCropLeavesTheFirstKeptOriginalAlone() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))

        let kept = try #require(AdjustRecord.original(for: photo))
        #expect(try size(of: kept) == CGSize(width: 80, height: 60),
                "the second crop overwrote the kept original with an already-cropped frame")
        #expect(try size(of: photo) == CGSize(width: 20, height: 15),
                "the second crop did not crop the file it was drawn on")
    }

    /// Flags, favorites and labels live in extended attributes on the file
    /// (D-3), and a write that replaced the file rather than its contents
    /// would take them with it.
    @Test func theFlagOnAPhotographSurvivesBeingCroppedInto() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)
        try MetadataIO.writeFlag(.keep, to: photo)

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(FolderScanner.ref(for: photo)?.flag == .keep, "the crop threw the flag away")
    }

    /// Undoing a copy leaves the folder as it found it: the copy and the
    /// original it inherited both go, and the photograph keeps its own (D-243).
    @Test func undoingACopyTakesTheOriginalItInheritedWithIt() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        let (dest, undo) = try FileOps.cropCopy(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let inherited = AdjustRecord.originalURL(for: dest)
        #expect(FileManager.default.fileExists(atPath: inherited.path))

        try await undo.undo()
        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: inherited.path),
                "the hidden half of the copy stayed in the folder")
        #expect(try FolderScanner.scan(dir).map(\.name) == ["a.jpg"])
    }

    /// A copy of a copy inherits the same frame, not the copy it came from:
    /// `arrival` reads the kept original when there is one.
    @Test func acopyOfACopyStillPointsAtTheFrameThatArrived() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)
        let arrived = try Data(contentsOf: photo)

        let (first, _) = try FileOps.cropCopy(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let (second, _) = try FileOps.cropCopy(first, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let kept = try #require(AdjustRecord.original(for: second))
        #expect(try Data(contentsOf: kept) == arrived,
                "the second copy's way back stops at the first copy")
    }

    /// Refused rather than re-encoded into something the container cannot
    /// hold, which is the rule the adjust overwrite already keeps.
    @Test func aformatThatCannotHoldTheWriteIsRefused() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let gif = dir.appendingPathComponent("a.gif")
        try Data([0x47, 0x49, 0x46]).write(to: gif)
        #expect(throws: FileOps.Failure.self) {
            _ = try FileOps.cropInPlace(gif, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        }
    }

    /// The copy still exists and still never touches the original: ⇧Return is
    /// an addition to Return, not a replacement for it.
    @Test func theCopyStillLeavesThePhotographAlone() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)
        let before = try Data(contentsOf: photo)

        let (dest, _) = try FileOps.cropCopy(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(dest.lastPathComponent == "a.crop.jpg")
        #expect(try Data(contentsOf: photo) == before, "the copy rewrote the original")
        #expect(AdjustRecord.original(for: photo) == nil, "the copy kept an original for the photograph")
        #expect(!AdjustRecord.isDerived(photo), "the copy marked the photograph it did not touch")
        // The copy gets one of its own, so Revert on it reaches the frame this
        // photograph arrived as rather than the crop it was made from (D-243).
        let keptForCopy = try #require(AdjustRecord.original(for: dest), "the copy has no way back")
        #expect(try Data(contentsOf: keptForCopy) == before, "the copy inherited the wrong frame")
        #expect(AdjustRecord.isDerived(dest), "an adjustment would develop the frame the copy inherited")
    }
}

/// What the app leaves behind when it quits (D-242).
///
/// Neither of these mutates the session directory the rest of the suite is
/// writing into: one counts what arrives in it, the other drives the removal
/// over a directory of its own. A test that took the real one away would be
/// deleting another test's backup between its two steps.
@Suite struct SessionBackupTests {
    /// The real `sessionBackups` is what these exercise, and without this the
    /// run leaves it behind with a copy of the photograph in it (D-299).
    init() { FileOps.useTestBackups(); Preferences.useTestDefaults() }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-session-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeJPEG(_ url: URL) throws {
        let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func names(in dir: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    /// The second overwrite of a photograph copies it into the session's own
    /// directory, at full size: this is what there is to clean up, and it is
    /// the reader's photograph.
    @Test func asecondOverwriteLeavesAFullSizeCopyInTheSessionDirectory() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        // The first write keeps its original beside the photograph; the second
        // is the one that puts a copy in the session directory.
        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.8, height: 0.8))
        let before = names(in: FileOps.sessionBackups)
        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.8, height: 0.8))
        let arrived = names(in: FileOps.sessionBackups).subtracting(before)

        #expect(arrived.contains { $0.hasSuffix("-a.jpg") },
                "the second overwrite kept no backup: \(arrived)")
        #expect(FileOps.sessionBackupDirectory != nil,
                "the app would quit without knowing it has something to clean up")
        // 0700 and a name nobody can guess, which is the other half of D-173.
        let mode = try FileManager.default.attributesOfItem(atPath: FileOps.sessionBackups.path)[.posixPermissions] as? Int
        #expect(mode == 0o700, "the session directory is readable by somebody else: \(mode ?? -1)")
    }

    /// And quitting takes it away. Driven over a directory of this test's own,
    /// for the reason in the suite's comment.
    @Test func quittingRemovesTheBackupDirectory() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let backups = dir.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("pixels".utf8).write(to: backups.appendingPathComponent("x-a.jpg"))

        FileOps.forgetBackups(in: backups)
        #expect(!FileManager.default.fileExists(atPath: backups.path),
                "the session's copies of the reader's photographs outlived the app")
    }

    /// A launch takes away what a session that crashed left behind (D-299).
    ///
    /// Driven through `forgetEndedSessions(at:)`, which is the call the launch
    /// makes, over paths of this test's own. Three of them, so the sweep has to
    /// choose rather than empty the list: one marked with a pid nothing answers
    /// for, one marked with this process's own, and one with no marker at all —
    /// which is what a path somebody edited into the preference would look
    /// like, and the case that makes this a marker check and not a path check.
    @Test func aLaunchSweepsTheBackupsOfSessionsThatEnded() throws {
        let parent = try tempDir(); defer { try? FileManager.default.removeItem(at: parent) }
        let fm = FileManager.default

        func session(_ name: String, pid: Int32?) throws -> URL {
            let dir = parent.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("pixels".utf8).write(to: dir.appendingPathComponent("x-a.jpg"))
            if let pid {
                try Data("\(pid)".utf8).write(to: dir.appendingPathComponent(FileOps.sessionMarker))
            }
            return dir
        }

        // A pid nothing answers for. Searched for rather than assumed: the
        // sweep turns on `kill(pid, 0)` failing with ESRCH, and a pid that
        // happened to be alive would make this pass for having found a live
        // session rather than for having swept a dead one.
        var dead: Int32 = 99_999
        while kill(dead, 0) == 0 || errno == EPERM { dead -= 1 }

        let ended = try session("ended", pid: dead)
        let running = try session("running", pid: ProcessInfo.processInfo.processIdentifier)
        let notOurs = try session("not-ours", pid: nil)

        let swept = FileOps.forgetEndedSessions(at: [ended.path, running.path, notOurs.path])

        #expect(!fm.fileExists(atPath: ended.path),
                "a crashed session's copies of the reader's photographs are still there")
        #expect(fm.fileExists(atPath: running.path),
                "the sweep took a live session's backups, which is its undo stack")
        #expect(fm.fileExists(atPath: notOurs.path),
                "the sweep deleted a directory carrying no marker of ours")
        // Two paths come off the list and only one directory goes. Deleting and
        // striking off are different answers: the unmarked one is struck off
        // because nothing will ever act on it, and an entry that buys nothing
        // is how the list grows by one a launch and never shrinks. This
        // assertion read `== [ended.path]` until the third audit pass found the
        // list unbounded; it was rewritten rather than loosened.
        #expect(swept.sorted() == [ended.path, notOurs.path].sorted(),
                "the sweep reported the wrong paths to strike off the list: \(swept)")
        #expect(!swept.contains(running.path),
                "a live session's entry was struck off, so nothing will sweep it later")
    }

    /// An entry whose directory is already gone is struck off rather than
    /// carried forever. Same branch as the unmarked directory above and the
    /// opposite answer, which is the pair worth holding: one has no marker
    /// because it is somebody else's, the other has none because there is
    /// nothing there.
    @Test func anEntryForADirectoryThatIsGoneIsStruckOff() throws {
        let parent = try tempDir(); defer { try? FileManager.default.removeItem(at: parent) }
        let missing = parent.appendingPathComponent("never-existed").path
        #expect(FileOps.forgetEndedSessions(at: [missing]) == [missing],
                "a stale entry stays on the list forever")
    }

    /// And so is an entry for a directory that is there but carries no marker.
    /// Nothing will ever sweep it, so holding the entry only grows the list —
    /// one a launch, forever. The directory itself is left where it is, which
    /// is the half this shares with the not-ours case above.
    @Test func anEntryForADirectoryWithNoMarkerIsStruckOffButNotDeleted() throws {
        let parent = try tempDir(); defer { try? FileManager.default.removeItem(at: parent) }
        let dir = parent.appendingPathComponent("no-marker")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("pixels".utf8).write(to: dir.appendingPathComponent("x-a.jpg"))

        #expect(FileOps.forgetEndedSessions(at: [dir.path]) == [dir.path],
                "the entry stays on the list although nothing can ever act on it")
        #expect(FileManager.default.fileExists(atPath: dir.path),
                "a directory with no marker of ours was deleted anyway")
    }

    /// The registry the launch reads is the one the launch writes: register
    /// hands back the others and leaves ours behind for the next process
    /// (D-299). The suite runs on a scratch preferences domain, so this touches
    /// nothing the person running it keeps.
    @Test func theSessionRegistryHandsBackEveryPathButThisOne() {
        Preferences.forgetSessionBackups(Preferences.sessionBackupPaths)
        _ = Preferences.registerSessionBackups("/tmp/sift-one")
        let others = Preferences.registerSessionBackups("/tmp/sift-two")

        #expect(others == ["/tmp/sift-one"],
                "the second session was not handed the first one's path: \(others)")
        #expect(Preferences.sessionBackupPaths.sorted() == ["/tmp/sift-one", "/tmp/sift-two"],
                "registering dropped a live session's directory from the list")

        Preferences.forgetSessionBackups(["/tmp/sift-one"])
        #expect(Preferences.sessionBackupPaths == ["/tmp/sift-two"],
                "striking one path off took the other with it")
        Preferences.forgetSessionBackups(Preferences.sessionBackupPaths)
    }

    /// A write puts the directory back if it has gone, so neither the cleanup
    /// nor the system's own sweep can leave an overwrite with nowhere to put
    /// the bytes it is replacing.
    @Test func aWriteRemakesTheDirectoryIfItHasGone() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)
        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.8, height: 0.8))

        #expect(throws: Never.self) {
            _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.8, height: 0.8))
        }
    }
}

/// The report: crop twice, press Revert, and the photograph comes back as the
/// crop in the middle rather than as the frame it arrived as.
@Suite struct RevertAfterTwoCropsTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-twice-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeJPEG(_ url: URL) throws {
        let ctx = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func size(of url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    @Test func revertAfterTwoCropsGivesTheWholeFrameBack() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(try size(of: photo) == CGSize(width: 40, height: 30))
        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(try size(of: photo) == CGSize(width: 20, height: 15))

        _ = try FileOps.revertAdjust(photo)
        #expect(try size(of: photo) == CGSize(width: 80, height: 60),
                "Revert came back at the crop in the middle")
        #expect(!AdjustRecord.isRevertable(photo))
    }

    @Test func undoingTheSecondCropLeavesRevertOnOffer() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try writeJPEG(photo)

        _ = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let second = try FileOps.cropInPlace(photo, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        try await second.undo()

        #expect(try size(of: photo) == CGSize(width: 40, height: 30), "undo did not land on the first crop")
        #expect(AdjustRecord.isRevertable(photo),
                "undoing the second crop took the way back to the original with it")
        _ = try FileOps.revertAdjust(photo)
        #expect(try size(of: photo) == CGSize(width: 80, height: 60))
    }
}

/// The same sequence through the router and the store, which is where the
/// report came from: crop, save over, crop again, save over, then ask for the
/// original back.
@MainActor
@Suite struct CropRoundTripTests {
    init() { Preferences.useTestDefaults() }

    private func folder() throws -> (LibraryStore, CommandRouter, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-crop-trip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.jpg")
        let ctx = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        // A real open, not an insert: `reload` returns early without a folder,
        // and the reload after a save is half of what these tests are about.
        let s = LibraryStore()
        s.open(dir)
        s.cursor = 0
        s.loadAdjustRecord()
        return (s, CommandRouter(store: s), url, dir)
    }

    private func size(of url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    /// Waits for whatever the progress banner is running.
    private func settle(_ s: LibraryStore) async throws {
        for _ in 0..<200 where s.progress != nil { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(30))
    }

    private func cropOver(_ router: CommandRouter, _ s: LibraryStore, _ rect: CGRect) async throws {
        router.perform(.crop)
        s.cropRect = rect
        router.perform(.saveOverOriginal)
        try await settle(s)
    }

    @Test func croppingTwiceAndRevertingGivesTheWholeFrameBack() async throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await cropOver(router, s, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(try size(of: url) == CGSize(width: 40, height: 30))
        #expect(s.adjustRevertable, "the first crop left nothing to revert to")

        try await cropOver(router, s, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(try size(of: url) == CGSize(width: 20, height: 15))
        #expect(s.adjustRevertable, "the second crop took the way back with it")

        router.perform(.revertToOriginal)
        #expect(s.reverting)
        router.perform(.confirm)
        try await settle(s)

        #expect(try size(of: url) == CGSize(width: 80, height: 60),
                "Revert came back at the crop in the middle")
        #expect(!s.adjustRevertable, "there is nothing left to revert to")
    }

    /// And the undo of the second crop, which is the other button in the same
    /// corner: it lands on the crop before it, and Revert is still on offer.
    /// Crop over the photograph, revert it, then take the revert back. The
    /// files come home correctly — the inverse copies the restored original
    /// aside before the cropped one goes back — but the bar went on saying
    /// there was nothing to revert to, so the crop was on screen with no way
    /// off it until you arrowed away and back (D-286).
    @Test func undoingARevertPutsRevertBackOnOffer() async throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await cropOver(router, s, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(s.adjustRevertable, "a save over the photograph keeps its original")

        // Revert opens a preview of the original and asks; the write is the
        // answer to it.
        router.perform(.revertToOriginal)
        router.perform(.confirm)
        try await settle(s)
        #expect(try size(of: url) == CGSize(width: 80, height: 60), "the revert did not land")
        #expect(s.adjustRevertable == false, "nothing left to revert to")

        router.perform(.undo)
        try await settle(s)

        #expect(try size(of: url) == CGSize(width: 40, height: 30), "the undo did not bring the crop back")
        #expect(AdjustRecord.isRevertable(url), "the kept original did not come back with it")
        #expect(s.adjustRevertable, "the file is revertable and the bar is the last to know")
    }

    @Test func undoingACropLeavesRevertOnOffer() async throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await cropOver(router, s, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        try await cropOver(router, s, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        router.perform(.undo)
        try await settle(s)

        #expect(try size(of: url) == CGSize(width: 40, height: 30), "undo did not land on the first crop")
        #expect(AdjustRecord.isRevertable(url), "the undo took the kept original with it")
        #expect(s.adjustRevertable, "the bar would not offer Revert on a photograph that has an original")
    }

    /// The reported sequence, and the one that used to land on the crop in the
    /// middle: the first save was a copy, which moves the cursor onto the copy,
    /// and the second save wrote into that copy. The copy's original was the
    /// first crop, so Revert went back to that and then had nothing left to
    /// offer. The copy inherits the frame the photograph arrived as now, so it
    /// goes all the way back (D-243).
    @Test func revertOnACroppedCopyReachesTheFrameThePhotographArrivedAs() async throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        router.perform(.crop)
        s.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        router.perform(.confirm)
        try await settle(s)
        // The store's own spelling of it: `/var` and `/private/var` are the
        // same place and the scanner canonicalizes (D-34).
        #expect(s.current?.name == "a.crop.jpg", "the cursor did not follow the copy")
        let copy = try #require(s.current?.url)
        #expect(try size(of: url) == CGSize(width: 80, height: 60), "the photograph was touched")

        s.loadAdjustRecord()
        #expect(s.adjustRevertable, "the copy came with no way back to the original")

        try await cropOver(router, s, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(try size(of: copy) == CGSize(width: 20, height: 15))

        router.perform(.revertToOriginal)
        router.perform(.confirm)
        try await settle(s)
        #expect(try size(of: copy) == CGSize(width: 80, height: 60),
                "Revert on a copy came back at the crop in the middle")
        #expect(try size(of: url) == CGSize(width: 80, height: 60), "the photograph was touched")
    }
}

/// The keyboard ring belongs to the bar that is on screen (D-244).
@MainActor
@Suite struct ModeBarKeyboardTests {
    init() { Preferences.useTestDefaults() }

    private func folder() throws -> (LibraryStore, CommandRouter, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-ring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.jpg")
        let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
        let s = LibraryStore()
        s.open(dir)
        s.cursor = 0
        s.focus = .preview
        return (s, CommandRouter(store: s), url, dir)
    }

    /// Tab during a crop used to move a ring around the preview bar, which is
    /// not on screen while the mode runs — and Return presses what the ring is
    /// on before it does anything else. Tab, Return, and the photograph you
    /// were cropping went to the Trash (D-244). It walks the crop bar now.
    @Test func tabDuringACropWalksTheCropBar() throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        router.perform(.crop)
        s.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        router.perform(.barNext)
        #expect(s.barCursor == nil, "a ring is on a control nobody can see")
        #expect(s.modeBarCursor == .ratio(.free), "Tab did not reach the bar that is on screen")

        router.perform(.confirm)
        #expect(FileManager.default.fileExists(atPath: url.path),
                "Return pressed something that was not the ring")
        #expect(s.cropping, "Return on a ratio left the mode")
    }

    /// The whole row, in the order it is drawn, and back again.
    @Test func tabWalksEveryStopTheCropBarDraws() throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try FileOps.cropInPlace(url, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        s.loadAdjustRecord()
        router.perform(.crop)
        s.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        s.cropRatio = .sixteenNine

        let drawn = s.modeBarStops
        #expect(drawn.contains(.turn), "16:9 can be stood up, so the mark is drawn and is a stop")
        #expect(drawn.contains(.revert), "this photograph has an original kept beside it")
        #expect(drawn.contains(.saveCopy) && drawn.contains(.saveOver), "there is a box to save")

        var seen: [ModeBarStop] = []
        for _ in drawn.indices {
            router.perform(.barNext)
            seen.append(try #require(s.modeBarCursor))
        }
        #expect(seen == drawn, "Tab walked a different row than the bar draws")
        router.perform(.barNext)
        #expect(s.modeBarCursor == drawn.first, "the walk does not come round")
        router.perform(.barPrevious)
        #expect(s.modeBarCursor == drawn.last)
    }

    /// A stop the bar does not draw is not a stop: no turn on a square, no
    /// Revert without an original, no saves without a box.
    @Test func theWalkHasNoStopForAControlThatIsNotDrawn() throws {
        let (s, router, _, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        router.perform(.crop)
        s.cropRatio = .square

        let drawn = s.modeBarStops
        #expect(!drawn.contains(.turn), "a square has nothing to turn")
        #expect(!drawn.contains(.revert), "nothing has been written into this photograph")
        #expect(!drawn.contains(.saveCopy) && !drawn.contains(.saveOver), "there is no box yet")
        #expect(drawn.contains(.cancel), "the way out is always drawn")
    }

    /// Return on a stop does what the click does, which is what makes the ring
    /// worth walking.
    @Test func returnOnAStopSetsTheRatioAndTurnsIt() throws {
        let (s, router, _, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        router.perform(.crop)

        router.pressModeBar(.ratio(.fourThree))
        #expect(s.cropRatio == .fourThree)
        router.pressModeBar(.turn)
        #expect(s.cropRatioTurned)
        router.pressModeBar(.cancel)
        #expect(!s.cropping, "Cancel on the ring stayed in the mode")
    }

    /// Esc leaves the ring before it leaves the mode: the ring is the innermost
    /// thing on screen, which is the rule the preview bar's already keeps.
    @Test func escapeLeavesTheRingBeforeTheMode() throws {
        let (s, router, _, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        router.perform(.crop)
        router.perform(.barNext)
        #expect(s.modeBarCursor != nil)

        router.perform(.cancel)
        #expect(s.modeBarCursor == nil)
        #expect(s.cropping, "Esc left the mode and the ring at once")
        router.perform(.cancel)
        #expect(!s.cropping)
    }

    /// The same while the revert preview is up.
    @Test func tabDuringARevertWalksItsTwoAnswers() throws {
        let (s, router, url, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try FileOps.cropInPlace(url, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        s.loadAdjustRecord()

        router.perform(.revertToOriginal)
        router.perform(.barNext)
        #expect(s.barCursor == nil)
        #expect(s.modeBarCursor == .cancel)
        router.perform(.barNext)
        #expect(s.modeBarCursor == .saveOver)
        #expect(s.reverting, "the walk took the mode with it")
    }

    /// Entering a mode takes the ring away rather than leaving it armed behind
    /// the bar that replaced it.
    @Test func enteringACropClearsTheRingThatWasAlreadyThere() throws {
        let (s, router, _, dir) = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        router.perform(.barNext)
        #expect(s.barCursor != nil, "the preview bar's own ring stopped working")
        router.perform(.crop)
        #expect(s.barCursor == nil, "the ring outlived the bar it was on")
    }
}
