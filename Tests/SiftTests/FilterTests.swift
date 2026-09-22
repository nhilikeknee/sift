import Testing
import Foundation
@testable import Sift

@Suite struct FilterTests {
    init() { Preferences.useTestDefaults() }

    private func p(_ name: String, flag: Flag? = nil, favorite: Bool = false) -> PhotoRef {
        PhotoRef(url: URL(fileURLWithPath: "/x/\(name)"), fileSize: 0, created: .now, modified: .now, flag: flag, favorite: favorite)
    }

    @Test func filters() {
        let keep = p("a", flag: .keep, favorite: true), rej = p("b", flag: .reject), plain = p("c")
        #expect(PhotoFilter.keep.includes(keep) && !PhotoFilter.keep.includes(rej))
        #expect(PhotoFilter.unflagged.includes(plain) && !PhotoFilter.unflagged.includes(keep))
        // The favorite cuts across the flags rather than ranking within them.
        #expect(PhotoFilter.favorite.includes(keep) && !PhotoFilter.favorite.includes(plain))
    }

    @Test func dateTakenSortFallsBackToCreated() {
        let old = Date(timeIntervalSince1970: 0), new = Date()
        var a = p("a"); a.dateTaken = new
        let b = PhotoRef(url: URL(fileURLWithPath: "/x/b"), fileSize: 0, created: old, modified: old)
        #expect(SortOrder.dateTaken.sort([a, b]).map(\.name) == ["b", "a"])
    }
}

/// Batch C: pins, and the folder grouping the recursive view is built on.
@Suite @MainActor struct RecursiveGroupingTests {
    init() { Preferences.useTestDefaults() }

    private func card() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sift-rec-" + UUID().uuidString)
        for (sub, names) in [("Day 1", ["b.jpg", "a.jpg"]), ("Day 2", ["c.jpg"])] {
            let dir = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for n in names { try Data([0]).write(to: dir.appendingPathComponent(n)) }
        }
        return root
    }

    @Test func recursivePhotosGroupByFolderAndSortInsideIt() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        // Said out loud rather than inherited: the sort is a preference, and a
        // test that reads one another test can write is a test that fails on
        // Tuesdays.
        store.sort = .name
        store.includeSubfolders = true
        store.open(root)

        #expect(store.photos.map(\.name) == ["a.jpg", "b.jpg", "c.jpg"])
        let sections = store.sections
        #expect(sections.map(\.title) == ["Day 1", "Day 2"])
        #expect(sections.map(\.count) == [2, 1])
        #expect(sections.map(\.start) == [0, 2])
    }

    @Test func oneFolderNeedsNoHeaders() throws {
        let root = try card()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        store.includeSubfolders = false
        store.open(root.appendingPathComponent("Day 1"))

        #expect(store.sections.isEmpty, "a single folder is not a stack of folders")
    }
}

@Suite @MainActor struct PinTests {
    init() { Preferences.useTestDefaults() }

    @Test func pinningIsAToggleAndSurvivesInPreferences() {
        let folder = URL(fileURLWithPath: "/tmp/sift-pin-\(UUID().uuidString)")
        let router = CommandRouter(store: LibraryStore())

        router.togglePin(folder)
        #expect(Preferences.isPinned(folder))
        #expect(router.store.pinned.contains(folder))
        #expect(router.store.toast?.message == "Pinned \(folder.lastPathComponent)")

        router.togglePin(folder)
        #expect(!Preferences.isPinned(folder))
        #expect(!router.store.pinned.contains(folder))
    }
}

/// The folder narrowed to what was loved, and the control that does it (D-176).
@Suite @MainActor struct FavoritesFilterTests {
    init() { Preferences.useTestDefaults() }

    private func store() -> LibraryStore { LibraryStore() }

    @Test func theCommandNarrowsAndTheSamePressWidensAgain() {
        let s = store()
        let router = CommandRouter(store: s)
        #expect(s.filter == .all)

        router.perform(.filterFavorites)
        #expect(s.filter == .favorite)

        router.perform(.filterFavorites)
        #expect(s.filter == .all, "the same press reverses it, so there is nothing to confirm")
    }

    /// "Only the favorites" is the whole of what it says, so it replaces
    /// whatever the filter was rather than adding a second condition.
    @Test func itReplacesAFilterThatWasAlreadyOnSomethingElse() {
        let s = store()
        let router = CommandRouter(store: s)
        s.filter = .reject

        router.perform(.filterFavorites)
        #expect(s.filter == .favorite)

        router.perform(.filterFavorites)
        #expect(s.filter == .all, "back to everything, not back to rejects")
    }

    /// The shifted partner of the favorite's own key, the way ⇧X reviews what
    /// x rejected.
    @Test func itIsOnTheShiftedFavoriteKey() {
        let map = KeyMap.standard
        #expect(map.command(for: .char(">"), focus: .gallery) == .filterFavorites)
        #expect(map.command(for: .char("."), focus: .gallery) == .toggleFavorite)
        #expect(map.command(for: .char(">"), focus: .preview) == .filterFavorites,
                "both windows, the way the flags are")
    }

    /// The header's heart says whether there is anything to narrow to, and it
    /// counts the whole folder rather than what a filter has left showing.
    @Test func theFolderCountIncludesFavoritesAcrossEveryFlag() {
        let s = store()
        func add(_ name: String, _ flag: Flag?, _ favorite: Bool) {
            s.insert(PhotoRef(url: URL(fileURLWithPath: "/x/\(name)"), fileSize: 0,
                              created: .now, modified: .now, flag: flag, favorite: favorite))
        }
        add("a", .keep, true)
        add("b", .reject, true)
        add("c", nil, false)
        #expect(s.folderCounts.favorite == 2, "a favorite is a favorite whatever it is flagged")
        #expect(s.folderCounts.unflagged == 1)
    }
}

/// Which way round a sort runs (D-349).
@Suite struct SortDirectionTests {
    private func ref(_ name: String, size: Int = 0, sharpness: Double? = nil) -> PhotoRef {
        var r = PhotoRef(url: URL(fileURLWithPath: "/x/\(name)"), fileSize: size,
                         created: .now, modified: .now)
        r.sharpness = sharpness
        return r
    }

    /// `natural` is whatever the field did before there was a choice, so
    /// nothing moved in anybody's window when the direction arrived.
    @Test func naturalIsWhatEveryOrderAlreadyDid() {
        let photos = [ref("c", size: 3), ref("a", size: 1), ref("b", size: 2)]
        for order in SortOrder.allCases {
            #expect(order.sort(photos, .natural).map(\.name) == order.sort(photos).map(\.name),
                    "\(order.rawValue) moved when the default direction was named")
        }
    }

    /// Flipping is the inverse, so flipping twice is where it started. The
    /// sort itself is not an inverse and was written as one here first: it
    /// orders the whole array from scratch every time, so asking it twice for
    /// `reversed` is reversed twice, not back.
    @Test func flippingTwiceIsWhereItStarted() {
        for direction in SortDirection.allCases {
            #expect(direction.flipped.flipped == direction)
            #expect(direction.flipped != direction)
        }
    }

    /// And one direction really is the other read backwards, for every field
    /// that has no rule about missing values.
    @Test func reversedIsTheNaturalOrderBackwards() {
        let photos = [ref("a", size: 3), ref("b", size: 1), ref("c", size: 2), ref("d", size: 4)]
        for order in SortOrder.allCases where order != .sharpness {
            let natural = order.sort(photos, .natural).map(\.name)
            #expect(order.sort(photos, .reversed).map(\.name) == natural.reversed(),
                    "\(order.rawValue) reversed is not its natural order backwards")
        }
    }

    /// An unknown is not a winner, and reversing does not make it one. Softest
    /// first is a claim about frames somebody measured; a frame nobody has
    /// measured stays at the end of both answers.
    @Test func anUnmeasuredFrameStaysLastWhicheverWayRound() {
        let photos = [ref("sharp", sharpness: 0.9), ref("unknown"), ref("soft", sharpness: 0.1)]
        #expect(SortOrder.sharpness.sort(photos, .natural).map(\.name) == ["sharp", "soft", "unknown"])
        #expect(SortOrder.sharpness.sort(photos, .reversed).map(\.name) == ["soft", "sharp", "unknown"])
    }

    /// The menu says what the direction does to the field it is under, not
    /// "ascending". Every pair is two different sentences, which is the check
    /// that one of them was not left as a copy of the other.
    @Test func everyFieldNamesItsOwnTwoEnds() {
        for order in SortOrder.allCases {
            let natural = order.label(.natural)
            let reversed = order.label(.reversed)
            #expect(natural != reversed, "\(order.rawValue) says \"\(natural)\" both ways")
            #expect(!natural.isEmpty && !reversed.isEmpty)
            for word in ["Ascending", "Descending", "ascending", "descending"] {
                #expect(!natural.contains(word) && !reversed.contains(word),
                        "\(order.rawValue) falls back on \"\(word)\" instead of naming its ends")
            }
        }
    }
}
