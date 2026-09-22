import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// The ten UX repairs of 2026-09-14, at the level a test can hold: which window
/// a sheet belongs to, what Esc backs out of first, what focus mode borrows and
/// gives back, and what the reject review is a review of.
@Suite @MainActor struct SecondPassTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int) -> LibraryStore {
        let s = LibraryStore()
        s.sort = .name
        s.includeSubfolders = false
        for i in 0..<count {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    // MARK: the command palette

    @Test func thePaletteOpensInTheWindowThatAskedForIt() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.focus = .preview
        r.perform(.commandPalette)
        #expect(s.palette == .preview, "the gallery must not present the preview's sheet")

        s.palette = nil
        s.focus = .gallery
        r.perform(.commandPalette)
        #expect(s.palette == .gallery)
    }

    /// Every command is findable by its own words. The one exception is the
    /// palette: a row that opens the thing you are already looking at.
    @Test func everyCommandButThePaletteIsSearchable() {
        for c in Command.allCases where c != .commandPalette {
            #expect(FuzzyMatch.score(c.label, in: c.label) != nil, "\(c) cannot find itself")
        }
    }

    // MARK: side by side

    @Test func sideBySideMarksANeighborWhenNothingIsMarked() {
        let s = store(count: 4)
        let r = CommandRouter(store: s)
        s.cursor = 2
        r.perform(.compareSideBySide)
        #expect(s.sideBySide)
        #expect(s.compareAnchor == s.photos[1].url, "the photo before it is the one you meant")
    }

    /// At the top of the folder there is nothing before the cursor, so the
    /// photo after it stands in rather than the command doing nothing.
    @Test func atTheFirstPhotoItReachesForward() {
        let s = store(count: 4)
        let r = CommandRouter(store: s)
        s.cursor = 0
        r.perform(.compareSideBySide)
        #expect(s.compareAnchor == s.photos[1].url)
    }

    @Test func aFolderOfOneCannotCompare() {
        let s = store(count: 1)
        let r = CommandRouter(store: s)
        r.perform(.compareSideBySide)
        #expect(!s.sideBySide)
        #expect(s.toast != nil, "it says why rather than doing nothing")
    }

    /// The flip and the pair are two answers to one question, so one is always off.
    @Test func theFlipAndThePairAreExclusive() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.cursor = 1
        r.perform(.setCompareAnchor)          // A is photo 1
        s.cursor = 2
        r.perform(.toggleCompare)
        #expect(s.showingCompare)
        r.perform(.compareSideBySide)
        #expect(s.sideBySide)
        #expect(!s.showingCompare)
    }

    // MARK: focus mode

    /// Rewritten at D-150, where focus mode stopped being a `Bool` two windows
    /// read and became the name of the window that asked for it. The rule this
    /// half holds is unchanged: the preview borrows its panels and gives them
    /// back. What is new is that it has to be the preview asking.
    @Test func focusModeBorrowsThePanelsAndGivesThemBack() {
        let s = store(count: 2)
        let r = CommandRouter(store: s)
        s.focus = .preview
        s.showInfo = true
        s.showFilmstrip = true
        r.perform(.toggleFocusMode)
        #expect(s.isBare(.preview))
        #expect(!s.showInfo && !s.showFilmstrip)
        r.perform(.toggleFocusMode)
        #expect(s.bareWindow == nil)
        #expect(s.showInfo && s.showFilmstrip, "what was on before is on again")
    }

    /// The gallery's own bare mode (D-150). `⇧F` there used to open the
    /// preview and strip that instead, which left the window carrying the most
    /// chrome as the one command for taking chrome away could not be used on.
    @Test func focusModeInTheGalleryStripsTheGalleryAndOpensNothing() {
        let s = store(count: 2)
        let r = CommandRouter(store: s)
        s.focus = .gallery
        s.showSidebar = true
        s.showFilmstrip = true
        r.perform(.toggleFocusMode)
        #expect(s.isBare(.gallery))
        #expect(!s.previewOpen, "the window you are in is the one that goes bare")
        #expect(!s.showSidebar)
        #expect(s.showFilmstrip, "the preview's furniture is not the gallery's to put away")
        r.perform(.toggleFocusMode)
        #expect(s.bareWindow == nil)
        #expect(s.showSidebar)
    }

    /// The reason the fact is a window and not a boolean: one store stands
    /// behind both scenes, so a `Bool` set in either presented in both.
    @Test func oneWindowGoingBareLeavesTheOtherAlone() {
        let s = store(count: 2)
        s.enterFocusMode(in: .gallery)
        #expect(s.isBare(.gallery))
        #expect(!s.isBare(.preview), "the preview is not stripped by the gallery being")
    }

    /// Esc unwinds the modes in the order they were entered, and only then
    /// starts closing windows.
    @Test func escapeBacksOutInnermostFirst() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.focus = .preview
        s.previewOpen = true
        s.cursor = 1
        r.perform(.toggleFocusMode)
        r.perform(.compareSideBySide)
        #expect(s.sideBySide && s.isBare(.preview))

        r.perform(.cancel)
        #expect(!s.sideBySide && s.isBare(.preview) && s.previewOpen)
        r.perform(.cancel)
        #expect(s.bareWindow == nil && s.previewOpen)
        r.perform(.cancel)
        #expect(!s.previewOpen)
    }

    // MARK: the preview bar answering the keyboard

    /// Rewritten on 2026-09-17. It used to say *any* command, and moving to
    /// another photo is now the exception: walking a folder is the app's main
    /// gesture, and a bar that came back on every arrow press was up for the
    /// whole of the one thing somebody opened the window to do (D-199). Every
    /// other command still brings it, which is the half D-64 is about.
    @Test func aPreviewCommandPulsesTheBarUnlessItIsJustMoving() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.focus = .gallery
        r.perform(.toggleFavorite)
        #expect(s.barPulse == 0, "the gallery has no bar to bring up")
        s.focus = .preview
        r.perform(.next)
        r.perform(.previous)
        #expect(s.barPulse == 0, "arrowing through the folder brings the bar back")
        r.perform(.toggleFavorite)
        r.perform(.rotateCW)
        #expect(s.barPulse == 2, "a command the bar would show the result of does not bring it")
    }

    /// The set and the enum agree: a command that moves the cursor and is not
    /// in the list would pulse the bar without anybody deciding it should.
    @Test func theNavigationSetIsTheCommandsThatOnlyMove() {
        for command in Command.navigation {
            #expect(Command.allCases.contains(command), "\(command) is not a command")
        }
        #expect(!Command.navigation.contains(.enterSingle), "opening the preview is not a move")
        #expect(!Command.navigation.contains(.barNext), "walking the bar is not a move")
    }

    // MARK: the reject review

    /// A filter left on from earlier must not hide half of what is about to be
    /// trashed, so the review reads the folder rather than what is on screen.
    @Test func theReviewIsOfTheFolderNotTheFilteredView() {
        let s = store(count: 4)
        for i in [0, 2] { s.update(s.photos[i].url) { $0.flag = .reject } }
        s.filter = .keep
        #expect(s.photos.isEmpty, "the filter hides them all")
        #expect(s.rejected.count == 2)
    }

    @Test func reviewingNothingSaysSoRatherThanOpeningAnEmptySheet() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        r.perform(.reviewRejects)
        #expect(!s.reviewingRejects)
        #expect(s.toast != nil)
    }

    @Test func aRejectOpensTheReview() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.update(s.photos[1].url) { $0.flag = .reject }
        r.perform(.reviewRejects)
        #expect(s.reviewingRejects)
    }

    /// Esc closes the review. The sheet's own button says "(Esc)" and the
    /// sheet asks for the key with `onExitCommand`, but the one key monitor
    /// takes Esc first, so the ladder is what keeps the promise (D-253).
    @Test func escapeClosesTheRejectReview() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.update(s.photos[1].url) { $0.flag = .reject }
        r.perform(.reviewRejects)
        #expect(s.reviewingRejects)

        r.perform(.cancel)
        #expect(!s.reviewingRejects)
    }

    /// And it closes the sheet before it closes anything under it. `⇧X` is
    /// bound in both windows, so the review can be raised from the preview;
    /// one Esc there must not take the window and leave the sheet.
    @Test func escapeClosesTheReviewBeforeTheWindowUnderIt() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.update(s.photos[1].url) { $0.flag = .reject }
        s.selected = [s.photos[0].url]
        s.focus = .preview
        s.previewOpen = true
        r.perform(.reviewRejects)

        r.perform(.cancel)
        #expect(!s.reviewingRejects)
        #expect(s.previewOpen, "the sheet was on top, so it is what Esc took")
        #expect(s.selected.count == 1, "and nothing else was cleared on the way")
    }

    /// The review closes when the batch runs, and the scope it borrowed to run
    /// it does not outlive the call: a stale scope aims the next keystroke at
    /// photos nobody is looking at.
    @Test func trashingTheRejectsClosesTheReviewAndDropsTheScope() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.update(s.photos[1].url) { $0.flag = .reject }
        s.reviewingRejects = true
        r.trashRejects()
        #expect(!s.reviewingRejects)
        #expect(s.actionScope == nil)
    }

    // MARK: hints

    @Test func aHintIsShownOnceEver() {
        Preferences.forgetHints(["test.once"])
        let s = store(count: 2)
        s.hintOnce("test.once", "First time")
        #expect(s.hint?.text == "First time")
        s.hint = nil
        s.hintOnce("test.once", "First time")
        #expect(s.hint == nil, "a hint that comes back twice is a notification")
        Preferences.forgetHints(["test.once"])
    }

    /// The rule this test used to hold has been reversed on purpose (D-206):
    /// selecting a second photograph explained the action bar above it, which
    /// is the one thing a first-run message must not do.
    @Test func aMultiSelectionSaysNothing() {
        let s = store(count: 4)
        s.selected = [s.photos[0].url]
        s.selected = [s.photos[0].url, s.photos[1].url]
        #expect(s.hint == nil, "the action bar names the target; a toast repeating it is a wall (D-206)")
    }
}

/// Batch 1 of the twenty-four taken from the other cullers: judging whether a
/// frame is sharp, and where a reject goes.
@Suite @MainActor struct JudgingTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int) -> LibraryStore {
        let s = LibraryStore()
        s.sort = .name
        s.includeSubfolders = false
        for i in 0..<count {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        return s
    }

    /// The headline of the batch: Photo Mechanic and FastRawViewer both hold
    /// the magnification across the arrow keys, and it is how a burst gets
    /// judged.
    @Test func arrowingThroughABurstHoldsTheMagnification() {
        let s = store(count: 5)
        let r = CommandRouter(store: s)
        s.oneToOneScale = 4
        r.perform(.zoomToggle)
        #expect(s.zoom == 4 && s.zoomIsActual)
        r.perform(.next)
        r.perform(.next)
        #expect(s.zoom == 4, "three frames in and still at 100%")
        #expect(s.zoomIsActual)
    }

    @Test func escapeIsWhatEndsTheZoom() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.previewOpen = true
        s.focus = .preview
        r.perform(.zoomToggle)
        #expect(s.zoom != nil)
        r.perform(.cancel)
        #expect(s.zoom == nil)
        #expect(s.previewOpen, "the zoom went before the window did")
    }

    @Test func zoomingOutAllTheWayIsAReset() {
        let s = store(count: 2)
        let r = CommandRouter(store: s)
        s.oneToOneScale = 1.2
        r.perform(.zoomToggle)
        r.perform(.zoomOut)          // 1.2 / 1.25 is under fit, so it lands at fit
        #expect(s.zoom == nil)
        #expect(!s.zoomIsActual)
    }

    /// Pinching to a number is not the same intent as asking for actual pixels,
    /// so it does not follow the next photo's dimensions.
    @Test func aPinchedZoomIsANumberNotAnIntent() {
        let s = store(count: 2)
        let r = CommandRouter(store: s)
        r.perform(.zoomIn)
        #expect(!s.zoomIsActual)
    }

    @Test func focusPeakingOpensThePreviewToShowIt() {
        let s = store(count: 2)
        let r = CommandRouter(store: s)
        r.perform(.toggleFocusPeaking)
        #expect(s.showFocusPeaking)
        #expect(s.previewOpen, "a mask over the photo needs the window with the photo in it")
    }

    @Test func movingRejectsAsideNeedsSomewhereToPutThem() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        s.reviewingRejects = true
        r.moveRejectsAside()
        #expect(!s.reviewingRejects, "no folder open, so nothing to do but close")
        #expect(s.actionScope == nil)
    }

    /// The sort answers one question, so it runs the other way from every other
    /// sort in the app, and an unmeasured frame is not the winner.
    @Test func sharpestFirstPutsTheUnmeasuredLast() {
        var a = PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now)
        var b = PhotoRef(url: URL(fileURLWithPath: "/x/b.jpg"), fileSize: 1, created: .now, modified: .now)
        let c = PhotoRef(url: URL(fileURLWithPath: "/x/c.jpg"), fileSize: 1, created: .now, modified: .now)
        a.sharpness = 12
        b.sharpness = 40
        let sorted = SortOrder.sharpness.sort([a, b, c])
        #expect(sorted.map(\.name) == ["b.jpg", "a.jpg", "c.jpg"])
    }
}

/// Batch 2: comparing. Survey, tournament, burst stacks and scene headings.
@Suite @MainActor struct ComparingTests {
    init() { Preferences.useTestDefaults() }

    private func store(count: Int, apart: TimeInterval = 3600) -> LibraryStore {
        let s = LibraryStore()
        s.includeSubfolders = false
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<count {
            var ref = PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i,
                               created: base.addingTimeInterval(Double(i) * apart), modified: .now)
            ref.dateTaken = base.addingTimeInterval(Double(i) * apart)
            s.insert(ref)
        }
        s.sort = .dateTaken
        s.cursor = 0
        return s
    }

    // MARK: survey

    @Test func theSurveyIsTheSelectionWhenThereIsOne() {
        let s = store(count: 10)
        s.selected = Set(s.photos.prefix(3).map(\.url))
        #expect(s.surveyRefs.count == 3)
    }

    /// With nothing selected it is the run the cursor is in, so pressing the
    /// key is never a question about what it will show.
    @Test func withNoSelectionTheSurveyIsTheRunAroundTheCursor() {
        let s = store(count: 20)
        s.cursor = 10
        let refs = s.surveyRefs
        #expect(refs.count == LibraryStore.surveyMax)
        #expect(refs.contains { $0.url == s.photos[10].url })
    }

    @Test func aShortFolderSurveysWhatThereIs() {
        let s = store(count: 3)
        #expect(s.surveyRefs.count == 3)
    }

    // MARK: tournament

    @Test func aTournamentHoldsTheChampionAndMovesOn() {
        let s = store(count: 4)
        let r = CommandRouter(store: s)
        s.cursor = 0
        r.perform(.tournament)
        #expect(s.tournament && s.sideBySide)
        #expect(s.champion == s.photos[0].url)
        #expect(s.cursor == 1, "the cursor is the challenger, not the champion")

        r.perform(.flagKeep)
        #expect(s.champion == s.photos[1].url, "keep promotes rather than flagging")
        #expect(s.cursor == 2)
    }

    /// Ending it writes the decision down. A comparison nobody recorded is a
    /// comparison you have to do again.
    @Test func endingATournamentKeepsTheSurvivor() {
        let s = store(count: 3)
        let r = CommandRouter(store: s)
        r.perform(.tournament)
        let champion = s.champion
        r.perform(.cancel)
        #expect(!s.tournament && !s.sideBySide)
        #expect(s.champion == nil)
        #expect(champion != nil)
    }

    @Test func onephotoIsNotATournament() {
        let s = store(count: 1)
        let r = CommandRouter(store: s)
        r.perform(.tournament)
        #expect(!s.tournament)
        #expect(s.toast != nil)
    }

    // MARK: stacks and scenes

    @Test func aBurstCollapsesToOneCellWithACount() {
        let s = store(count: 6, apart: 0.5)
        #expect(s.photos.count == 6)
        s.stackBursts = true
        #expect(s.photos.count == 1, "half a second apart is one burst")
        #expect(s.stackCounts[s.photos[0].url] == 6)
    }

    @Test func openingAStackShowsItsFrames() {
        let s = store(count: 4, apart: 0.5)
        s.stackBursts = true
        let leader = s.photos[0].url
        s.toggleStack(leader)
        #expect(s.photos.count == 4)
        s.toggleStack(leader)
        #expect(s.photos.count == 1)
    }

    @Test func framesFarApartAreNotABurst() {
        let s = store(count: 4, apart: 30)
        s.stackBursts = true
        #expect(s.photos.count == 4)
        #expect(s.stackCounts.isEmpty)
    }

    @Test func theGridBreaksWhereTheShootPauses() {
        let s = LibraryStore()
        s.includeSubfolders = false
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Two runs, ten minutes apart.
        for (i, offset) in [0.0, 1.0, 2.0, 600.0, 601.0].enumerated() {
            var ref = PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i,
                               created: base.addingTimeInterval(offset), modified: .now)
            ref.dateTaken = base.addingTimeInterval(offset)
            s.insert(ref)
        }
        s.sort = .dateTaken
        s.groupByScene = true
        let sections = s.sections
        #expect(sections.count == 2)
        #expect(sections.map(\.count) == [3, 2])
        #expect(sections.allSatisfy { $0.folder == nil }, "a scene is a time, not a place")
    }

    @Test func oneSceneNeedsNoHeading() {
        let s = store(count: 4, apart: 1)
        s.groupByScene = true
        #expect(s.sections.isEmpty)
    }
}

/// Batch 3: moving photos. Copy, hand-off, ingest, slideshow.
@Suite @MainActor struct MovingTests {
    init() { Preferences.useTestDefaults() }

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-copy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The whole point of copy over move: the original is still where it was.
    @Test func copyLeavesTheOriginalWhereItIs() throws {
        let src = try folder(), dest = try folder()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dest) }
        let file = src.appendingPathComponent("a.jpg")
        try Data([0]).write(to: file)

        let (written, _) = try FileOps.copy(file, into: dest)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: written.path))
        #expect(written.lastPathComponent == "a.jpg")
    }

    /// A second copy of the same name does not overwrite the first.
    @Test func copyingTwiceMakesTwoFiles() throws {
        let src = try folder(), dest = try folder()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dest) }
        let file = src.appendingPathComponent("a.jpg")
        try Data([0]).write(to: file)

        let (first, _) = try FileOps.copy(file, into: dest)
        let (second, _) = try FileOps.copy(file, into: dest)
        #expect(first.lastPathComponent == "a.jpg")
        #expect(second.lastPathComponent == "a 2.jpg")
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    /// Undoing a copy trashes what it wrote rather than deleting it outright:
    /// undo is not allowed to be the one operation that destroys something.
    @Test func undoingACopyTrashesTheCopy() async throws {
        let src = try folder(), dest = try folder()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dest) }
        let file = src.appendingPathComponent("a.jpg")
        try Data([0]).write(to: file)

        let (written, undo) = try FileOps.copy(file, into: dest)
        try await undo.undo()
        #expect(!FileManager.default.fileExists(atPath: written.path))
        #expect(FileManager.default.fileExists(atPath: file.path), "the original is untouched either way")
    }

    @Test func aCardOffersToCopyRatherThanToOpen() {
        let offer = FolderOffer(label: "Copy the photos off", folder: URL(fileURLWithPath: "/Volumes/CARD/DCIM"), ingests: true)
        #expect(offer.ingests, "culling off a card is culling over a bus you can unplug")
    }

    @Test func theSlideshowIsAModeYouCanLeave() {
        let s = LibraryStore()
        s.includeSubfolders = false
        for i in 0..<3 {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        let r = CommandRouter(store: s)
        r.perform(.slideshow)
        #expect(s.slideshow && s.previewOpen)
        r.perform(.slideshow)
        #expect(!s.slideshow)
    }
}

/// Batch 4: not losing work. The undo stack across folders, and the sidecar.
@Suite @MainActor struct KeepingTests {
    init() { Preferences.useTestDefaults() }

    /// Lightroom's own numbers, so the translation is readable by the thing it
    /// is being translated for.
    @Test func theSidecarSpeaksLightroomsRatings() {
        #expect(XMPSidecar.rating(flag: .reject, favorite: false) == -1)
        #expect(XMPSidecar.rating(flag: .keep, favorite: false) == 1)
        #expect(XMPSidecar.rating(flag: .keep, favorite: true) == 5, "a favorite is the top of the scale")
        #expect(XMPSidecar.rating(flag: nil, favorite: false) == nil, "nothing to declare")
    }

    @Test func aSidecarSitsBesideThePhotoWhereAdobeLooks() {
        let photo = URL(fileURLWithPath: "/x/DSC_0001.jpg")
        #expect(XMPSidecar.url(for: photo).lastPathComponent == "DSC_0001.xmp")
    }

    @Test func writingThenClearingRemovesTheSidecar() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-xmp-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("a.jpg")
        try Data([0]).write(to: photo)

        try XMPSidecar.write(flag: .keep, favorite: true, for: photo)
        let read = XMPSidecar.read(for: photo)
        #expect(read?.rating == 5)

        // Nothing left to say, so the file goes: a stale sidecar claiming a
        // rating the photo no longer has is worse than none.
        try XMPSidecar.write(flag: nil, favorite: false, for: photo)
        #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: photo).path))
    }

    /// The point of D-93: walking into the next shoot no longer throws away the
    /// way back out of the last thing you did.
    @Test func theUndoStackSurvivesAFolderChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-undo-" + UUID().uuidString)
        let a = root.appendingPathComponent("Day 1"), b = root.appendingPathComponent("Day 2")
        for dir in [a, b] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0]).write(to: dir.appendingPathComponent("p.jpg"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        store.sort = .name
        store.includeSubfolders = false
        store.open(a)
        store.pushUndo(UndoableOp(label: "Flag", inverse: .all([])))
        #expect(store.undo.canUndo)
        #expect(store.undoElsewhere == nil, "it happened here")

        store.open(b)
        #expect(store.undo.canUndo, "the way back outlives the folder")
        #expect(store.undoElsewhere?.lastPathComponent == "Day 1", "and it says where")
    }

    /// Walking to the next shoot with the review up closes it. The sheet is a
    /// review of one folder's rejects, and it cannot outlive the folder: what
    /// is left on screen for a frame reads "0 rejected photos" over photographs
    /// it is not about (D-253).
    @Test func theRejectReviewDoesNotOutliveItsFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-review-" + UUID().uuidString)
        let a = root.appendingPathComponent("Day 1"), b = root.appendingPathComponent("Day 2")
        for dir in [a, b] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0]).write(to: dir.appendingPathComponent("p.jpg"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        store.sort = .name
        store.includeSubfolders = false
        store.open(a)
        store.update(store.photos[0].url) { $0.flag = .reject }
        store.reviewingRejects = true

        store.open(b)
        #expect(!store.reviewingRejects)
    }
}

/// Batch 5: the conventions Sift broke. Space, color labels, Caps Lock, and
/// searching for something other than a filename.
@Suite @MainActor struct ConventionTests {
    init() { Preferences.useTestDefaults() }

    private let map = KeyMap.standard

    /// Space is Quick Look on this platform and zoom-to-100% in Lightroom. It
    /// is not "next photo" anywhere but in the app this replaced.
    @Test func spaceIsQuickLookInTheGalleryAndTheZoomInThePreview() {
        #expect(map.command(for: .space, focus: .gallery) == .enterSingle)
        #expect(map.command(for: .space, focus: .preview) == .zoomToggle)
        #expect(map.command(for: .right, focus: .gallery) == .next, "the arrows still do what they did")
    }

    @Test func theFiveLabelsAreOnLightroomsFiveKeys() {
        #expect(map.command(for: .char("1"), focus: .gallery) == .labelRed)
        #expect(map.command(for: .char("5"), focus: .gallery) == .labelPurple)
        #expect(map.command(for: .char("0"), focus: .gallery) == .clearLabel)
    }

    /// A color is stored as the Finder tag of the same name, so Finder colors
    /// it too and nothing else in the app has to know.
    @Test func aLabelIsAFinderTag() {
        #expect(MetadataIO.label(fromTags: ["Blue", "Keep"]) == .blue)
        #expect(MetadataIO.label(fromTags: ["Keep"]) == nil)
    }

    @Test func theFilterKnowsTheColors() {
        var ref = PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now)
        ref.label = .green
        #expect(PhotoFilter.colored(.green).includes(ref))
        #expect(!PhotoFilter.colored(.red).includes(ref))
        #expect(PhotoFilter.all.includes(ref))
    }

    /// Caps Lock overrides the toggle rather than replacing it, so the key you
    /// can see on your own keyboard wins.
    @Test func capsLockAdvancesEvenWithTheToggleOff() {
        let s = LibraryStore()
        s.includeSubfolders = false
        for i in 0..<3 {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(i).jpg"), fileSize: i, created: .now, modified: .now))
        }
        s.cursor = 0
        s.autoAdvance = false

        LibraryStore.capsLockIsDown = { false }
        s.advanceIfEnabled()
        #expect(s.cursor == 0, "off, and the toggle is off, so it holds")

        LibraryStore.capsLockIsDown = { true }
        s.advanceIfEnabled()
        #expect(s.cursor == 1)
        LibraryStore.capsLockIsDown = { false }
    }

    // MARK: the query

    @Test func bareWordsAreStillTheFilename() {
        let q = PhotoQuery("beach sunset")
        #expect(q.isNameOnly)
        #expect(q.words == ["beach", "sunset"])
    }

    @Test func aKeyMatchesOneField() {
        let q = PhotoQuery("camera:X-T5 iso:6400")
        #expect(!q.isNameOnly)
        #expect(q.camera == "X-T5")
        #expect(q.isoRange == 6400...6400)
    }

    @Test func isoTakesARange() {
        #expect(PhotoQuery("iso:800-6400").isoRange == 800...6400)
        #expect(PhotoQuery("iso:nonsense").isoRange == nil)
    }

    @Test func everyConditionHasToHold() {
        var ref = PhotoRef(url: URL(fileURLWithPath: "/x/beach.jpg"), fileSize: 1, created: .now, modified: .now)
        ref.camera = "FUJIFILM X-T5"
        ref.iso = 3200
        #expect(PhotoQuery("beach camera:x-t5").matches(ref))
        #expect(!PhotoQuery("beach camera:nikon").matches(ref), "one miss is a miss")
        #expect(PhotoQuery("iso:1600-6400").matches(ref))
        #expect(!PhotoQuery("iso:100-400").matches(ref))
    }

    /// A photo whose EXIF has not been read yet cannot match a camera query,
    /// rather than matching everything.
    @Test func anUnreadPhotoMatchesNoCameraQuery() {
        let ref = PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now)
        #expect(!PhotoQuery("camera:anything").matches(ref))
    }

    @Test func dateIsAPrefixSoAMonthWorks() {
        var ref = PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now)
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 14; parts.hour = 10; parts.minute = 0
        ref.dateTaken = Calendar.current.date(from: parts)
        #expect(PhotoQuery("date:2026-09").matches(ref))
        #expect(PhotoQuery("date:2026-09-14").matches(ref))
        #expect(!PhotoQuery("date:2025").matches(ref))
    }
}

/// Batch 6: the automatic pass. Everything here is advisory, and none of it is
/// ever written to a file.
@Suite @MainActor struct AutomaticTests {
    init() { Preferences.useTestDefaults() }

    private func store(faces: Int) -> LibraryStore {
        let s = LibraryStore()
        s.includeSubfolders = false
        s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now))
        s.cursor = 0
        s.faces = (0..<faces).map {
            Face(id: $0,
                 bounds: CGRect(x: 0.1 * Double($0), y: 0.2, width: 0.1, height: 0.1),
                 framed: CGRect(x: 0.1 * Double($0), y: 0.18, width: 0.15, height: 0.15),
                 eyesClosed: $0 == 1 ? true : false)
        }
        return s
    }

    /// Around the faces one at a time, then back to the whole frame. A cycle
    /// with no way out is a key you stop pressing.
    @Test func zoomToFaceGoesRoundAndThenBackToFit() {
        let s = store(faces: 2)
        s.zoomToNextFace()
        #expect(s.focusRequest == s.faces[0].framed)
        s.focusRequest = nil
        s.zoomToNextFace()
        #expect(s.focusRequest == s.faces[1].framed)
        s.focusRequest = nil
        s.zoomToNextFace()
        #expect(s.focusRequest == nil, "past the last face it goes back to the whole photo")
        #expect(s.faceCursor == 0)
    }

    /// Rewritten at D-151. It used to pass on a store whose faces had never
    /// been looked for, which was the whole defect: detection only ever ran
    /// from the info panel, so "No faces in this one" was what `⇧Z` said about
    /// a photograph full of them. The command runs a pass of its own now, so
    /// the answer is the same sentence and it has been earned.
    @Test func aPhotoWithNoFacesSaysSoRatherThanDoingNothing() async {
        let s = store(faces: 0)
        let r = CommandRouter(store: s)
        r.perform(.zoomToFace)
        // It says it is looking before it knows, because Vision on a full
        // frame is not instant and a key that goes quiet has failed.
        #expect(s.toast?.message == "Looking for faces")
        for _ in 0..<200 where s.toast?.message == "Looking for faces" {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(s.toast?.message == "No faces in this one")
        #expect(s.focusRequest == nil)
    }

    /// The faces a pass found are kept, so pressing the key again walks them
    /// rather than starting Vision over (D-151).
    @Test func asecondPressWalksTheFacesRatherThanLookingAgain() {
        let s = store(faces: 2)
        let r = CommandRouter(store: s)
        r.perform(.zoomToFace)
        #expect(s.focusRequest == s.faces[0].framed, "faces on hand are used, not re-found")
        #expect(s.toast == nil, "and nothing is said, because there is nothing to wait for")
    }

    /// The faces belong to the photo on screen, so moving off it drops them
    /// rather than leaving the last photo's faces under this one.
    @Test func movingOnForgetsTheFaces() {
        let s = store(faces: 2)
        s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/b.jpg"), fileSize: 2, created: .now, modified: .now))
        s.cursor = 0
        s.faces = store(faces: 2).faces
        s.move(by: 1)
        #expect(s.faces.isEmpty)
        #expect(s.faceCursor == 0)
    }

    /// Nothing Vision says reaches the file. The flag, the favorite and the
    /// label are the only things Sift writes about a photo.
    @Test func nothingAutomaticIsWrittenDown() {
        let s = store(faces: 2)
        #expect(s.faces.contains { $0.eyesClosed == true })
        #expect(s.photos[0].flag == nil)
        #expect(!s.photos[0].favorite)
        #expect(s.photos[0].label == nil)
    }
}

/// Tech debt 30: the dates, camera-facts and sharpness sweeps folded into one
/// pass (D-101).
@Suite @MainActor struct FolderFactsTests {
    init() { Preferences.useTestDefaults() }

    private func folder(count: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-facts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<count {
            let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: Double(i) / Double(count), green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            let url = dir.appendingPathComponent("f\(i).jpg")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
        return dir
    }

    /// Setting a store's sort writes it to the shared preference, and the
    /// suites run in parallel (tech debt 25). Putting it straight back leaves
    /// this store sorted and no other store inheriting it: a stray `.sharpness`
    /// sets every concurrent test decoding its whole folder.
    private func ask(_ store: LibraryStore, toSortBy sort: Sift.SortOrder) {
        let was = Preferences.sort
        store.sort = sort
        Preferences.sort = was
    }

    /// Polls rather than sleeping a fixed time: the pass hops off the main
    /// actor and back, and how many hops that is depends on the machine.
    private func settle(_ store: LibraryStore, until done: () -> Bool) async {
        for _ in 0..<400 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func oneHeaderReadAnswersBothQuestionsAboutIt() async throws {
        let dir = try folder(count: 3); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore()
        store.includeSubfolders = false
        store.open(dir)
        ask(store, toSortBy: .dateTaken)
        await settle(store) { store.factsLoaded.contains(.dates) }

        #expect(store.factsLoaded.contains(.camera),
                "the sort asked for dates, and the same header call answered camera:")
        #expect(store.allPhotos.allSatisfy { $0.camera != nil },
                "read and empty, not unread: the sentinel is what stops a second pass")

        store.searchText = "camera:nikon"
        #expect(store.factsRunning.isEmpty, "nothing left to read, so no second sweep")
    }

    @Test func aSecondQuestionMidReadWaitsRatherThanOpeningItsOwnBanner() async throws {
        let dir = try folder(count: 6); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore()
        store.includeSubfolders = false
        // Before the open, not after: the default sort is capture date and
        // reads the headers as the folder lands (D-378), so the first pass
        // here would be the dates rather than the sharpness this is about.
        ask(store, toSortBy: .name)
        store.open(dir)
        ask(store, toSortBy: .sharpness)
        #expect(store.factsRunning == .sharpness)

        store.searchText = "iso:100-800"
        #expect(store.factsRunning == .sharpness, "the header read does not start a banner beside this one")

        await settle(store) { store.factsLoaded.contains(.camera) }
        #expect(store.factsLoaded.contains(.sharpness))
        #expect(store.factsLoaded.contains(.camera), "it went on its own once the first pass was done")
        #expect(store.progress == nil, "and the banner came down after the last of them")
    }

    @Test func aFolderChangeStartsOverRatherThanCarryingTheLastOneForward() async throws {
        let a = try folder(count: 2); defer { try? FileManager.default.removeItem(at: a) }
        let b = try folder(count: 2); defer { try? FileManager.default.removeItem(at: b) }
        let store = LibraryStore()
        store.includeSubfolders = false
        store.open(a)
        ask(store, toSortBy: .dateTaken)
        await settle(store) { store.factsLoaded.contains(.dates) }

        store.open(b)
        #expect(store.factsLoaded.isEmpty, "what the last folder knew says nothing about this one")
        await settle(store) { store.factsLoaded.contains(.dates) }
        #expect(store.allPhotos.allSatisfy { $0.camera != nil })
    }

    @Test func theBannerNamesWhatWasAskedFor() {
        #expect(LibraryStore.factsLabel(.dates) == "Reading dates")
        #expect(LibraryStore.factsLabel(.sharpness) == "Measuring sharpness")
        #expect(LibraryStore.factsLabel(.camera) == "Reading camera details")
        #expect(LibraryStore.factsLabel([.dates, .camera]) == "Reading camera details")
        #expect(LibraryStore.factsLabel([.dates, .sharpness]) == "Reading the folder",
                "two unrelated jobs have no honest short name")
    }
}

/// Tech debt 27: the rubber band asks the lattice, not the cells that happen to
/// have been drawn (D-106).
@Suite struct CellLatticeTests {
    /// 100pt thumbnails with a 24pt name under them, 12pt gaps, four columns,
    /// the first cell at (16, 16). The cell stopped being square when the name
    /// moved onto it (D-115), so the two pitches differ: 112 across, 136 down.
    private func lattice(count: Int, from start: Int = 0) -> CellLattice {
        CellLattice(anchor: start, frame: CGRect(x: 16, y: 16, width: 100, height: 124),
                    cellWidth: 100, cellHeight: 124, gap: 12, columns: 4,
                    range: start..<(start + count))!
    }

    @Test func aCellThatWasNeverDrawnStillHasAPlace() {
        let grid = lattice(count: 400)
        // Row 50, column 2: far past anything a scroll view would have built.
        #expect(grid.frame(of: 202) == CGRect(x: 16 + 2 * 112, y: 16 + 50 * 136, width: 100, height: 124))
        #expect(grid.frame(of: 400) == nil, "past the end of the run is not a place")
    }

    @Test func theLatticeIsWorkedBackFromWhicheverCellWasMeasured() {
        // The same grid, anchored on a cell in the middle of the third row.
        let fromFirst = lattice(count: 40)
        let fromMiddle = CellLattice(anchor: 9, frame: CGRect(x: 16 + 112, y: 16 + 2 * 136, width: 100, height: 124),
                                     cellWidth: 100, cellHeight: 124, gap: 12, columns: 4, range: 0..<40)!
        #expect(fromFirst == fromMiddle, "any drawn cell fixes the whole lattice")
    }

    @Test func aBandDraggedPastTheDrawnRowsTakesTheRowsPastThem() {
        let grid = lattice(count: 400)
        // From the first cell down to y = 4000: row 35 and everything above it.
        let taken = grid.indices(in: CGRect(x: 16, y: 16, width: 460, height: 4000))
        // 4000pt of drag over a 136pt pitch reaches row 29 and everything above.
        #expect(taken.count == 4 * 30, "nine rows on screen used to be nine rows selected")
        #expect(taken.last == 119)
    }

    @Test func theSpaceBetweenTwoPhotosIsNeitherOfThem() {
        let grid = lattice(count: 40)
        // The 12pt gutter between column 0 and column 1, and nothing else.
        let gutter = CGRect(x: 16 + 101, y: 16 + 20, width: 10, height: 10)
        #expect(grid.indices(in: gutter).isEmpty)
    }

    @Test func aBandAboveTheGridTakesNothing() {
        let grid = lattice(count: 40)
        #expect(grid.indices(in: CGRect(x: 16, y: -200, width: 400, height: 100)).isEmpty)
    }

    @Test func aSectionStartsItsOwnRowsAtItsOwnIndices() {
        // The second section of a sectioned grid: photos 40 to 59, laid out
        // from its own first row rather than continuing the first section's.
        let grid = lattice(count: 20, from: 40)
        #expect(grid.frame(of: 40)?.origin == CGPoint(x: 16, y: 16))
        #expect(grid.frame(of: 44)?.origin == CGPoint(x: 16, y: 16 + 136))
        #expect(grid.frame(of: 39) == nil, "the section before it is not this section's business")
    }

    @Test func anAnchorOutsideTheRunIsNotALattice() {
        #expect(CellLattice(anchor: 5, frame: .zero, cellWidth: 100, cellHeight: 124,
                            gap: 12, columns: 4, range: 10..<20) == nil)
        #expect(CellLattice(anchor: 0, frame: .zero, cellWidth: 100, cellHeight: 124,
                            gap: 12, columns: 0, range: 0..<20) == nil)
    }
}

/// Tech debt 29: a sidecar somebody else wrote is edited, not replaced (D-107).
@Suite struct SidecarMergeTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sift-xmp-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Shaped like what Lightroom leaves beside a raw file: a develop recipe, a
    /// keyword list, and a rating written as a child element rather than an
    /// attribute. Hand-written rather than harvested — see tech debt.
    private let lightroomish = """
    <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 9.0">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""
        xmlns:xmp="http://ns.adobe.com/xap/1.0/"
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        crs:Exposure2012="+0.35"
        crs:Temperature="5200"
        xmp:CreatorTool="Adobe Lightroom Classic">
       <xmp:Rating>3</xmp:Rating>
       <dc:subject>
        <rdf:Bag>
         <rdf:li>harbour</rdf:li>
         <rdf:li>morning</rdf:li>
        </rdf:Bag>
       </dc:subject>
      </rdf:Description>
     </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end="w"?>
    """

    @Test func anotherToolsWorkSurvivesAFlag() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("DSC_0001.jpg")
        try Data().write(to: photo)
        try Data(lightroomish.utf8).write(to: XMPSidecar.url(for: photo))

        try XMPSidecar.write(flag: .reject, favorite: false, for: photo)
        let after = try String(contentsOf: XMPSidecar.url(for: photo), encoding: .utf8)

        #expect(after.contains("crs:Exposure2012=\"+0.35\""), "a develop recipe is somebody's afternoon")
        #expect(after.contains("<rdf:li>harbour</rdf:li>"))
        #expect(after.contains("crs:Temperature=\"5200\""))
        #expect(XMPSidecar.read(for: photo)?.rating == -1, "and the reject did land")
        #expect(!after.contains(">3<"), "the rating it had is replaced, not added beside")
    }

    @Test func theShapeTheFileArrivedInIsTheShapeItKeeps() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("DSC_0002.jpg")
        try Data().write(to: photo)
        try Data(lightroomish.utf8).write(to: XMPSidecar.url(for: photo))

        try XMPSidecar.write(flag: .keep, favorite: true, for: photo)
        let after = try String(contentsOf: XMPSidecar.url(for: photo), encoding: .utf8)
        #expect(after.contains("<xmp:Rating>5</xmp:Rating>"), "it wrote an element, so it gets an element back")
    }

    @Test func clearingAFlagTakesOutOurFieldAndLeavesTheFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("DSC_0003.jpg")
        try Data().write(to: photo)
        try Data(lightroomish.utf8).write(to: XMPSidecar.url(for: photo))

        try XMPSidecar.write(flag: nil, favorite: false, for: photo)
        let sidecar = XMPSidecar.url(for: photo)
        #expect(FileManager.default.fileExists(atPath: sidecar.path),
                "a sidecar Sift did not write is not Sift's to delete")
        let after = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(!after.contains("xmp:Rating"), "but the rating we put there is gone")
        #expect(after.contains("<rdf:li>morning</rdf:li>"))
    }

    @Test func ourOwnEmptySidecarIsStillRemoved() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("DSC_0004.jpg")
        try Data().write(to: photo)

        try XMPSidecar.write(flag: .keep, favorite: false, for: photo)
        #expect(FileManager.default.fileExists(atPath: XMPSidecar.url(for: photo).path))
        try XMPSidecar.write(flag: nil, favorite: false, for: photo)
        #expect(!FileManager.default.fileExists(atPath: XMPSidecar.url(for: photo).path),
                "no stale sidecar claiming a rating the photo no longer has")
    }

    @Test func aFieldThePacketHasNeverHeardOfIsAddedToIt() {
        let bare = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Some Other Tool">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" dc:format="image/jpeg"/>
         </rdf:RDF>
        </x:xmpmeta>
        """
        let after = XMPSidecar.setting("xmp:Rating", to: "5", in: bare)
        #expect(after.contains("xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\""), "the namespace comes with the field")
        #expect(after.contains("xmp:Rating=\"5\""))
        #expect(after.contains("dc:format=\"image/jpeg\""))
        #expect(after.hasSuffix("</x:xmpmeta>"))
    }

    @Test func aPrefixThatMerelyEndsInOursIsNotOurs() {
        let odd = #"<rdf:Description rdf:about="" myxmp:Rating="9" xmp:Rating="1"/>"#
        let after = XMPSidecar.setting("xmp:Rating", to: "5", in: odd)
        #expect(after.contains(#"myxmp:Rating="9""#), "somebody else's field with a similar name is left alone")
        #expect(after.contains(#"xmp:Rating="5""#))
    }
}
