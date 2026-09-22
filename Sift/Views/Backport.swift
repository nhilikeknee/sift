import SwiftUI
import AppKit

/// What macOS 15 added and this app used, written so 14 gets the same behavior
/// by another route (D-389).
///
/// Three modifiers and one scene modifier, each named for what it does rather
/// than for the system call behind it, so the `#available` check lives here
/// once instead of at thirty-six call sites. The 15 path is the system's own;
/// the 14 path is what everybody wrote before it existed.
extension View {
    /// The pointing hand over something that can be pressed.
    ///
    /// A cursor rect rather than a tracking area: rects are geometry the window
    /// asks for, so this works from a background layer that takes no clicks.
    @ViewBuilder
    func linkCursor(_ enabled: Bool = true) -> some View {
        if #available(macOS 15, *) {
            pointerStyle(enabled ? .link : nil)
        } else {
            background(CursorArea(cursor: enabled ? .pointingHand : nil))
        }
    }

    /// The pointer over a divider somebody can drag sideways.
    @ViewBuilder
    func resizeCursor() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.frameResize(position: .trailing))
        } else {
            background(CursorArea(cursor: .resizeLeftRight))
        }
    }

    /// A window that keeps its title for the Window menu and stops drawing it
    /// (D-208).
    @ViewBuilder
    func plainWindowChrome() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title)
        } else {
            background(WindowFlag { $0.titleVisibility = .hidden })
        }
    }

    /// A window that does not come back at the next launch (D-309).
    ///
    /// `restorationBehavior(.disabled)` is a scene modifier, and `SceneBuilder`
    /// takes no `if #available`, so this sets the flag the scene modifier sets
    /// and does it on every system rather than one way on 15 and another on 14.
    func withoutRestoration() -> some View {
        background(WindowFlag { $0.isRestorable = false })
    }
}

/// A view that owns a cursor rect and nothing else.
private struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor?

    func makeNSView(context: Context) -> Area { Area() }

    func updateNSView(_ view: Area, context: Context) {
        guard view.cursor != cursor else { return }
        view.cursor = cursor
    }

    final class Area: NSView {
        var cursor: NSCursor? {
            didSet { window?.invalidateCursorRects(for: self) }
        }

        override func resetCursorRects() {
            guard let cursor else { return }
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

/// One flag set on the window a view is in.
///
/// `updateNSView` can run before the view has a window, so the work is queued
/// as well as done: whichever of the two arrives second is the one that takes.
private struct WindowFlag: NSViewRepresentable {
    let set: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { set(window) }
        DispatchQueue.main.async {
            if let window = view.window { set(window) }
        }
    }
}
