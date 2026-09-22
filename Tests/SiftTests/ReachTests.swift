import Testing
import Foundation
import AppKit
import SwiftUI
@testable import Sift

/// The rules behind the on-screen controls: what a control drawn on one photo
/// acts on, where the cursor ends up afterwards, and how the header names both
/// (D-47). These are store and router rules rather than pixels, which is the
/// half a test can hold.
@Suite @MainActor struct ReachTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int) -> LibraryStore {
        let s = LibraryStore()
        for i in 0..<count {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    /// Nowhere is a state (D-141). Reported three times as "the first photo
    /// is selected when I open a folder": the gray tile is the cursor and not
    /// a selection, which is true and did not help, because the only thing on
    /// screen that draws a cursor is a mark that reads as chosen. So the
    /// cursor stops existing until somebody puts it somewhere.
    @Test func aFolderOpensWithTheKeyboardNowhere() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-nowhere-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 1...3 { try Data([0]).write(to: root.appendingPathComponent("p\(i).jpg")) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root)
        #expect(router.store.cursor == nil, "opening a folder marked a photo nobody chose")
        #expect(router.store.targets.isEmpty, "a command would have acted on a photo nobody chose")
    }

    /// And the first key puts it somewhere, rather than being swallowed.
    @Test func theFirstKeyFromNowhereLandsOnTheFirstPhoto() {
        for delta in [1, -1, 4, -4] {
            let s = store(count: 6)
            s.cursor = nil
            s.move(by: delta)
            #expect(s.cursor == 0, "a \(delta) step from nowhere went to \(String(describing: s.cursor))")
        }
    }

    /// Clicking a photograph moved the grid: every cursor change scrolled the
    /// cell to the middle of the window, so the grid slid out from under the
    /// hand that had just clicked and the next click landed on whatever had
    /// taken its place (D-374). A cursor the pointer moved asks for nothing
    /// to be revealed.
    @Test func clickingAPhotographDoesNotAskTheGridToScroll() {
        let s = store(count: 20)
        s.cursor = 3
        #expect(s.revealCursor == 3, "a command moving the cursor should bring the cell into view")
        s.fromPointer { s.cursor = 11 }
        #expect(s.cursor == 11, "the click should still move the cursor")
        #expect(s.revealCursor == nil, "the click asked the grid to scroll to the cell under the pointer")
    }

    /// And the keyboard still gets its cell brought into view afterwards,
    /// which is the half a flag left set would break.
    @Test func theKeyboardStillRevealsAfterAClick() {
        let s = store(count: 20)
        s.fromPointer { s.cursor = 11 }
        s.move(by: 1)
        #expect(s.revealCursor == 12, "the arrow after a click did not bring its cell into view")
    }

    /// Open A, close it, open B, and A was on screen for a moment before B
    /// decoded: SwiftUI keeps the preview's photo view across a close, and
    /// the frame it holds is the last one looked at. The view is keyed on the
    /// opening now, which changes when the window comes back and never when
    /// the cursor moves, so the crossfade between two frames survives
    /// (D-63, D-375).
    @Test func eachOpeningOfThePreviewGetsItsOwnIdentity() {
        let s = store(count: 4)
        let first = s.previewOpening
        s.notePreviewOpened()
        #expect(s.previewOpening != first, "reopening the preview reused the last photograph's view")
        let second = s.previewOpening
        s.cursor = 2
        s.cursor = 3
        #expect(s.previewOpening == second,
                "moving the cursor rebuilt the photo view, which is the crossfade gone")
    }

    @Test func clickingTheCanvasTakesAwayBothMarks() {
        let s = store(count: 4)
        s.cursor = 2
        s.selected = [s.photos[0].url, s.photos[1].url]
        s.clearCursorAndSelection()
        #expect(s.cursor == nil)
        #expect(s.selected.isEmpty)
        #expect(s.folderCursor == nil)
    }

    /// Trashing a selection used to plant a cursor on the first photo as a
    /// side effect, through a `?? 0` in `remove` (D-141).
    @Test func trashingFromNowhereLeavesTheKeyboardNowhere() {
        let s = store(count: 4)
        s.cursor = nil
        let gone = s.photos[2].url
        s.selected = [gone]
        s.remove([gone])
        #expect(s.photos.count == 3)
        #expect(s.cursor == nil)
    }

    @Test func aControlOnOnePhotoActsOnThatPhotoAlone() {
        let s = store(count: 4)
        s.cursor = 0
        let far = s.photos[3]
        #expect(s.targets(for: far).map(\.url) == [far.url])
    }

    @Test func aPhotoInsideTheSelectionCarriesTheSelection() {
        let s = store(count: 4)
        s.selected = [s.photos[1].url, s.photos[2].url]
        let inside = s.photos[1]
        #expect(s.targets(for: inside).count == 2)
        // The photo beside it is not in the selection, so it still goes alone.
        #expect(s.targets(for: s.photos[3]).count == 1)
    }

    /// Rewritten with `aiming` (D-104): the aim cannot be set without the
    /// thing that puts it back, so the test takes one rather than assigning.
    @Test func aScopedActionOverridesTheCursorAndTheSelection() {
        let s = store(count: 4)
        s.selected = [s.photos[0].url]
        s.aiming(at: [s.photos[3]]) {
            #expect(s.targets.map(\.name) == ["3.jpg"])
        }
        #expect(s.targets.map(\.name) == ["0.jpg"], "leaving the scope hands the targets back")
    }

    @Test func autoAdvanceFollowsADecisionOnlyOnThePhotoYouAreOn() {
        let s = store(count: 4)
        s.autoAdvance = true
        s.cursor = 0

        s.aiming(at: [s.photos[3]]) { s.advanceIfEnabled() }
        #expect(s.cursor == 0, "a click on a cell across the grid is about that cell")

        s.aiming(at: [s.photos[0]]) { s.advanceIfEnabled() }
        #expect(s.cursor == 1, "a decision on the photo under the cursor steps on")
    }

    /// D-144. Keep, reject and a label sort a photograph and finish with it,
    /// so the cursor follows. The favorite does not: it is a toggle, and it is
    /// made while looking at a frame that is usually being flagged in the same
    /// breath. Advancing took the heart off screen at the moment it was
    /// pressed, and put the second press that would undo it on the next
    /// photograph.
    @Test func favoritingStaysOnThePhotographWhileFlaggingMovesOn() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-favorite-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 1...3 { try Data([0]).write(to: root.appendingPathComponent("p\(i).jpg")) }

        let router = CommandRouter(store: LibraryStore())
        router.open(root)
        router.store.autoAdvance = true
        router.store.cursor = 0

        router.perform(.toggleFavorite)
        #expect(router.store.cursor == 0, "the heart moved the cursor off the photo it marked")
        #expect(router.store.photos[0].favorite, "and it did not mark it")

        // Pressing it again undoes it, on the same photograph, which is the
        // half that advancing made unreachable.
        router.perform(.toggleFavorite)
        #expect(router.store.cursor == 0)
        #expect(!router.store.photos[0].favorite, "a second press did not clear the first")

        // The flags are unchanged: they still step on.
        router.perform(.flagKeep)
        #expect(router.store.cursor == 1, "keep stopped advancing")
    }

    @Test func theHeaderCountsWhatTheNextCommandWillActOnAndTheCellNamesIt() {
        let s = store(count: 3)
        s.cursor = 1
        // Rewritten 2026-09-15 for D-115: a single photo is named by its own
        // cell in the grid, so the header no longer says it a second time. The
        // label is now only the thing a cell cannot say — how many.
        #expect(s.targetLabel == nil)
        s.selected = [s.photos[0].url, s.photos[2].url]
        #expect(s.targetLabel == "2 of 3 selected", "the whole sentence, since it is the only place it is said")
        s.clearSelection()
        s.remove(Set(s.photos.map(\.url)))
        #expect(s.targetLabel == nil, "an empty folder has nothing to count")
    }

    @Test func anErrorIsAToastAndStillReadableAsTheLastError() {
        let s = store(count: 1)
        s.showError("That name is already taken.")
        #expect(s.toast?.isError == true)
        #expect(s.lastError == "That name is already taken.")
    }

    @Test func thumbnailSizeStepsAndStopsAtBothEnds() {
        let s = store(count: 1)
        let router = CommandRouter(store: s)
        let steps = Tokens.Layout.gridCellSteps

        s.cellSize = steps[0]
        router.perform(.thumbsSmaller)
        #expect(s.cellSize == steps[0], "the smallest step does not wrap round to the largest")

        router.perform(.thumbsLarger)
        #expect(s.cellSize == steps[1])

        s.cellSize = steps[steps.count - 1]
        router.perform(.thumbsLarger)
        #expect(s.cellSize == steps[steps.count - 1])
    }

    @Test func progressWithNothingToCountSaysSoRatherThanDrawingAnEmptyBar() {
        let counted = ProgressState(label: "Rotating", done: 2, total: 8)
        #expect(!counted.isIndeterminate)
        #expect(counted.fraction == 0.25)
        #expect(ProgressState(label: "Undoing", done: 0, total: 0).isIndeterminate)
    }

    // MARK: the peek (D-130)

    @Test func neitherHalfOfThePeekIsEnoughOnItsOwn() {
        let s = store(count: 4)
        s.pointer(true, on: s.photos[2])
        #expect(s.peeked == nil, "a hover with no modifier is just a hover")
        s.pointer(false, on: s.photos[2])
        s.optionHeld = true
        #expect(s.peeked == nil, "a modifier with no pointer has nothing to look at")
    }

    @Test func theTwoTogetherArePeekingAtThatPhoto() {
        let s = store(count: 4)
        s.optionHeld = true
        s.pointer(true, on: s.photos[2])
        #expect(s.peeked?.url == s.photos[2].url)
    }

    @Test func thePeekGoesWithWhicheverHalfEndsFirst() {
        let s = store(count: 4)
        s.optionHeld = true
        s.pointer(true, on: s.photos[1])
        s.pointer(false, on: s.photos[1])
        #expect(s.peeked == nil, "the pointer left the thumbnail")

        s.pointer(true, on: s.photos[1])
        s.optionHeld = false
        #expect(s.peeked == nil, "the modifier came up")
    }

    /// AppKit delivers the arriving cell's enter before the leaving cell's
    /// exit. An unconditional clear on the way out wipes the claim the new
    /// cell just made, and the peek blinks off in the middle of a sweep.
    @Test func sweepingFromOneThumbnailToTheNextNeverBlanks() {
        let s = store(count: 4)
        s.optionHeld = true
        s.pointer(true, on: s.photos[0])
        s.pointer(true, on: s.photos[1])   // enter, out of order
        s.pointer(false, on: s.photos[0])  // then the exit it beat
        #expect(s.peeked?.url == s.photos[1].url, "the sweep lost the cell it arrived on")
    }

    /// A look, not a place. Nothing about where the keyboard is or what is
    /// selected may move, or a peek over a row would quietly retarget every
    /// command that reads the cursor.
    @Test func peekingMovesNeitherTheCursorNorTheSelection() {
        let s = store(count: 4)
        s.cursor = 0
        s.selected = [s.photos[0].url]
        let selected = s.selected
        s.optionHeld = true
        s.pointer(true, on: s.photos[3])
        #expect(s.peeked?.url == s.photos[3].url)
        #expect(s.cursor == 0)
        #expect(s.selected == selected)
    }

    /// The peek draws in the gallery. If it ever needed the preview window it
    /// would be the preview window, which is the thing it exists not to open.
    @Test func peekingOpensNoWindow() {
        let s = store(count: 4)
        s.optionHeld = true
        s.pointer(true, on: s.photos[1])
        #expect(s.peeked != nil)
        #expect(!s.previewOpen)
    }

    // MARK: where the peek lands (D-131)

    private func peek(_ anchor: CGRect) -> PeekOverlay {
        PeekOverlay(ref: PhotoRef(url: URL(fileURLWithPath: "/x/1.jpg"),
                                  fileSize: 1, created: .now, modified: .now),
                    anchor: anchor)
    }

    @Test func thePanelSitsToTheRightWhenThereIsRoom() {
        let cell = CGRect(x: 40, y: 200, width: 160, height: 160)
        let p = peek(cell).placement(in: CGSize(width: 1200, height: 800))
        #expect(p.x > cell.maxX, "the panel overlapped the thumbnail it is about")
    }

    @Test func itFlipsToTheLeftAtTheRightEdge() {
        let cell = CGRect(x: 1000, y: 200, width: 160, height: 160)
        let p = peek(cell).placement(in: CGSize(width: 1200, height: 800))
        #expect(p.x + p.side <= cell.minX, "the panel ran off the right edge")
    }

    /// Centered on the cell, except where centering would hang it off the
    /// window. A cell in the top row is the case that finds this.
    @Test func itIsPushedBackInsideAtTheTopAndTheBottom() {
        let size = CGSize(width: 1200, height: 800)
        let top = peek(CGRect(x: 40, y: 0, width: 160, height: 160)).placement(in: size)
        #expect(top.y >= 0)
        let bottom = peek(CGRect(x: 40, y: 760, width: 160, height: 160)).placement(in: size)
        #expect(bottom.y + bottom.side <= size.height)
    }

    /// Every cell in a plausible grid, in a window narrow enough that the
    /// panel has to shrink. Nothing may leave the window on any side.
    @Test func noCellPutsThePanelOutsideTheWindow() {
        let size = CGSize(width: 780, height: 520)
        for row in 0..<3 {
            for col in 0..<4 {
                let cell = CGRect(x: CGFloat(col) * 180 + 20, y: CGFloat(row) * 170 + 10,
                                  width: 160, height: 160)
                let p = peek(cell).placement(in: size)
                #expect(p.x >= 0 && p.x + p.side <= size.width, "off the side at \(cell)")
                #expect(p.y >= 0 && p.y + p.side <= size.height, "off the top or bottom at \(cell)")
                #expect(p.side > 0, "the panel collapsed at \(cell)")
            }
        }
    }

    /// The guarantee the whole placement exists for (D-131, D-235): the panel
    /// goes *beside* the thumbnail, so the cell stays visible and the answer to
    /// "which one is this" is the thing next to it.
    ///
    /// `noCellPutsThePanelOutsideTheWindow` above checked the window's edges and
    /// not this one, which is how a narrow window came to draw the panel over
    /// the cell it was previewing: at 900 points with the cursor in the middle
    /// of a row the panel covered its own thumbnail completely.
    ///
    /// Every cell of a plausible grid at every width from one that cannot hold
    /// the panel to one that holds it twice over. Overlap is checked in x
    /// alone, because a panel that clears the cell horizontally clears it.
    @Test func thePanelNeverCoversTheThumbnailItIsAbout() {
        for width in stride(from: 420.0, through: 1400, by: 20) {
            let size = CGSize(width: width, height: 620)
            let step = 180.0
            for col in 0..<max(1, Int((width - 40) / step)) {
                for row in 0..<3 {
                    let cell = CGRect(x: Double(col) * step + 20, y: Double(row) * 170 + 10,
                                      width: 160, height: 160)
                    guard cell.maxX <= width else { continue }
                    let p = peek(cell).placement(in: size)
                    let panel = CGRect(x: p.x, y: p.y, width: p.side, height: p.side)
                    #expect(!panel.intersects(cell),
                            "at \(Int(width)) the panel \(panel) covered the cell \(cell)")
                    #expect(p.x >= 0 && p.x + p.side <= width, "off the side at \(cell) in \(Int(width))")
                }
            }
        }
    }

    /// Shrinking is the price of never overlapping, and it is paid only where
    /// it has to be: a window with room on the right still gets the full panel.
    @Test func thePanelKeepsItsFullSizeWhereThereIsRoomForIt() {
        let cell = CGRect(x: 40, y: 200, width: 160, height: 160)
        let p = peek(cell).placement(in: CGSize(width: 1200, height: 800))
        #expect(p.side == Tokens.Layout.peekPanel)
    }

    // MARK: what the header counts (D-133)

    /// Rewritten 2026-09-17 for D-202. This used to assert the status slot
    /// carried the count, and the count was also on the action bar four inches
    /// to the right: the header read "4 selected of 8  ·  4 selected", which
    /// makes a reader check whether two numbers agree. One place now, and it is
    /// the action bar, because the rule is that a target is named beside the
    /// controls that will act on it.
    @Test func theCountIsSaidOnceAndBesideTheControlsThatUseIt() {
        let s = store(count: 8)
        s.cursor = 1
        s.selected = [s.photos[1].url]
        #expect(s.targetLabel == "1 of 8 selected")
        #expect(!GalleryBand.status(of: s).contains("selected"), "the count is in two places again")
        s.selected = Set(s.photos.prefix(6).map(\.url))
        #expect(s.targetLabel == "6 of 8 selected")
        #expect(!GalleryBand.status(of: s).contains("selected"))
    }

    /// With nothing chosen the slot says nothing. Not "0 selected of 8",
    /// which is a sentence about an absence, and not the cursor's position
    /// either: the readout is about the selection or it is not there.
    @Test func withNothingSelectedItSaysNothing() {
        let s = store(count: 8)
        s.cursor = 1
        s.selected = []
        #expect(!GalleryBand.status(of: s).contains("of 8"))
        #expect(!GalleryBand.status(of: s).contains("selected"))
    }

    /// The one count that is not about the selection. A blank window with no
    /// word on it is a window that might be broken.
    @Test func anEmptyFolderStillSaysSo() {
        let s = store(count: 0)
        #expect(GalleryBand.status(of: s).contains("empty"))
    }

    // MARK: the clipboard (D-135)

    @Test func copyingLoadsTheClipboardAndPastingLeavesItLoaded() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clip-\(UUID().uuidString)")
        let from = root.appendingPathComponent("from"), a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        for d in [from, a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let one = from.appendingPathComponent("one.jpg")
        try Data([0xFF, 0xD8]).write(to: one)

        let router = CommandRouter(store: LibraryStore())
        router.store.clipboard = [one]

        // Into the first folder, then the second, off one copy.
        for dest in [a, b] {
            router.open(dest)
            router.perform(.pasteHere)
            #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("one.jpg").path),
                    "nothing landed in \(dest.lastPathComponent)")
            #expect(router.store.clipboard == [one], "the clipboard emptied itself")
        }
        // And the original never moved, which is what makes the second paste
        // possible at all.
        #expect(FileManager.default.fileExists(atPath: one.path))
    }

    @Test func aPasteIsOneUndo() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clip-\(UUID().uuidString)")
        let from = root.appendingPathComponent("from"), into = root.appendingPathComponent("into")
        for d in [from, into] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        var urls: [URL] = []
        for n in 1...3 {
            let u = from.appendingPathComponent("\(n).jpg")
            try Data([0xFF, 0xD8]).write(to: u)
            urls.append(u)
        }
        let router = CommandRouter(store: LibraryStore())
        router.open(into)
        router.store.clipboard = urls
        router.perform(.pasteHere)
        let landed = try FileManager.default.contentsOfDirectory(atPath: into.path)
        #expect(landed.count == 3)
        #expect(router.store.undo.canUndo, "three files pasted and nothing to undo")
    }

    @Test func clearingTheClipboardEmptiesIt() {
        let s = store(count: 2)
        let router = CommandRouter(store: s)
        s.clipboard = s.photos.map(\.url)
        router.perform(.clearClipboard)
        #expect(s.clipboard.isEmpty)
    }

    @Test func everyCommandInTheMapIsNamedAndGrouped() {
        // The help overlay filters on these two strings, so a command with a
        // blank one is a command the search cannot find.
        for command in Command.allCases {
            #expect(!command.label.isEmpty)
            #expect(Command.groups.contains(command.group))
        }
    }
}

/// The breadcrumb's menus (D-61). SwiftUI's `Menu` dropped the chevron in its
/// label and the crumbs ran together; the replacement pops an `NSMenu` out of a
/// plain `Button`, which only works if the button has a real view behind it.
@Suite @MainActor struct PopMenuTests {
    init() { Preferences.useTestDefaults() }

    private func host(_ view: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    @Test func theMenuHasAViewToComeOutOf() {
        let anchor = PopMenuAnchor()
        let window = host(
            PopMenuButton(hint: "Subfolders", accessibilityLabel: "Subfolders", anchor: anchor) {
                [PopMenuItem(title: "Day 1") {}]
            } label: {
                Glyph.draw(Glyph.Chevron())
                    .frame(width: Tokens.Layout.glyphButton, height: Tokens.Layout.glyphButton)
            }
        )
        #expect(anchor.view != nil)
        #expect(anchor.view?.window === window)
        // A zero-size anchor would pop the menu in the window's corner.
        #expect((anchor.view?.bounds.width ?? 0) >= Tokens.Layout.glyphButton)
    }

    @Test func aCheckedItemIsTheBranchThePathRunsThrough() {
        let items = [PopMenuItem(title: "Day 1", checked: true) {},
                     PopMenuItem(title: "Day 2") {}]
        #expect(items.filter(\.checked).map(\.title) == ["Day 1"])
    }
}

/// Tech debt 16: the aim is taken for the length of a closure and put back
/// however that closure leaves (D-104).
@Suite @MainActor struct AimTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int) -> LibraryStore {
        let s = LibraryStore()
        for i in 0..<count {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    @Test func anAimNestedInsideAnotherGivesTheOuterOneBack() {
        let s = store(count: 4)
        s.aiming(at: [s.photos[1]]) {
            s.aiming(at: [s.photos[3]]) {
                #expect(s.targets.map(\.name) == ["3.jpg"])
            }
            #expect(s.targets.map(\.name) == ["1.jpg"],
                    "the inner command finished, and the outer one is still running")
        }
        #expect(s.actionScope == nil)
    }

    @Test func aBodyThatThrowsStillPutsTheAimBack() {
        struct Stop: Error {}
        let s = store(count: 3)
        #expect(throws: Stop.self) {
            try s.aiming(at: [s.photos[2]]) { throw Stop() }
        }
        #expect(s.actionScope == nil, "the failure that used to leave every later command aimed at a stale photo")
        #expect(s.targets.map(\.name) == ["0.jpg"])
    }

    @Test func anEarlyReturnPutsItBackToo() {
        let s = store(count: 3)
        func act() -> String {
            s.aiming(at: [s.photos[1]]) {
                if s.photos.count > 1 { return "left early" }
                return "ran on"
            }
        }
        #expect(act() == "left early")
        #expect(s.actionScope == nil)
    }

    @Test func theAimIsWhatTheBodyReturns() {
        let s = store(count: 2)
        let name = s.aiming(at: [s.photos[1]]) { s.targets.map(\.name).joined() }
        #expect(name == "1.jpg")
    }
}

/// D-145. The sidebar is 220pt and a shoot is called "2025-06-12 San
/// Francisco", so the row truncates and the tooltip is how the name is read.
/// It used to be the path alone, which is the name with the answer buried at
/// the end of a line of home directory.
@Suite @MainActor struct FolderTooltipTests {
    @Test func theTooltipLeadsWithTheNameAndKeepsThePath() {
        let url = URL(fileURLWithPath: "/Users/x/Documents/2025-06-12 San Francisco")
        let tip = FolderSidebar.tooltip(for: url)
        #expect(tip.hasPrefix("2025-06-12 San Francisco\n"),
                "the name has to be the first thing read, not the last")
        #expect(tip.contains(url.path), "two shoots a year apart can share a name")
    }

    /// The name is never cut in the tooltip, whatever the row does to it: the
    /// tooltip exists precisely because the row cut it.
    @Test func theTooltipNeverTruncates() {
        let long = String(repeating: "shoot-", count: 40) + "end"
        let tip = FolderSidebar.tooltip(for: URL(fileURLWithPath: "/Users/x/" + long))
        #expect(tip.hasPrefix(long + "\n"))
        #expect(!tip.contains("\u{2026}"))
    }
}

/// Tech debt 24: the empty heart no longer needs a pointer (D-105). Keep and
/// reject answered to `CellOffer` too until their pill left the cell (D-170),
/// which is what took four of these tests with it.
@Suite @MainActor struct FavoriteReachTests {
    @Test func theCursorIsOfferedTheHeartWithNoPointerInvolved() {
        #expect(CellOffer.offeredMark(hovering: false, isCursor: true),
                "a run done entirely on the keyboard is offered the favorite")
    }

    @Test func thePointerStillOffersItOnAnyPhoto() {
        #expect(CellOffer.offeredMark(hovering: true, isCursor: false))
    }

    @Test func aPhotoThatIsNeitherKeepsItsCorner() {
        #expect(!CellOffer.offeredMark(hovering: false, isCursor: false),
                "one offer on screen at a time, not a heart stamped on every cell")
    }

    /// Rewritten at D-142, which is where this rule changed. It used to read
    /// `!offeredMark(...)` at the smallest sizes, on the grounds that a mark
    /// crowds a small photograph. A set heart is drawn at 96px regardless, so
    /// what the gate actually did was take the control away at the moment it
    /// was used: click the heart on a 128px cell and the favorite cleared, and
    /// no pointer could ever set it again.
    @Test func theHeartIsOfferedAtEveryCellSize() {
        #expect(CellOffer.offeredMark(hovering: true, isCursor: false),
                "the pointer sets a favorite at 96px, where the set heart already draws")
        #expect(CellOffer.offeredMark(hovering: false, isCursor: true),
                "and so does the keyboard")
    }

    /// The rule itself, in full. It was one rule for two marks until the pill
    /// left (D-170); the heart still answers it, and a gate added back for the
    /// pair is what would fail here.
    @Test func theMarkIsOfferedToThePointerAndTheCursorAndNobodyElse() {
        for hovering in [true, false] {
            for isCursor in [true, false] {
                #expect(CellOffer.offeredMark(hovering: hovering, isCursor: isCursor) == (hovering || isCursor),
                        "mark: hover \(hovering), cursor \(isCursor)")
            }
        }
    }

    /// The defect itself, as a rule: a favorite cleared by its own mark leaves
    /// the mark behind to be pressed again. Anything that can be turned off by
    /// pressing it can be turned back on the same way (D-142).
    @Test func clearingAFavoriteLeavesTheControlOnScreen() {
        // What the cell draws: `ref.favorite || revealed`, at every step of
        // the size control.
        for size in Tokens.Layout.gridCellSteps {
            let revealed = CellOffer.offeredMark(hovering: true, isCursor: false)
            #expect(true || revealed, "a set heart draws at \(size)")
            #expect(false || revealed, "and the pointer can set it again at \(size)")
        }
    }
}

/// Tech debt 37: the photograph used to lose the same 16pt at every grid step
/// (D-120).
@Suite struct CellInsetTests {
    @Test func theInsetIsOnTheSpacingScaleAtEveryStep() {
        let scale: Set<CGFloat> = [Tokens.Space.s4, Tokens.Space.s8, Tokens.Space.s12,
                                   Tokens.Space.s16, Tokens.Space.s24]
        for step in Tokens.Layout.gridCellSteps {
            #expect(scale.contains(Tokens.Layout.cellInset(for: step)),
                    "the inset at \(step) is off the 4px scale")
        }
    }

    @Test func theSmallCellKeepsMoreOfItsPicture() {
        // The whole point of the change: at 96 the constant 8 took a sixth of
        // the photograph away, and the largest step never noticed the number.
        let small = Tokens.Layout.cellInset(for: 96)
        let large = Tokens.Layout.cellInset(for: 300)
        #expect(small < large)
        #expect(96 - small * 2 > 96 - Tokens.Space.s8 * 2,
                "the 96pt cell shows more photograph than it used to")
    }

    @Test func theInsetNeverEatsMoreThanASixthOfTheCell() {
        for step in Tokens.Layout.gridCellSteps {
            let lost = Tokens.Layout.cellInset(for: step) * 2
            #expect(lost / step <= 1.0 / 6.0,
                    "a \(step)pt cell loses \(lost)pt of photograph")
        }
    }
}

/// A crop can be adjusted after it is drawn (D-159). The gesture cannot be
/// driven from a test; the geometry it delegates to can, which is why the
/// geometry is a type rather than four branches inside the gesture.
@Suite struct CropGripTests {
    private let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func aPressAwayFromTheRectangleDrawsANewOne() {
        let grip = CropGrip(at: CGPoint(x: 10, y: 10), in: rect)
        #expect(grip.isNew)
        let drawn = grip.apply(translation: CGSize(width: 50, height: 40),
                               to: CGPoint(x: 10, y: 10), at: CGPoint(x: 60, y: 50), within: frame)
        #expect(drawn == CGRect(x: 10, y: 10, width: 50, height: 40))
    }

    @Test func aPressOnAnEdgeMovesThatEdgeAndLeavesTheOthers() {
        let grip = CropGrip(at: CGPoint(x: 100, y: 150), in: rect)
        #expect(grip.left && !grip.right && !grip.top && !grip.bottom)
        let pulled = grip.apply(translation: CGSize(width: -40, height: 0),
                                to: CGPoint(x: 100, y: 150), at: CGPoint(x: 60, y: 150), within: frame)
        #expect(pulled == CGRect(x: 60, y: 100, width: 240, height: 100),
                "the left edge moved and the other three stayed")
    }

    @Test func aPressOnACornerMovesBothItsEdges() {
        let grip = CropGrip(at: CGPoint(x: 300, y: 200), in: rect)
        #expect(grip.right && grip.bottom)
        let pulled = grip.apply(translation: CGSize(width: 50, height: 50),
                                to: CGPoint(x: 300, y: 200), at: CGPoint(x: 350, y: 250), within: frame)
        #expect(pulled == CGRect(x: 100, y: 100, width: 250, height: 150))
    }

    @Test func aPressInsideMovesTheWholeRectangle() {
        let grip = CropGrip(at: CGPoint(x: 200, y: 150), in: rect)
        #expect(grip.moving)
        let moved = grip.apply(translation: CGSize(width: 30, height: -20),
                               to: CGPoint(x: 200, y: 150), at: CGPoint(x: 230, y: 130), within: frame)
        #expect(moved == CGRect(x: 130, y: 80, width: 200, height: 100),
                "the same crop, somewhere else on the photograph")
    }

    /// Nothing leaves the photograph. A crop dragged off the frame would save
    /// a copy of pixels that are not there.
    @Test func aMoveStopsAtTheEdgeOfThePhotograph() {
        let grip = CropGrip(at: CGPoint(x: 200, y: 150), in: rect)
        let moved = grip.apply(translation: CGSize(width: 10_000, height: 10_000),
                               to: CGPoint(x: 200, y: 150), at: CGPoint(x: 10_200, y: 10_150), within: frame)
        #expect(frame.contains(moved))
        #expect(moved.width == rect.width && moved.height == rect.height,
                "pushed against the edge it stops rather than shrinking")
    }

    /// An edge dragged past its opposite swaps the two. The alternative is a
    /// rectangle with a negative side, which is not what the pointer looks
    /// like it is doing.
    @Test func anEdgeDraggedPastItsOppositeFlipsRatherThanInverting() {
        let grip = CropGrip(at: CGPoint(x: 100, y: 150), in: rect)
        let flipped = grip.apply(translation: CGSize(width: 260, height: 0),
                                 to: CGPoint(x: 100, y: 150), at: CGPoint(x: 360, y: 150), within: frame)
        #expect(flipped.width > 0 && flipped.height > 0)
        #expect(flipped.minX == 300, "the old right edge is the new left one")
    }

    @Test func anEdgePulledOntoItsOppositeKeepsTheCropUsable() {
        let grip = CropGrip(at: CGPoint(x: 100, y: 150), in: rect)
        let squashed = grip.apply(translation: CGSize(width: 199, height: 0),
                                  to: CGPoint(x: 100, y: 150), at: CGPoint(x: 299, y: 150), within: frame)
        #expect(squashed == rect, "a crop too small to see is refused, not saved")
    }

    @Test func thereAreEightGripsAndTheyAreOnTheRectangle() {
        let grips = CropGrip.grips(of: rect)
        #expect(grips.count == 8)
        for point in grips {
            #expect(rect.insetBy(dx: -1, dy: -1).contains(point))
        }
        #expect(!grips.contains(CGPoint(x: rect.midX, y: rect.midY)), "no grip in the middle")
    }
}

/// `⌘↓` and a step sideways offer folders that lead somewhere (D-152).
@Suite @MainActor struct SubfolderOfferTests {
    private func tree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-tree-" + UUID().uuidString)
        let fm = FileManager.default
        for name in ["shoot", "exports", "deeper", "deeper/inside"] {
            try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data([0]).write(to: root.appendingPathComponent("shoot/a.jpg"))
        try Data([0]).write(to: root.appendingPathComponent("deeper/inside/b.jpg"))
        try Data([0]).write(to: root.appendingPathComponent("exports/notes.txt"))
        return root
    }

    @Test func aFolderOfPhotographsLeadsSomewhere() throws {
        let root = try tree(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(FolderScanner.leadsSomewhere(root.appendingPathComponent("shoot")))
    }

    /// The case that makes this "dead end" rather than "no photographs": a
    /// card's DCIM holds no images itself and is the way to every one of them.
    @Test func aFolderOfFoldersLeadsSomewhere() throws {
        let root = try tree(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(FolderScanner.leadsSomewhere(root.appendingPathComponent("deeper")))
    }

    @Test func aFolderOfOtherFilesIsADeadEnd() throws {
        let root = try tree(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FolderScanner.leadsSomewhere(root.appendingPathComponent("exports")))
    }

    @Test func theMenuDropsTheDeadEnds() throws {
        let root = try tree(); defer { try? FileManager.default.removeItem(at: root) }
        let offered = CommandRouter.worthOffering(FolderScanner.subfolders(of: root))
            .map(\.lastPathComponent)
        #expect(offered.contains("shoot") && offered.contains("deeper"))
        #expect(!offered.contains("exports"))
    }

    /// A step sideways has to find its own place in the row, so the folder
    /// being stood in stays in the list whatever it holds.
    @Test func theFolderYouAreInIsNeverDroppedFromTheRow() throws {
        let root = try tree(); defer { try? FileManager.default.removeItem(at: root) }
        let here = root.appendingPathComponent("exports")
        let offered = CommandRouter.worthOffering(FolderScanner.subfolders(of: root), keeping: here)
            .map(\.lastPathComponent)
        #expect(offered.contains("exports"), "you cannot step sideways out of a folder you are not in")
    }
}

/// The zoom readout is the zoom control (D-154), and the pair has one at all
/// (D-155).
@Suite @MainActor struct ZoomControlTests {
    init() { Preferences.useTestDefaults() }

    private func store() -> LibraryStore {
        let s = LibraryStore()
        s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now))
        s.cursor = 0
        s.oneToOneScale = 4
        return s
    }

    @Test func theReadoutTogglesTheSameZoomTheDoubleClickDoes() {
        let s = store()
        s.toggleActualSize()
        #expect(s.zoom == 4 && s.zoomIsActual)
        s.toggleActualSize()
        #expect(s.zoom == nil && !s.zoomIsActual)
    }

    /// Back to fit is back to the whole frame, the way Esc already was: a
    /// visible rect left behind at the old zoom is a histogram about a corner
    /// of a photograph nobody is looking at any more.
    @Test func goingBackToFitAlsoGoesBackToTheWholeFrame() {
        let s = store()
        s.toggleActualSize()
        s.visibleRect = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        s.toggleActualSize()
        #expect(s.visibleRect == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// A pair is drawn smaller than one photograph in the same window, so 1:1
    /// there is a different number. Passing it in is what keeps one method
    /// answering for both (D-155).
    @Test func aPairAsksForItsOwnActualSize() {
        let s = store()
        s.toggleActualSize(oneToOne: 9)
        #expect(s.zoom == 9, "the pair's own 1:1, not the single frame's")
    }
}

/// The first-time hints can be brought back (D-153).
/// The app writes down where you have been, so there has to be a way to take
/// it back off the disk (D-173).
@Suite(.serialized) @MainActor struct ForgetHistoryTests {
    init() { Preferences.useTestDefaults() }

    /// What is left in the domain after the clear, rather than what the source
    /// says it writes (S-27).
    ///
    /// `everyStoredPathIsInTheListTheControlClears` reads `Preferences.swift`
    /// for `d.set(…​.path, forKey:)`. `sessionBackups` is written from a
    /// `[String]` built the line before, so the scan never saw it: the control
    /// had a path it did not clear and a green test saying every path was in
    /// the list. A scan sees the spellings somebody thought of. This reads the
    /// whole scratch domain back and judges by the shape of what is stored, so
    /// a key added in any spelling at all is caught.
    ///
    /// Two survivors are named rather than tolerated. A pin is a choice the
    /// reader made. `sessionBackups` is what the next launch reads to sweep
    /// the backup directories a crash left, and those hold full-size copies of
    /// photographs: forgetting the path leaves them on disk with nothing that
    /// knows to take them away.
    @Test func theClearLeavesOnlyThePathsItSaysItLeaves() {
        let shoot = URL(fileURLWithPath: "/Users/someone/Pictures/Iceland 2026")
        let keepers = URL(fileURLWithPath: "/Users/someone/Pictures/Keepers")
        let backup = "/private/var/folders/ab/sift-backups-1"
        // Every path here is its own folder, and `keepers` is the only one
        // pinned. Sharing one between the pin and a cleared key is how the
        // first version of this test passed with `lastMoveFolder` taken out of
        // `historyKeys`: the survivor was allowed for the pin's sake (S-27).
        let moved = URL(fileURLWithPath: "/Users/someone/Pictures/Moved")
        let ingested = URL(fileURLWithPath: "/Users/someone/Pictures/Ingested")
        Preferences.noteRecent(shoot)
        Preferences.lastFolder = shoot
        Preferences.lastMoveFolder = moved
        Preferences.lastIngestFolder = ingested
        Preferences.lastEditor = URL(fileURLWithPath: "/Applications/Preview.app")
        Preferences.setResume(shoot.appendingPathComponent("a.jpg"), for: shoot)
        Preferences.pin(keepers)
        _ = Preferences.registerSessionBackups(backup)

        Preferences.forgetHistory()

        var left: [String] = []
        func walk(_ value: Any) {
            switch value {
            case let text as String where text.hasPrefix("/"): left.append(text)
            case let list as [Any]: for item in list { walk(item) }
            case let map as [String: Any]: for (key, item) in map { walk(key); walk(item) }
            default: break
            }
        }
        let scratch = UserDefaults(suiteName: "sift.tests")
        let domain = scratch?.persistentDomain(forName: "sift.tests") ?? [:]
        for (key, value) in domain { walk(key); walk(value) }

        let allowed = Set(Preferences.pinnedFolders.map(\.path) + Preferences.sessionBackupPaths)
        #expect(allowed.contains(keepers.path), "the pin was not written, so this asserts nothing")
        #expect(allowed.contains(backup), "the backup was not registered, so this asserts nothing")
        // The read is the half that can fail silently: an empty domain walks
        // nothing, finds nothing and passes. Taking `lastMoveFolder` out of
        // `historyKeys` has to turn this test red, and the first version of it
        // stayed green through exactly that (S-27).
        #expect(left.contains(keepers.path), "the domain read found no paths at all, so this asserts nothing")
        for path in left {
            #expect(allowed.contains(path),
                    "\(path) survives Forget Recent Folders and is neither a pin nor a session backup")
        }
    }

    @Test func forgettingClearsEveryPathAndKeepsThePins() {
        let shoot = URL(fileURLWithPath: "/Users/someone/Pictures/Iceland 2026")
        let keepers = URL(fileURLWithPath: "/Users/someone/Pictures/Keepers")
        Preferences.noteRecent(shoot)
        Preferences.lastFolder = shoot
        Preferences.lastMoveFolder = keepers
        Preferences.lastIngestFolder = shoot
        Preferences.lastEditor = URL(fileURLWithPath: "/Applications/Preview.app")
        Preferences.setResume(shoot.appendingPathComponent("a.jpg"), for: shoot)
        Preferences.pin(keepers)
        #expect(Preferences.anyHistory)

        Preferences.forgetHistory()

        #expect(Preferences.recentFolders.isEmpty)
        #expect(Preferences.lastFolder == nil)
        #expect(Preferences.lastMoveFolder == nil)
        #expect(Preferences.lastIngestFolder == nil)
        #expect(Preferences.lastEditor == nil)
        #expect(Preferences.resumeFile(for: shoot) == nil)
        #expect(!Preferences.anyHistory, "the control would still offer to clear what it just cleared")
        #expect(Preferences.pinnedFolders.map(\.path) == [keepers.path],
                "a pin was chosen; a recent was only recorded (D-173)")
    }

    /// One row out of the list, and the way back (D-321).
    ///
    /// A path can sit in four places at once. What the reader asked to forget
    /// is the folder, not the row their pointer was over, so all four go — and
    /// because getting the wrong row is a real mistake on a control that keeps
    /// the rest on purpose, the removal hands back what it took.
    @Test func forgettingOnePathTakesItOutOfEveryPlaceItIsStored() {
        // The scratch domain is wiped once a run, not once a test.
        Preferences.forgetHistory()
        let shoot = URL(fileURLWithPath: "/Users/someone/Pictures/Iceland 2026")
        let other = URL(fileURLWithPath: "/Users/someone/Pictures/Keepers")
        Preferences.noteRecent(other)
        Preferences.noteRecent(shoot)
        Preferences.lastFolder = shoot
        Preferences.lastMoveFolder = shoot
        Preferences.lastIngestFolder = other
        Preferences.setResume(shoot.appendingPathComponent("a.jpg"), for: shoot)
        Preferences.setResume(other.appendingPathComponent("b.jpg"), for: other)

        let forgotten = Preferences.forget(path: shoot)

        #expect(Preferences.recentFolders.map(\.path) == [other.path])
        #expect(Preferences.lastFolder == nil)
        #expect(Preferences.lastMoveFolder == nil)
        #expect(Preferences.resumeFile(for: shoot) == nil)
        #expect(!forgotten.isEmpty)
        // The rest of the list is the whole reason somebody used this control
        // rather than the one above it.
        #expect(Preferences.lastIngestFolder?.path == other.path)
        #expect(Preferences.resumeFile(for: other)?.lastPathComponent == "b.jpg")
    }

    @Test func puttingAForgottenPathBackRestoresEveryPlaceItWas() {
        // The scratch domain is wiped once a run, not once a test.
        Preferences.forgetHistory()
        let shoot = URL(fileURLWithPath: "/Users/someone/Pictures/Iceland 2026")
        Preferences.noteRecent(shoot)
        Preferences.lastFolder = shoot
        Preferences.setResume(shoot.appendingPathComponent("a.jpg"), for: shoot)

        Preferences.restore(Preferences.forget(path: shoot))

        #expect(Preferences.recentFolders.map(\.path) == [shoot.path])
        #expect(Preferences.lastFolder?.path == shoot.path)
        #expect(Preferences.resumeFile(for: shoot)?.lastPathComponent == "a.jpg")
    }

    /// Put back where it was, not at the front: an undo that reorders ⌘1 to
    /// ⌘9 is an undo that changed something else.
    @Test func aRestoredRecentGoesBackToItsOwnPlaceInTheList() {
        // The scratch domain is wiped once a run, not once a test.
        Preferences.forgetHistory()
        let one = URL(fileURLWithPath: "/Users/someone/Pictures/One")
        let two = URL(fileURLWithPath: "/Users/someone/Pictures/Two")
        let three = URL(fileURLWithPath: "/Users/someone/Pictures/Three")
        for folder in [one, two, three] { Preferences.noteRecent(folder) }
        #expect(Preferences.recentFolders.map(\.lastPathComponent) == ["Three", "Two", "One"])

        Preferences.restore(Preferences.forget(path: two))

        #expect(Preferences.recentFolders.map(\.lastPathComponent) == ["Three", "Two", "One"])
    }

    /// The open panel's keys are AppKit's, rewritten from its own domain on
    /// every panel, so a row removed there comes back. Left alone rather than
    /// offered and undone.
    @Test func forgettingOnePathLeavesTheOpenPanelsOwnKeysAlone() throws {
        // The scratch domain is wiped once a run, not once a test.
        Preferences.forgetHistory()
        let domain = try #require(UserDefaults(suiteName: "sift.tests"))
        let shoot = URL(fileURLWithPath: "/Users/someone/Pictures/Iceland 2026")
        domain.set(shoot.path, forKey: "NSNavLastRootDirectory")
        domain.set([shoot.path], forKey: "NSNavRecentPlaces")
        Preferences.noteRecent(shoot)

        _ = Preferences.forget(path: shoot)

        #expect(Preferences.recentFolders.isEmpty)
        #expect(domain.string(forKey: "NSNavLastRootDirectory") == shoot.path)
        #expect(domain.stringArray(forKey: "NSNavRecentPlaces") == [shoot.path])
    }

    /// A path that is stored nowhere reports nothing removed, so the row does
    /// not offer an undo for an act that did not happen.
    @Test func forgettingAPathThatIsNotStoredOffersNoUndo() {
        #expect(Preferences.forget(path: URL(fileURLWithPath: "/Users/someone/nowhere")).isEmpty)
    }

    /// The trail AppKit keeps, which the control missed until the sweep before
    /// going public (D-234).
    ///
    /// `NSOpenPanel` writes where it was last pointed into the app's own
    /// domain, under keys this app never names. The scan below cannot see
    /// them, because it reads the lines `Preferences.swift` writes, and that
    /// is exactly how it was missed: the button said it cleared every trail
    /// and left a bookmark with a full path in readable bytes.
    ///
    /// The fixture is a real bookmark of a real directory rather than a
    /// stand-in blob, because the first half of this test is the claim that
    /// the bytes are sensitive at all.
    @Test func forgettingClearsTheTrailTheOpenPanelKeeps() throws {
        let domain = try #require(UserDefaults(suiteName: "sift.tests"))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("2026-06-18 Go Karting Team Event-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // What AppKit leaves behind after one trip through the open panel.
        domain.set(try dir.bookmarkData(), forKey: "NSOSPLastRootDirectory")
        domain.set([dir.path], forKey: "NSNavRecentPlaces")

        let blob = try #require(domain.data(forKey: "NSOSPLastRootDirectory"))
        #expect(String(decoding: blob, as: UTF8.self).contains("Go Karting"),
                "the bookmark stopped carrying a readable path, so this test is no longer about anything")
        #expect(Preferences.anyHistory,
                "a trail the button cannot see is one it will offer not to clear")

        Preferences.forgetHistory()

        #expect(domain.object(forKey: "NSOSPLastRootDirectory") == nil,
                "the open panel's bookmark survived Forget Recent Folders")
        #expect(domain.object(forKey: "NSNavRecentPlaces") == nil,
                "the open panel's recent places survived Forget Recent Folders")
    }

    /// Every key that holds a path is in the list the control acts on. A
    /// preference added later that records a folder and is not listed here is
    /// a trail the button claims to have cleared and did not.
    ///
    /// The scan reads the literal keys, which is the shape all five of them
    /// are written in; `resume` is keyed by a constant and is checked by the
    /// test above instead.
    @Test func everyStoredPathIsInTheListTheControlClears() throws {
        let text = try Repo.text("Sift/Store/Preferences.swift")
        // Every line that writes a path under a key: `d.set(…​.path, forKey:
        // "x")`, in the one spelling the file uses for one.
        let recorded = Set(text.components(separatedBy: .newlines)
            .filter { $0.contains("d.set(") && $0.contains(".path") }
            .compactMap { line -> String? in
                guard let after = line.components(separatedBy: "forKey: \"").dropFirst().first
                else { return nil }
                return after.components(separatedBy: "\"").first
            })
        #expect(recorded.count >= 5, "the scan found almost nothing, so it is asserting nothing")
        for key in recorded {
            #expect(Preferences.historyKeys.contains(key), "\(key) records a path and is never cleared")
        }
        #expect(!Preferences.historyKeys.contains("pinnedFolders"),
                "a pin is a choice and survives the clear (D-173)")
    }
}

@Suite(.serialized) @MainActor struct HintRestoreTests {
    init() { Preferences.useTestDefaults() }

    @Test func aSpentHintComesBackWhenTheHintsAreRestored() {
        Preferences.forgetHints()
        let s = LibraryStore()
        s.hintOnce("undo", "first")
        #expect(s.hint != nil)
        s.hint = nil
        s.hintOnce("undo", "again")
        #expect(s.hint == nil, "a hint is shown once, ever (D-66)")

        Preferences.forgetHints()
        s.hintOnce("undo", "and again")
        #expect(s.hint != nil, "the control in Settings has to actually bring them back")
    }

    /// The list is what the control acts on, so a hint missing from it would
    /// be spent forever while the button claims to have restored everything.
    @Test func everyHintTheAppShowsIsInTheList() throws {
        let ids = try ["Sift/Input/CommandRouter.swift", "Sift/Store/LibraryStore.swift"]
            .flatMap { path -> [String] in
                let text = try Repo.text(path)
                return text.components(separatedBy: "hintOnce(\"").dropFirst()
                    .compactMap { $0.components(separatedBy: "\"").first }
            }
        #expect(!ids.isEmpty, "the scan found nothing, so it is asserting nothing")
        for id in Set(ids) {
            #expect(Preferences.hintIDs.contains(id), "\(id) is shown and cannot be restored")
        }
    }

    @Test func theControlSaysWhetherThereIsAnythingToBringBack() {
        Preferences.forgetHints()
        #expect(!Preferences.anyHintSeen)
        _ = Preferences.claimHint("undo")
        #expect(Preferences.anyHintSeen)
        Preferences.forgetHints()
    }
}

/// D-183. The header's right-hand group changes what the grid is showing.
/// Settings opens a window and the keyboard map opens an overlay: neither is
/// about the folder, and sitting with the filter and the sort they made a row
/// of five where there are two groups. They live in the sidebar's floor now,
/// and the sidebar got the visible toggle it had never had.
@Suite @MainActor struct ChromeHomeTests {
    init() { Preferences.useTestDefaults() }

    private func source(_ path: String) throws -> String { try Repo.text(path) }

    /// A source scan rather than a rendered toolbar: SwiftUI will not say what
    /// it drew, and the rule here is about which panel a control lives in,
    /// which is a fact about the file. The same shape as
    /// `everyHintTheAppShowsIsInTheList`.
    @Test func theAppsOwnControlsAreInTheSidebarAndNotInTheToolbar() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        let sidebar = try source("Sift/Views/FolderSidebar.swift")
        for glyph in ["Glyph.Gear()", "Glyph.Question()"] {
            #expect(!toolbar.contains(glyph), "\(glyph) is back in the row over the photographs")
            #expect(sidebar.contains(glyph), "\(glyph) has no control on screen at all")
        }
        #expect(!toolbar.contains("SettingsWindow.open()"), "the toolbar opens Settings again")
        #expect(sidebar.contains("SettingsWindow.open()"), "nothing on screen opens Settings")
    }

    /// The three are one sentence: the folder on screen, narrowed or reordered.
    /// A fourth kind of thing joining them is the drift this is here to catch.
    /// The group has a type of its own now (`WhatTheGridShows`), so the scan
    /// reads that declaration rather than an `HStack` it had to find by its
    /// spacing (D-208).
    @Test func theToolbarsViewControlsAreOnlyAboutTheGrid() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        let afterOpen = try #require(toolbar
            .components(separatedBy: "private struct WhatTheGridShows: CustomizableToolbarContent {")
            .dropFirst().first)
        let group = try #require(afterOpen.components(separatedBy: "\n}").first)
        let named = ["FavoritesItem()", "SearchItem()", "SortItem()"]
        for control in named {
            #expect(group.contains(control), "\(control) left the view-control group")
        }
        let items = group.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard let open = line.range(of: "{ "), line.hasSuffix(" }") else { return nil }
                return String(line[open.upperBound...].dropLast(2))
            }
        #expect(Set(items) == Set(named), "something that is not about the grid joined the group: \(items)")
    }

    /// The folder list was the one piece of the gallery's chrome with no
    /// control on screen, and putting Settings and the keyboard map inside it
    /// made that a dead end rather than an inconvenience (D-42).
    @Test func theFolderListHasAWayInThatIsNotAKeystroke() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        #expect(toolbar.contains("router.perform(.toggleSidebar)"),
                "nothing in the toolbar opens the folder list")
        #expect(toolbar.contains("Glyph.Sidebar(showing: store.showSidebar)"),
                "the toggle stopped reading the state it sets")

        let router = CommandRouter(store: LibraryStore())
        let was = router.store.showSidebar
        router.perform(.toggleSidebar)
        #expect(router.store.showSidebar != was, "the control does not move the state")
        router.perform(.toggleSidebar)
        #expect(router.store.showSidebar == was, "and it does not come back")
    }

    /// The reach rule runs both ways (D-205), and the toolbar is what makes the
    /// platform's half bite.
    ///
    /// This project's half is that no command is keyboard-only: everything has
    /// something on screen that starts it. The platform's half is the reverse —
    /// and it used to be a rule about a toolbar this app did not have. It has
    /// one now: `allowsUserCustomization` is on, so a reader can drag every
    /// file command out of the bar, and the menu bar is the only place left
    /// that a command cannot be taken from (D-208).
    @Test func everyCommandTheToolbarStartsIsAlsoInTheMenuBar() throws {
        let menus = try source("Sift/SiftApp.swift")
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        var missing: [String] = []
        for command in Command.allCases {
            guard toolbar.contains("perform(.\(command.rawValue))")
                || toolbar.contains("command: .\(command.rawValue),") else { continue }
            if !menus.contains("perform(.\(command.rawValue))") { missing.append(command.rawValue) }
        }
        #expect(missing.isEmpty, """
            the toolbar starts these and the menu bar does not: \(missing.joined(separator: ", "))
            A toolbar can be hidden, and this one can be emptied. The menu bar is the place a
            command cannot be taken from.
            """)
    }

    /// Share is in all three places, and the reach test above cannot see it.
    ///
    /// `everyCommandTheToolbarStartsIsAlsoInTheMenuBar` scans for
    /// `perform(.someCommand)`, and a `ShareLink` is not a command in this
    /// app's key map — it is the system's own control. So the rule it exists to
    /// enforce has to be asserted for this one by name, or the toolbar's share
    /// item could be dragged out of the bar and leave no way in (D-211).
    @Test func shareIsInTheToolbarTheMenuBarAndTheContextMenu() throws {
        for name in ["Sift/Views/GalleryToolbar.swift", "Sift/SiftApp.swift",
                     "Sift/Views/PhotoActions.swift"] {
            let file = try source(name)
            #expect(file.contains("ShareLink(items:"), "\(name) has no way to share")
        }
    }

    /// The toolbar draws no ground of its own, and that is the point of it.
    ///
    /// The rule this replaces said the opposite: every control in the
    /// hand-built header had to apply `controlFill`, because the six file
    /// actions had none and read as labels beside buttons (D-203). An
    /// `NSToolbar` draws the hover and the pressed state itself, so a
    /// `controlFill` inside the toolbar would be this app's rectangle over the
    /// system's — two edges for one control, which is the same defect D-203
    /// fixed, arriving from the other side (D-208).
    @Test func theToolbarLetsThePlatformDrawItsOwnControls() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        #expect(!toolbar.contains(".controlFill("),
                "the toolbar draws a second ground over the one the system already drew")
        #expect(!toolbar.contains("HeaderIcon("),
                "a toolbar item is drawing its own icon-and-caption instead of a Label")
        // And the preview bar is still the other exception, named: its controls
        // sit on a scrim over a photograph, and a second ground on one is two
        // edges for one control (D-184).
        let bar = try source("Sift/Views/PreviewBar.swift")
        #expect(!bar.contains(".controlFill("), "the bar over the photograph grew a second ground")
    }


    /// The readout is the control, so the ink has to differ between the two
    /// states rather than only the tooltip (D-183). The mark is a symbol now
    /// and there is no path to ask about, so this asks the pixels instead:
    /// the leading column is filled in while the list is up and drawn as rules
    /// while it is away, which is three quarters ink against a half. The pane
    /// beside it is empty either way, because the pane is on screen in both
    /// states and filling it would say the wrong thing twice.
    @Test func theSidebarGlyphSaysWhichStateItIsIn() throws {
        let up = try inkShare(of: Glyph.Sidebar(showing: true).symbol)
        let away = try inkShare(of: Glyph.Sidebar(showing: false).symbol)
        #expect(up.column > 0.7, "the column is not filled while the list is up: \(up.column)")
        #expect(away.column < 0.55, "the column is filled while the list is away: \(away.column)")
        #expect(up.column - away.column > 0.2,
                "the two states are within a hair of each other: \(up.column) and \(away.column)")
        #expect(up.pane < 0.3 && away.pane < 0.3,
                "the photographs' half is filled in: \(up.pane) and \(away.pane)")
    }

    /// How much of the leading third and of the trailing two thirds of a
    /// symbol is ink, at the size the header draws it.
    private func inkShare(of name: String) throws -> (column: Double, pane: Double) {
        let symbol = try #require(NSImage(systemSymbolName: name, accessibilityDescription: nil)
            .flatMap { $0.withSymbolConfiguration(
                .init(pointSize: Tokens.Layout.glyphAction, weight: .regular)) })
        let scale = 4
        let w = Int(symbol.size.width.rounded(.up)) * scale
        let h = Int(symbol.size.height.rounded(.up)) * scale
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()

        // The band down the middle of the box, so the rounded corners of the
        // rectangle count for neither side.
        let rows = (h * 4 / 10)...(h * 6 / 10)
        func share(_ columns: ClosedRange<Int>) -> Double {
            var ink = 0, total = 0
            for y in rows { for x in columns {
                total += 1
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 { ink += 1 }
            } }
            return total == 0 ? 0 : Double(ink) / Double(total)
        }
        // Inside the box's own edges on both sides: the outline is ink in
        // every state, and this is a question about what it encloses.
        return (share((w * 8 / 100)...(w * 28 / 100)),
                share((w * 45 / 100)...(w * 90 / 100)))
    }
}

/// D-185. A stroked glyph hit-tests on its stroke. A `Button` whose label is
/// one and nothing else is a control you press by tracing a 2pt line, which is
/// how the keyboard panel's reset arrow shipped: it looked like a button, said
/// it was a button, and answered about one press in four.
///
/// `GlyphButton` and `HeaderIcon` both lay a rectangle down, so the rule is
/// really "go through one of those, or say `contentShape` yourself". The scan
/// is the only way to hold it: SwiftUI will not report a view's hit shape.
@Suite @MainActor struct HitTargetTests {
    @Test func everyGlyphInAButtonHasARectangleUnderIt() throws {
        let views = Repo.at("Sift/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 20, "the scan found almost nothing, so it is asserting nothing")

        var thin: [String] = []
        var seen = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            // Each `Button`'s label block, taken as the text from the word
            // itself to the `.buttonStyle` that closes it. A real one only:
            // `GlyphButton` and `PopMenuButton` end in the same six letters
            // and lay their own rectangle down.
            let starts = text.ranges(of: try Regex("[^A-Za-z0-9_.]Button[ ]*[({]"))
            for (n, start) in starts.enumerated() {
                // To the next `Button`, not to the end of the file: a view
                // drawing a glyph *after* the last button in the file used to
                // land in that button's label and fail it.
                let stop = n + 1 < starts.count ? starts[n + 1].lowerBound : text.endIndex
                let rest = text[start.lowerBound..<stop]
                // And only when the chunk actually closes with a `buttonStyle`.
                // Without that the last button in a file swallows everything
                // written below it, which is how a mark that is not a control
                // at all ended up being asked for a hit target.
                guard rest.contains(".buttonStyle"),
                      let label = rest.components(separatedBy: ".buttonStyle").first,
                      label.contains("Glyph.draw")
                else { continue }
                seen += 1
                if !label.contains("contentShape") { thin.append(file.lastPathComponent) }
            }
        }
        #expect(seen >= 3, "the scan matched no glyph buttons at all, so it is asserting nothing")
        #expect(thin.isEmpty, "a glyph is its own hit target in \(Set(thin).sorted())")
    }
}

/// D-188. An app that paints its own header owes the reflexes the title bar it
/// replaced had. Double-click is the one people do without deciding to, and
/// what it does is a system setting rather than ours.
@Suite @MainActor struct TitleBarTests {
    /// What `TitleBarAction` reads out of a defaults holding this one value,
    /// with the domain taken away again afterwards.
    ///
    /// The cleanup used to run *before* the write rather than after, so every
    /// `swift test` left four `sift.titlebar.<uuid>` domains in
    /// `~/Library/Preferences`; 1,268 had accumulated by the time anybody
    /// counted them. It is the shape D-299 already fixed one layer down, where
    /// the suite left a backup directory per run in the temporary area: a test
    /// that touches machine state has to put it back (D-310).
    ///
    /// The `defer` runs while the value is still needed, which is why this
    /// returns the answer rather than the defaults: a helper handing back an
    /// object it has already emptied would be a helper that always reports the
    /// unset case, and three of these five tests would have passed on it.
    ///
    /// **One name and not a fresh UUID each time**, which is the half of this
    /// that took three tries. `removePersistentDomain` empties a domain and
    /// leaves its plist in `~/Library/Preferences`, so a new UUID per call
    /// left a file per call whether or not anything cleaned up after it: the
    /// count went up by four on a run that emptied all four. A fixed name
    /// leaves one file, forever, instead of four a run. The emptying still has
    /// to happen, because the next call reads this same domain and a value
    /// left in it is the unset case answering with the previous test's.
    ///
    /// **Not `register(defaults:)`,** which was the second try and was worse
    /// than the bug. It writes nothing to disk, which was the point, but the
    /// registration domain belongs to the *process* and not to the suite, so
    /// the value one call set was still there for the next: the two tests
    /// asking what an unset default does read the `None` left behind by the
    /// test above them and answered `.nothing`. Caught on the first run, which
    /// is the argument for holding the unset case at all (D-310).
    private static let domain = "sift.titlebar.test"

    private func action(_ value: String?) -> TitleBarAction {
        let d = UserDefaults(suiteName: Self.domain)!
        d.removePersistentDomain(forName: Self.domain)
        defer { d.removePersistentDomain(forName: Self.domain) }
        if let value { d.set(value, forKey: "AppleActionOnDoubleClick") }
        return TitleBarAction.configured(in: d)
    }

    @Test func theSettingDecides() {
        #expect(action("Maximize") == .zoom)
        #expect(action("Minimize") == .minimize)
        #expect(action("None") == .nothing)
    }

    /// Unset is the shipped default, and a value a later OS invents is still a
    /// title bar: zoom rather than nothing, because doing nothing looks like a
    /// dead header.
    @Test func anUnknownOrAbsentSettingZooms() {
        #expect(action(nil) == .zoom)
        #expect(action("FillScreen") == .zoom)
    }

    /// Asserted on the window, not on the call: `performZoom` is a method that
    /// a window is free to ignore, and a test that only proved it was called
    /// would pass on a window that never moved.
    @Test func zoomingActuallyResizesTheWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        let before = window.frame
        TitleBarAction.zoom.perform(on: window)
        #expect(window.frame != before, "the window did not move")
        #expect(window.isZoomed)
        TitleBarAction.zoom.perform(on: window)
        #expect(window.frame == before, "and it did not come back")
    }

    @Test func doingNothingLeavesTheWindowAlone() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let before = window.frame
        TitleBarAction.nothing.perform(on: window)
        #expect(window.frame == before)
    }

    /// The gesture is the platform's again (D-208).
    ///
    /// `TitleBarAction` exists because the app drew its own header over the
    /// title bar and owed the reflexes the bar it replaced had: a double-click
    /// there had to do whatever "Double-click a window's title bar to" is set
    /// to (D-188). The window has a real title bar now, so AppKit answers that
    /// double-click itself and nothing in this app may answer it first —
    /// a second handler would be this app's guess running beside the setting.
    ///
    /// The type stays. It reads a system preference, it is tested above, and
    /// the preview window can still want it.
    @Test func nothingInTheGalleryClaimsTheTitleBarDoubleClick() throws {
        for name in ["Sift/Views/GalleryToolbar.swift", "Sift/Views/RootView.swift",
                     "Sift/Views/Breadcrumb.swift"] {
            let file = try Repo.text(name)
            #expect(!file.contains("TitleBarAction.configured()"),
                    "\(name) answers the title bar's double-click over the top of AppKit")
        }
    }
}

/// Folder access: the route to macOS's own switches, and how it is reached
/// (D-309).
///
/// The premise these were written under is gone. Sift held no bookmarks and
/// had no access to give up, so this row could only point at the place that
/// did; since D-324 the app is sandboxed and the row's first job is the list
/// of grants it holds and the Revoke on each. What stays true is the seam —
/// the button goes through the presenter — and the refusal state, which is
/// what these three are about. The grants themselves are in `SandboxTests`.
@Suite @MainActor struct FolderAccessTests {

    /// The row goes through the presenter rather than reaching AppKit itself.
    ///
    /// The seam is the whole reason this is testable: the real presenter
    /// launches System Settings, which a suite has no business doing over
    /// whatever is on the author's screen. A view that built the URL inline
    /// would be a button no test could press.
    @Test func theFolderAccessRowGoesThroughThePresenter() throws {
        let view = try Repo.text("Sift/Views/SettingsWindow.swift")
        #expect(view.contains("openFolderAccessSettings()"),
                "the Folder access row stopped asking the presenter to open the pane")
        #expect(!view.contains("NSWorkspace"),
                "SettingsWindow reaches AppKit directly; the presenter is the seam (D-197)")
    }

    /// The stub counts the call and answers what it was told to, so the row's
    /// third state — System Settings refused to open — is a state a test can
    /// reach rather than one only the comment describes.
    @Test func theRefusalIsAStateAndNotAnAssumption() {
        let presenter = StubPresenter()
        #expect(presenter.openFolderAccessSettings())
        presenter.opensSettings = false
        #expect(!presenter.openFolderAccessSettings())
        #expect(presenter.openedFolderAccess == 2)
    }

    /// The pane identifier is Apple's, spelled once.
    ///
    /// Asserted on the shape rather than on the whole string, which would be
    /// this constant compared with a copy of itself. What is worth holding is
    /// that it is the settings scheme and names the Files & Folders anchor: a
    /// typo in either opens System Settings at whatever it was last showing,
    /// which looks like it worked.
    @Test func theFilesAndFoldersPaneIsTheOneApplePublishes() {
        let pane = AppKitPresenter.filesAndFoldersPane
        #expect(pane.hasPrefix("x-apple.systempreferences:"))
        #expect(pane.contains("com.apple.preference.security"))
        #expect(pane.hasSuffix("?Privacy_FilesAndFolders"))
        #expect(URL(string: pane) != nil, "the anchor does not parse as a URL")
    }

    /// Every section of the Settings form is a name `SIFT_SETTINGS_AT` takes,
    /// and every name it takes is a section.
    ///
    /// D-270 added the variable because the General form is twice the window's
    /// height and nothing outside the app can scroll it, so four of the five
    /// sections had never been photographed. The list was written by hand
    /// beside the `.id()`s, which is the shape of rule that breaks on the
    /// sixth one: **Folder access** is that sixth one, and it would have gone
    /// in unphotographable with nothing saying so.
    ///
    /// Both directions, for the reason the CONTRIBUTING table is checked both
    /// ways: a name the list has and the form does not sends a screenshot run
    /// to a section that is not there, and the refusal it gets back is
    /// indistinguishable from asking for a section that never existed.
    @Test func everySectionOfSettingsIsANameTheScreenshotVariableTakes() throws {
        let view = try Repo.text("Sift/Views/SettingsWindow.swift")
        let ids = Set(view.components(separatedBy: ".id(\"").dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first })
        let listed = Set(SettingsWindow.sections)
        // `history` stopped being a section on 2026-09-18, when the folder
        // list absorbed it (D-325), and stayed a name the variable takes so
        // a script or a habit lands on the list rather than on a refusal.
        // Named here rather than dropped from the check: an alias is a
        // deliberate exception, and the next name to go missing should still
        // fail this.
        let aliases: Set<String> = ["history"]

        #expect(ids.count > 4, "the scan found \(ids.count) sections, which is too few to be reading the form")
        #expect(ids.subtracting(listed).isEmpty,
                "the form has sections SIFT_SETTINGS_AT cannot reach: \(ids.subtracting(listed).sorted())")
        #expect(listed.subtracting(ids).subtracting(aliases).isEmpty,
                "SIFT_SETTINGS_AT names sections the form does not have: \(listed.subtracting(ids).subtracting(aliases).sorted())")
        // An alias has to land somewhere, and the somewhere has to exist.
        #expect(view.contains("at == \"history\" ? \"access\""),
                "the history alias no longer points at a section that exists")
    }

    /// A stored path is drawn the way the header draws one, with exactly the
    /// slashes a path has.
    ///
    /// Two cases and they take different branches. Under the home directory
    /// the walk starts at `Home` and the join is ordinary. Outside it the walk
    /// starts at the root, whose name is already `/`, and joining every
    /// segment with a slash wrote `//tmp/…`. The build was green and the row
    /// said `//tmp`; the photograph is what said so (D-311).
    @Test func aStoredPathIsDrawnWithTheSlashesItHas() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let under = SettingsWindow.shown(home.appendingPathComponent("Pictures/Shoot"))
        #expect(under == "Home/Pictures/Shoot")
        #expect(!under.contains("/Users/"), "an absolute path reached the screen")

        let outside = SettingsWindow.shown(URL(fileURLWithPath: "/tmp/card"))
        #expect(outside == "/tmp/card")
        #expect(!outside.contains("//"), "the root segment doubled its own slash")
    }

    /// And CONTRIBUTING's row for the variable names the same six.
    ///
    /// SECURITY.md sends anybody auditing the launch surface to that table, and
    /// the row spells the section names out. A list five long against a form
    /// six long reads exactly like a complete one.
    @Test func theContributingRowNamesEverySection() throws {
        let row = try Repo.text("CONTRIBUTING.md")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix("| `SIFT_SETTINGS_AT`") }
        let text = try #require(row.map(String.init), "CONTRIBUTING has no SIFT_SETTINGS_AT row")
        for section in SettingsWindow.sections {
            #expect(text.contains("`\(section)`"),
                    "CONTRIBUTING's SIFT_SETTINGS_AT row does not name \(section)")
        }
    }
}

/// A toolbar icon that ships hidden, and the rule that catches what it takes
/// with it (D-347).
@Suite struct ToolbarDefaultTests {
    /// Which commands the toolbar ships without an icon for.
    private static func hidden() throws -> [String] {
        let lines = try Repo.text("Sift/Views/GalleryToolbar.swift")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        for (i, raw) in lines.enumerated()
        where raw.trimmingCharacters(in: .whitespaces) == ".defaultCustomization(.hidden)" {
            // Back to the `command:` of the item this modifier is on.
            for j in stride(from: i, through: max(0, i - 8), by: -1) {
                guard let at = lines[j].range(of: "command: .") else { continue }
                let name = lines[j][at.upperBound...].prefix { $0.isLetter }
                out.append(String(name))
                break
            }
        }
        return out
    }

    /// Taking an icon off the bar is a decision about the bar. It is not a
    /// decision to make the command keyboard-only, and that is what it does
    /// unless something else on the thing it acts on offers it. `copyToFolder`
    /// had a key and a toolbar icon and nothing else; hiding the icon left
    /// `⇧C` as the whole of it, and a capability reachable only by a keystroke
    /// is undiscoverable, which means it is missing.
    @Test func anIconTakenOffTheBarIsStillOnThePhotoItActsOn() throws {
        let menu = try Repo.text("Sift/Views/PhotoActions.swift")
        let hidden = try Self.hidden()
        #expect(!hidden.isEmpty, "no toolbar item ships hidden; this test has nothing to hold")
        for command in hidden {
            #expect(menu.contains("router.perform(.\(command)"), """
                `\(command)` has no icon on the toolbar by default and no line in the \
                photo's context menu, so the only way to it is its key.
                """)
        }
    }

    /// And the two that ship hidden are the two that were decided on, so a
    /// third one arriving is a decision rather than a diff nobody read.
    @Test func onlyMoveAndCopyShipOffTheBar() throws {
        #expect(Set(try Self.hidden()) == ["moveToFolder", "copyToFolder"], """
            The set of actions the toolbar ships without has changed. Every icon \
            is customizable already; shipping one hidden is the stronger claim that \
            most sittings do not want it, and it belongs in the PRD first.
            """)
    }
}

/// Every reusable button in the app says it is a button before it is pressed
/// (D-357).
@Suite struct PointerStyleTests {
    /// The four a control is built from, plus the footer that wraps the
    /// platform's own. A fifth arriving without one is the question this asks.
    @Test func everyButtonPrimitiveChangesThePointer() throws {
        let primitives = [
            ("Sift/Views/PhotoActions.swift", ["GlyphButton", "WordButton", "BoxedButton"]),
            ("Sift/Views/SheetFooter.swift", ["SheetFooter"]),
        ]
        for (file, names) in primitives {
            let text = try Repo.text(file)
            for name in names {
                guard let start = text.range(of: "struct \(name)") else {
                    Issue.record("\(name) is gone from \(file)")
                    continue
                }
                // To the next type declaration, or the end of the file.
                let rest = text[start.upperBound...]
                let end = rest.range(of: "\nstruct ")?.lowerBound ?? rest.endIndex
                #expect(rest[..<end].contains("pointerStyle"), """
                    `\(name)` does not change the pointer, so a reader crosses it \
                    without being told it can be pressed.
                    """)
            }
        }
    }
}
