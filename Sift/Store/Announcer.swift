import AppKit

/// What the app says out loud, for the reader who cannot see it say anything.
///
/// Sift reports in pixels. A refusal is a toast, and an undoable act raises no
/// message at all because the way back is the message (D-283). Both are silent
/// to VoiceOver, so a command that refuses is, to somebody listening, a command
/// that did nothing and said nothing (A-11).
///
/// Two things speak and the other forty-four toast sites stay quiet, which is
/// the owner's call on the record: announcing every outcome talks over a cull
/// that runs at three keystrokes a second, and the one nobody can afford to
/// miss is the one that says the keystroke did not work.
///
/// A seam rather than a call written where it is needed, because
/// `NSAccessibility.post` has no readback of any kind: standing in front of it
/// is the only way a test can read what the app tried to say.
@MainActor
enum Announcer {
    /// How much an announcement is allowed to interrupt.
    enum Insistence {
        /// A refusal. It goes in front of whatever is being read, because the
        /// reader has just pressed a key and is waiting to hear what happened.
        case interrupting
        /// The way back, after something worked. It waits its turn, and inside
        /// a fast cull each one replaces the one before it rather than piling
        /// a queue of them up behind the reader.
        case ordinary
    }

    static var say: (String, Insistence) -> Void = { message, insistence in
        let priority: NSAccessibilityPriorityLevel = insistence == .interrupting ? .high : .medium
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: priority.rawValue])
    }
}
