import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// The screenshot harness, checked the way it checks the app: on the outcome.
///
/// `SIFT_SHOW=zoom` sets four marks on the cursor's photograph and the contact
/// sheet photographs the corner they land in (D-222). On 2026-09-17 a run came
/// back with none of them and the sheet called it a success, because its only
/// guard was whether the picture had come out identical to the grid, and a
/// preview window with no marks on it is not the grid (D-227).
///
/// So the screen says what it asked for and the app reads it back off the store
/// before the capture. This is that read-back, over a store put into each state
/// by hand: a check that only ever runs inside a screenshot launch is a check
/// nothing watches.
@MainActor
@Suite struct ScreenCheckTests {
    init() { Preferences.useTestDefaults() }

    /// A folder of two photographs, with the cursor on the first.
    private func store() throws -> LibraryStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.jpg", "b.jpg"] {
            let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            let url = folder.appendingPathComponent(name)
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
        let store = LibraryStore()
        store.open(folder)
        store.cursor = 0
        return store
    }

    /// All four marks on and the zoom up: nothing to say.
    @Test func theScreenItAsksForPassesSilently() throws {
        let store = try store()
        store.zoom = 2
        let url = try #require(store.current?.url)
        store.update(url) { $0.flag = .keep; $0.label = .red; $0.favorite = true }
        #expect(GalleryWindow.zoomScreenProblem(store) == nil)
    }

    /// The `undo` screen's own check, both ways round (D-232). The corner
    /// control is what this screen exists to photograph and it draws from three
    /// things at once, so all three are asserted rather than only that a store
    /// exists.
    @Test func theUndoScreenPassesOnlyWithAnUnfavoriteOnTop() throws {
        let store = try store()
        let router = CommandRouter(store: store)
        #expect(GalleryWindow.undoScreenProblem(store)?.contains("nothing on the undo stack") == true)

        router.perform(.toggleFavorite)
        #expect(GalleryWindow.undoScreenProblem(store)?.contains("Favorite") == true,
                "one press leaves a favorite on top, which is not this screen")

        router.perform(.toggleFavorite)
        #expect(GalleryWindow.undoScreenProblem(store) == nil)

        // `undoable: false`, because an undoable one raises no message at all
        // now — the pill is the message (D-283). What is being checked is
        // unchanged: a message in the corner is standing where the pill goes.
        store.showToast("something happened", undoable: false)
        #expect(GalleryWindow.undoScreenProblem(store)?.contains("toast") == true,
                "the corner control does not draw under a toast, so the screen is not what it says")
    }

    /// One mark missing is a complaint that names it, which is the line that
    /// reaches stderr and fails the capture.
    @Test func everyMissingMarkIsNamed() throws {
        let store = try store()
        store.zoom = 2
        let url = try #require(store.current?.url)

        store.update(url) { $0.flag = nil; $0.label = .red; $0.favorite = true }
        #expect(GalleryWindow.zoomScreenProblem(store)?.contains("keep") == true)

        store.update(url) { $0.flag = .keep; $0.label = nil; $0.favorite = true }
        #expect(GalleryWindow.zoomScreenProblem(store)?.contains("label") == true)

        store.update(url) { $0.flag = .keep; $0.label = .red; $0.favorite = false }
        #expect(GalleryWindow.zoomScreenProblem(store)?.contains("favorite") == true)

        store.update(url) { $0.favorite = true }
        store.zoom = nil
        #expect(GalleryWindow.zoomScreenProblem(store)?.contains("zoom") == true)
    }

    /// The failure this exists for: the launch reached the screen with no
    /// photograph under the cursor, so there was nothing to mark and nothing
    /// said so.
    @Test func noPhotographIsAComplaintRatherThanASilentPass() throws {
        let store = try store()
        store.cursor = nil
        #expect(GalleryWindow.zoomScreenProblem(store) == "no photograph on screen")
    }
}

/// The sidebar's drag. The pointer cannot be driven from outside this process
/// (no Accessibility permission), so the part a test can reach is the
/// arithmetic between the drag and the width (D-229).
@MainActor
@Suite struct SidebarDragTests {
    init() { Preferences.useTestDefaults() }

    /// Rewritten deliberately, not loosened: this asserted the opposite until
    /// the stutter was measured. The 4pt scale is for the measurements this
    /// project authors, and a width somebody drags is not one of them. Rounding
    /// to it moved the divider in four-point hops while the grid behind it,
    /// centered in the width that was left, slid two points against the drag —
    /// two things moving at different rates, which is what was reported as
    /// jittery thumbnails (D-344).
    @Test func theEdgeGoesWhereThePointerIs() {
        // Both sides cast to `CGFloat` by hand. Left to the implicit
        // Double conversion, `#expect` rewrites the two sides separately and
        // reports 183.0 not equal to 183.0, which costs a while to believe.
        for translation in stride(from: -37.0, through: 37.0, by: 1.0) {
            let want: CGFloat = CGFloat(220 + translation).rounded()
            let w = SidebarDivider.width(from: 220, by: CGFloat(translation))
            #expect(w == want, "a drag of \(translation) left the sidebar at \(w)")
        }
        // The point of the change: a one-point drag moves the edge one point.
        // On the old scale the first three did nothing and the fourth hopped.
        #expect(SidebarDivider.width(from: 220, by: 1) == 221)
        #expect(SidebarDivider.width(from: 220, by: 2) == 222)
        #expect(SidebarDivider.width(from: 220, by: 3) == 223)
    }

    @Test func neitherEndCanBeDraggedPast() {
        #expect(SidebarDivider.width(from: 220, by: -9999) == Tokens.Layout.sidebarMin)
        #expect(SidebarDivider.width(from: 220, by: 9999) == Tokens.Layout.sidebarMax)
    }

    /// The drag measures from where it started, not from where the sidebar is
    /// now: a gesture reports its total translation, so reading the live width
    /// each time makes the second event of a drag move twice as far.
    @Test func theDragMeasuresFromWhereItStarted() {
        let start: CGFloat = 220
        #expect(SidebarDivider.width(from: start, by: 20) == 240)
        #expect(SidebarDivider.width(from: start, by: 40) == 260)
    }

    /// A width written by an older build, or edited by hand, cannot wedge the
    /// window at something nothing can recover from.
    @Test func aStoredWidthIsClampedOnTheWayOut() {
        // Written through the setter, which clamps too, so the read is doing
        // the work a second time: a stale value can only arrive from an older
        // build or a hand-edited domain, and neither is reachable from here.
        Preferences.sidebarWidth = 4000
        #expect(Preferences.sidebarWidth == Tokens.Layout.sidebarMax)
        Preferences.sidebarWidth = 1
        #expect(Preferences.sidebarWidth == Tokens.Layout.sidebarMin)
    }
}

/// How many cells the grid puts on a row, which is the number a sidebar drag
/// walks through (D-345).
@MainActor
@Suite struct GridColumnTests {
    private static let gap = Tokens.Space.s12
    private static let inset = Tokens.Space.s16

    /// The formula divided the whole width by the pitch and never subtracted
    /// the padding the cells sit inside, so for an eight-point band below every
    /// boundary it asked for a column there was no room for. 48 widths between
    /// 400 and 1400 were wrong, and a drag on the sidebar crosses one band per
    /// boundary: the row overflows, the centered grid pushes the outer cells
    /// under both edges, and it snaps back a few points later.
    @Test func everyChosenColumnCountFitsTheWidthItWasChosenFor() {
        var overflowing: [String] = []
        for cell in Tokens.Layout.gridCellSteps {
            for w in stride(from: 320.0, through: 2400.0, by: 1.0) {
                let width = CGFloat(w)
                let n = GridView.columns(fitting: width, cell: cell, gap: Self.gap, inset: Self.inset)
                let used = CGFloat(n) * cell + CGFloat(n - 1) * Self.gap + Self.inset * 2
                if n > 1 && used > width {
                    overflowing.append("cell \(Int(cell)) at \(Int(width)): \(n) columns need \(Int(used))")
                }
            }
        }
        let fits = overflowing.isEmpty
        #expect(fits, """
            The grid asked for more columns than the width holds, so the row runs \
            under the padding at both edges:
            \(overflowing.prefix(6).joined(separator: "\n"))
            """)
    }

    /// And it does not go the other way either: one more column would not have
    /// fitted. A count that is merely safe is a column of empty on every window.
    @Test func oneMoreColumnWouldNotHaveFitted() {
        for cell in Tokens.Layout.gridCellSteps {
            for w in stride(from: 320.0, through: 2400.0, by: 7.0) {
                let width = CGFloat(w)
                let n = GridView.columns(fitting: width, cell: cell, gap: Self.gap, inset: Self.inset)
                let more = CGFloat(n + 1) * cell + CGFloat(n) * Self.gap + Self.inset * 2
                #expect(more > width,
                        "cell \(Int(cell)) at \(Int(width)) took \(n) columns with room for \(n + 1)")
            }
        }
    }
}
