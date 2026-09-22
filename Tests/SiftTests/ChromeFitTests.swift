import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Sift

/// The header gets narrower by putting things in a menu, never by hiding them
/// (D-113).
/// The gallery's chrome is the platform's toolbar (D-208), so the rules the
/// seven-rung ladder used to carry are checked against the toolbar and the
/// band under it instead.
///
/// The `»` menu is the system's now, and an `NSToolbar` will not say what it
/// put in its overflow. That is the trade this suite records: the tests that
/// asked "is it in the menu when the row gives it up" are gone, and the
/// guarantee behind them moved to `everyCommandTheToolbarStartsIsAlsoInTheMenuBar`
/// in `ReachTests`, which is the stronger check — a toolbar item can be
/// customized away entirely, and a menu item cannot.
@Suite @MainActor struct GalleryChromeTests {
    init() { Preferences.useTestDefaults() }

    private func folderWithPhotos() throws -> (CommandRouter, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-header-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 1...3 { try Data([0]).write(to: root.appendingPathComponent("p\(i).jpg")) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root)
        router.store.cursor = 0
        return (router, root)
    }

    private func source(_ path: String) throws -> String { try Repo.text(path) }

    @Test func narrowingToFavoritesAddsNoChip() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store

        let before = HeaderChips.specs(store: store, router: router).map(\.id)
        router.perform(.filterFavorites)
        #expect(store.filter == .favorite)
        let after = HeaderChips.specs(store: store, router: router).map(\.id)

        #expect(after == before, "the heart is the readout; the chip was the same fact twice")
        #expect(!after.contains("filter"))
    }

    /// The other filter states have no control of their own, so they keep it.
    @Test func everyOtherFilterStateStillGetsItsChip() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        for state in [PhotoFilter.keep, .reject, .unflagged, .colored(.red)] {
            router.store.filter = state
            let ids = HeaderChips.specs(store: router.store, router: router).map(\.id)
            #expect(ids.contains("filter"), "\(state.label) has no readout at all")
        }
    }

    /// The rule this replaces was `aRunningFilterIsStillAnnouncedWhenTheChipsAreGone`,
    /// and it is stronger now rather than weaker. The chips used to be the
    /// third rung the ladder gave up, so a filtered folder at 740pt looked like
    /// a folder with nine photographs in it and the overflow had to say
    /// otherwise. The chips are not chrome any more: they are a band under the
    /// toolbar that no width takes away (D-208).
    @Test func aRunningFilterIsAnnouncedAtEveryWidth() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        router.store.searchText = "frame"
        defer { router.store.searchText = "" }
        // The readout moved rather than went: the name filter is its own slot
        // at the trailing end of the band now, under the magnifier that opens
        // it, so it is no longer one of `specs` (D-220). What this test is for
        // is unchanged, which is why it is asking the same question of the new
        // place rather than being loosened to pass.
        #expect(HeaderChips.nameFilter(router.store) != nil,
                "a filter is running and nothing on screen says so")
        // And the band draws whenever there is a chip, which is the part no
        // ladder can now take away.
        let band = try source("Sift/Views/GalleryBand.swift")
        #expect(band.contains("HeaderChips()"), "the band stopped carrying the chips")
        #expect(band.contains("NameFilter()"), "the band stopped carrying the name filter")
    }

    /// The filter's way in that is not `/` (D-42, D-143).
    @Test func theFilterIsReachableWithoutTheSlashKey() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        #expect(toolbar.contains("router.perform(.search)"),
                "nothing in the toolbar starts the filename filter")
    }

    /// The appearance moved off the chrome (D-134). Two ways in, both away
    /// from the row over the photographs: Settings and the View menu.
    @Test func theAppearanceIsInSettingsAndNotInTheToolbar() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        for gone in ["Glyph.Sun()", "Glyph.Moon()", "AppModel.shared.appearance"] {
            #expect(!toolbar.contains(gone), "\(gone) is back in the row over the photographs")
        }
        for choice in Appearance.allCases {
            AppModel.shared.appearance = choice
            #expect(AppModel.shared.appearance == choice)
        }
        AppModel.shared.appearance = .system
    }

    /// No order is reachable only from the menu bar (D-115). The toolbar's
    /// sort pull-down is built from `SortOrder.allCases`, so the check that
    /// matters is that it still is, rather than a hand-written list that a
    /// seventh order would quietly miss.
    @Test func everyOrderTheFolderCanTakeHasAControlOnScreen() throws {
        let toolbar = try source("Sift/Views/GalleryToolbar.swift")
        #expect(toolbar.contains("ForEach(SortOrder.allCases"),
                "the sort menu stopped being built from every order there is")
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        for order in SortOrder.allCases {
            router.store.sort = order
            #expect(router.store.sort == order, "\(order.label) cannot be set")
        }
        router.store.sort = .name
    }

    /// One fact each: the subfolder flag for the band's status, the selection
    /// for the toolbar's target. They were both the selection until D-202, and
    /// the split survives the move into two different parts of the window.
    @Test func theStatusAndTheTargetSayDifferentThings() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        router.store.includeSubfolders = true
        router.store.selected = [router.store.photos[0].url]
        defer { router.store.clearSelection(); router.store.includeSubfolders = false }

        let status = GalleryBand.status(of: router.store)
        let target = try #require(router.store.targetLabel)
        #expect(status.contains("subfolders"))
        #expect(!status.contains("selected"), "the count is in two places again")
        #expect(target.contains("selected"))
    }

    /// D-195. The chip row is written out as slots rather than a `ForEach`.
    /// Slots need a ceiling, and a chip past the last one would fall off the
    /// end of the row in silence. This is the counter.
    @Test func theChipRowHasASlotForEveryChip() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store
        defer { store.filter = .all; store.sort = .name; store.searchText = "" }
        store.searchText = "p"
        store.filter = .keep
        store.sort = .size
        store.insert(PhotoRef(url: root.appendingPathComponent("rejected.jpg"),
                              fileSize: 1, created: .now, modified: .now, flag: .reject))
        let specs = HeaderChips.specs(store: store, router: router)
        #expect(specs.count == HeaderChips.maxChips,
                "every chip should be showing: \(specs.map(\.id))")
        #expect(specs.count <= HeaderChips.maxChips,
                "a chip past the last slot is a chip nobody sees")
    }

    /// The way into the second pass is a control that says what it does. It
    /// had read "6 rejected", which is a status: it opened the review on a
    /// click and nothing on screen said so, and a reader on their first cull
    /// has no reason to guess a shortcut (D-376).
    @Test func theRejectsChipSaysWhatPressingItDoes() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store
        defer { store.filter = .all; store.sort = .name; store.searchText = "" }
        store.insert(PhotoRef(url: root.appendingPathComponent("rejected.jpg"),
                              fileSize: 1, created: .now, modified: .now, flag: .reject))
        let spec = HeaderChips.specs(store: store, router: router).first { $0.id == "rejects" }
        let chip = try #require(spec, "a folder with a reject should offer the review")
        #expect(chip.text.hasPrefix("Review "), "the chip reads as a status: \(chip.text)")
        #expect(chip.text.contains("\(store.folderCounts.reject)"),
                "the count left the label, which is where the second readout starts: \(chip.text)")
        #expect(chip.act != nil, "the label has to be the control")
    }

    /// D-219 put a flexible space between the navigation cluster and the
    /// actions. It went back only when there was none at all, so a rebuild
    /// that left the space somewhere else was a row nothing looked at again:
    /// the actions sat in the middle of the bar until the next selection
    /// change happened to fix them, which is why it only went wrong sometimes
    /// (D-381).
    @Test func theSpaceGoesBeforeWhicheverActionComesFirst() {
        let selected = ["sidebar", "history", "path", "target", "rotateCCW", "trash", "sort"]
        #expect(ToolbarConfigurator.spaceBelongs(in: selected) == 3, "before the selection's name")

        let none = ["sidebar", "history", "path", "rotateCCW", "trash", "sort"]
        #expect(ToolbarConfigurator.spaceBelongs(in: none) == 3, "before the first action when there is no name")

        #expect(ToolbarConfigurator.spaceBelongs(in: ["sidebar", "history", "path"]) == nil,
                "a row with nothing to push wants no space")
    }

    /// The index is the one to insert at once the old spaces are gone, so a
    /// space already in the row must not shift the answer. It did: the anchor
    /// was found in the list *with* the space in it, so correcting a misplaced
    /// space put the new one a slot further along every time.
    @Test func aSpaceAlreadyInTheRowDoesNotMoveTheAnswer() {
        let misplaced = ["sidebar", "history", "path", "target", "rotateCCW",
                         NSToolbarItem.Identifier.flexibleSpace.rawValue, "trash", "sort"]
        #expect(ToolbarConfigurator.spaceBelongs(in: misplaced) == 3)

        let leading = [NSToolbarItem.Identifier.flexibleSpace.rawValue,
                       "sidebar", "history", "path", "rotateCCW", "trash"]
        #expect(ToolbarConfigurator.spaceBelongs(in: leading) == 3)
    }

    /// The plan applied, which is the outcome `pushActionsRight` produces.
    /// `NSToolbar` builds no items off a window, so the row is a list of
    /// identifiers and the walk here is the one the real caller makes.
    private func applying(_ ids: [String]) -> [String] {
        guard let plan = ToolbarConfigurator.spacePlan(for: ids) else { return ids }
        var row = ids
        for i in plan.remove { row.remove(at: i) }
        row.insert(NSToolbarItem.Identifier.flexibleSpace.rawValue, at: plan.insert)
        return row
    }

    /// Every row ends the same way, whatever it started as: one space, sitting
    /// immediately before the first thing that acts on a photograph.
    @Test func everyRowEndsWithOneSpaceInFrontOfTheActions() {
        let space = NSToolbarItem.Identifier.flexibleSpace.rawValue
        let want = ["sidebar", "history", "path", space, "target", "rotateCCW", "trash"]

        // Already right, and it has to be left alone rather than rebuilt.
        #expect(ToolbarConfigurator.spacePlan(for: want) == nil)
        #expect(applying(want) == want)

        // Moved, which is the row D-381 was reported on.
        #expect(applying(["sidebar", "history", "path", "target", space, "rotateCCW", "trash"]) == want)
        // Dropped, which is the only row the old code repaired.
        #expect(applying(["sidebar", "history", "path", "target", "rotateCCW", "trash"]) == want)
        // Two of them: one in the right slot and one adrift. A check that
        // stopped at the first space would call this row finished.
        #expect(applying(["sidebar", "history", "path", space, "target", space, "rotateCCW", "trash"]) == want)
        // Three, to prove the removals run back to front. Front to back, the
        // second index would point past the item it named.
        #expect(applying([space, "sidebar", space, "history", "path", space,
                          "target", "rotateCCW", "trash"]) == want)

        // Nothing to push, so nothing is inserted and the row is untouched.
        let bare = ["sidebar", "history", "path"]
        #expect(ToolbarConfigurator.spacePlan(for: bare) == nil)
        #expect(applying(bare) == bare)
    }

    /// The sort menu in the toolbar checks the field the grid is on, so the
    /// band saying it again was one fact in two places (D-373). A sort away
    /// from the default, on its own, draws no chip and no band.
    @Test func aSortOffTheDefaultPutsNothingInTheBand() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store
        defer { store.sort = .name; store.sortDirection = .natural }
        store.sort = .dateTaken
        store.sortDirection = .reversed
        let specs = HeaderChips.specs(store: store, router: router)
        #expect(specs.isEmpty, "the sort put a chip in the band: \(specs.map(\.id))")
        // Not `isEmpty`: the suites share one scratch preference domain and
        // another setting can be off its default here. The rule is that the
        // sort is not in the sentence.
        let status = GalleryBand.status(of: store)
        #expect(!status.lowercased().contains("date"),
                "the sort came back as a status line instead: \(status)")
    }

    /// Absence is a state (D-65). A folder in its default order with no filter
    /// draws no band at all, rather than an empty strip of padding.
    @Test func aFolderWithNothingToSayDrawsNoBand() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        // The defaults are set here rather than assumed. The suites share one
        // scratch preference domain, so a stray `.dateTaken` or an
        // auto-advance somebody else switched off is a band this test did not
        // ask for (tech debt 25) — and `autoAdvance` is the one that bit:
        // it ships on, and the band says so only when it is off.
        let previousSort = router.store.sort
        let previousAdvance = router.store.autoAdvance
        defer { router.store.sort = previousSort; router.store.autoAdvance = previousAdvance }
        router.store.sort = .name
        router.store.filter = .all
        router.store.autoAdvance = true
        router.store.includeSubfolders = false
        #expect(HeaderChips.specs(store: router.store, router: router).isEmpty)
        #expect(GalleryBand.status(of: router.store).isEmpty,
                "a folder with nothing to say: \(GalleryBand.status(of: router.store))")
    }
}


/// The preview bar narrows the way the header does: by putting bands into a
/// menu, never by letting them run off the edge of the window (D-158).
@Suite @MainActor struct PreviewBarLadderTests {
    init() { Preferences.useTestDefaults() }

    private func photo() -> PhotoRef {
        PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now)
    }

    @Test func theLadderOnlyEverGivesUpMore() {
        for (a, b) in zip(BarPiece.ladder, BarPiece.ladder.dropFirst()) {
            #expect(a.isSubset(of: b), "\(b) brings something back that \(a) had put away")
            #expect(a != b, "two rungs are the same arrangement")
        }
    }

    @Test func theWidestRungGivesUpNothingAndTheNarrowestGivesUpEverything() {
        #expect(BarPiece.ladder.first == [])
        #expect(BarPiece.ladder.last == BarPiece.all)
    }

    @Test func everyPieceIsGivenUpSomewhereOnTheLadder() {
        #expect(BarPiece.ladder.reduce(into: Set<BarPiece>()) { $0.formUnion($1) } == BarPiece.all)
    }

    /// The promise of a ladder: nothing a row gave up is unreachable. With
    /// every feature on, every rung that puts a band away has to offer it.
    @Test func everythingPutAwayComesBackInTheMenu() {
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        let ref = photo()
        store.insert(ref)
        store.cursor = 0
        let all = FeatureSet.everything
        for rung in BarPiece.ladder where !rung.isEmpty {
            let rows = PreviewBar.rows(putAway: rung, ref: ref, store: store,
                                       router: router, features: all)
            #expect(!rows.isEmpty, "\(rung) put things away and offered nothing")
        }
    }

    /// Every band, named. A rung that hides the rotations and offers no way to
    /// rotate is the defect the ladder exists to prevent.
    @Test func theNarrowestRungCarriesEveryCommandTheRowDropped() {
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        let ref = photo()
        store.insert(ref)
        store.cursor = 0
        let all = FeatureSet.everything
        let titles = PreviewBar.rows(putAway: BarPiece.all, ref: ref, store: store,
                                     router: router, features: all).map(\.title)
        // Adjust joined the editing band in D-161. A band that grows and does
        // not grow here is a control the narrowest window drops silently.
        //
        // Highlights and Mark A left the bar in D-166 — the first for the
        // adjust panel, the second pending a rethink — so they are not in its
        // menu either: the menu is what the row put away, not a second list of
        // everything.
        for expected in ["Info", "Focus", "Survey", "Tournament",
                         "Slideshow", "Crop", "Adjust", "Rotate Counterclockwise", "Rotate Clockwise"] {
            #expect(titles.contains(expected), "\(expected) is not in the menu")
        }
    }

    /// Off means gone, in the menu as well as in the row (D-123). A feature
    /// switched off must not come back as a menu item the moment the window
    /// narrows.
    @Test func aSwitchedOffFeatureIsNotInTheMenuEither() {
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        let ref = photo()
        store.insert(ref)
        store.cursor = 0
        // Nothing on but the bands that have no feature behind them.
        let none = FeatureSet(off: Set(Feature.allCases))
        let titles = PreviewBar.rows(putAway: BarPiece.all, ref: ref, store: store,
                                     router: router, features: none).map(\.title)
        for gone in ["Highlights", "Focus", "Survey", "Tournament", "Slideshow", "Crop", "Mark A"] {
            #expect(!titles.contains(gone), "\(gone) is off and still in the menu")
        }
        #expect(titles.contains("Info"), "info has no feature switch and stays")
    }

    /// The two ends of the bar are on no rung: keep and reject lead it and the
    /// bin closes it, and a bar that gave those up would be a bar with nothing
    /// in it.
    @Test func theCullMarksAreOnNoRung() {
        let store = LibraryStore()
        let router = CommandRouter(store: store)
        let ref = photo()
        store.insert(ref)
        store.cursor = 0
        let all = FeatureSet.everything
        let titles = PreviewBar.rows(putAway: BarPiece.all, ref: ref, store: store,
                                     router: router, features: all).map(\.title)
        for kept in ["Flag keep", "Flag reject", "Move to Trash"] {
            #expect(!titles.contains(kept), "\(kept) left the row, and it never may")
        }
    }
}

/// Tab walks the preview bar and Return presses what it lands on (D-157). The
/// walk goes through the key map rather than through AppKit's focus ring,
/// because the key monitor takes Return before a focused control could see it.
@Suite @MainActor struct PreviewBarWalkTests {
    init() { Preferences.useTestDefaults() }

    private func ready() -> (LibraryStore, CommandRouter, PhotoRef) {
        let store = LibraryStore()
        let ref = PhotoRef(url: URL(fileURLWithPath: "/x/a.jpg"), fileSize: 1, created: .now, modified: .now)
        store.insert(ref)
        store.cursor = 0
        store.focus = .preview
        return (store, CommandRouter(store: store), ref)
    }

    @Test func tabIsBoundInThePreviewAndNowhereElse() {
        let map = KeyMap.standard
        #expect(map.command(for: .tab, focus: .preview) == .barNext)
        #expect(map.command(for: .tab(shift: true), focus: .preview) == .barPrevious)
        #expect(map.command(for: .tab, focus: .gallery) == nil,
                "the gallery's Tab is not the bar's to take")
    }

    @Test func theFirstTabLandsOnTheFirstControl() {
        let (store, router, ref) = ready()
        #expect(store.barCursor == nil, "nothing is ringed until somebody asks")
        router.perform(.barNext)
        let walk = PreviewBar.controls(putAway: store.barRung, ref: ref, store: store,
                                       features: AppModel.shared.features).map(\.command)
        #expect(store.barCursor == walk.first)
    }

    @Test func shiftTabFromNowhereLandsOnTheLast() {
        let (store, router, ref) = ready()
        router.perform(.barPrevious)
        let walk = PreviewBar.controls(putAway: store.barRung, ref: ref, store: store,
                                       features: AppModel.shared.features).map(\.command)
        #expect(store.barCursor == walk.last, "and the last control is the bin, at the far end")
    }

    /// A short row with a dead end at each side is a row where Tab stops
    /// working and nobody can tell why.
    @Test func theWalkWrapsAtBothEnds() {
        let (store, router, ref) = ready()
        let walk = PreviewBar.controls(putAway: store.barRung, ref: ref, store: store,
                                       features: AppModel.shared.features).map(\.command)
        store.barCursor = walk.last
        router.perform(.barNext)
        #expect(store.barCursor == walk.first)
        router.perform(.barPrevious)
        #expect(store.barCursor == walk.last)
    }

    @Test func returnPressesTheControlTheRingIsOn() {
        let (store, router, _) = ready()
        store.barCursor = .toggleInfo
        #expect(!store.showInfo)
        router.perform(.confirm)
        #expect(store.showInfo, "Return ran the control rather than closing the window")
        #expect(store.barCursor == nil, "and the ring is spent")
    }

    /// Return still means what it meant when the bar is not being walked.
    @Test func returnWithNoRingStillClosesThePreview() {
        let (store, router, _) = ready()
        store.previewOpen = true
        router.perform(.confirm)
        #expect(!store.previewOpen)
    }

    @Test func escapeLeavesTheBarBeforeItLeavesAnythingElse() {
        let (store, router, _) = ready()
        store.previewOpen = true
        store.barCursor = .toggleInfo
        router.perform(.cancel)
        #expect(store.barCursor == nil)
        #expect(store.previewOpen, "the ring was the innermost thing on screen")
        router.perform(.cancel)
        #expect(!store.previewOpen)
    }

    /// D-195, the preview bar's half. The row is slots, so a fifteenth control
    /// would be built and never drawn.
    @Test func theBarHasASlotForEveryControl() {
        let (store, _, ref) = ready()
        // Everything that can put a control on the row at once: every feature
        // on, compare's controls switched on (D-270), a face to zoom to, and an
        // anchor to compare against.
        Preferences.compareControlsInBar = true
        defer { Preferences.compareControlsInBar = false }
        let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        store.faces = [Face(id: 0, bounds: box, framed: box, eyesClosed: nil)]
        store.compareAnchor = URL(fileURLWithPath: "/x/b.jpg")
        let widest = PreviewBar.controls(putAway: [], ref: ref, store: store,
                                         features: .everything)
        #expect(widest.count == PreviewBar.maxControls,
                "the widest row is \(widest.count) controls, not \(PreviewBar.maxControls): \(widest.map(\.command))")
    }

    /// Compare's three commands each have a control **when the preference that
    /// draws them is on**, which is the rule about a shortcut never being the
    /// only way in, written down where it can fail.
    ///
    /// It could not fail before. D-166 took `Mark A` off the bar and left `a`
    /// as the only way to start a compare, and 547 tests stayed green through
    /// it, because the rule lived in a house document and in nothing a
    /// compiler or a suite reads. The gap was found by a reader looking at the
    /// bar (D-268).
    ///
    /// The preference is off by default now (D-270), so this test asks the
    /// narrower question the app actually promises: turned on, all three are
    /// there and they say what state they are in.
    @Test func compareIsEnterableWithoutTheKeyboardWhenItsControlsAreOn() {
        let (store, _, ref) = ready()
        Preferences.compareControlsInBar = true
        defer { Preferences.compareControlsInBar = false }

        // Nothing marked: the anchor is the way in, and it is on the row.
        let cold = PreviewBar.controls(putAway: [], ref: ref, store: store, features: .everything)
        #expect(cold.contains { $0.command == .setCompareAnchor },
                "with nothing marked there is no on-screen way to start a compare")

        // Marked elsewhere: the flip and side by side arrive, because now there
        // is a second photograph for either of them to act on.
        store.compareAnchor = URL(fileURLWithPath: "/x/b.jpg")
        let warm = PreviewBar.controls(putAway: [], ref: ref, store: store, features: .everything)
        for command in [Command.setCompareAnchor, .toggleCompare, .compareSideBySide] {
            #expect(warm.contains { $0.command == command },
                    "\(command) is keyboard-only while an anchor is set")
        }

        // And on this photograph the anchor reads as on, so the mark you look
        // at is the thing you press rather than a second control for one fact.
        store.compareAnchor = ref.url
        let here = PreviewBar.controls(putAway: [], ref: ref, store: store, features: .everything)
        #expect(here.first { $0.command == .setCompareAnchor }?.isOn == true,
                "the anchor control does not say that this photo is A")
        #expect(!here.contains { $0.command == .compareSideBySide },
                "side by side offered A against itself")
    }

    /// Off by default, and off means the bar is six controls again (D-270).
    /// This is the deliberate half of the rule: the capability stays, the
    /// chrome goes, and the keys and the View menu carry it.
    @Test func compareDrawsNoControlsUntilTheyAreSwitchedOn() {
        let (store, _, ref) = ready()
        Preferences.compareControlsInBar = false
        store.compareAnchor = URL(fileURLWithPath: "/x/b.jpg")
        let row = PreviewBar.controls(putAway: [], ref: ref, store: store, features: .everything)
        for command in [Command.setCompareAnchor, .toggleCompare, .compareSideBySide] {
            #expect(!row.contains { $0.command == command },
                    "\(command) is drawn with its controls switched off")
        }
        // And the command still exists to be pressed: this hides chrome, it
        // does not take the capability away the way the Feature switch does.
        #expect(KeyMap.standard.command(for: .char("a"), focus: .preview) == .setCompareAnchor,
                "hiding the controls took the key with it")
    }

    /// Switching compare off takes all three with it whatever the preference
    /// says: off means gone, not grayed out (D-123).
    @Test func compareOffLeavesNoneOfItsThreeControls() {
        let (store, _, ref) = ready()
        Preferences.compareControlsInBar = true
        defer { Preferences.compareControlsInBar = false }
        store.compareAnchor = URL(fileURLWithPath: "/x/b.jpg")
        var features = FeatureSet.everything
        features.set(.compare, on: false)
        let row = PreviewBar.controls(putAway: [], ref: ref, store: store, features: features)
        for command in [Command.setCompareAnchor, .toggleCompare, .compareSideBySide] {
            #expect(!row.contains { $0.command == command },
                    "\(command) is still on the bar with compare switched off")
        }
    }

    /// The walk is the row: a control the window is too narrow to draw is not
    /// a control the keyboard can land on.
    @Test func theWalkFollowsTheRungThatDrew() {
        let (store, _, ref) = ready()
        store.barRung = BarPiece.all
        let narrow = PreviewBar.controls(putAway: BarPiece.all, ref: ref, store: store,
                                         features: .everything).map(\.command)
        let wide = PreviewBar.controls(putAway: [], ref: ref, store: store,
                                       features: .everything).map(\.command)
        #expect(narrow.count < wide.count)
        #expect(!narrow.contains(.rotateCW), "a control in the menu is not on the row")
        // Keep and reject led this row until D-166 took them out of the bar,
        // so the narrowest rung is now the bin alone. Rewritten rather than
        // loosened: the rule it encodes — a rung keeps what the window is for
        // and the menu carries the rest — is the one that changed.
        #expect(narrow == [.trash],
                "what the narrowest row keeps is the bin")
    }

    /// Every control the keyboard can land on has to be a command the key map
    /// knows, or Return would ring something that does nothing.
    @Test func everyControlInTheWalkIsABoundCommand() {
        let (store, _, ref) = ready()
        for rung in BarPiece.ladder {
            for control in PreviewBar.controls(putAway: rung, ref: ref, store: store, features: .everything) {
                #expect(!KeyMap.standard.keys(for: control.command).isEmpty,
                        "\(control.command) is in the bar and unbound")
            }
        }
    }
}

/// The header is one row of controls, not two families sharing a line (D-160).
@Suite struct HeaderIconTests {
    /// This pair used to check that a bigger icon was drawn in a heavier line,
    /// and that the two scales came out at the same ratio. Both rules are
    /// gone, on purpose: the icons are SF Symbols, the weight comes off the
    /// text axis at the point size the step names, and there is no stroke
    /// token left for a call site to get wrong (D-198).
    ///
    /// What replaces them is the thing that can actually break. A symbol is a
    /// name, a name is a string, and a string that no longer resolves draws
    /// nothing at all — a missing icon is invisible to every other test in
    /// this suite. So every mark in the set is asked for at each of the three
    /// steps, in both states, and has to come back as an image with ink in it.
    @Test func everyMarkResolvesToARealSymbolAtEverySize() throws {
        var checked = 0
        for name in Glyph.everySymbol {
            for size in Tokens.Layout.glyphSteps {
                let image = try #require(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                                         "\(name) is not a symbol on this system")
                let sized = try #require(image.withSymbolConfiguration(
                    .init(pointSize: size, weight: .regular)), "\(name) will not draw at \(size)")
                #expect(sized.size.width > 0 && sized.size.height > 0,
                        "\(name) draws nothing at \(size)")
                checked += 1
            }
        }
        #expect(checked == Glyph.everySymbol.count * 3, "a step or a mark went missing")
        #expect(Glyph.everySymbol.count >= 24, "the set lost a mark without anyone noticing")
    }

    /// The manifest is hand-kept, which is the one way a mark can dodge the
    /// test above. This counts the declarations in the file against it.
    @Test func themanifestHasEveryMarkTheFileDeclares() throws {
        let source = try Repo.text("Sift/Design/Glyphs.swift")
        let declared = source.split(separator: "\n")
            .filter { $0.contains(": GlyphShape {") }
            .compactMap { $0.split(separator: " ").dropFirst().first.map { String($0.dropLast()) } }
        let inTheList = Set(Glyph.everyMark.map { String(describing: type(of: $0)) })
        for name in declared {
            #expect(inTheList.contains(name), "\(name) is drawn but never checked: add it to everyMark")
        }
        #expect(declared.count == inTheList.count, "the manifest and the file disagree")
    }

    @Test func theCaptionStaysUnderTheOneSizeItIsAllowedToBe() {
        #expect(Tokens.Layout.glyphAction > 0)
        // The word is a label on a drawing, not text to read: every icon it
        // names also carries the word in its tooltip and its accessibility
        // label (DESIGN, text roles).
        #expect(TextRole.caption.font != TextRole.label.font)
    }
}
/// The way back outlives the toast, and it does it in the corner of the
/// gallery rather than in the header (D-48, D-182).
@Suite @MainActor struct UndoAffordanceTests {
    init() { Preferences.useTestDefaults() }

    private func folderWithPhotos() throws -> (CommandRouter, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-undo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 1...3 { try Data([0]).write(to: root.appendingPathComponent("p\(i).jpg")) }
        let router = CommandRouter(store: LibraryStore())
        router.open(root)
        router.store.cursor = 0
        return (router, root)
    }

    /// The header stopped carrying it. A chip that arrived with every file
    /// operation was the widest thing the ladder had to negotiate around, and
    /// it put the undo for a photograph at the opposite corner of the window
    /// from the photograph.
    @Test func thereIsNoUndoChipInTheHeader() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store
        store.pushUndo(UndoableOp(label: "Favorite", inverse: .all([])))

        #expect(store.undo.canUndo)
        #expect(store.undo.topLabel == "Favorite")
        let ids = HeaderChips.specs(store: store, router: router).map(\.id)
        #expect(!ids.contains("undo"), "the undo belongs beside the photographs, not in the header")
    }

    /// A toast that says where the cursor is stops being true when the cursor
    /// moves. "Last photo" used to sit over a photograph in the middle of the
    /// folder for the rest of its four seconds, offering to open the next
    /// folder (D-221).
    @Test func theEndOfFolderToastGoesWhenYouLeaveTheEnd() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        router.store.moveToLast()
        router.perform(.next)
        #expect(router.store.toast?.message.hasPrefix("Last photo") == true)

        router.perform(.previous)
        #expect(router.store.toast == nil, "the toast outlived the thing it was about")
    }

    /// The other kind, and the reason this is a property of the toast rather
    /// than something the cursor does to every toast it finds (D-221).
    ///
    /// Rewritten for D-283: an undoable operation no longer raises a toast at
    /// all — the way back *is* the message — so what used to be checked on the
    /// toast is checked on the pill's own two facts. A decision that steps you
    /// on keeps the way back on screen and names the photograph it is about,
    /// and a move you make yourself takes it away.
    @Test func theWayBackSurvivesTheMoveTheDecisionCausedAndNotTheOneYouMake() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store
        store.autoAdvance = true
        store.cursor = 0
        let first = try #require(store.current?.url)
        store.pushUndo(UndoableOp(label: "Trash", inverse: .all([])))
        #expect(store.undo.topAt == first, "the pill knows which photograph it is about")

        store.advanceIfEnabled()
        #expect(store.undoLeftBehind == false, "the decision moved you, so the way back stays")
        #expect(store.current?.url != first, "and it is now about the photograph behind you")

        store.move(by: 1)
        #expect(store.undoLeftBehind, "a move you make yourself takes it off screen")
    }

    /// The undo names what the operation *did*, not which command ran it
    /// (D-232). Favorite and unfavorite are one command and used to push one
    /// label, so favoriting and then unfavoriting left a button reading "Undo
    /// favorite" over a stack whose top was the unfavorite: pressing it
    /// favorited the photograph, which is the opposite of what it said.
    @Test func undoingAnUnfavoriteSaysUnfavorite() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store

        router.perform(.toggleFavorite)
        #expect(store.current?.favorite == true)
        #expect(store.undo.topLabel == "Favorite")

        router.perform(.toggleFavorite)
        #expect(store.current?.favorite == false)
        #expect(store.undo.topLabel == "Unfavorite",
                "the button offers to undo a favorite and would put one back")
    }

    /// The same defect in the other two toggles. Clearing a flag pushed
    /// "Flag", so the way back out of a clear read as the way back out of a
    /// flag; clearing a color label pushed "Label" for the same reason.
    @Test func undoingAClearedFlagOrLabelSaysClear() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store

        router.perform(.flagKeep)
        #expect(store.undo.topLabel == "Keep")
        router.perform(.flagReject)
        #expect(store.undo.topLabel == "Reject")
        router.perform(.unflag)
        #expect(store.undo.topLabel == "Clear flag")

        store.cursor = 0
        router.perform(.labelRed)
        #expect(store.undo.topLabel == "Label")
        store.cursor = 0
        router.perform(.labelRed)
        #expect(store.undo.topLabel == "Clear label", "pressing a color a photo wears clears it")
    }

    /// There is one place an undo is offered now, so the two can no longer
    /// disagree about what it undoes: an undoable operation raises no message
    /// at all and the pill in the corner is the whole report (D-283).
    @Test func anUndoableOperationRaisesNoMessageOfItsOwn() throws {
        let (router, root) = try folderWithPhotos()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = router.store
        store.pushUndo(UndoableOp(label: "Move", inverse: .all([])))
        store.showToast("Moved 1 photo", undoable: true)

        #expect(store.toast == nil, "the way back is the message; a second one is a second control")
        #expect(store.undo.topLabel == "Move")

        // What cannot be taken back still reports, in the same pill without the
        // icon, because nothing else on screen would say it happened.
        store.showToast("Picture copied", undoable: false)
        #expect(store.toast?.message == "Picture copied")
    }
}

/// Every key chip in Settings is one width, and that width is the key column
/// plus the padding the chip puts around it (D-315).
///
/// The chips sit in a right-aligned stack, so a chip that outgrows the rest
/// hangs off the left of the stack, and one line out of a run of forty reads
/// as a mistake rather than as a long key. It happened because the box was
/// measured against `layout.keyColumn`, which is the *text* column the help
/// overlay draws bare: "Return  Space" is 112.5 of that 120 and the chip's two
/// 8pt paddings took it past.
///
/// Measured rather than counted, because these strings are arrows and
/// modifier glyphs as much as letters and none of them is one character wide.
/// `NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)` is what
/// `Tokens.Font.data` resolves to on this platform; if that pairing ever
/// breaks, this test measures the wrong thing and the chips are what show it.
@Suite struct KeyCapFitTests {
    private let mono = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let ui = NSFont.systemFont(ofSize: 14)

    private func width(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    @Test func theChipIsTheKeyColumnPlusItsOwnPadding() {
        #expect(Tokens.Layout.keyCapWidth == Tokens.Layout.keyColumn + Tokens.Space.s8 * 2, """
            the chip's width is the column it draws plus the padding it adds. \
            Change one of the three and this says which (D-315).
            """)
    }

    @Test func noCommandsKeysOutgrowTheChipTheyAreDrawnIn() {
        let map = KeyMap.standard
        let room = Tokens.Layout.keyCapWidth - Tokens.Space.s8 * 2
        for command in Command.allCases {
            let keys = map.keys(for: command).map(\.display).joined(separator: "  ")
            guard !keys.isEmpty else { continue }
            #expect(width(keys, mono) <= room, """
                "\(keys)" for \(command.label) is \(String(format: "%.1f", width(keys, mono)))pt \
                wide, over the \(room)pt inside a key chip. Every other chip is \
                `layout.keyCapWidth`, so this one hangs off the left of the stack. Widen the \
                token, or give the command fewer keys (D-315).
                """)
        }
    }

    /// The chip says this while it waits for a key, in `quiet` rather than
    /// `data`, so it is the one string in that column set in the proportional
    /// face. A chip that resized as it started listening would move the row
    /// under the pointer that just clicked it.
    @Test func theWaitingChipIsNoWiderThanTheRest() {
        let room = Tokens.Layout.keyCapWidth - Tokens.Space.s8 * 2
        #expect(width("Press a key", ui) <= room)
    }
}
