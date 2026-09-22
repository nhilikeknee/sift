import SwiftUI
import AppKit

/// Dragging a whole selection out of the grid, to Finder or to any app that
/// takes files (D-72).
///
/// SwiftUI's `onDrag` hands back one `NSItemProvider`, and one provider is one
/// file however many are selected — which is why dragging thirty keepers into a
/// folder moved the one under the pointer. AppKit's dragging session takes an
/// array of items, so the session is started by hand, from a view that sits
/// behind the cell and never takes a click.
///
/// The files are already on disk, so each item is a plain `NSURL` pasteboard
/// writer. `NSFilePromiseProvider` is for files that do not exist until the
/// drop, which is not this case.
struct DragOut: NSViewRepresentable {
    /// Read at the moment the drag starts rather than when the view is made:
    /// the selection changes under cells that are already on screen.
    let urls: () -> [URL]
    let handle: DragOutHandle

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView()
        view.urls = urls
        view.onEnd = { [weak handle] in handle?.dragging = false }
        handle.view = view
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) {
        view.urls = urls
        handle.view = view
    }
}

/// Transparent, and invisible to the mouse: `hitTest` returns nil, so every
/// click still lands on the SwiftUI cell in front of it. Its only job is to be
/// a view in a window that a dragging session can start from.
final class DragOutView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var onEnd: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Outside the app the files copy or move, the way a Finder drag does.
        // Inside it, nothing: Sift's own drop targets are fed by SwiftUI's drop
        // destinations, which read an item provider instead.
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnd()
    }

    /// Starts the session, and says what stopped it when it does not. A drag
    /// that quietly fails to begin looks exactly like a photo that refused to
    /// move (D-103), so every way out of here has a name.
    @discardableResult
    func beginDrag() -> DragOutStart {
        let files = urls()
        guard !files.isEmpty else { return .noFiles }
        guard let window else { return .detached }
        let event = Self.anchorEvent(in: window)
        let items: [NSDraggingItem] = files.enumerated().map { i, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: Self.iconEdge, height: Self.iconEdge)
            // A short cascade, so a drag of thirty reads as a stack of files
            // rather than as one file that happens to be thirty.
            let offset = CGFloat(min(i, Self.stackDepth)) * Self.stackStep
            let origin = NSPoint(x: bounds.midX - Self.iconEdge / 2 + offset,
                                 y: bounds.midY - Self.iconEdge / 2 - offset)
            item.setDraggingFrame(NSRect(origin: origin, size: icon.size), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
        return .started
    }

    /// What the dragging session hangs on. `NSApp.currentEvent` is the mouse
    /// event driving the gesture in practice and guaranteed by nothing: during
    /// menu tracking, or on a drag begun by anything but the mouse, it is some
    /// other event or none, and AppKit refuses the session. When it is not a
    /// mouse event, one is made from where the pointer actually is, which is
    /// the anchor AppKit would have read off the real one anyway.
    static func anchorEvent(in window: NSWindow) -> NSEvent {
        if let current = NSApp.currentEvent, Self.mouseTypes.contains(current.type) { return current }
        return NSEvent.mouseEvent(with: .leftMouseDragged,
                                  location: window.mouseLocationOutsideOfEventStream,
                                  modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: 1)
            ?? NSEvent()
    }

    private static let mouseTypes: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseDragged, .rightMouseDown,
                                                             .rightMouseDragged, .otherMouseDown, .otherMouseDragged]

    /// How many files deep the stack is drawn before it stops offsetting, how
    /// far apart each one sits, and how big each icon is.
    private static let stackDepth = 4
    private static let stackStep: CGFloat = 4
    private static let iconEdge: CGFloat = 64
}

/// How a drag out ended before it began. None of these is something the reader
/// did wrong, which is why each one says so rather than leaving the photo
/// sitting still with no explanation (D-103).
enum DragOutStart: Equatable {
    case started
    case noFiles
    case detached

    var message: String? {
        switch self {
        case .started: nil
        case .noFiles: "Nothing to drag"
        case .detached: "That photo is not in a window yet"
        }
    }
}

/// The SwiftUI side's handle on the AppKit view behind the cell, so a drag
/// gesture on the cell can start a real multi-file session.
@MainActor
final class DragOutHandle: ObservableObject {
    weak var view: DragOutView?
    /// True while a session is running, so a gesture that reports a hundred
    /// changes starts one drag rather than a hundred.
    var dragging = false

    /// Nil while a session is already running: a gesture reports a hundred
    /// changes and only the first of them is a drag. Otherwise the outcome,
    /// which the caller is expected to say out loud when it is not `.started`.
    @discardableResult
    func begin() -> DragOutStart? {
        guard !dragging else { return nil }
        dragging = true
        guard let view else { dragging = false; return .detached }
        let outcome = view.beginDrag()
        if outcome != .started { dragging = false }
        return outcome
    }
}
