import SwiftUI
import AppKit

/// Reports which window the keyboard is talking to. The key map disambiguates
/// bindings by window (Return opens the preview from the gallery, closes it from
/// the preview), so that answer has to be exact rather than inferred.
struct WindowFocusReporter: NSViewRepresentable {
    let focus: WindowFocus
    /// `@MainActor @Sendable`, because the notification closure below is
    /// `@Sendable` and this is what it calls. Without it the capture is a Swift
    /// 6 warning on a clean build, and the app it is about has one rule for
    /// where this can run: the main actor, which is where AppKit posts it.
    let onBecomeKey: @MainActor @Sendable (WindowFocus) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observe(window, focus: focus, report: onBecomeKey)
            if window.isKeyWindow { onBecomeKey(focus) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.stop() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var token: (any NSObjectProtocol)?

        func observe(_ window: NSWindow, focus: WindowFocus,
                     report: @escaping @MainActor @Sendable (WindowFocus) -> Void) {
            guard token == nil else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { report(focus) }
            }
        }

        // The window outlives this view, so the observer has to come off explicitly.
        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}


/// The same trick as `WindowFocusReporter`, for the question "which gallery is
/// the keyboard talking to" when there is more than one (D-40).
struct WindowKeyReporter: NSViewRepresentable {
    let onBecomeKey: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observe(window, report: onBecomeKey)
            if window.isKeyWindow { onBecomeKey() }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.stop() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var token: (any NSObjectProtocol)?

        func observe(_ window: NSWindow, report: @escaping @MainActor @Sendable () -> Void) {
            guard token == nil else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { report() }
            }
        }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}


/// Holds the window a scene is in. A box rather than a value because the
/// closures the router borrows are made at `onAppear`, which can be before the
/// view has a window to name (D-102).
@MainActor
final class WindowBox {
    weak var window: NSWindow?
}

/// Hands back the `NSWindow` this view is in, and nil when it leaves one. The
/// scene that owns a window is the only thing that can name it without
/// guessing: `NSApp.windows.first { $0.title == "Preview" }` stopped matching
/// the moment the preview started titling itself with the photo's filename, and
/// fell through to `NSApp.keyWindow`, which is whatever the reader last clicked.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReadingView(frame: .zero)
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowReadingView)?.onWindow = onWindow
    }
}

final class WindowReadingView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A turn later: this runs inside a layout pass, and the caller writes
        // SwiftUI state with the answer.
        let window = self.window
        DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
    }
}

/// What a double-click on a title bar does. A system setting, not ours: it is
/// "Double-click a window's title bar to" in Desktop & Dock, and an app that
/// picks for itself is an app that zooms a window somebody told the machine to
/// minimize (D-188).
///
/// The raw values are the strings the setting writes. An unset key means
/// Maximize, which is the shipped default, and so does a value from a later
/// version of the OS that this does not know — zooming is the answer somebody
/// expects from a title bar even when the name has changed.
enum TitleBarAction: String {
    case zoom = "Maximize"
    case minimize = "Minimize"
    case nothing = "None"

    /// Injectable, for the reason the pasteboard is (D-54): a test that asks
    /// what a double-click does must not depend on how the machine running it
    /// is set up. `UserDefaults.standard` searches the global domain, which is
    /// where this key lives.
    static func configured(in defaults: UserDefaults = .standard) -> TitleBarAction {
        guard let raw = defaults.string(forKey: "AppleActionOnDoubleClick") else { return .zoom }
        return TitleBarAction(rawValue: raw) ?? .zoom
    }

    @MainActor
    func perform(on window: NSWindow?) {
        guard let window else { return }
        switch self {
        case .zoom: window.performZoom(nil)
        case .minimize: window.performMiniaturize(nil)
        case .nothing: break
        }
    }
}
