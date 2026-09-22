import Testing
import Foundation
@testable import Sift

@Suite struct FolderScannerTests {
    init() { Preferences.useTestDefaults() }

    @Test func filtersToImagesAndSkipsHidden() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.JPG", "b.heic", "c.txt", ".hidden.png", "d.webp", "e.gif"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub.png"), withIntermediateDirectories: true)

        let names = try FolderScanner.scan(dir).map(\.name).sorted()
        #expect(names == ["a.JPG", "b.heic", "d.webp", "e.gif"])
    }

    @Test func sortsByNameNaturally() {
        let refs = ["img10.jpg", "img2.jpg", "img1.jpg"].map {
            PhotoRef(url: URL(fileURLWithPath: "/x/\($0)"), fileSize: 0, created: .now, modified: .now)
        }
        #expect(SortOrder.name.sort(refs).map(\.name) == ["img1.jpg", "img2.jpg", "img10.jpg"])
    }
}

@Suite struct SubfolderTests {
    init() { Preferences.useTestDefaults() }

    private func tree(_ names: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data([0]).write(to: dir.appendingPathComponent("a.jpg"))
        return dir
    }

    @Test func listsVisibleFoldersInFinderOrder() throws {
        let dir = try tree(["Day 10", "Day 2", ".git", "Day 1"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FolderScanner.subfolders(of: dir).map(\.lastPathComponent) == ["Day 1", "Day 2", "Day 10"])
    }

    @Test func packagesAreNotFolders() throws {
        let dir = try tree(["Trip.photoslibrary", "Raw"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FolderScanner.subfolders(of: dir).map(\.lastPathComponent) == ["Raw"])
    }

    @Test func aLeafFolderHasNothingBelowIt() throws {
        let dir = try tree([])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FolderScanner.subfolders(of: dir).isEmpty)
    }
}

@Suite struct FolderPreviewTests {
    init() { Preferences.useTestDefaults() }

    @Test func countsOnlyTheImagesOneLevelDown() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("deeper"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["b.jpg", "a.png", "notes.txt", ".hidden.jpg"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }
        try Data([0]).write(to: dir.appendingPathComponent("deeper/c.jpg"))

        let preview = FolderScanner.preview(of: dir)
        #expect(preview.count == 2)
        // And the covers are the frames the folder will open on, in that
        // order, not whichever names the file system handed back (D-350).
        // `a.png` sorts before `b.jpg`, and the subfolder and hidden files
        // are not candidates at all.
        #expect(preview.covers.map(\.name) == ["a.png", "b.jpg"])
    }

    /// A folder with nothing in it has no cover, so the tile draws the folder
    /// mark rather than an empty square.
    @Test func aFolderWithNoPhotographsHasNoCover() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0]).write(to: dir.appendingPathComponent("notes.txt"))
        let preview = FolderScanner.preview(of: dir)
        #expect(preview.count == 0)
        #expect(preview.covers.isEmpty)
    }

    /// Four is what the tile draws, and the walk that finds them keeps the
    /// order without sorting the folder: a card can hold nineteen thousand
    /// frames and this runs on every tile (D-318, D-351). The shuffle is the
    /// point — an insertion that only looks at the tail would pass on a list
    /// that happens to arrive sorted.
    @Test func fourCoversComeBackInNameOrderWithoutSortingTheFolder() {
        let names = (1...40).map { "IMG_\(String(format: "%04d", $0)).jpg" }
        let urls = names.shuffled().map { URL(fileURLWithPath: "/x/\($0)") }
        let picked = FolderScanner.firstByName(urls, limit: FolderPreview.coverCount)
        #expect(picked.map(\.lastPathComponent)
                == ["IMG_0001.jpg", "IMG_0002.jpg", "IMG_0003.jpg", "IMG_0004.jpg"])
    }

    /// Fewer photographs than places is the ordinary case for a folder of one
    /// or two, and it must not come back padded or short-sorted.
    @Test func aShortFolderGivesBackEverythingItHas() {
        let urls = ["c.jpg", "a.jpg", "b.jpg"].map { URL(fileURLWithPath: "/x/\($0)") }
        #expect(FolderScanner.firstByName(urls, limit: 4).map(\.lastPathComponent)
                == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(FolderScanner.firstByName([], limit: 4).isEmpty)
    }

    @Test func theCaptionCountsInWords() {
        #expect(FolderPreview(count: 0).caption == "no photos")
        #expect(FolderPreview(count: 1).caption == "1 photo")
        #expect(FolderPreview(count: 128).caption == "128 photos")
    }
}

@Suite struct FuzzyMatchTests {
    init() { Preferences.useTestDefaults() }

    @Test func initialsAndRunsBeatScatteredLetters() {
        #expect(FuzzyMatch.score("day", in: "Day 2") != nil)
        #expect(FuzzyMatch.score("d2", in: "Day 2") != nil)
        #expect(FuzzyMatch.score("xyz", in: "Day 2") == nil)

        let start = FuzzyMatch.score("ice", in: "Iceland 2026")!
        let middle = FuzzyMatch.score("ice", in: "Office pictures")!
        #expect(start > middle, "a name that starts with the letters is the better answer")
    }

    @Test func theShorterNameWinsAllElseEqual() {
        let short = FuzzyMatch.score("day", in: "Day 1")!
        let long = FuzzyMatch.score("day", in: "Day 1 second camera backup")!
        #expect(short > long)
    }

    @Test func anEmptyNeedleMatchesEverything() {
        #expect(FuzzyMatch.score("", in: "anything") == 0)
    }
}
