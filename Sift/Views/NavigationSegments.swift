import AppKit
import SwiftUI

/// Back and forward, as one segmented control with a history menu behind each
/// half. What Finder, Safari, Music and the App Store all draw (D-209).
///
/// SwiftUI's `ControlGroup(.navigation)` is meant to be this and is not, inside
/// a toolbar item: it drew two bare chevrons with the row's own spacing between
/// them, so the leading edge read as two controls rather than one — the same
/// defect D-205 had just fixed by hand in the header it replaced. And a
/// `Button` has nowhere to hang a press-and-hold menu, which is how every Mac
/// app offers the history behind its arrows, so `router.backList` and
/// `goBack(steps:)` had become dead code.
///
/// `NSSegmentedControl` is all three: one bezel with a divider, momentary
/// tracking so neither half stays lit, and `setMenu(_:forSegment:)` for the
/// press-and-hold.
///
/// **The arrows are arrows, not chevrons.** Finder uses chevrons and can,
/// because nothing sits beside them; here the breadcrumb's own separator is a
/// chevron a few points to the right, and one mark for both made the path look
/// like it had four separators (D-138). Aligning with the platform means
/// taking its answer to the problem it has, not copying the glyph it chose for
/// a row this app does not have.
@MainActor
struct NavigationSegments: NSViewRepresentable {
    let canGoBack: Bool
    let canGoForward: Bool
    let backList: [URL]
    let forwardList: [URL]
    /// One step, which is what a click is.
    let step: (Bool) -> Void
    /// Several, which is what a pick from the history menu is.
    let jump: (Bool, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.segmentStyle = .separated
        control.trackingMode = .momentary
        control.setImage(NSImage(systemSymbolName: "arrow.left", accessibilityDescription: "Back"), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Forward"), forSegment: 1)
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        control.setAccessibilityLabel("Back and forward")
        // Its own size, not one this app picks: two targets and the divider
        // between them is what the platform's metrics say, and a width chosen
        // here was wider than the gap to the path beside it (D-209).
        control.sizeToFit()
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.setEnabled(canGoBack, forSegment: 0)
        control.setEnabled(canGoForward, forSegment: 1)
        // The menu is rebuilt rather than mutated: a history is short, and a
        // stale row here walks somebody to a folder they did not ask for.
        control.setMenu(context.coordinator.menu(back: true, urls: backList), forSegment: 0)
        control.setMenu(context.coordinator.menu(back: false, urls: forwardList), forSegment: 1)
        control.setToolTip(canGoBack ? "Back (⌘[)" : "Nowhere back to go", forSegment: 0)
        control.setToolTip(canGoForward ? "Forward (⌘])" : "Nowhere forward to go", forSegment: 1)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NavigationSegments
        init(_ parent: NavigationSegments) { self.parent = parent }

        @objc func clicked(_ sender: NSSegmentedControl) {
            parent.step(sender.selectedSegment == 0)
        }

        /// The folders behind that arrow, nearest first, which is the order
        /// every history menu on this platform uses.
        func menu(back: Bool, urls: [URL]) -> NSMenu? {
            guard !urls.isEmpty else { return nil }
            let menu = NSMenu()
            for (i, url) in urls.prefix(12).enumerated() {
                let item = NSMenuItem(title: url.lastPathComponent,
                                      action: #selector(picked(_:)), keyEquivalent: "")
                item.target = self
                item.toolTip = url.path
                // The step count, not the index: "two back" is what the caller
                // takes, and it is one more than the row's position.
                item.tag = (back ? 1 : -1) * (i + 1)
                menu.addItem(item)
            }
            return menu
        }

        @objc func picked(_ sender: NSMenuItem) {
            let steps = sender.tag
            parent.jump(steps > 0, abs(steps))
        }
    }
}
