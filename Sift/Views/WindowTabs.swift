import AppKit
import SwiftUI

/// One `NSWindow`, held weakly, so a dictionary of them does not keep a closed
/// window alive (D-370).
@MainActor
final class WeakWindow {
    weak var window: NSWindow?
    init(_ window: NSWindow?) { self.window = window }
}

/// What makes two gallery windows tabs of one window (D-370).
///
/// A macOS tab *is* a window. Nothing about the view tree changes: every tab
/// keeps its own `Session`, its own cursor, its own selection, its own sidebar
/// and its own toolbar, which is what the window already had. All this does is
/// tell AppKit that these windows may be stacked, and then stack the one that
/// was asked for as a tab.
///
/// The system gets the rest for free: the tab bar, dragging a tab out into a
/// window and dropping it back, Show All Tabs, Merge All Windows, and
/// `⌘⇧[` / `⌘⇧]` in the Window menu. None of those is code here, and every
/// one of them would have been with a tab bar the app drew itself.
///
/// It is an `NSViewRepresentable` of its own rather than a `WindowReader`
/// because of *when* it has to run. `WindowReader` answers a turn later, which
/// is after the window has been ordered on screen, and a window pulled into a
/// tab bar after it is already up is a window that appears and vanishes. This
/// runs in `viewWillMove(toWindow:)`, before the window is shown (D-372).
@MainActor
struct GalleryTabbing: NSViewRepresentable {
    let id: UUID

    /// Every gallery carries the same one, which is the whole of what says
    /// these windows belong together. The preview window carries none and
    /// refuses tabbing outright: there is one of it, and a lone tab in a bar
    /// is a title bar with a second title in it.
    static let identifier = NSWindow.TabbingIdentifier("gallery")

    func makeNSView(context: Context) -> NSView { TabbingView(id: id) }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// The view that does it. It draws nothing; it exists to be told which window
/// it has been put into, early enough to matter.
final class TabbingView: NSView {
    private let id: UUID

    init(id: UUID) {
        self.id = id
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Before the window is on screen, which is the whole point of overriding
    /// this one rather than `viewDidMoveToWindow`.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        MainActor.assumeIsolated { claim(newWindow) }
    }

    @MainActor
    private func claim(_ window: NSWindow) {
        window.tabbingIdentifier = GalleryTabbing.identifier
        let model = AppModel.shared
        model.forgetClosedWindows()
        model.windows[id] = WeakWindow(window)
        guard let hostID = model.tabHost[id], let host = model.window(of: hostID), host !== window
        else {
            // `.automatic`, not `.preferred`: `⌘N` is a window and `⌘T` is a
            // tab, which is the pair Safari, Terminal and Finder all have.
            // `.preferred` on every window would make both of them tabs.
            window.tabbingMode = .automatic
            return
        }
        // Asked for as a tab, so this one window prefers tabs *before* it is
        // ordered in and AppKit puts it in the bar itself. Adding it to the
        // group after the fact is the version that flashes: the window is
        // already up by then, and the reader watches it appear and be taken
        // away again (D-372).
        window.tabbingMode = .preferred
        // AppKit picks the group by front-to-back order and the request names
        // a window, so this checks the answer once the window is up and
        // corrects it if the two disagree. The mode goes back to `.automatic`
        // in the same breath: it was set for this one placement.
        DispatchQueue.main.async { [weak window, weak host] in
            guard let window else { return }
            model.tabHost[self.id] = nil
            window.tabbingMode = .automatic
            guard let host, window.tabGroup == nil || window.tabGroup !== host.tabGroup else { return }
            host.addTabbedWindow(window, ordered: .above)
        }
    }
}

