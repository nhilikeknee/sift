import AppKit

/// How a control was set off: by the pointer, or by anything else.
///
/// A `Button`'s action is not run only by a click. VoiceOver presses one
/// through the accessibility API, and an `accessibilityAction` runs whatever it
/// was given. Neither is a mouse event, and `NSApp.currentEvent` in the middle
/// of one holds whatever AppKit last happened to process: a stale click on
/// another window, a key, or nothing.
///
/// Full Keyboard Access is not on that list in this app, and it is worth
/// saying why rather than leaving it to be rediscovered. `space` and
/// `returnKey` are bound to `.enterSingle` in the gallery, and `KeyMonitor`
/// takes them before any focused control does.
///
/// Two controls asked that global how many clicks it carried and branched on
/// the answer, which gave them no defined behavior for any reader who is not
/// holding a mouse. The worst of the three answers ends the process:
/// `NSEvent.clickCount` is valid for mouse events and raises
/// `NSInternalInconsistencyException` for the rest, and an Objective-C
/// exception raised under Swift cannot be caught (A-7).
///
/// So the question is asked here, once, and the type says what it found. A
/// call site decides what a press means for its own control; what it cannot do
/// any more is mistake one for a click (D-367).
enum Activation: Equatable {
    /// The pointer, with the count AppKit has already worked out.
    case click(count: Int)
    /// A keyboard, a screen reader, or an accessibility action. No count, and
    /// asking for one is the crash.
    case press

    /// Mouse events, which are the ones `clickCount` answers for. Dragged is
    /// in the list because the platform counts those too and leaving it out
    /// would make a drag look like a press.
    private static let pointer: Set<NSEvent.EventType> = [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    /// Reads `NSEvent.type` before reading anything else. `type` is valid on
    /// every event; almost nothing else on `NSEvent` is.
    static func of(_ event: NSEvent?) -> Activation {
        guard let event, pointer.contains(event.type) else { return .press }
        return .click(count: event.clickCount)
    }

    /// Whether this asks for the control's own verb rather than for the
    /// pointer's first step. A second click does; so does a press, because
    /// somebody who reached a control with the keyboard has already done the
    /// part a first click is for.
    /// Whether the event asked for the result somewhere other than here:
    /// Command held on the click. It is one question across the platform —
    /// a link, a Finder folder, a Safari bookmark all open in a new tab on a
    /// Command-click — and it is asked of the event rather than of a flags
    /// snapshot, because `NSEvent.modifierFlags` as a static reads whatever
    /// the keyboard holds now rather than what it held when the button was
    /// pressed (D-370).
    ///
    /// Guarded on the type for D-367's reason: only a pointer event is asked
    /// anything beyond `type`.
    static func wantsASecondPlace(_ event: NSEvent?) -> Bool {
        guard let event, pointer.contains(event.type) else { return false }
        return event.modifierFlags.contains(.command)
    }

    var wantsThePrimaryAction: Bool {
        switch self {
        case .press: true
        case .click(let count): count >= 2
        }
    }
}
