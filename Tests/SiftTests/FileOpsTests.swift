import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// Real files in a temp folder: these operations only make sense against disk.
@Suite struct FileOpsTests {
    init() { FileOps.useTestBackups(); Preferences.useTestDefaults() }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a 40x20 JPEG (wider than tall) so rotation is observable.
    private func writeJPEG(_ url: URL, width: Int = 40, height: Int = 20, orientation: Int? = nil) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        // `#require` rather than `!`: a name the filesystem will not hold
        // returns nil here, and a force unwrap takes the whole run down with
        // a signal instead of failing the one test that asked for it.
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.jpeg.identifier as CFString, 1, nil),
                                "no JPEG writer for \(url.lastPathComponent)")
        let props = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(dest, img, props)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func ref(_ url: URL) -> PhotoRef { FolderScanner.ref(for: url)! }

    @Test func flagRoundTripsThroughFinderTags() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        try (f as NSURL).setResourceValue(["Blue"] as NSArray, forKey: .tagNamesKey)

        _ = try FileOps.setFlag(.keep, on: ref(f))
        #expect(ref(f).flag == .keep)
        let tags = try f.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        #expect(tags.contains("Blue"), "unrelated tags survive")

        let undo = try FileOps.setFlag(.reject, on: ref(f))
        #expect(ref(f).flag == .reject)
        try await undo.undo()
        #expect(ref(f).flag == .keep)
    }

    @Test func favoriteRoundTripsThroughFinderTags() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        #expect(ref(f).favorite == false)
        let undo = try FileOps.setFavorite(true, on: ref(f))
        #expect(ref(f).favorite)
        try await undo.undo()
        #expect(ref(f).favorite == false)
    }

    /// The flag and the favorite are two tags on one file, and writing either
    /// reads the list back rather than replacing it (D-55).
    @Test func theFavoriteAndTheFlagDoNotOverwriteEachOther() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)

        _ = try FileOps.setFlag(.keep, on: ref(f))
        _ = try FileOps.setFavorite(true, on: ref(f))
        #expect(ref(f).flag == .keep && ref(f).favorite)

        _ = try FileOps.setFlag(.reject, on: ref(f))
        #expect(ref(f).favorite, "changing the flag leaves the favorite alone")

        let undo = try FileOps.setFavorite(false, on: ref(f))
        #expect(ref(f).flag == .reject && !ref(f).favorite)
        try await undo.undo()
        #expect(ref(f).flag == .reject && ref(f).favorite)
    }

    @Test func renameAndUndo() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        let (dest, undo) = try FileOps.rename(f, to: "b.jpg")
        #expect(dest.lastPathComponent == "b.jpg")
        #expect(!FileManager.default.fileExists(atPath: f.path))
        try await undo.undo()
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func renameRefusesToClobber() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.jpg"); try writeJPEG(a)
        let b = dir.appendingPathComponent("b.jpg"); try writeJPEG(b)
        #expect(throws: (any Error).self) { try FileOps.rename(a, to: "b.jpg") }
    }

    /// A rename is a rename, not a move (D-173). `appendingPathComponent`
    /// would have read every one of these as a path, so `../out.jpg` took the
    /// photograph out of the folder and a batch pattern with a slash in it
    /// took the selection with it. The assertion is on the file still being
    /// where it was, not only on the throw: a guard that rejects the name
    /// after the move has already happened passes a test that reads the error.
    @Test func renameRefusesAPathRatherThanAName() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let parent = dir.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let a = parent.appendingPathComponent("a.jpg"); try writeJPEG(a)

        for name in ["../escaped.jpg", "sub/a.jpg", "/tmp/a.jpg", "..", ".", "  ", ".hidden.jpg", "a:b.jpg"] {
            #expect(throws: (any Error).self) { try FileOps.rename(a, to: name) }
        }
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escaped.jpg").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["a.jpg"])
    }

    /// The ingest's **Into** field is a name, and it is the second place in the
    /// app that builds a path out of typed text (D-303).
    ///
    /// `nameOnly` had one caller. A fourth security pass filed "path traversal
    /// is closed" against the guard rather than against the call sites, and the
    /// ingest was never one: `appendingPathComponent` reads `..` as the parent,
    /// so `../../Elsewhere` created a directory outside the folder the picker
    /// named, the card copied into it, and the app then opened it, so the
    /// screen showed a copy that had gone somewhere else. There is no undo for
    /// an ingest to offer afterwards.
    ///
    /// The outcome on disk, not the throw. A guard that refuses after the
    /// directory has been made is a guard that passes a test reading the error.
    @Test func theIngestSubfolderIsANameAndCannotLeaveTheChosenFolder() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let chosen = dir.appendingPathComponent("Pictures/Chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)

        for name in ["../../Escaped", "..", ".", "sub/deeper", "/tmp/absolute", ".hidden", "a:b"] {
            #expect(throws: (any Error).self) {
                let dest = try FileOps.ingestDestination(chosen, subfolder: name)
                // Only reached when the guard let it through. Do what the
                // ingest does next, so a name that escapes leaves the evidence
                // this test is looking for rather than a passing throw.
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            }
        }

        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Escaped").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["Pictures"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Pictures").path) == ["Chosen"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: chosen.path).isEmpty)
    }

    /// The names that are names still work, and an empty field still means the
    /// folder that was picked rather than one inside it.
    @Test func theIngestSubfolderTakesAnOrdinaryNameAndAnEmptyOne() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try FileOps.ingestDestination(dir, subfolder: "") == dir)
        #expect(try FileOps.ingestDestination(dir, subfolder: "   ") == dir)
        #expect(try FileOps.ingestDestination(dir, subfolder: "Harbor Weekend")
                == dir.appendingPathComponent("Harbor Weekend"))
        #expect(try FileOps.ingestDestination(dir, subfolder: "  2026-09-18  ")
                == dir.appendingPathComponent("2026-09-18"))
    }

    /// The **Rename** field is a name too, and it is the half D-303 left open.
    ///
    /// D-303 made **Into** a name and stopped there. The field under it takes
    /// a pattern that becomes a filename, the two are typed in one sitting,
    /// and nothing refused a `/` in the second one. It could not escape the
    /// folder — `rename` runs the same guard — so what happened instead was
    /// silence: the copy landed, the rename threw, the ingest swallowed it
    /// with `try?`, and the toast counted the file as copied (D-304).
    @Test func theIngestRefusesARenamePatternThatIsNotAName() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try FileOps.ingestPlan(destination: dir, subfolder: "", pattern: "") == dir)
        #expect(try FileOps.ingestPlan(destination: dir, subfolder: "", pattern: "  ") == dir)
        #expect(try FileOps.ingestPlan(destination: dir, subfolder: "Shoot", pattern: "{date}_{nnn}")
                == dir.appendingPathComponent("Shoot"))

        for bad in ["holiday/{nnn}", "{name}:1", ".{nnn}", "/tmp/{nnn}", "..", "."] {
            #expect(throws: FileOps.Failure.self) {
                try FileOps.ingestPlan(destination: dir, subfolder: "", pattern: bad)
            }
        }
        // Into is the field above, so a sheet with both wrong names that one.
        #expect(throws: FileOps.Failure.self) {
            try FileOps.ingestPlan(destination: dir, subfolder: "../out", pattern: "a/b")
        }
    }

    /// A copy that lands and cannot take its new name is counted and said out
    /// loud, rather than reported as an ordinary success (D-304).
    ///
    /// The collision is the case that gets hit, and it needs no strange input:
    /// a pattern with no counter in it asks every frame on the card for one
    /// name. `rename` refuses the second, and the photograph stays on disk
    /// under the name it arrived with — which is the state the sentence has to
    /// describe.
    @Test func aCopyThatKeptItsCardNameIsCountedAndSaidOutLoud() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("DSC_0001.JPG")
        let second = dir.appendingPathComponent("DSC_0002.JPG")
        try writeJPEG(first)
        try writeJPEG(second)

        _ = try FileOps.rename(first, to: "Harbor.JPG")
        #expect(throws: (any Error).self) { _ = try FileOps.rename(second, to: "Harbor.JPG") }
        // The outcome on disk: the refusal left the file where it was, under
        // the name the card gave it.
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
                == ["DSC_0002.JPG", "Harbor.JPG"])

        #expect(CommandRouter.ingestReport(copied: 60, failed: 0, keptCardName: 59, stopped: false)
                == "Copied 60 photos, 59 kept the name on the card")
        #expect(CommandRouter.ingestReport(copied: 60, failed: 0, keptCardName: 0, stopped: false)
                == "Copied 60 photos")
        #expect(CommandRouter.ingestReport(copied: 2, failed: 1, keptCardName: 1, stopped: false)
                == "Copied 2 photos, 1 failed, 1 kept the name on the card")
    }

    /// The whitespace a name is typed with is not part of it, and trimming it
    /// is the one change `nameOnly` is allowed to make.
    @Test func renameTrimsRatherThanRefusing() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.jpg"); try writeJPEG(a)
        let (dest, _) = try FileOps.rename(a, to: "  b.jpg  ")
        #expect(dest.lastPathComponent == "b.jpg")
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    /// Where an overwrite's original waits is the owner's alone and cannot be
    /// guessed, so nobody else on the machine can arrange to be handed a copy
    /// of it (D-173). Asserting on the mode rather than on the API that was
    /// called: the directory the system hands back already exists, and
    /// `createDirectory` applies attributes only to what it creates.
    @Test func theKeptOriginalsSitInAPrivateDirectory() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.jpg"); try writeJPEG(a)
        // Two overwrites: the second is the one that keeps its backup in the
        // session directory, which is the directory under test.
        var adjust = Adjustments(); adjust.exposure = 0.3
        _ = try FileOps.adjustInPlace(a, adjust)
        let op = try FileOps.adjustInPlace(a, adjust)
        guard case .all(let steps) = op.inverse,
              case .moveBack(let backup, _) = steps.first
        else { Issue.record("an overwrite's inverse moves a backup home"); return }

        let holder = backup.deletingLastPathComponent()
        let mode = try FileManager.default.attributesOfItem(atPath: holder.path)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o700)
        #expect(holder.lastPathComponent.count > "Sift-originals-".count + 4)
    }

    @Test func moveAndUndo() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("sub"); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        let (dest, undo) = try FileOps.move(f, into: sub)
        #expect(dest == sub.appendingPathComponent("a.jpg"))
        #expect(FileManager.default.fileExists(atPath: dest.path))
        try await undo.undo()
        #expect(FileManager.default.fileExists(atPath: f.path))
    }

    @Test func rotateIsLosslessAndKeepsTheFavorite() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f, width: 40, height: 20)
        _ = try FileOps.setFavorite(true, on: ref(f))
        let before = try Data(contentsOf: f)

        let undo = try FileOps.rotate(f, clockwise: true)
        let decoded = try #require(ImageLoader.shared.decodeSync(f))
        #expect(decoded.width == 20 && decoded.height == 40, "orientation tag makes it portrait")
        #expect(ref(f).favorite, "the tag survives replaceItemAt")

        try await undo.undo()
        let back = try #require(ImageLoader.shared.decodeSync(f))
        #expect(back.width == 40 && back.height == 20)
        // Only the metadata block changed, so the file is about the same size, not re-encoded.
        let after = try Data(contentsOf: f)
        #expect(abs(after.count - before.count) < 200)
    }

    @Test func cropWritesACopyAndUndoTrashesIt() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f, width: 40, height: 20)
        let (copy, undo) = try FileOps.cropCopy(f, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(copy.lastPathComponent == "a.crop.jpg")
        let px = try #require(ImageLoader.pixelSize(of: copy))
        #expect(px.width == 20 && px.height == 20)
        #expect(FileManager.default.fileExists(atPath: f.path), "original untouched")
        try await undo.undo()
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    /// A frame shot vertically is stored landscape with an orientation flag
    /// that turns it, and everything laid out over the photograph — the fitted
    /// rect, the 1:1 scale, the clipping and focus masks — needs the size it is
    /// *drawn* at (D-167). The stored size put a portrait photograph inside a
    /// landscape rectangle and the masks painted the rectangle.
    @Test func pixelSizeIsTheSizeThePhotoIsDrawnAt() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let turned = dir.appendingPathComponent("turned.jpg")
        try writeJPEG(turned, width: 40, height: 20, orientation: 8)
        let px = try #require(ImageLoader.pixelSize(of: turned))
        #expect(px.width == 20 && px.height == 40, "the quarter turn was not applied")

        let flat = dir.appendingPathComponent("flat.jpg")
        try writeJPEG(flat, width: 40, height: 20, orientation: 1)
        let flatPx = try #require(ImageLoader.pixelSize(of: flat))
        #expect(flatPx.width == 40 && flatPx.height == 20, "an upright photo was turned")
    }

    @Test func patternExpansion() {
        let r = PhotoRef(url: URL(fileURLWithPath: "/x/IMG_0001.HEIC"), fileSize: 0,
                         created: Date(timeIntervalSince1970: 0), modified: .now)
        #expect(FileOps.expand(pattern: "{name}", ref: r, index: 1) == "IMG_0001.HEIC")
        #expect(FileOps.expand(pattern: "trip-{nn}", ref: r, index: 7) == "trip-07.HEIC")
        #expect(FileOps.expand(pattern: "{date}_{n}.jpg", ref: r, index: 3).hasSuffix("_3.jpg"))
        #expect(FileOps.expand(pattern: "{date}_{n}.jpg", ref: r, index: 3).hasPrefix("19"))
    }

    /// The `{date}` stamp does not belong to the person renaming the files
    /// (D-259). `DateFormatter` reads the machine's calendar and numerals
    /// unless it is told not to, so this shoot renamed to `2569-05-28` on a
    /// Thai machine and to `٢٠٢٦-٠٥-٢٨` on an Arabic one, and neither sorts
    /// beside what was already in the folder.
    ///
    /// The locales are the ones that actually broke it: Buddhist and Japanese
    /// eras move the year, Arabic and Persian move the digits.
    @Test func theRenameDateIsGregorianAndAsciiInEveryLocale() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let stamp = FileOps.dateStamp(date)
        #expect(stamp.hasPrefix("2026-"), "the default stamp is a Gregorian year, got \(stamp)")
        #expect(stamp.allSatisfy { $0.isASCII })
        for id in ["th_TH", "ja_JP", "ar_SA", "fa_IR", "hi_IN"] {
            #expect(FileOps.dateStamp(date, locale: Locale(identifier: id)) == stamp,
                    "\(id) renamed the shoot to something else")
        }
    }

    /// A rotate leaves the filename alone and replaces the bytes, so a view that
    /// keys its decode on the URL keeps painting the frame from before the turn.
    /// `contentID` is what makes the change visible.
    @Test func rotatingAPhotoChangesItsContentID() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        let before = ref(f).contentID

        _ = try FileOps.rotate(f, clockwise: true)
        #expect(ref(f).contentID != before, "a turned photo must re-decode")
    }

    /// The decode that loses the race. A thumbnail task started before a rotate
    /// can finish after it; keyed by URL it would hand the pre-rotation frame
    /// back to the view that just asked for the new one. Keyed by content, the
    /// late write lands somewhere nothing reads.
    @Test func aDecodeLandingAfterARotateCannotBeReadBackAsTheNewFrame() async throws {
        try await withIsolatedCaches {
            let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
            let before = ref(f).contentID

            let ctx = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let stale = DecodedImage(cgImage: ctx.makeImage()!)

            _ = try FileOps.rotate(f, clockwise: true)
            // The late write, arriving after the file on disk has already changed.
            ImageCache.thumbnails[before] = stale

            #expect(ImageCache.thumbnails[ref(f).contentID] == nil, "the turned photo must miss the cache and decode again")
        }
    }

    /// The other half: flags and the favorite are tags and never touch the bytes,
    /// so they must not invalidate a decode. A cull flags on nearly every frame,
    /// and re-decoding each one would be felt.
    @Test func flaggingAPhotoLeavesItsContentIDAlone() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        let before = ref(f).contentID

        _ = try FileOps.setFlag(.keep, on: ref(f))
        _ = try FileOps.setFavorite(true, on: ref(f))
        #expect(ref(f).contentID == before, "judging a photo must not re-decode it")
    }


    /// A mixed selection goes all-on rather than inverting photo by photo
    /// (D-55). The alternative reads as "flip each of these", which nobody
    /// means when they press one key over a dozen photos.
    @Test @MainActor func favoritingAMixedSelectionMakesThemAllFavorites() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "b.jpg", "c.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)
        store.selectAll()
        _ = try FileOps.setFavorite(true, on: store.photos[0])
        store.update(store.photos[0].url) { $0.favorite = true }

        router.perform(.toggleFavorite)
        let afterFirst = store.photos.filter { $0.favorite }.count
        #expect(afterFirst == 3, "one already set does not make it an invert")
        #expect(store.lastError == nil)

        router.perform(.toggleFavorite)
        let afterSecond = store.photos.filter { $0.favorite }.count
        #expect(afterSecond == 0, "all set means the next press clears them")
    }

    /// D-379. The rename sheet selects this much of the name.
    @Test func theStemIsWhatARenameOffers() {
        #expect(FileOps.stemRange(of: "frame-08.jpg") == NSRange(location: 0, length: 8))
        #expect(FileOps.stemRange(of: "archive.tar.gz") == NSRange(location: 0, length: 11),
                "the last dot, so a double extension keeps its tail")
        #expect(FileOps.stemRange(of: "README") == NSRange(location: 0, length: 6),
                "no extension means the whole name is the stem")
        #expect(FileOps.stemRange(of: ".hidden") == NSRange(location: 0, length: 7),
                "a leading dot is not an extension")
        // UTF-16, because that is what the field editor counts. Six scalars,
        // seven units: the flag is a surrogate pair.
        #expect(FileOps.stemRange(of: "sunset\u{1F1EF}\u{1F1F5}.jpg").length
                == ("sunset\u{1F1EF}\u{1F1F5}" as NSString).length)
    }
    /// The pixel width on disk, so a test can tell which photograph took a
    /// name rather than only that the name exists.
    private func width(of url: URL) throws -> Int {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        return try #require(props[kCGImagePropertyPixelWidth] as? Int)
    }

    /// Names in the folder, visible ones only, sorted. What the grid would show.
    private func names(_ dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    /// Everything on disk including the hidden files, so a parked photograph
    /// or a stranded kept original cannot pass as a clean run.
    private func everything(_ dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    /// A renumber is a permutation, and the old loop renamed one file at a
    /// time, so it collided with itself on the first frame and stopped.
    @Test @MainActor func renumberingASetIntoItsOwnNamesFinishes() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for (i, name) in ["01.jpg", "02.jpg", "03.jpg", "04.jpg"].enumerated() {
            try writeJPEG(dir.appendingPathComponent(name), width: 40 + i * 2)
        }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)
        // Reversed, so the plan is 04→01, 03→02, 02→03, 01→04: a true cycle,
        // not a shift that happens to have a free name at one end.
        let widths = try store.photos.reversed().map { ($0.url.lastPathComponent, try width(of: $0.url)) }

        router.batchRename(Array(store.photos.reversed()), pattern: "{nn}")
        await store.settle()

        #expect(try names(dir) == ["01.jpg", "02.jpg", "03.jpg", "04.jpg"])
        #expect(store.lastError == nil)
        for (i, (_, px)) in widths.enumerated() {
            let landed = dir.appendingPathComponent(String(format: "%02d.jpg", i + 1))
            #expect(try width(of: landed) == px, "each photograph took the name the plan gave it")
        }
    }

    /// The pattern is already applied. Nothing to do is not an error, and it
    /// used to be "Same name." on the first file and no rename at all.
    @Test @MainActor func rerunningAPatternThatIsAlreadyAppliedIsNotAnError() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "b.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)

        router.batchRename(store.photos, pattern: "{name}")
        await store.settle()

        #expect(try names(dir) == ["a.jpg", "b.jpg"])
        #expect(store.lastError == nil)
        #expect(store.undo.ops.isEmpty, "nothing happened, so there is nothing to take back")
    }

    /// Four photographs cannot share one name. The loop used to rename the
    /// first, refuse the second, and leave the shoot under two schemes.
    @Test @MainActor func aPatternWithNoCounterRefusesInsteadOfRenamingOne() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "b.jpg", "c.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)

        router.batchRename(store.photos, pattern: "Harbor")
        await store.settle()

        #expect(try names(dir) == ["a.jpg", "b.jpg", "c.jpg"], "refused before the first file moved")
        #expect(store.lastError != nil)
        #expect(store.undo.ops.isEmpty)
    }

    /// A name taken by a file nobody selected is a skip, counted in the
    /// sentence at the end, and the run carries on past it (D-41).
    @Test @MainActor func aNameTakenOutsideTheSelectionIsSkippedAndCounted() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "b.jpg", "c.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        // The intruder owns the name the third photograph is about to ask for.
        let intruder = dir.appendingPathComponent("shot-03.jpg")
        try writeJPEG(intruder, width: 60)
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)
        let selection = store.photos.filter { $0.name != "shot-03.jpg" }
        #expect(selection.count == 3)

        router.batchRename(selection, pattern: "shot-{nn}")
        await store.settle()

        #expect(try names(dir) == ["shot-01.jpg", "shot-02.jpg", "shot-03.jpg", "c.jpg"].sorted())
        #expect(try width(of: intruder) == 60, "the file nobody selected was not written over")
        #expect(store.toast?.message == "Renamed 2 photos, skipped 1")
    }

    /// The undo of a permutation is a permutation, so it is two-phase too:
    /// N `moveBack`s in any order land the first file on the second.
    @Test @MainActor func oneUndoTakesAWholeRenumberBack() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for (i, name) in ["01.jpg", "02.jpg", "03.jpg"].enumerated() {
            try writeJPEG(dir.appendingPathComponent(name), width: 40 + i * 2)
        }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)
        let before = try store.photos.map { ($0.url.lastPathComponent, try width(of: $0.url)) }

        router.batchRename(Array(store.photos.reversed()), pattern: "{nn}")
        await store.settle()
        #expect(store.undo.ops.count == 1, "one batch, one thing to press")

        router.perform(.undo)
        await store.settle()

        #expect(store.lastError == nil)
        #expect(try everything(dir) == ["01.jpg", "02.jpg", "03.jpg"])
        for (name, px) in before {
            #expect(try width(of: dir.appendingPathComponent(name)) == px,
                    "\(name) is the photograph it was before the batch, not just the name")
        }
    }

    /// The kept original's name is derived from the photograph's, so it has to
    /// park and place with it or a renumber drops it on the floor.
    @Test @MainActor func theKeptOriginalFollowsARenumber() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["01.jpg", "02.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        let one = dir.appendingPathComponent("01.jpg")
        try FileManager.default.copyItem(at: one, to: AdjustRecord.originalURL(for: one))
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)

        router.batchRename(Array(store.photos.reversed()), pattern: "{nn}")
        await store.settle()

        // 02→01 and 01→02, so the record that was 01's is now 02's.
        let moved = dir.appendingPathComponent("02.jpg")
        #expect(AdjustRecord.original(for: moved) != nil, "the record went where the photograph went")
        #expect(AdjustRecord.original(for: dir.appendingPathComponent("01.jpg")) == nil,
                "and did not stay behind under the old name")

        router.perform(.undo)
        await store.settle()
        #expect(AdjustRecord.original(for: one) != nil, "and came home with it")
        #expect(try everything(dir).filter { $0.contains("sift-original") }.count == 1)
    }

    /// A parked photograph is hidden, so a run that leaves one behind leaves a
    /// photograph nobody can see. Clean run, skip and stop, all three.
    @Test @MainActor func aBatchRenameLeavesNoHiddenFileBehind() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "b.jpg", "c.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        try writeJPEG(dir.appendingPathComponent("shot-03.jpg"))
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)

        router.batchRename(store.photos.filter { $0.name != "shot-03.jpg" }, pattern: "shot-{nn}")
        await store.settle()
        #expect(try everything(dir).filter { $0.contains("sift-renaming") }.isEmpty, "after a skip")

        store.reload()
        router.batchRename(store.photos, pattern: "frame-{nn}")
        await store.settle()
        #expect(try everything(dir).filter { $0.contains("sift-renaming") }.isEmpty, "after a clean run")
    }

    /// Esc during a rename. Every photograph is back under a name the grid
    /// shows, whether it had been parked yet or not.
    @Test @MainActor func escDuringARenameLeavesEveryPhotographUnderAVisibleName() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for i in 1...12 { try writeJPEG(dir.appendingPathComponent(String(format: "a%02d.jpg", i))) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        store.open(dir)
        let before = try names(dir)

        router.batchRename(store.photos, pattern: "b{nn}")
        // The claim is synchronous and the work is not, so this lands inside
        // the run.
        store.cancelProgress()
        await store.settle()

        #expect(try everything(dir).filter { $0.contains("sift-renaming") }.isEmpty)
        let after = try names(dir)
        #expect(after.count == before.count, "every photograph is visible under some name")
        #expect(Set(after).isSubset(of: Set(before).union((1...12).map { String(format: "b%02d.jpg", $0) })))
    }

    /// A park name adds 53 units to the stem. Without a cap the move throws on
    /// a long name, the photograph is counted as skipped, and it keeps its old
    /// name with nothing on screen saying which one or why.
    ///
    /// Three alphabets, because the ceiling is 255 UTF-16 code units and each
    /// one spends them at a different rate: one per letter, one per CJK
    /// character, two per emoji, and eleven for a family that is a single
    /// `Character`. A cap counting characters passes the first three and
    /// overflows on the fourth, so the fourth is the case that has to be here.
    /// Twenty-two of them and not more: at 23 the name with `.jpg` on it is
    /// 257 units and the filesystem will not hold the fixture either.
    @Test func aLongNameStillParks() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for stem in [String(repeating: "h", count: 200),
                     String(repeating: "\u{8377}", count: 200),
                     String(repeating: "\u{1F4F7}", count: 120),
                     String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", count: 22)] {
            let long = stem + ".jpg"
            let f = dir.appendingPathComponent(long); try writeJPEG(f)

            let parked = try FileOps.park(f)
            #expect(parked.lastPathComponent.utf16.count <= 255, "the unit the filesystem counts")
            #expect(parked.lastPathComponent.hasPrefix("."), "and is still hidden")
            #expect(parked.pathExtension == "jpg", "and still says what it is")
            try FileOps.unpark(parked, to: f)
            #expect(try names(dir) == [long])
            try FileManager.default.removeItem(at: f)
        }
    }

    /// An undo whose photograph will not move says so. It counted the failure
    /// as nothing and reported the batch as taken back.
    @Test func anUndoThatCannotMoveAPhotographRefusesOutLoud() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let here = dir.appendingPathComponent("a.jpg"); try writeJPEG(here)
        // The hop names a photograph that is not there, which is what an undo
        // aimed at a file somebody deleted in the Finder meets.
        let gone = dir.appendingPathComponent("gone.jpg")
        let inverse = Inverse.renameBack([.init(from: gone, to: here)])
        #expect(throws: (any Error).self) { try inverse.run() }
    }

    // MARK: the plan, before anything moves

    @Test func renamePlanValidatesEveryNameBeforeAnyFileMoves() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.jpg"); try writeJPEG(f)
        let refs = [ref(f)]
        for pattern in ["../{name}", "sub/{name}", ".{name}", "{name}:x", "  "] {
            #expect(throws: FileOps.Failure.self, "\(pattern) is not a name") {
                try FileOps.renamePlan(pattern: pattern, refs: refs)
            }
        }
    }

    @Test func renamePlanRefusesTwoPhotographsOneName() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "b.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        let refs = ["a.jpg", "b.jpg"].map { ref(dir.appendingPathComponent($0)) }
        #expect(throws: FileOps.Failure.self) { try FileOps.renamePlan(pattern: "Harbor", refs: refs) }

        let plan = try FileOps.renamePlan(pattern: "Harbor-{n}", refs: refs)
        #expect(plan.changing.count == 2)
        #expect(plan.unchanged == 0)
    }

    /// A name a photograph already has is an identity, not a move and not a
    /// failure — which is the whole of the re-run case.
    @Test func renamePlanCountsTheNamesThatAreNotMoving() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["01.jpg", "b.jpg"] { try writeJPEG(dir.appendingPathComponent(name)) }
        let refs = ["01.jpg", "b.jpg"].map { ref(dir.appendingPathComponent($0)) }
        let plan = try FileOps.renamePlan(pattern: "{nn}", refs: refs)
        #expect(plan.unchanged == 1, "01.jpg is already 01.jpg")
        #expect(plan.changing.count == 1)
        #expect(plan.changing[0].dest.lastPathComponent == "02.jpg")
    }
}

/// Mass rotation: a whole selection at once, off the main actor (D-41).
@Suite @MainActor struct MassRotateTests {
    init() { Preferences.useTestDefaults() }

    private func folder(jpegs: Int, plusUnrotatable: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-rot-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        let img = ctx.makeImage()!
        for i in 1...jpegs {
            let url = dir.appendingPathComponent("p\(i).jpg")
            // `#require` rather than `!`, for the reason the writer above
            // gives: a force unwrap takes the whole run down with a signal.
            let dest = try #require(CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil),
                "no JPEG writer for \(url.lastPathComponent)")
            CGImageDestinationAddImage(dest, img, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
        // A GIF cannot be rotated (PRD known gap), which is what makes it useful here.
        if plusUnrotatable { try Data([0x47, 0x49, 0x46]).write(to: dir.appendingPathComponent("z.gif")) }
        return dir
    }

    private func orientation(_ url: URL) -> UInt32 {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return 0 }
        return props[kCGImagePropertyOrientation] as? UInt32 ?? 1
    }

    /// Waits for the run itself rather than for its banner. The banner comes
    /// down before the undo is pushed and the toast is written (the toast must
    /// not stack under it), so spinning on `progress` used to return early and
    /// read the state one step before the one under test.
    private func settle(_ store: LibraryStore) async { await store.settle() }

    @Test func theWholeSelectionTurnsAndOneUndoTurnsItBack() async throws {
        let dir = try folder(jpegs: 4)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.perform(.rotateCW)
        await settle(store)

        #expect(store.photos.allSatisfy { orientation($0.url) == 6 }, "every photo in the selection turned")
        // No message: a clean batch is reported by the pill that offers to take
        // it back, and a second sentence saying the same thing is a second
        // control (D-283).
        #expect(store.toast == nil)
        #expect(store.undo.topLabel == "Rotate")
        #expect(store.undo.ops.count == 1, "one undo for the batch, not four")

        router.perform(.undo)
        // Undo finishes on a task of its own; the toast is how it says so.
        while store.toast?.message.hasPrefix("Undid") != true { await Task.yield() }
        #expect(store.photos.allSatisfy { orientation($0.url) == 1 })
    }

    /// The whole chain a redraw depends on: rotate writes, the store rescans,
    /// and the ref the grid hands to its image view is a different one than
    /// before. If this passes and the screen still shows the old frame, the
    /// break is below the store, not in it.
    @Test func afterARotateTheStoreHandsOutANewContentID() async throws {
        let dir = try folder(jpegs: 2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()
        let before = store.photos.map(\.contentID)

        router.perform(.rotateCW)
        await settle(store)

        let after = store.photos.map(\.contentID)
        #expect(after.count == before.count)
        for (b, a) in zip(before, after) {
            #expect(a != b, "the store still describes the photo as it was before the turn")
        }
    }

    @Test func aFileThatCannotTurnIsSkippedRatherThanEndingTheRun() async throws {
        let dir = try folder(jpegs: 3, plusUnrotatable: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.perform(.rotateCW)
        await settle(store)

        // A skip says more than the pill can, so this one still reports (D-283).
        #expect(store.toast?.message == "Rotated 3 photos, skipped 1")
        #expect(store.photos.filter { $0.url.pathExtension == "jpg" }.allSatisfy { orientation($0.url) == 6 })
        #expect(store.lastError == nil, "a skipped file is a count, not an alert")
    }

    @Test func aRunReportsProgressAndCanBeStopped() async throws {
        let dir = try folder(jpegs: 6)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.perform(.rotateCW)
        #expect(store.progress?.total == 6, "the run says how much there is to do before it starts")
        router.perform(.cancel)
        await settle(store)

        #expect(store.toast?.message.hasPrefix("Stopped") == true)
        #expect(store.selected.count == 6, "Esc stopped the rotation, it did not clear the selection")
    }

    /// D-196. The loop rotate has had since D-41 is every file command's now,
    /// so the stop and the skip are tested through a move rather than only
    /// through a turn: it is the same code, and the move is the one the PRD
    /// calls the organizing verb.
    @Test func aStoppedMoveKeepsWhatItMovedAndSaysSo() async throws {
        let dir = try folder(jpegs: 6)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.presenter = StubPresenter([dest])
        router.perform(.moveToFolder)
        #expect(store.progress?.total == 6, "the run says how much there is to do before it starts")
        router.perform(.cancel)
        await settle(store)

        #expect(store.toast?.message.hasPrefix("Stopped") == true,
                "a stopped move has to say it stopped: \(store.toast?.message ?? "no toast")")
        let landed = try FileManager.default.contentsOfDirectory(atPath: dest.path).count
        #expect(landed < 6, "the stop did nothing")
        // Esc can land before the first file or after the fourth, so the count
        // is not the rule. The rule is that a run leaves one undo for whatever
        // it managed, never one per file and never a partial run with no way
        // back at all.
        #expect(store.undo.ops.count == (landed > 0 ? 1 : 0),
                "\(landed) moved left \(store.undo.ops.count) undo entries")
    }

    /// A file the operation refuses is counted, not fatal. Before D-196 the
    /// three file commands stopped on the first error, which left the rest of a
    /// five-hundred frame move undone and said nothing about why.
    @Test func aFileThatWillNotMoveIsSkippedRatherThanEndingTheRun() async throws {
        let dir = try folder(jpegs: 3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        // Something already at the destination under the name the second photo
        // would take, and not writable over.
        try Data([0]).write(to: dest.appendingPathComponent("p2.jpg"))
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.presenter = StubPresenter([dest])
        router.perform(.moveToFolder)
        await settle(store)

        let message = store.toast?.message ?? "no toast"
        #expect(!message.hasPrefix("Nothing"), "one refusal ended the whole run: \(message)")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("p3.jpg").path),
                "the run stopped at the file it could not move instead of carrying on")
    }

    /// D-196 made the file commands asynchronous, and the progress claim
    /// refuses a second one. A refusal nobody can see is a keystroke that did
    /// nothing, which is what these commands never used to do.
    @Test func aSecondBatchIsRefusedOutLoudRatherThanSilently() async throws {
        let dir = try folder(jpegs: 6)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.perform(.rotateCW)
        #expect(store.progress != nil, "the first run did not take the banner")
        router.presenter = StubPresenter([dest])
        router.perform(.moveToFolder)

        #expect(store.toast?.message.hasPrefix("Still") == true,
                "the refused move said nothing: \(store.toast?.message ?? "no toast")")
        await settle(store)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty,
                "the refused move moved something anyway")
    }

    /// The command dismissed, not the function behind it. Impossible to test
    /// before D-197, because the panel was built inline and nothing could
    /// answer it.
    @Test func dismissingTheFolderPanelMovesNothing() async throws {
        let dir = try folder(jpegs: 3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        router.presenter = StubPresenter([])
        router.perform(.moveToFolder)
        await settle(store)

        #expect(store.photos.count == 3, "a dismissed panel took photos out of the folder")
        #expect(store.undo.ops.isEmpty, "a dismissed panel left something to undo")
        #expect(store.progress == nil, "a dismissed panel put a banner up")
    }

    @Test func rotatingWithNoSelectionStillTurnsThePhotoUnderTheCursor() async throws {
        let dir = try folder(jpegs: 2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        // Rewritten for D-141. The rule it holds is unchanged: with nothing
        // selected, a command acts on the photo under the cursor and only
        // that one. What changed is that opening a folder no longer puts a
        // cursor on the first photo, so the fixture has to say where the
        // keyboard is instead of inheriting it. Not loosened: the assertions
        // are the same two.
        store.cursor = 0

        router.perform(.rotateCW)
        await settle(store)

        #expect(orientation(store.photos[0].url) == 6)
        #expect(orientation(store.photos[1].url) == 1)
    }
}

/// Tech debt 3: the inverse is a description now, so a test can read it, a
/// missing card can be named, and persisting it later is a decision rather than
/// a rewrite (D-108).
@Suite struct InverseTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-inv-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeJPEG(_ url: URL) throws {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        // `#require` rather than `!`: a name the filesystem will not hold
        // returns nil here, and a force unwrap takes the whole run down with
        // a signal instead of failing the one test that asked for it.
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL,
                                                                UTType.jpeg.identifier as CFString, 1, nil),
                                "no JPEG writer for \(url.lastPathComponent)")
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func aMoveSaysWhereItWouldPutTheFileBack() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let away = dir.appendingPathComponent("away")
        try FileManager.default.createDirectory(at: away, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.jpg"); try writeJPEG(file)

        let (moved, op) = try FileOps.move(file, into: away)
        #expect(op.inverse == .moveBack(from: moved, to: file),
                "the way back is readable without running it")
    }

    @Test func anUndoAimedAtAFolderThatIsGoneSaysSo() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let card = dir.appendingPathComponent("NO NAME/DCIM")
        let inverse = Inverse.moveBack(from: card.appendingPathComponent("a.jpg"),
                                       to: card.appendingPathComponent("b.jpg"))

        #expect(inverse.missingFolder()?.lastPathComponent == "DCIM")
        #expect(throws: FileOps.Failure.self) { try inverse.run() }
        do {
            try inverse.run()
        } catch let failure as FileOps.Failure {
            #expect(failure.message.contains("DCIM"), "it names the folder that is not there")
            #expect(failure.message.contains("can't be undone"))
        }
    }

    @Test func aBatchIsCheckedBeforeAnyOfItRuns() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let here = dir.appendingPathComponent("a.jpg"); try writeJPEG(here)
        let gone = dir.appendingPathComponent("unplugged/b.jpg")

        let batch = Inverse.all([.trash(here), .moveBack(from: gone, to: gone)])
        #expect(throws: FileOps.Failure.self) { try batch.run() }
        #expect(FileManager.default.fileExists(atPath: here.path),
                "the half that could have run did not: a batch is all or nothing about being reachable")
    }

    @Test func aBatchUndoesItsLastOperationFirst() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let one = dir.appendingPathComponent("1.jpg"); try writeJPEG(one)
        let two = dir.appendingPathComponent("2.jpg"); try writeJPEG(two)
        let renamedOne = dir.appendingPathComponent("first.jpg")
        let renamedTwo = dir.appendingPathComponent("second.jpg")
        try FileManager.default.moveItem(at: one, to: renamedOne)
        try FileManager.default.moveItem(at: two, to: renamedTwo)

        try Inverse.all([.moveBack(from: renamedOne, to: one), .moveBack(from: renamedTwo, to: two)]).run()
        #expect(FileManager.default.fileExists(atPath: one.path))
        #expect(FileManager.default.fileExists(atPath: two.path))
    }

    // MARK: batch rename (D-380)

    @Test func anInverseSurvivesBeingWrittenDownAndReadBack() throws {
        let inverses: [Inverse] = [
            .moveBack(from: URL(fileURLWithPath: "/x/a.jpg"), to: URL(fileURLWithPath: "/y/a.jpg")),
            .trash(URL(fileURLWithPath: "/x/b.crop.jpg")),
            .restoreMark(.label, url: URL(fileURLWithPath: "/x/c.jpg"), flag: .keep, favorite: true, label: "Red"),
            .turn(URL(fileURLWithPath: "/x/d.jpg"), clockwise: false),
            .renameBack([.init(from: URL(fileURLWithPath: "/x/01.jpg"), to: URL(fileURLWithPath: "/x/02.jpg"))])
        ]
        let op = UndoableOp(label: "Move", folder: URL(fileURLWithPath: "/x"), inverse: .all(inverses))
        let data = try JSONEncoder().encode(op)
        #expect(try JSONDecoder().decode(UndoableOp.self, from: data) == op,
                "which is what makes persisting the stack a decision rather than a rewrite")
    }

    @Test func restoringOneMarkRestoresTheSidecarsWholeTriple() async throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.jpg"); try writeJPEG(file)
        // On disk, not just on the ref: the inverse carries what the tags say.
        _ = try FileOps.setFavorite(true, on: FolderScanner.ref(for: file)!)
        let ref = FolderScanner.ref(for: file)!
        #expect(ref.favorite)

        let op = try FileOps.setFlag(.reject, on: ref)
        #expect(op.inverse == .restoreMark(.flag, url: file, flag: nil, favorite: true, label: nil),
                "the favorite comes along, because the sidecar carries all three")
        try await op.undo()
        #expect(FolderScanner.ref(for: file)?.flag == nil)
        #expect(FolderScanner.ref(for: file)?.favorite == true, "and it did not clear what it was carrying")
    }
}

/// The stack itself, once the inverse is data (D-108).
@Suite @MainActor struct UndoStackTests {
    init() { Preferences.useTestDefaults() }

    @Test func anUndoThatCouldNotRunGoesBackOnTheStack() async {
        let store = LibraryStore()
        let gone = URL(fileURLWithPath: "/Volumes/NO NAME/DCIM/a.jpg")
        store.pushUndo(UndoableOp(label: "Move to Trash", inverse: .moveBack(from: gone, to: gone)))

        let router = CommandRouter(store: store)
        router.perform(.undo)
        for _ in 0..<200 where store.lastError == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.lastError?.contains("DCIM") == true, "it says which folder is missing")
        #expect(store.undo.canUndo, "and the way back is still there for when the card is plugged in again")
    }
}

/// Tech debt 2: an undo no longer empties the caches (D-109).
@Suite @MainActor struct UndoCacheTests {
    init() { Preferences.useTestDefaults() }

    @Test func undoingOnePhotoKeepsEveryOtherPhotosThumbnail() async throws {
        // A private pair of caches: the assertion below is that nothing in the
        // undo path emptied them, which only means something when this test is
        // the only writer (D-149).
        try await withIsolatedCaches {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-cache-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let file = dir.appendingPathComponent("a.jpg")
            let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            #expect(CGImageDestinationFinalize(dest))

            // A neighbor's thumbnail, the kind a wholesale clear used to take with it.
            let neighbor = "cache-test-\(UUID().uuidString)"
            ImageCache.thumbnails[neighbor] = DecodedImage(cgImage: ctx.makeImage()!)

            let store = LibraryStore()
            store.pushUndo(try FileOps.setFlag(.keep, on: FolderScanner.ref(for: file)!))
            let router = CommandRouter(store: store)
            router.perform(.undo)
            for _ in 0..<200 where store.toast == nil && store.lastError == nil {
                try? await Task.sleep(for: .milliseconds(5))
            }

            #expect(store.lastError == nil)
            #expect(store.toast?.message == "Undid flag", "the undo did run, so the check below is about something")
            #expect(ImageCache.thumbnails[neighbor] != nil,
                    "the folder's other decodes survive an undo of one photo")
        }
    }
}

/// D-189. `store.progress` is one slot. It used to be written by six places,
/// two of which checked whether anybody else had it, and the collision was
/// reachable in one keystroke: rotate a take, press `⌘Z` while it runs.
@Suite @MainActor struct ProgressHandleTests {
    init() { Preferences.useTestDefaults() }

    private func folder(jpegs n: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-progress-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<n {
            let image = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
            let url = dir.appendingPathComponent("p\(i).jpg")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        return dir
    }

    /// The bug, as a keystroke. Before the handle, the undo replaced the
    /// rotation's banner, the rotation went on incrementing the undo's counter,
    /// and the undo's `defer` took the banner down with the rotation still
    /// running — so its stop button was gone and nothing on screen said a
    /// hundred files were still being rewritten.
    @Test func anUndoCannotTakeTheBannerFromARotationInFlight() async throws {
        let dir = try folder(jpegs: 6)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(dir)
        store.selectAll()

        // Something on the stack to undo, so the refusal is the reason nothing
        // happens rather than an empty stack being it.
        router.perform(.toggleFavorite)
        let undosBefore = store.undo.ops.count
        #expect(undosBefore > 0, "the test has nothing to try to undo")

        router.perform(.rotateCW)
        #expect(store.progress?.label == "Rotating", "the banner is up in the same turn as the key")

        router.perform(.undo)
        #expect(store.progress?.label == "Rotating", "the undo took the rotation's banner")
        #expect(store.toast?.message == "Still rotating", "and it did so silently")
        #expect(store.undo.ops.count == undosBefore, "the refused undo swallowed the way back")

        while store.progress != nil { await Task.yield() }
        #expect(store.progress == nil, "the rotation left the banner up")
    }

    /// The token, not a Bool: a run that has lost the banner writes nothing,
    /// so a late `end` cannot clear the banner of whatever took its place.
    @Test func aRunThatLostTheBannerTouchesNothing() {
        let store = LibraryStore()
        let first = store.beginProgress("First", total: 10)
        first.advance(to: 3)
        #expect(store.progress?.done == 3)

        // While it is up, nobody else can claim it.
        let second = store.beginProgress("Second", total: 4)
        second.advance(to: 2)
        #expect(store.progress?.label == "First", "a second claim took the banner")
        #expect(store.progress?.done == 3, "a run with no claim moved somebody else's counter")

        first.end()
        #expect(store.progress == nil)

        // And now the slot is free, so the stale handle must still do nothing.
        let third = store.beginProgress("Third", total: 5)
        first.advance(to: 9)
        first.end()
        #expect(store.progress?.label == "Third", "a stale end took down a live banner")
        #expect(store.progress?.done == 0, "a stale advance moved a live counter")
        third.end()
    }

    /// `end` is idempotent, because the scoped helper ends every run behind the
    /// caller as a safety net and a run that reports after its banner is down
    /// calls it first.
    @Test func endingTwiceIsTheSameAsEndingOnce() {
        let store = LibraryStore()
        let run = store.beginProgress("Work")
        run.end()
        run.end()
        #expect(store.progress == nil)
    }

    /// A read runs whether or not it can say so, which is why the folder-facts
    /// pass takes this one: a folder opened during a rotation still needs its
    /// dates.
    @Test func aSilentRunIsEveryCallAndNoBanner() {
        let store = LibraryStore()
        let quiet = store.beginProgress("Reading", total: 3, showing: false)
        quiet.advance(to: 2)
        quiet.step()
        #expect(store.progress == nil, "a run asked not to show put a banner up")
        #expect(quiet.cancelled == false, "a banner nobody can see cannot be stopped")
        quiet.end()
        #expect(store.progress == nil)
    }
}

/// D-193. A trash is a plain action with an undo, except when a favorite is in
/// it. That is the one mark somebody set deliberately, and the undo covering a
/// trash is in memory only — quit after trashing a loved frame and the way back
/// is Finder, not this app.
@Suite @MainActor struct TrashConfirmTests {
    init() { Preferences.useTestDefaults() }

    private func folder(_ n: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-confirm-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<n { try Data([0xFF, 0xD8, 0xFF]).write(to: dir.appendingPathComponent("p\(i).jpg")) }
        return dir
    }

    private func open(_ dir: URL) -> CommandRouter {
        let router = CommandRouter(store: LibraryStore())
        router.open(dir)
        return router
    }

    /// The common case is unchanged. A guardrail on every trash is a dialog
    /// that gets clicked through, which is worse than none.
    /// `await settle()` is new here, and it is the behavior change rather than a
    /// loosened test: a trash runs off the main actor now, so the file is gone
    /// when the run finishes rather than when the command returns (D-196). What
    /// the test asserts is unchanged — no question was asked, and the photo
    /// went.
    @Test func trashingSomethingUnlovedStillGoesStraightThrough() async throws {
        let dir = try folder(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        router.store.cursor = 0
        let gone = router.store.photos[0].url

        router.perform(.trash)
        #expect(router.store.trashConfirm == nil, "an unloved photo was put behind a question")
        await router.store.settle()
        #expect(!FileManager.default.fileExists(atPath: gone.path), "and it did not go")
    }

    @Test func trashingAFavoriteAsksFirstAndTouchesNothing() throws {
        let dir = try folder(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        router.store.cursor = 0
        router.perform(.toggleFavorite)
        let loved = router.store.photos[0].url

        router.perform(.trash)
        let asked = try #require(router.store.trashConfirm, "a favorite went to the Trash unasked")
        #expect(asked.refs.map(\.url) == [loved])
        #expect(FileManager.default.fileExists(atPath: loved.path), "it went before the question was answered")
    }

    @Test func sayingNoLeavesItWhereItIs() throws {
        let dir = try folder(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        router.store.cursor = 0
        router.perform(.toggleFavorite)
        let loved = router.store.photos[0].url

        router.perform(.trash)
        router.store.trashConfirm = nil
        #expect(FileManager.default.fileExists(atPath: loved.path))
        #expect(router.store.photos.count == 2, "the folder lost a photo to a cancelled question")
    }

    /// The question carries the photographs, not a promise to re-read the aim.
    /// `aiming(at:)` restores the outer aim the moment `perform` returns
    /// (D-104), and the cursor is free to move while the sheet is up — so a yes
    /// that looked at `store.targets` would trash whatever was under the cursor
    /// by then.
    @Test func sayingYesTrashesWhatTheQuestionNamedEvenIfTheCursorMoved() async throws {
        let dir = try folder(3)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        router.store.cursor = 0
        router.perform(.toggleFavorite)
        let named = try #require(router.store.photos.first).url

        router.perform(.trash)
        let asked = try #require(router.store.trashConfirm)
        router.store.cursor = 2
        let bystander = router.store.photos[2].url

        router.performTrash(asked.refs)
        await router.store.settle()
        #expect(!FileManager.default.fileExists(atPath: named.path), "the photo named in the question stayed")
        #expect(FileManager.default.fileExists(atPath: bystander.path), "it trashed whatever the cursor had moved to")
        #expect(router.store.trashConfirm == nil, "the question stayed up after it was answered")
        #expect(router.store.undo.ops.count > 0, "a confirmed trash is still undoable")
    }

    /// A selection asks when any of it is loved, and says how many.
    @Test func aMixedSelectionAsksAndCountsTheFavorites() throws {
        let dir = try folder(4)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        let store = router.store
        store.cursor = 0
        router.perform(.toggleFavorite)
        store.cursor = 1
        router.perform(.toggleFavorite)
        store.selectAll()

        router.perform(.trash)
        let asked = try #require(store.trashConfirm)
        #expect(asked.refs.count == 4)
        #expect(asked.favorites.count == 2)
        #expect(asked.question == "Move 4 photos to the Trash?")
        #expect(asked.because == "2 of them are favorites.")
        #expect(asked.reassurance.hasPrefix("They go"))
    }

    @Test func oneLovedPhotoIsNamedRatherThanCounted() throws {
        let dir = try folder(1)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        router.store.cursor = 0
        router.perform(.toggleFavorite)

        router.perform(.trash)
        let asked = try #require(router.store.trashConfirm)
        #expect(asked.question == "Move p0.jpg to the Trash?")
        #expect(asked.because == "It is a favorite.")
        #expect(asked.reassurance.hasPrefix("It goes"), "the question says \"they\" about one photograph")
    }

    /// The key monitor stands down while the sheet is up, but a control on a
    /// photograph does not, so a second press must not stack a second question.
    @Test func askingTwiceLeavesOneQuestion() throws {
        let dir = try folder(2)
        defer { try? FileManager.default.removeItem(at: dir) }
        let router = open(dir)
        router.store.cursor = 0
        router.perform(.toggleFavorite)

        router.perform(.trash)
        let first = try #require(router.store.trashConfirm)
        router.store.cursor = 1
        router.perform(.trash)
        #expect(router.store.trashConfirm?.id == first.id, "a second press replaced the question")
    }
}


/// Answers the panel, so a command that ends in one can be driven whole rather
/// than from the function behind it (D-197).
@MainActor
final class StubPresenter: Presenter {
    var folders: [URL] = []
    private(set) var asked = 0

    init(_ folders: [URL] = []) { self.folders = folders }

    func chooseFolders(prompt: String, message: String?, multiple: Bool, startingAt: URL?) -> [URL] {
        asked += 1
        return folders
    }

    /// No window and nothing picked, which is the same answer AppKit gives with
    /// no key window. The callers that care take their fallback path.
    func menu(_ items: [(title: String, url: URL)], x: CGFloat?, drop: CGFloat,
              pick: @escaping (URL) -> Void) -> Bool { false }

    /// Counted rather than done: the real one launches System Settings over
    /// whatever is on screen, which a test run has no business doing (D-309).
    /// `opensSettings` is what it answers, so a suite can drive the refusal
    /// the Settings row has a sentence for.
    private(set) var openedFolderAccess = 0
    var opensSettings = true
    @discardableResult
    func openFolderAccessSettings() -> Bool {
        openedFolderAccess += 1
        return opensSettings
    }
}
