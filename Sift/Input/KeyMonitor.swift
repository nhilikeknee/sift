import AppKit

/// Installs the one local key monitor (D-7). Keystrokes inside a text field pass through.
@MainActor
final class KeyMonitor {
    private var token: Any?
    private var upToken: Any?
    private var flagsToken: Any?
    private var resignToken: Any?

    /// `SIFT_SHOW=peek` holds `⌥` down for one launch, and the clear below is
    /// exactly why it needs saying out loud: a script's launch goes inactive
    /// the moment the terminal takes the front back, which is the one thing
    /// that ends a peek without a pointer or a key being involved. The contact
    /// sheet photographed a plain grid and called it `peek`, which is the
    /// failure D-118 exists to catch, caught. Read once, like every other
    /// `SIFT_` (D-112, D-123, D-130).
    ///
    /// Gated in the same commit as the screen assembler it belongs to, and for
    /// the reason D-302 exists rather than for anything this line does: one
    /// variable with two readers and a gate on one of them is exactly the
    /// shape D-302 was written about, and this was the second reader. The
    /// fifth security pass used *this line*, an ungated `SIFT_SHOW` read
    /// present in both builds, as the control proving the `SIFT_SCRIPT`
    /// differential could tell the binaries apart. A control is not an audit
    /// of its own subject (D-308).
    nonisolated private static let peekPinnedForScreenshot: Bool = {
#if DEBUG
        ProcessInfo.processInfo.environment["SIFT_SHOW"]?.contains("peek") == true
#else
        false
#endif
    }()

    /// A launch that is driving itself takes no keystrokes from anybody.
    ///
    /// `SIFT_SCRIPT` replays commands through the router, so a scripted run
    /// never needed the keyboard; and since `SIFT_FLOAT` put the window above
    /// every other one, the app is both visible and reachable for the whole
    /// take. Two takes were lost to that: a sentence typed into another app
    /// went into Sift, its `n` opened Rename over the gallery and its `a` put a
    /// compare anchor on the frame. Swallowing the key is the whole fix, and it
    /// costs a scripted run nothing, because a scripted run is not pressing any
    /// (D-278).
    /// Gated the way the run itself is (D-300, D-302). Reading the variable
    /// here was the half of D-278 the debug gate did not cover: the replay was
    /// out of the download and the swallow was not, so a release build launched
    /// with `SIFT_SCRIPT` set to anything at all came up with a live window and
    /// a dead keyboard, scripting nothing and explaining nothing. Found by
    /// `SecurityClaimTests` on the first run of a test written for the other
    /// half.
    nonisolated private static let drivingItself: Bool = {
#if DEBUG
        ProcessInfo.processInfo.environment["SIFT_SCRIPT"]?.isEmpty == false
#else
        false
#endif
    }()

    /// One monitor for the app, however many windows are open: it asks the model
    /// which session is key on every keystroke (D-40).
    func install(model: AppModel) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.drivingItself { return nil }
            let bindings = KeyBindings.shared
            // Before every other guard, the text-field one included: the
            // filter field in Settings can still hold focus while a row is
            // waiting, and a keystroke asked for is not a keystroke meant
            // (D-175). Swallowed either way, so the key being recorded does
            // not also run the command it is bound to today.
            if bindings.recording != nil {
                bindings.finishRecording(with: Key(event: event))
                return nil
            }
            // Read per keystroke rather than captured at install: a key
            // reassigned in Settings has to take effect on the next press, not
            // the next launch (D-175).
            let map = bindings.map
            let store = model.active.store
            let router = model.active.router
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            if NSApp.modalWindow != nil || store.sheetHasTheKeyboard { return event }
            guard let key = Key(event: event) else { return event }
            let command = map.command(for: key, focus: store.focus, features: AppModel.shared.features)
            if store.showHelp, command != .toggleHelp { store.showHelp = false; return nil }
            if store.showSummary, command != .showSummary { store.showSummary = false; return nil }
            guard let command else { return event }
            // Holding a key auto-repeats; a held zoom must not toggle itself off.
            if event.isARepeat, command == .zoomToggle { return nil }
            router.perform(command)
            return nil
        }
        // `⌥` for the peek (D-130). It reads the flags rather than being a
        // `Command`, because a modifier held on its own is not a keystroke and
        // the key map is a map of keystrokes. The event is passed on: a
        // monitor that swallowed a modifier change would break every other
        // thing in the app that reads one.
        flagsToken = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            model.active.store.optionHeld = event.modifierFlags.contains(.option)
            return event
        }
        // A `flagsChanged` only arrives while Sift is frontmost, so ⌥-tabbing
        // away leaves the flag set and the peek waiting to appear on the next
        // hover. Going inactive is the release the app never gets told about.
        resignToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            guard !Self.peekPinnedForScreenshot else { return }
            MainActor.assumeIsolated { model.active.store.optionHeld = false }
        }
        upToken = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            if Self.drivingItself { return nil }
            let session = model.active
            let map = KeyBindings.shared.map
            guard let key = Key(event: event),
                  map.command(for: key, focus: session.store.focus, features: AppModel.shared.features) == .zoomToggle else { return event }
            session.router.releasePeek()
            return nil
        }
    }
}
