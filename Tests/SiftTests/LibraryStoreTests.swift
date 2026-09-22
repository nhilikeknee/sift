import Testing
import Foundation
@testable import Sift

@Suite @MainActor struct LibraryStoreTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int) -> LibraryStore {
        let s = LibraryStore()
        for i in 0..<count {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    @Test func removeKeepsCursorOnNextPhoto() {
        let s = store(count: 3)
        s.cursor = 1
        s.remove([s.current!.url])
        #expect(s.current?.name == "2.jpg")
    }

    @Test func removeLastClampsBack() {
        let s = store(count: 3)
        s.cursor = 2
        s.remove([s.current!.url])
        #expect(s.cursor == 1)
    }

    @Test func removeOnlyPhotoClearsCursor() {
        let s = store(count: 1)
        s.remove([s.current!.url])
        #expect(s.cursor == nil)
        #expect(s.current == nil)
    }

    @Test func moveClamps() {
        let s = store(count: 3)
        s.move(by: 10)
        #expect(s.cursor == 2)
        s.move(by: -10)
        #expect(s.cursor == 0)
    }

    @Test func extendingSelectionIsARangeFromTheAnchor() {
        let s = store(count: 5)
        s.cursor = 1
        s.move(by: 1, extendingSelection: true)
        s.move(by: 1, extendingSelection: true)
        #expect(s.selected.count == 3)
        s.move(by: -3, extendingSelection: true)
        #expect(s.selected.count == 2, "shrinking back past the anchor flips the range")
        #expect(s.targets.count == 2)
        s.clearSelection()
        #expect(s.targets.count == 1, "no selection means the cursor is the target")
    }

    /// D-377. The grid moved only the cursor on a plain click, so clicking one
    /// cell inside a selected run left the run selected and the next command
    /// acted on all of it.
    @Test func aPlainClickLeavesOneThingSelected() {
        let s = store(count: 5)
        s.selectAll()
        #expect(s.targets.count == 5)
        s.selectOnly(3)
        #expect(s.selected == [s.photos[3].url])
        #expect(s.cursor == 3)
        #expect(s.targets.map(\.url) == [s.photos[3].url])
        // And it is the anchor, so a shift-click after it runs from here.
        s.move(by: 1, extendingSelection: true)
        #expect(s.selected.count == 2)
    }

    @Test func filterHidesButKeepsAll() {
        let s = store(count: 3)
        s.update(s.photos[1].url) { $0.flag = .keep }
        s.filter = .keep
        #expect(s.photos.count == 1)
        #expect(s.allPhotos.count == 3)
        s.filter = .all
        #expect(s.photos.count == 3)
    }

    /// A crop belongs to the photo it was drawn on, so it goes. The zoom does
    /// not: holding 100% while arrowing through a burst is how the sharp frame
    /// is found, and every other culler works this way (D-79).
    @Test func cursorChangeKeepsTheZoomAndDropsTheCrop() {
        let s = store(count: 2)
        s.zoom = 3
        s.cropping = true
        s.move(by: 1)
        #expect(s.zoom == 3)
        #expect(!s.cropping)
    }

    /// 1:1 is an intent, not a number: two photos of different dimensions need
    /// two different multipliers to show the same pixels.
    @Test func actualPixelsFollowsThePhotoRatherThanTheMultiplier() {
        let s = store(count: 2)
        s.oneToOneScale = 2
        s.zoom = 2
        s.zoomIsActual = true
        s.oneToOneScale = 5              // the next photo is smaller on screen
        #expect(s.zoom == 5)

        // A zoom someone pinched to is a number, and it stays that number.
        s.zoomIsActual = false
        s.zoom = 3
        s.oneToOneScale = 9
        #expect(s.zoom == 3)
    }

    @Test func resetZoomGoesBackToTheWholeFrame() {
        let s = store(count: 2)
        s.zoom = 4
        s.zoomIsActual = true
        s.visibleRect = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        s.resetZoom()
        #expect(s.zoom == nil)
        #expect(!s.zoomIsActual)
        #expect(s.visibleRect == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The place you are looking survives the walk to the next frame, which is
    /// the half of D-79 that had never been true. The zoom was held in the
    /// store and resolved against each photograph; the pan was `@State` in the
    /// view and zeroed on every new one, so a burst walked at 20% snapped back
    /// to the middle of each frame and the clip made to show it showed the
    /// opposite (D-273).
    ///
    /// The round trip is what the view does across a cursor move: read the
    /// place off the pan of the photograph being left, then work out the pan
    /// that shows the same place on the one arriving.
    @Test func thePlaceYouAreLookingIsHeldAcrossFramesOfDifferentShapes() {
        let burst = CGSize(width: 690, height: 918)
        let pan = CGSize(width: 0, height: -211)
        let look = LibraryStore.look(fromPan: pan, in: burst)
        #expect(abs(look.y - 0.73) < 0.005, "the window is centered 73% down the frame")

        // The next frame of the burst is the same shape, so the same offset.
        #expect(abs(LibraryStore.pan(lookingAt: look, in: burst).height - pan.height) < 0.0001)

        // A landscape frame at the same zoom is a different size in points, so
        // holding the *offset* would land somewhere else. Holding the place
        // means a smaller offset, and the same 73%.
        let landscape = CGSize(width: 918, height: 690)
        let moved = LibraryStore.pan(lookingAt: look, in: landscape)
        #expect(abs(moved.height + 158.7) < 0.5)
        #expect(abs(LibraryStore.look(fromPan: moved, in: landscape).y - look.y) < 0.0001)
    }

    /// Fit shows the whole photograph, so there is nowhere else to be looking.
    /// Leaving the old place behind is what makes zooming back in start from
    /// the middle rather than from wherever the last burst ended.
    @Test func goingBackToFitForgetsThePlace() {
        let s = store(count: 2)
        s.zoom = 4
        s.lookingAt = CGPoint(x: 0.3, y: 0.73)
        s.zoom = nil
        #expect(s.lookingAt == CGPoint(x: 0.5, y: 0.5))
    }
}

/// A folder of folders has a ceiling, and the screen says where it is (D-318).
///
/// Built out of real directories rather than a list of URLs, because what broke
/// was a real directory: the system temporary folder, 23,543 entries and 19,176
/// of them folders. Sift took 99% of a core and 4.1GB and never answered again.
/// The directory reads were never the cost — all 19,176 take about 1.4 seconds
/// — so nothing here measures scanning. What is held is the count that reaches
/// the view, because that is what SwiftUI builds a hover region for.
@Suite @MainActor struct FolderCeilingTests {
    init() { Preferences.useTestDefaults() }

    /// `folderTileMax` plus twenty, so the cap has something to cut and the
    /// leftover is a number a failure can name.
    private func manyFolders() throws -> (LibraryStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-ceiling-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<(LibraryStore.folderTileMax + 20) {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(String(format: "shoot-%04d", i)),
                withIntermediateDirectories: true)
        }
        let store = LibraryStore()
        store.open(root)
        return (store, root)
    }

    @Test func theGridIsHandedTheCapAndNotTheFolder() throws {
        let (store, root) = try manyFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.subfolders.count == LibraryStore.folderTileMax + 20)
        #expect(store.shownSubfolders.count == LibraryStore.folderTileMax, """
            the grid was handed \(store.shownSubfolders.count) folders. Every tile costs a \
            SwiftUI pointer region, and 19,176 of them is a main thread that never returns \
            to the run loop (D-318).
            """)
        #expect(store.subfoldersLeftOut == 20)
        // The row the keyboard walks is the row on screen, or the cursor is an
        // index into a list nobody is looking at.
        #expect(store.folderRow.count == store.shownSubfolders.count)
    }

    @Test func theNameFilterReachesFolderNames() throws {
        let (store, root) = try manyFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        store.searchText = "shoot-0001"
        #expect(store.shownSubfolders.map(\.lastPathComponent) == ["shoot-0001"])
        #expect(store.subfoldersLeftOut == 0)
        store.searchText = ""
        #expect(store.shownSubfolders.count == LibraryStore.folderTileMax)
    }

    /// A query about photographs empties the folder list rather than ignoring
    /// the part it cannot answer.
    @Test func aQueryAboutExifMatchesNoFolder() {
        #expect(PhotoQuery("shoot").matchesFolder(named: "shoot-0001"))
        #expect(!PhotoQuery("camera:x-t5").matchesFolder(named: "shoot-0001"))
        #expect(!PhotoQuery("iso:6400").matchesFolder(named: "shoot-0001"))
        #expect(!PhotoQuery("nope").matchesFolder(named: "shoot-0001"))
    }

    /// The cursor cannot sit past the end of what the cap left on screen.
    @Test func theFolderCursorStaysInsideTheDrawnRow() throws {
        let (store, root) = try manyFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        store.folderCursor = LibraryStore.folderTileMax - 1
        store.searchText = "shoot-0002"
        #expect(store.folderCursor.map { store.folderRow.indices.contains($0) } != false)
    }
}

/// What "inside" means, which is the one piece of D-319's arithmetic that
/// outlived it.
///
/// The sidebar's root was a computed thing until 2026-09-18 — the open
/// folder's parent on arrival, raised a step on the way up — and these held
/// its three cases. It is not computed any more: a root is a folder Sift has
/// been handed, and the set of roots is the set of grants (D-327). The rules
/// those tests encoded were retired with the thing they described, rather
/// than left passing against a function nothing calls.
///
/// `contains` stayed, because every one of the new rules rests on it: which
/// root holds the open folder, which grant covers a path, whether one grant
/// sits inside another.
@Suite @MainActor struct FolderContainmentTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// A name that starts with another's name is not inside it. Prefix
    /// matching on strings says `/Users/a/Photo` contains `/Users/a/Photos`,
    /// which would hand over a folder nobody chose.
    @Test func aPrefixOfAFoldersNameIsNotInsideIt() {
        #expect(!FolderScanner.contains(url("/Users/a/Photo"), url("/Users/a/Photos")))
        #expect(FolderScanner.contains(url("/Users/a/Photos"), url("/Users/a/Photos/June")))
        #expect(FolderScanner.contains(url("/"), url("/Users")))
    }

    /// A folder contains itself, which is what lets a grant cover the folder
    /// it was made for and not only the folders under it.
    @Test func aFolderContainsItself() {
        #expect(FolderScanner.contains(url("/Users/a/Photos"), url("/Users/a/Photos")))
    }
}
