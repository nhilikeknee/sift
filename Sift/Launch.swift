import Foundation

/// The launch harness: the environment variables that assemble a screen or
/// drive a run, and the one channel they answer on.
///
/// `SIFT_SHOW`, `SIFT_SCRIPT`, `SIFT_SCRIPT_SETUP` and `SIFT_FEATURES_OFF` each
/// read a comma-separated list, and each of them, plus `SIFT_APPEARANCE`, says
/// out loud when it cannot do what it was asked. Six hand-written copies of the
/// same two lines had grown up around them, each carrying its own
/// force-unwrapped `data(using:)`, which is six places to write a crash into a
/// path that only ever runs while nobody is watching (D-254).
enum Launch {
    /// Where a launch says things, when it is not standard error. A task-local
    /// rather than a global, so two tests capturing at once cannot take each
    /// other's lines: the suite runs them in parallel (D-265).
    @TaskLocal private static var sink: (@Sendable (String) -> Void)?

    /// What a launch says to whatever is holding it. Standard error, not a log
    /// file: `open --stderr` is how a recorder catches these, and the launch
    /// check and the contact sheet both read them the same way.
    static func say(_ message: String) {
        if let sink { sink(message); return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Everything a launch said while `body` ran.
    ///
    /// The line *is* the outcome for a refusal: nothing on screen changes, and
    /// what `contact-sheet.sh` greps for is this. A test that only read the
    /// value back passed against a version that refused nothing and said
    /// nothing, which is how this one got written twice (D-265).
    static func saying(_ body: () -> Void) -> [String] {
        let lines = Lines()
        $sink.withValue({ lines.append($0) }) { body() }
        return lines.all
    }

    /// Somewhere to put them that two threads can share, because `say` is not
    /// promised to be called on one.
    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    /// What a launch variable actually asked for, or nil when it asked for
    /// nothing. Unset and empty are the same answer.
    ///
    /// `open --env SIFT_CURSOR=` sets the variable to the empty string rather
    /// than leaving it out, and that is how `contact-sheet.sh` says "no cursor
    /// on this screen": one `open` with every variable on it and most of them
    /// blank. A refusal there is a refusal on thirty screens out of thirty-two
    /// (D-266).
    static func asked(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Whether a launch variable is switched on. The same rule as `asked`, and
    /// the reason it is here rather than at each of the three call sites:
    /// `SIFT_BAR` read `!= nil`, so the blank the contact sheet passes on every
    /// screen but two pinned the preview bar up on all of them (D-266).
    static func isOn(_ raw: String?) -> Bool {
        asked(raw) != nil
    }

    /// The comma-separated list an environment variable holds, whitespace off
    /// each entry and the empty ones dropped. A trailing comma is a typo, and
    /// refusing the run over it would fail a recording for nothing.
    static func list(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A whole number of milliseconds from a launch variable, or the fallback
    /// when nobody named one. A value that cannot be read is refused out loud
    /// and comes back nil, the way `wait:1s` is: the recorder works out how
    /// long to film from the same number it hands the app, so a step the app
    /// quietly replaced with its default is a clip trimmed against a length
    /// nothing ran to (D-264).
    ///
    /// The string rather than the variable, so a test can ask it without
    /// setting one on the machine it is running on.
    static func milliseconds(_ raw: String?, or fallback: Int, named name: String) -> Int? {
        guard let raw = asked(raw) else { return fallback }
        guard let value = Int(raw), value >= 0 else {
            refuse(name, "a gap is a whole number of milliseconds, not \(raw)")
            return nil
        }
        return value
    }

    /// A launch variable that could not do what it was asked, in the one form
    /// every harness reads. `contact-sheet.sh` fails a capture on any of these:
    /// a launch that cannot assemble the screen it was asked for must not hand
    /// back a photograph of something else (D-227).
    ///
    /// One prefix rather than one per variable. `SIFT_APPEARANCE` and
    /// `SIFT_FEATURES_OFF` each said so in their own words, and the sheet only
    /// ever grepped for `SIFT_SHOW`, so a launch asked for a palette it could
    /// not read said so on the log and was photographed anyway (D-265).
    static func refuse(_ variable: String, _ why: String) {
        say("SIFT-REFUSED \(variable): \(why)")
    }

    /// Which photograph a launch asked the cursor to land on, or nil when
    /// nobody asked. A number past the end of the folder is refused rather
    /// than dropped: the heart and the keep/reject pill draw on the cursor's
    /// cell only, so a cursor left where it was is a picture of the wrong
    /// photograph with nothing marked on it, which is the exact miss D-227
    /// exists to catch (D-265).
    static func index(_ raw: String?, within count: Int, named name: String) -> Int? {
        guard let raw = asked(raw) else { return nil }
        guard let index = Int(raw) else {
            refuse(name, "a photograph is named by number, not \(raw)")
            return nil
        }
        guard index >= 0, index < count else {
            refuse(name, "no photograph \(index) in a folder of \(count)")
            return nil
        }
        return index
    }

    /// A positive measurement from a launch variable, or nil when nobody named
    /// one. Refused out loud when it cannot be read, for the reason above: a
    /// thumbnail step the app quietly replaced with the saved preference is a
    /// contact sheet shot at a size nobody asked for (D-265).
    static func measurement(_ raw: String?, named name: String) -> Double? {
        guard let raw = asked(raw) else { return nil }
        guard let value = Double(raw), value > 0 else {
            refuse(name, "a measurement is a positive number, not \(raw)")
            return nil
        }
        return value
    }

    /// Which launch variables have already been acted on. A latch, because some
    /// of them are once per process and `.onAppear` is once per window: see
    /// `claim`.
    @MainActor
    private static var claimed: Set<String> = []

    /// Whether this is the launch variable's one turn. `newWindow` is a
    /// `Command` like any other, and the window it opens comes up through the
    /// same `pending` handoff that starts a script, so a `SIFT_SCRIPT` with
    /// `newWindow` in it started itself again in the new window, which opened
    /// another one, until the run was killed (D-264).
    @MainActor
    static func claim(_ name: String) -> Bool {
        claimed.insert(name).inserted
    }

    /// Hands the latch back, so one test's claim is not the next test's
    /// refusal. Nothing in the app calls this: a process gets one launch.
    @MainActor
    static func releaseClaims() {
        claimed.removeAll()
    }
}
