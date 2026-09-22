import Foundation
import Observation

/// The reader's own keys, laid over the one table (D-175).
///
/// `KeyMap.standard` stays what it has always been: the defaults, a constant,
/// and the thing the app is designed around. This holds what somebody changed
/// about it, resolves the two into the map every keystroke goes through, and
/// is the only place that decides whether a reassignment is allowed.
///
/// One instance. The key monitor asks it on every keystroke, so `map` is
/// resolved when an override changes rather than per event.
@MainActor
@Observable
final class KeyBindings {
    static let shared = KeyBindings()

    /// What the app answers to right now.
    private(set) var map: KeyMap = .standard

    /// Command to the keys it was moved onto. Empty is the shipped map.
    private(set) var overrides: [Command: [Key]] = [:]

    private init() {
        overrides = Self.load()
        map = KeyMap.standard.applying(overrides)
    }

    /// The command waiting for a keystroke, or nil.
    ///
    /// The one key monitor reads this before anything else, so a keystroke
    /// arriving while Settings is asking for one is the answer to that
    /// question rather than the command it is currently bound to (D-175).
    /// Nothing else in the app handles a raw event, and this does not change
    /// that: the monitor stays the only reader (D-7).
    var recording: Command?

    /// What the last attempt was refused for, so the row that asked can say
    /// why rather than appearing to have done nothing.
    private(set) var refused: (command: Command, reason: Refusal)?

    func beginRecording(_ command: Command) {
        refused = nil
        recording = command
    }

    func cancelRecording() {
        recording = nil
        refused = nil
    }

    /// The keystroke that answers the question, from the key monitor.
    ///
    /// Escape cancels rather than being refused: it is reserved, so it could
    /// never be the answer, and the reader pressing it while a row is waiting
    /// means "never mind" in every other part of the app.
    func finishRecording(with key: Key?) {
        guard let command = recording else { return }
        recording = nil
        guard let key else {
            // `Key(event:)` gives nothing back for an Option chord, because ⌥
            // rewrites the character before the event arrives (⌥z is Ω).
            refused = (command, .reserved("⌥ rewrites the character, so it can't be a shortcut."))
            return
        }
        guard key != .escape else { return }
        refused = assign(key, to: command).map { (command, $0) }
    }

    /// Why a keystroke cannot become this command's key. Nil means it can.
    enum Refusal: Equatable {
        /// The app needs this one for something no binding should take.
        case reserved(String)
        /// Another command holds it and has no other key, so taking it would
        /// leave that command with none.
        case wouldStrand(Command)

        var message: String {
            switch self {
            case .reserved(let why): why
            case .wouldStrand(let c): "\(c.label) has no other key. Give it one first."
            }
        }
    }

    /// Whether a keystroke can be moved onto a command, and why not if it
    /// cannot. A key already held by a command with a second key is allowed:
    /// it moves, and the command it came from keeps the other (D-175).
    func refusal(for key: Key, on command: Command) -> Refusal? {
        if let why = Key.reserved[key] { return .reserved(why) }
        guard let holder = map.holder(of: key), holder != command else { return nil }
        return map.keys(for: holder).count > 1 ? nil : .wouldStrand(holder)
    }

    /// Moves a command onto one keystroke. Returns what stopped it, or nil.
    ///
    /// Every key the command had goes: "reassign" is one key, and a row that
    /// reads "Trash · Delete D T" after two edits is a row nobody can act on.
    /// `reset` is how both defaults come back.
    @discardableResult
    func assign(_ key: Key, to command: Command) -> Refusal? {
        if let refusal = refusal(for: key, on: command) { return refusal }
        overrides[command] = [key]
        // The command that held it keeps its remaining keys, written down as
        // an override of its own so the resolve does not have to re-derive it.
        if let holder = map.holder(of: key), holder != command {
            let left = map.keys(for: holder).filter { $0 != key }
            if !left.isEmpty { overrides[holder] = left }
        }
        commit()
        return nil
    }

    /// Back to what the app shipped with, for one command.
    func reset(_ command: Command) {
        overrides[command] = nil
        commit()
    }

    /// Back to the shipped map entirely.
    func resetAll() {
        overrides = [:]
        commit()
    }

    /// Whether a command is on a key somebody chose rather than the one it
    /// shipped on, which is what the row's revert control appears for.
    func isOverridden(_ command: Command) -> Bool { overrides[command] != nil }

    var anyOverride: Bool { !overrides.isEmpty }

    private func commit() {
        map = KeyMap.standard.applying(overrides)
        Preferences.keyOverrides = overrides.reduce(into: [:]) { out, pair in
            out[pair.key.rawValue] = pair.value.map(\.stored)
        }
    }

    /// A stored override whose command or key no longer parses is dropped
    /// rather than defaulted to something: the shipped binding is a better
    /// answer than a guess.
    private static func load() -> [Command: [Key]] {
        Preferences.keyOverrides.reduce(into: [:]) { out, pair in
            guard let command = Command(rawValue: pair.key) else { return }
            let keys = pair.value.compactMap(Key.init(stored:))
            if !keys.isEmpty { out[command] = keys }
        }
    }
}
