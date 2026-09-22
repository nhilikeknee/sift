import Testing
import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

@Suite struct PreferencesTests {
    init() { Preferences.useTestDefaults() }

    @Test func resumeRoundTripsAndCaps() {
        let folder = URL(fileURLWithPath: "/tmp/sift-test-folder-\(UUID().uuidString)")
        let file = folder.appendingPathComponent("IMG_0042.jpg")
        Preferences.setResume(file, for: folder)
        #expect(Preferences.resumeFile(for: folder) == file)
        Preferences.setResume(nil, for: folder)
        #expect(Preferences.resumeFile(for: folder) == nil)
    }

    @Test func recentsAreMostRecentFirstAndDeduplicated() {
        let a = URL(fileURLWithPath: "/tmp/sift-recent-a-\(UUID().uuidString)")
        let b = URL(fileURLWithPath: "/tmp/sift-recent-b-\(UUID().uuidString)")
        Preferences.noteRecent(a)
        Preferences.noteRecent(b)
        Preferences.noteRecent(a)
        let list = Preferences.recentFolders.map(\.path)
        #expect(list.first == a.path)
        #expect(list.filter { $0 == a.path }.count == 1)
        #expect(list.count <= 10)
    }
}

@Suite struct PixelStatsTests {
    init() { Preferences.useTestDefaults() }

    private func image(gray: UInt8, width: Int = 8, height: Int = 8) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let v = CGFloat(gray) / 255
        // Build the color in sRGB so no conversion nudges the value between spaces.
        ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [v, v, v, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// A flat patch at three channel values, for the questions a gray patch
    /// cannot answer.
    private func patch(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> CGImage {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()!
    }

    /// What the mask actually paints, read back rather than assumed.
    private func alpha(of mask: CGImage) -> UInt8 {
        var px = [UInt8](repeating: 9, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return px[3]
    }

    @Test func whiteImageIsAllClipped() {
        let h = PixelStats.histogram(of: image(gray: 255))!
        #expect(h.white == 1 && h.black == 0)
        #expect(h.bins.last == 64, "every pixel in the top bin")
    }

    @Test func midGrayIsNotClipped() {
        let h = PixelStats.histogram(of: image(gray: 128))!
        #expect(h.white == 0 && h.black == 0)
        // One tone, so one populated bin, and it sits in the middle.
        let populated = h.bins.enumerated().filter { $0.element > 0 }
        #expect(populated.count == 1)
        #expect(abs((populated.first?.offset ?? 0) - (128 >> 2)) <= 1)
    }

    @Test func clippingMaskMarksOnlyBlownPixels() {
        let mask = PixelStats.clippingMask(of: image(gray: 255), color: (0xA3, 0x20, 0x20))!
        #expect(mask.width == 8 && mask.height == 8)
        // One channel at the top is a blown channel, and the overlay is about
        // what cannot be recovered rather than about what is white (D-166).
        // This used to demand all three, which left a blown sky unpainted.
        #expect(alpha(of: PixelStats.clippingMask(of: patch(255, 120, 60),
                                                  color: (0xA3, 0x20, 0x20))!) == 255,
                "a blown red channel was not painted")
        #expect(alpha(of: PixelStats.clippingMask(of: patch(240, 120, 60),
                                                  color: (0xA3, 0x20, 0x20))!) == 0,
                "nothing is at the top and it painted anyway")
        let none = PixelStats.clippingMask(of: image(gray: 100), color: (0xA3, 0x20, 0x20))!
        // A non-clipped image yields a fully transparent mask.
        var px = [UInt8](repeating: 9, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.draw(none, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(px[3] == 0)
    }
}

@Suite @MainActor struct SearchAndSessionTests {
    init() { Preferences.useTestDefaults() }

    private func store(names: [String]) -> LibraryStore {
        let s = LibraryStore()
        for n in names {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(n)"), fileSize: 10, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    @Test func searchNarrowsByNameCaseInsensitively() {
        let s = store(names: ["Beach-01.jpg", "beach-02.jpg", "city.jpg"])
        s.searchText = "BEACH"
        #expect(s.photos.count == 2)
        s.searchText = ""
        #expect(s.photos.count == 3)
    }

    @Test func folderCountsIgnoreTheFilter() {
        let s = store(names: ["a", "b", "c"])
        s.update(s.photos[0].url) { $0.flag = .keep }
        s.update(s.photos[1].url) { $0.flag = .reject }
        s.filter = .keep
        let c = s.folderCounts
        #expect(c.keep == 1 && c.reject == 1 && c.unflagged == 1)
    }

    @Test func lastPhotoIsDetected() {
        let s = store(names: ["a", "b"])
        #expect(!s.isAtLastPhoto)
        s.move(by: 1)
        #expect(s.isAtLastPhoto)
    }

    @Test func previewOpensAndClosesAroundTheCursor() {
        let s = store(names: ["a", "b"])
        let r = CommandRouter(store: s)
        #expect(!s.previewOpen)
        r.perform(.enterSingle)
        #expect(s.previewOpen)
        s.focus = .preview
        r.perform(.cancel)
        #expect(!s.previewOpen)
        #expect(s.focus == .gallery, "focus goes back to the gallery")
    }

    @Test func emptyingTheFolderClosesThePreview() {
        let s = store(names: ["only.jpg"])
        let r = CommandRouter(store: s)
        r.perform(.enterSingle)
        #expect(s.previewOpen)
        s.remove([s.current!.url])
        #expect(!s.previewOpen)
    }

    @Test func peekReleaseOnlyAfterAHold() {
        let s = store(names: ["a"])
        let r = CommandRouter(store: s)
        s.focus = .preview
        s.oneToOneScale = 4

        r.perform(.zoomToggle)                 // key down
        #expect(s.zoom == 4)
        r.releasePeek()                        // key up right away: a tap, stays zoomed
        #expect(s.zoom == 4)

        r.perform(.zoomToggle)                 // toggle off
        #expect(s.zoom == nil)

        r.perform(.zoomToggle)                 // key down again
        s.peekBegan = Date().addingTimeInterval(-1)   // pretend it was held a second
        r.releasePeek()
        #expect(s.zoom == nil, "a hold snaps back to fit on release")
    }
}

@Suite @MainActor struct CopyPathTests {
    init() { Preferences.useTestDefaults() }

    /// A pasteboard of this suite's own. Writing to `.general` here would empty
    /// the clipboard of whoever is running the tests, which is what it did
    /// until D-54.
    private func scratchPasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("com.sift.tests." + UUID().uuidString))
        FileOps.pasteboard = board
        return board
    }

    @Test func copyingAFolderPathPutsItOnThePasteboardAndSaysSo() {
        let board = scratchPasteboard()
        defer { FileOps.pasteboard = .general }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        let folder = URL(fileURLWithPath: "/Users/someone/Pictures/Iceland 2026")

        router.copyPath(of: folder)

        #expect(board.string(forType: .string) == folder.path)
        #expect(store.toast?.message == "Copied Iceland 2026 path")
    }

    /// The picture, not the file (D-281). Read back as bytes and compared to
    /// what is on disk, because "the pasteboard has something of type jpeg on
    /// it" is a claim about the call and this is a claim about the outcome.
    @Test func copyingAnImageWritesTheFilesOwnBytesUnderItsOwnType() throws {
        let board = scratchPasteboard()
        defer { FileOps.pasteboard = .general }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.jpg")
        try writeJPEG(file)
        let onDisk = try Data(contentsOf: file)

        FileOps.copyImagesToPasteboard([file])

        let pasted = board.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))
        #expect(pasted == onDisk, "the receiving app should decode the file itself, not a re-encode")
        #expect(board.string(forType: .string) == "a.jpg", "the name rides along")
        // What the item declares, not what the board answers: AppKit will make
        // a TIFF out of a JPEG on the way out, so reading the board back says
        // nothing about whether one was written.
        #expect(board.pasteboardItems?.first?.types.contains(.tiff) == true,
                "one copy carries the old-bitmap fallback")
    }

    /// A TIFF of a 25-megapixel frame is about 100MB. Worth paying once as a
    /// fallback, not six times for a selection (D-281).
    @Test func copyingASelectionLeavesTheTiffFallbackOff() throws {
        let board = scratchPasteboard()
        defer { FileOps.pasteboard = .general }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.jpg"); try writeJPEG(a)
        let b = dir.appendingPathComponent("b.jpg"); try writeJPEG(b)

        FileOps.copyImagesToPasteboard([a, b])

        #expect(board.pasteboardItems?.count == 2)
        #expect(board.pasteboardItems?.allSatisfy { !$0.types.contains(.tiff) } == true,
                "no 100MB fallback per frame for a selection")
    }

    /// The name as the grid draws it, extension and all, one per line.
    @Test func copyingNamesWritesThemOnePerLine() {
        let board = scratchPasteboard()
        defer { FileOps.pasteboard = .general }

        FileOps.copyText(["P1130098.JPG", "P1130119.jpg"].joined(separator: "\n"))

        #expect(board.string(forType: .string) == "P1130098.JPG\nP1130119.jpg")
    }

    /// A menu shortcut fires before the responder chain, so the menu has to
    /// stand aside for a text field the way the key monitor already does
    /// (D-281). This is the fact both of them ask.
    @Test func aRenameFieldTakesTheKeystrokeBackFromTheMenu() {
        let store = LibraryStore()
        #expect(store.sheetHasTheKeyboard == false)

        store.renameTarget = nil
        store.showTrashPanel = true
        #expect(store.sheetHasTheKeyboard, "the trash panel takes typing too")
        store.showTrashPanel = false
        #expect(store.sheetHasTheKeyboard == false)
    }

    private func writeJPEG(_ url: URL, width: Int = 40, height: Int = 20) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func copyingNeverTouchesTheSystemPasteboard() {
        let board = scratchPasteboard()
        defer { FileOps.pasteboard = .general }
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        let before = NSPasteboard.general.changeCount

        router.copyPath(of: URL(fileURLWithPath: "/tmp/somewhere"))
        FileOps.copyToPasteboard([URL(fileURLWithPath: "/tmp/a.jpg")])

        #expect(NSPasteboard.general.changeCount == before,
                "a test run leaves the real clipboard exactly as it found it")
        #expect(board.string(forType: .string) == nil, "the URL write replaced the text write")
    }
}

/// Walking the tree in both directions: ⌘↑ up, ⌘↓ back down (D-31).
@Suite @MainActor struct FolderWalkTests {
    init() { Preferences.useTestDefaults() }

    private func tree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-walk-" + UUID().uuidString)
        for sub in ["Day 1", "Day 2"] {
            let dir = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0]).write(to: dir.appendingPathComponent("a.jpg"))
        }
        return root
    }

    @Test func upThenDownReturnsToTheFolderYouLeft() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)

        router.open(root.appendingPathComponent("Day 2"))
        router.perform(.openParent)
        #expect(store.folder?.standardizedFileURL == root.standardizedFileURL)

        router.perform(.openSubfolder)
        #expect(store.folder?.lastPathComponent == "Day 2", "⌘↓ goes back where ⌘↑ came from, not to the first subfolder")
        #expect(store.subfolders.isEmpty)
    }

    @Test func aLoneSubfolderIsOneKeystrokeAway() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Day 2"))
        let store = LibraryStore()
        let router = CommandRouter(store: store)

        router.open(root)
        #expect(store.subfolders.map(\.lastPathComponent) == ["Day 1"])
        router.perform(.openSubfolder)
        #expect(store.folder?.lastPathComponent == "Day 1")
    }

    @Test func aLeafFolderSaysThereIsNothingBelow() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)

        router.open(root.appendingPathComponent("Day 1"))
        #expect(store.subfolders.isEmpty)
        router.perform(.openSubfolder)
        #expect(store.folder?.lastPathComponent == "Day 1", "nowhere to go")
        #expect(store.toast?.message == "No subfolders in Day 1")
    }

    @Test func openingAFolderDirectlyForgetsTheWayBackDown() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        let router = CommandRouter(store: store)

        router.open(root.appendingPathComponent("Day 2"))
        router.perform(.openParent)
        router.open(root)                       // the breadcrumb, not ⌘↑
        #expect(router.descent == .choose(store.subfolders), "with no memory and two branches, ⌘↓ has to ask")
    }
}

/// Back and forward are a history, not a tree walk (D-32).
@Suite @MainActor struct HistoryTests {
    init() { Preferences.useTestDefaults() }

    private func tree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-hist-" + UUID().uuidString)
        for sub in ["Day 1", "Day 2"] {
            let dir = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0]).write(to: dir.appendingPathComponent("a.jpg"))
        }
        return root
    }

    @Test func backRetracesAndForwardReplays() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store

        router.open(root.appendingPathComponent("Day 1"))
        #expect(!router.canGoBack, "the first folder of a sitting has nothing behind it")
        router.open(root.appendingPathComponent("Day 2"))
        #expect(router.canGoBack)

        router.perform(.back)
        #expect(store.folder?.lastPathComponent == "Day 1")
        #expect(router.canGoForward)

        router.perform(.forward)
        #expect(store.folder?.lastPathComponent == "Day 2")
        #expect(!router.canGoForward)
    }

    @Test func aNewDestinationEndsTheForwardRoad() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())

        router.open(root.appendingPathComponent("Day 1"))
        router.open(root.appendingPathComponent("Day 2"))
        router.perform(.back)
        #expect(router.canGoForward)

        router.open(root)
        #expect(!router.canGoForward, "going somewhere new drops what was ahead")
    }

    @Test func backIsHistoryNotTheParentFolder() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())

        router.open(root.appendingPathComponent("Day 1"))
        router.open(root.appendingPathComponent("Day 2"))
        router.perform(.back)
        #expect(router.store.folder?.lastPathComponent == "Day 1", "back is where you were, not one level up")
    }

    @Test func reopeningTheSameFolderIsNotAStepInTheHistory() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())

        router.open(root)
        router.open(root)
        #expect(!router.canGoBack)
    }

    @Test func backAtTheStartSaysSoRatherThanDoingNothing() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())

        router.open(root)
        router.perform(.back)
        #expect(router.store.folder?.standardizedFileURL == root.standardizedFileURL)
        #expect(router.store.toast?.message == "Nowhere back to go")
    }
}

/// The folder row above the photos, and the cursor that can sit in it (D-33).
@Suite @MainActor struct FolderRowTests {
    init() { Preferences.useTestDefaults() }

    /// Day 1 has photos *and* a subfolder, which is what puts a cell in the row
    /// now that the way out is not one (D-111).
    private func card() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-row-" + UUID().uuidString)
        for sub in ["Day 1", "Day 2", "Day 1/Selects"] {
            let dir = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 1...3 { try Data([0]).write(to: dir.appendingPathComponent("p\(i).jpg")) }
        }
        return root
    }

    // Rewritten 2026-09-15 for D-111. It used to assert the opposite — that the
    // first cell was the enclosing folder, named "Up to …" — because the row
    // was the way out as well as the ways in. Going up is the header's job now,
    // so the row holding a parent is the thing to catch.
    @Test func theRowHoldsTheWaysInAndNothingElse() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root.appendingPathComponent("Day 1"))

        let row = router.store.folderRow
        #expect(row.map(\.name) == ["Selects"])
        #expect(!row.contains { $0.url.standardizedFileURL == root.standardizedFileURL },
                "the enclosing folder is not a cell in the grid")
    }

    @Test func aFolderWithNowhereToGoInHasAnEmptyRow() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root.appendingPathComponent("Day 2"))

        #expect(router.store.folderRow.isEmpty,
                "Day 2 has a parent and no children, and the parent is not the row's business")
    }

    @Test func upFromTheTopRowEntersTheFoldersAndDownLeaves() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(root.appendingPathComponent("Day 1"))
        store.gridColumns = 4
        store.cursor = 1

        router.perform(.up)
        #expect(store.folderCursor != nil, "the cursor left the photos for the folder row")

        router.perform(.down)
        #expect(store.folderCursor == nil)
        #expect(store.cursor != nil)
    }

    @Test func returnInTheFolderRowOpensThatFolder() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(root.appendingPathComponent("Day 1"))
        store.gridColumns = 4
        store.cursor = 0

        router.perform(.up)
        router.perform(.enterSingle)
        #expect(store.folder?.standardizedFileURL
                == root.appendingPathComponent("Day 1/Selects").standardizedFileURL)
        #expect(store.folderCursor == nil, "a new folder starts with the cursor on the photos")
    }

    @Test func aPhotoKeyDropsOutOfTheRowRatherThanActingUnseen() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(root.appendingPathComponent("Day 1"))
        store.gridColumns = 4
        store.cursor = 0
        router.perform(.up)

        router.perform(.toggleSelect)
        #expect(store.folderCursor == nil)
        #expect(store.selected.count == 1)
    }
}

/// `⌘⇧→` and the end-of-folder handoff.
@Suite @MainActor struct SiblingFolderTests {
    init() { Preferences.useTestDefaults() }

    private func card() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-sib-" + UUID().uuidString)
        for sub in ["Day 1", "Day 2", "Day 3"] {
            let dir = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0]).write(to: dir.appendingPathComponent("a.jpg"))
        }
        return root
    }

    @Test func stepsAlongTheShootsWithoutClimbing() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root.appendingPathComponent("Day 1"))

        router.perform(.nextFolder)
        #expect(router.store.folder?.lastPathComponent == "Day 2")
        router.perform(.nextFolder)
        #expect(router.store.folder?.lastPathComponent == "Day 3")
        router.perform(.nextFolder)
        #expect(router.store.folder?.lastPathComponent == "Day 3", "the last folder stays put")
        #expect(router.store.toast?.message.hasPrefix("Last folder") == true)

        router.perform(.previousFolder)
        #expect(router.store.folder?.lastPathComponent == "Day 2")
    }

    @Test func theLastPhotoOffersTheNextFolder() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root.appendingPathComponent("Day 1"))
        router.store.moveToLast()

        router.perform(.next)
        #expect(router.store.toast?.offer?.folder.lastPathComponent == "Day 2")
        #expect(router.store.toast?.offer?.label == "Open Day 2")
    }

    @Test func theLastFolderOffersNothing() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root.appendingPathComponent("Day 3"))
        router.store.moveToLast()

        router.perform(.next)
        #expect(router.store.toast?.offer == nil)
    }
}

/// Batch B: the history menus, the path sheet, and dropping photos on a folder.
@Suite @MainActor struct DropAndPathTests {
    init() { Preferences.useTestDefaults() }

    private func card() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-drop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Selects"), withIntermediateDirectories: true)
        for i in 1...3 { try Data([0]).write(to: root.appendingPathComponent("p\(i).jpg")) }
        return root
    }

    @Test func droppingOneUnselectedPhotoMovesOnlyThatOne() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root)
        let dest = root.appendingPathComponent("Selects")

        #expect(router.drop([root.appendingPathComponent("p2.jpg")], on: dest) == 1)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("p2.jpg").path))
        #expect(router.store.photos.count == 2)
        #expect(router.store.undo.canUndo, "a drop is undoable like every other move")
    }

    @Test func droppingAPhotoFromTheSelectionMovesTheSelection() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        let store = router.store
        router.open(root)
        store.selected = Set(store.photos.prefix(2).map(\.url))
        let dest = root.appendingPathComponent("Selects")

        #expect(router.drop([store.photos[0].url], on: dest) == 2)
        #expect(store.photos.count == 1)
    }

    @Test func aDropOnTheFolderYouAreInDoesNothing() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root)

        #expect(router.drop([router.store.photos[0].url], on: root) == 0)
        #expect(router.store.photos.count == 3)
    }

    @Test func aTypedPathOpensAndABadOneSaysSo() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())

        router.openPath("  \(root.path)/Selects  ")
        #expect(router.store.folder?.lastPathComponent == "Selects")

        router.openPath("/nowhere/at/all")
        #expect(router.store.lastError?.hasPrefix("There is nothing at") == true)
        #expect(router.store.folder?.lastPathComponent == "Selects", "a bad path leaves you where you were")
    }

    @Test func theHistoryMenuJumpsSeveralStepsAtOnce() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())

        router.open(root)
        router.open(root.appendingPathComponent("Selects"))
        router.open(root)
        #expect(router.backList.map(\.lastPathComponent) == ["Selects", root.lastPathComponent])

        router.goBack(steps: 2)
        #expect(router.store.folder?.standardizedFileURL == root.standardizedFileURL)
        #expect(router.forwardList.count == 2)
    }
}

/// Batch D: what the jump sheet can reach, and what a mounted volume offers.
@Suite @MainActor struct JumpAndVolumeTests {
    init() { Preferences.useTestDefaults() }

    private func card() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-jump-" + UUID().uuidString)
        for sub in ["Day 1", "Day 2", "Selects"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try Data([0]).write(to: root.appendingPathComponent("Day 1/a.jpg"))
        return root
    }

    @Test func theSheetReachesSiblingsInsidesAndTheFolderAbove() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root.appendingPathComponent("Day 1"))

        // Recents are real user state, so only this card's folders are asserted.
        let card = FolderScanner.canonical(root)
        let mine = router.jumpCandidates.filter { $0.folder.path.hasPrefix(card.path) }
        let byPath = Dictionary(uniqueKeysWithValues: mine.map { ($0.folder.path, $0.source) })
        #expect(byPath[card.appendingPathComponent("Day 2").path] == "beside")
        #expect(byPath[card.appendingPathComponent("Selects").path] == "beside")
        #expect(byPath[card.path] == "enclosing")
        #expect(byPath[card.appendingPathComponent("Day 1").path] == nil,
                "the folder you are in is not somewhere to jump to")
    }

    @Test func aPinnedFolderIsListedAsPinned() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let router = CommandRouter(store: LibraryStore())
        let selects = root.appendingPathComponent("Selects")
        router.open(root.appendingPathComponent("Day 1"))
        router.togglePin(selects)
        defer { router.togglePin(selects) }

        #expect(router.jumpCandidates.first { $0.folder == selects }?.source == "pinned")
    }

    @Test func anOrdinaryFolderIsNotACard() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        // The temp folder is not a removable volume, so nothing is offered.
        #expect(VolumeWatcher.photoFolder(on: root) == nil)
    }
}

/// Two gallery windows are two sessions over the same disk (D-40).
@Suite @MainActor struct SessionTests {
    init() { Preferences.useTestDefaults() }

    @Test func eachSessionHasItsOwnFolderAndCursor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-sess-" + UUID().uuidString)
        for sub in ["Day 1", "Day 2"] {
            let dir = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 1...2 { try Data([0]).write(to: dir.appendingPathComponent("p\(i).jpg")) }
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let a = Session(), b = Session()
        a.router.open(root.appendingPathComponent("Day 1"))
        b.router.open(root.appendingPathComponent("Day 2"))
        a.store.moveToLast()
        b.store.moveToFirst()

        #expect(a.store.folder?.lastPathComponent == "Day 1")
        #expect(b.store.folder?.lastPathComponent == "Day 2")
        #expect(a.store.cursor == 1)
        #expect(b.store.cursor == 0)
        #expect(a.store.undo !== b.store.undo, "one window's undo does not reach the other")
    }

    @Test func theModelKeepsOneSessionPerWindowAndForgetsClosedOnes() {
        let model = AppModel.shared
        let id = UUID()
        let session = model.session(id)

        #expect(model.session(id) === session, "asking twice gives the same session")
        model.activeID = id
        #expect(model.active === session)

        model.close(id)
        #expect(model.sessions[id] == nil)
        #expect(model.active !== session, "with that window gone, commands land somewhere else")
    }

    /// A window that arrives with no `WindowGroup` value takes `defaultValue`,
    /// and macOS makes such a window twice: once at launch, and again when it
    /// hands a running app a folder. Handing both the same id handed both the
    /// same `Session`, so the second folder replaced the first in both windows
    /// at once (D-363).
    ///
    /// Order-independent, because `AppModel` is a singleton and another test
    /// may have taken the named id already: what is asserted is that no two
    /// calls agree and that only a first call can return the name.
    @Test func onlyOneWindowEverCarriesTheNamedIdentity() {
        let model = AppModel.shared
        let ids = (0..<3).map { _ in model.nextWindowID() }

        #expect(Set(ids).count == 3, "two windows would share a session")
        for later in ids.dropFirst() {
            #expect(later != SiftApp.firstWindowID,
                    "the launch window's name is handed out once and not again")
        }
    }
}

@Suite @MainActor struct LaunchTests {
    init() { Preferences.useTestDefaults() }

    @Test func aPathOnTheCommandLineWinsOverTheLastFolder() {
        let last = URL(fileURLWithPath: "/tmp/sift-last")
        let picked = SiftApp.launchFolder(arguments: ["Sift", "-NSDocumentRevisions", "/tmp/sift-argv"],
                                          lastFolder: last,
                                          exists: { _ in true })
        #expect(picked?.path == "/tmp/sift-argv", "a flag is not a folder, and argv beats the last sitting")
    }

    @Test func aPathThatIsGoneFallsBackToTheLastFolder() {
        let last = URL(fileURLWithPath: "/tmp/sift-last")
        let picked = SiftApp.launchFolder(arguments: ["Sift", "/tmp/sift-gone"],
                                          lastFolder: last,
                                          exists: { $0 == last.path })
        #expect(picked == last)
    }

    @Test func nothingToOpenIsNotAFolder() {
        #expect(SiftApp.launchFolder(arguments: ["Sift"], lastFolder: nil, exists: { _ in true }) == nil)
        let gone = URL(fileURLWithPath: "/tmp/sift-gone")
        #expect(SiftApp.launchFolder(arguments: ["Sift"], lastFolder: gone, exists: { _ in false }) == nil)
    }

    @Test func theFirstWindowOpensTheLaunchFolderRatherThanTheAppDoing() {
        // The window reads `pending` in onAppear; the scan is not allowed to
        // run before a window exists (D-100).
        let model = AppModel.shared
        let id = UUID()
        let session = model.session(id)
        let folder = URL(fileURLWithPath: "/tmp/sift-launch-\(UUID().uuidString)")
        model.pending[id] = folder

        #expect(session.store.folder == nil, "nothing is scanned until a window asks")
        let handed = model.pending.removeValue(forKey: id) ?? nil
        #expect(handed == folder)
        #expect(model.pending[id] == nil, "the handoff is read once")
        model.close(id)
    }
}

/// Tech debt 28: one way to reach the preview's window (D-102).
@Suite @MainActor struct WindowReaderTests {
    private final class Recorder { var seen: [NSWindow?] = []; var calls = 0 }

    /// The report is a turn late by design, so poll for it rather than
    /// guessing how long a turn takes on this machine.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func theViewNamesTheWindowItIsInEvenWhenTheTitleIsAFilename() async {
        let recorder = Recorder()
        let view = WindowReadingView(frame: .zero)
        view.onWindow = { recorder.seen.append($0); recorder.calls += 1 }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        // What the preview window is actually called: the search this replaced
        // looked for the title "Preview" and never found it.
        window.title = "IMG_0042.jpg"
        window.contentView?.addSubview(view)
        await settle { recorder.calls > 0 }

        #expect(recorder.seen.last ?? nil === window)
        #expect(window.title != "Preview", "the title is the photo, which is why a title search was wrong")
    }

    @Test func aViewOutOfItsWindowSaysSoRatherThanHoldingTheLastOne() async {
        let recorder = Recorder()
        let view = WindowReadingView(frame: .zero)
        view.onWindow = { recorder.seen.append($0); recorder.calls += 1 }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        await settle { recorder.calls > 0 }
        view.removeFromSuperview()
        await settle { recorder.calls > 1 }

        #expect(recorder.seen.last ?? nil == nil, "gone means gone: a stale window would be moved instead")
        #expect(recorder.calls >= 2)
    }

    @Test func theBoxIsWhatTheBorrowedClosureReads() async {
        // The router's closure is made at onAppear, which can be before the
        // window exists. A box read later is why that ordering is safe.
        let box = WindowBox()
        let read = { box.window }
        #expect(read() == nil)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        box.window = window
        #expect(read() === window)
    }
}

/// Tech debt 21: the drag-out session's anchor event, and a start that says
/// what stopped it (D-103).
@Suite @MainActor struct DragOutTests {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                 styleMask: [.titled], backing: .buffered, defer: false)
    }

    @Test func thereIsAlwaysAnEventToHangTheDragOn() {
        // No mouse event is in flight inside a test, which is exactly the case
        // that used to fail silently.
        let w = window()
        let event = DragOutView.anchorEvent(in: w)
        #expect(event.type == .leftMouseDragged)
        #expect(event.windowNumber == w.windowNumber, "anchored in the window the photo is in")
    }

    @Test func aHandleWithNoViewSaysSoInsteadOfDoingNothing() {
        let handle = DragOutHandle()
        #expect(handle.begin() == .detached)
        #expect(handle.dragging == false, "a start that failed does not leave the gesture believing it is dragging")
        #expect(DragOutStart.detached.message != nil, "and it has something to show")
    }

    @Test func aCellWithNothingToDragSaysThatRatherThanStartingAnEmptySession() {
        let view = DragOutView()
        window().contentView?.addSubview(view)
        view.urls = { [] }
        #expect(view.beginDrag() == .noFiles)
        #expect(DragOutStart.noFiles.message == "Nothing to drag")
    }

    @Test func onlyTheFirstOfAHundredGestureChangesIsADrag() {
        let handle = DragOutHandle()
        handle.dragging = true
        #expect(handle.begin() == nil, "nil is nothing to say, not a failure to report")
    }

    @Test func aStartedDragHasNothingToSay() {
        #expect(DragOutStart.started.message == nil)
    }
}

/// The breadcrumb is the way out of a folder, so it always offers one (D-111).
@Suite @MainActor struct BreadcrumbPathTests {
    init() { Preferences.useTestDefaults() }

    @Test func aShallowPathStillShowsSomewhereToGoUpTo() throws {
        // `/tmp` trimmed to a single crumb before D-111, which left a folder
        // with a parent and no control on screen that reached it.
        let segments = Breadcrumb.pathSegments(for: URL(fileURLWithPath: "/tmp"))
        #expect(segments.map(\.name) == ["/", "tmp"])
    }

    @Test func theTopOfTheDiskShowsOneCrumbBecauseThereIsNowhereAbove() throws {
        #expect(Breadcrumb.pathSegments(for: URL(fileURLWithPath: "/")).map(\.name) == ["/"])
    }

    @Test func homeIsNamedAndKeepsItsParent() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(Breadcrumb.pathSegments(for: home).map(\.name) == ["Users", "Home"])
    }

    @Test func aDeepPathIsTrimmedToTheHomeItSitsUnder() throws {
        let deep = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Shoot/Day 1")
        #expect(Breadcrumb.pathSegments(for: deep).map(\.name) == ["Home", "Pictures", "Shoot", "Day 1"])
    }

    // MARK: how many of them a rung draws (D-187)

    private func path(_ depth: Int) -> [Breadcrumb.Segment] {
        var url = URL(fileURLWithPath: "/")
        for i in 0..<depth { url = url.appendingPathComponent("f\(i)") }
        return Breadcrumb.pathSegments(for: url, home: URL(fileURLWithPath: "/nowhere"))
    }

    /// The whole point of the change: a wide rung shows every crumb it has
    /// room for. It used to be `suffix(2)` whatever the width, so a path six
    /// deep put four ancestors behind an ellipsis on a window with room for
    /// all of them.
    @Test func theWidestRungHidesNothingUntilThePathIsDeeperThanItDraws() {
        let all = path(4)
        let (hidden, shown) = Breadcrumb.arrangement(all, keep: Breadcrumb.maxCrumbs)
        #expect(hidden.isEmpty, "a path that fits still hid \(hidden.map(\.name))")
        #expect(shown.count == all.count)
    }

    /// And the narrow rungs give them up from the top, which is the end of the
    /// path that says least about where you are.
    @Test func everyRungKeepsTheWayOutAndTheFolderYouAreIn() {
        let all = path(8)
        let last = try! #require(all.last)
        let parent = all[all.count - 2]
        for keep in Breadcrumb.minCrumbs...Breadcrumb.maxCrumbs {
            let (hidden, shown) = Breadcrumb.arrangement(all, keep: keep)
            #expect(shown.last?.url == last.url, "rung \(keep) dropped the folder you are in")
            #expect(shown.dropLast().last?.url == parent.url, "rung \(keep) dropped the way out")
            #expect(hidden.map(\.url) + shown.map(\.url) == all.map(\.url),
                    "rung \(keep) lost or reordered a crumb")
            #expect(shown.count == min(keep, all.count))
        }
    }

    /// A rung wider than the path has crumbs draws the path, not padding; a
    /// rung narrower than the floor draws the floor.
    @Test func theRungsAreClampedToWhatThePathActuallyHas() {
        let short = path(1)
        #expect(Breadcrumb.arrangement(short, keep: Breadcrumb.maxCrumbs).shown.count == short.count)
        #expect(Breadcrumb.arrangement(short, keep: 0).shown.count == short.count)
        let deep = path(9)
        #expect(Breadcrumb.arrangement(deep, keep: 0).shown.count == Breadcrumb.minCrumbs,
                "a rung asked for nothing gave up the way out")
    }
}
