import AppKit
import SwiftUI

/// A menu whose button actually draws.
///
/// SwiftUI's `Menu` renders text and images in its label and silently drops
/// everything else, so a `Shape` in a `Menu` label paints nothing while its
/// frame still reserves the space (tech debt 19, D-61). Every glyph in this app
/// is a `Shape`, which made the breadcrumb chevrons invisible. A plain `Button`
/// draws whatever it is handed, so the menu becomes an `NSMenu` popped from the
/// button's own frame — the same thing `CommandRouter.presentSubfolderMenu`
/// does for ⌘↓, generalized to a control rather than a fixed header offset.
struct PopMenuItem {
    let title: String
    /// Drawn as a checkmark. The branch the open path already runs through.
    var checked = false
    /// A row that is a fact rather than a verb — what the header could not fit
    /// and had nowhere else to say (D-113). AppKit grays an item with no action,
    /// which is what "this is a readout" looks like in a menu.
    var enabled = true
    /// A rule above this row. Groups what the header had to put away by the
    /// band it came from.
    var separatorBefore = false
    var act: () -> Void = {}
}

/// `NSMenu` wants a target, a selector, and a view to pop out of. This is the
/// smallest object that is all three.
@MainActor final class PopMenuAnchor: NSObject {
    private(set) weak var view: NSView?
    private var items: [PopMenuItem] = []

    fileprivate func adopt(_ view: NSView) { self.view = view }

    func present(_ items: [PopMenuItem]) {
        guard let view, !items.isEmpty else { return }
        self.items = items
        let menu = NSMenu()
        for (i, entry) in items.enumerated() {
            if entry.separatorBefore, !menu.items.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: entry.title,
                                  action: entry.enabled ? #selector(pick(_:)) : nil,
                                  keyEquivalent: "")
            item.target = entry.enabled ? self : nil
            item.tag = i
            item.state = entry.checked ? .on : .off
            menu.addItem(item)
        }
        // The bottom edge of the control, so the list drops out of the thing
        // that was clicked rather than covering it.
        let y = view.isFlipped ? view.bounds.maxY : view.bounds.minY
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }
        items[sender.tag].act()
    }
}

/// A plain `NSView` sitting behind the button, matching its frame, only so the
/// menu has something in the window's coordinate space to pop out of.
struct PopMenuAnchorView: NSViewRepresentable {
    let anchor: PopMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        anchor.adopt(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.adopt(nsView)
    }
}

/// A button that pops a menu. The items are built on the click rather than on
/// every render, because the header redraws on each cursor move.
struct PopMenuButton<Label: View>: View {
    let hint: String
    let accessibilityLabel: String
    /// What the button says about its own state, kept apart from its name so a
    /// change to it is passed on. The breadcrumb's count of subfolders is the
    /// one that has one (D-343).
    let accessibilityValue: String
    let items: () -> [PopMenuItem]
    let label: () -> Label

    @State private var anchor: PopMenuAnchor

    /// The anchor is a parameter so a test can host the button and check the
    /// menu has a real view to come out of. Nothing in the app passes one.
    init(hint: String,
         accessibilityLabel: String,
         accessibilityValue: String = "",
         anchor: PopMenuAnchor = PopMenuAnchor(),
         items: @escaping () -> [PopMenuItem],
         @ViewBuilder label: @escaping () -> Label) {
        self.hint = hint
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.items = items
        self.label = label
        _anchor = State(initialValue: anchor)
    }

    var body: some View {
        Button { anchor.present(items()) } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .background(PopMenuAnchorView(anchor: anchor))
        .help(hint)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}
