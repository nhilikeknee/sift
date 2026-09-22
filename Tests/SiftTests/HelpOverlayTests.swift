import Testing
import Foundation
import CoreGraphics
@testable import Sift

/// The help overlay's panel against the window it is drawn in (D-333).
///
/// `maxWidth` is a ceiling, not a limit. When the content's own minimum width
/// is larger — a search field pinned at 260 and two key columns came to more
/// than 700 — SwiftUI grows past the ceiling and the layer grows with it. On a
/// 700pt window that pushed the sidebar out of the left edge and ran the panel
/// off the right. Build green, suite green, and nobody found it until somebody
/// made the window small and pressed `?`.
@Suite struct HelpOverlayTests {
    private func room(_ w: CGFloat, _ h: CGFloat) -> HelpOverlay.Room {
        HelpOverlay.Room(window: CGSize(width: w, height: h))
    }

    /// The rule, swept rather than sampled: at no window size does the panel
    /// plus its margins come to more than the window.
    @Test func thePanelNeverAsksForMoreThanTheWindowHas() {
        // The first few, not all of them. The array itself stays out of the
        // expectation: `#expect` prints what it evaluated, and a sweep that
        // fails everywhere prints thousands of lines nobody reads.
        var tooBig: [String] = []
        for w in stride(from: CGFloat(200), through: 2400, by: 20) where tooBig.count < 6 {
            for h in stride(from: CGFloat(200), through: 1600, by: 50) where tooBig.count < 6 {
                let r = room(w, h)
                if r.width + Tokens.Space.s32 * 2 > w { tooBig.append("\(w)x\(h): \(r.width) wide") }
                if r.height + Tokens.Space.s32 * 2 > h { tooBig.append("\(w)x\(h): \(r.height) tall") }
            }
        }
        let fits = tooBig.isEmpty
        #expect(fits, "the panel asks for more than the window has: \(tooBig.joined(separator: ", "))")
    }

    /// Never negative, whatever the window does. A window narrower than the
    /// margins is not a real window, but a negative frame is a crash rather
    /// than a small panel.
    @Test func aWindowSmallerThanItsOwnMarginsGivesAnEmptyPanelRatherThanANegativeOne() {
        for size in [CGSize(width: 0, height: 0), CGSize(width: 40, height: 40),
                     CGSize(width: 64, height: 64)] {
            let r = HelpOverlay.Room(window: size)
            #expect(r.width >= 0 && r.height >= 0, "negative frame at \(size)")
            #expect(r.columns >= 1, "a panel always draws at least one column")
        }
    }

    /// Two columns when there is room for two. 820 is the ceiling, so anything
    /// wider than 820 plus its margins is the widest the panel ever gets.
    @Test func theGridTakesTwoColumnsOnlyWhenBothFit() {
        #expect(room(1100, 760).columns == 2)
        #expect(room(1100, 760).width == Tokens.Layout.helpMaxWidth)
        #expect(room(700, 560).columns == 1, "700pt is the window that reported this")
        // The boundary, stated rather than found: two columns need two of them
        // plus the grid's gutter, inside the panel's own padding.
        let needed = Tokens.Layout.helpColumn * 2 + Tokens.Space.s24 + Tokens.Space.s32 * 2
        #expect(room(needed + Tokens.Space.s32 * 2, 800).columns == 2)
        #expect(room(needed + Tokens.Space.s32 * 2 - 4, 800).columns == 1)
    }
}
