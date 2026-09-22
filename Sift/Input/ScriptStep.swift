import CoreGraphics

/// One step of a `SIFT_SCRIPT` run, worked out before anything is performed.
///
/// The grammar and the driving were one loop, and the loop was written twice:
/// the setup pass took `Command` raw values only, so `wait` meant a rest in the
/// take and a stopped run in the setup. Splitting the reading off the doing
/// makes the grammar one thing, and a thing the suite can hold: until now the
/// only way to find out a token was wrong was to film a clip and watch it
/// (D-254).
enum ScriptStep: Equatable, Sendable {
    /// A `Command` raw value. The recording is made out of the same table the
    /// shortcuts overlay and the command palette read, so a rebound key cannot
    /// break it.
    case run(Command)
    /// `wait` rests one step, `wait:1200` rests that many milliseconds.
    case rest(milliseconds: Int?)
    /// Crop is a drag and a script has no pointer. The rectangle is the store's
    /// alone since D-159, so asking for one is setting one: two of these in a
    /// row, a little apart, is a box being pulled in.
    case cropBox(CGRect)
    /// Pan is a drag too, and the same reasoning applies: the rect the single
    /// view should fill the window with and center on is `focusRequest`, so
    /// asking for one is aiming the view. It is the only way a script reaches
    /// the *place* somebody is looking; `zoomIn` reaches the magnification and
    /// nothing else, and `zoomToFace` needs a face the frame may not have.
    case lookAt(CGRect)
    /// A slider is a drag as much as a crop box is, and the adjust panel's are
    /// pointer-only: the key monitor takes the arrow keys for the cursor before
    /// a focused control sees them, so nothing in the app can nudge a knob from
    /// the keyboard and nothing outside it can reach the panel at all.
    /// `knob:exposure 35` sets one the way a hand would. One knob per step,
    /// because a step apart is what makes four of them read as sliders being
    /// moved rather than as a recipe appearing at once (D-291).
    case knob(Adjustments.Knob, Double)
    /// The Option peek, which is a modifier and a pointer and so is neither a
    /// command nor reachable from outside the app. `peek:6` hovers that
    /// photograph and warps the real cursor onto its cell, `peek:on` and
    /// `peek:off` hold and release Option. The warp is `CGWarpMouseCursorPosition`,
    /// which is not an event tap and needs no Accessibility grant, the same
    /// call `park-cursor.swift` has used since D-252. A still could say what
    /// the peek looks like and not what it is: hovering (D-297).
    case peek(Peek)
    /// Which half of the peek a `peek:` token is asking for.
    enum Peek: Equatable, Sendable {
        case hover(Int)
        case option(Bool)
    }
    /// Dragging the sidebar is a drag like the crop box is, and the width is
    /// the store's alone, so asking for a width is setting one. `sidebar:160
    /// 360 1` sweeps the edge from 160 to 360 a point at a time, which is the
    /// one way to reproduce a resize: the pointer cannot be driven from outside
    /// this process (D-229), so until this existed a report of jitter while
    /// resizing could only be reasoned about (D-345).
    case sidebar(from: CGFloat, to: CGFloat, by: CGFloat)
    /// Why the token was refused, in the words the log prints. A run stops on
    /// the first one: a recording that quietly skips the step it was made for
    /// is worse than no recording.
    case refused(String)

    private static let restPrefix = "wait:"
    private static let cropPrefix = "cropBox:"
    private static let lookPrefix = "lookAt:"
    private static let knobPrefix = "knob:"
    private static let peekPrefix = "peek:"
    private static let sidebarPrefix = "sidebar:"

    static func parse(_ token: String) -> ScriptStep {
        if token.hasPrefix(cropPrefix) {
            guard let rect = rect(after: cropPrefix, in: token) else {
                return .refused("a crop box is four numbers")
            }
            return .cropBox(rect)
        }
        if token.hasPrefix(lookPrefix) {
            guard let rect = rect(after: lookPrefix, in: token) else {
                return .refused("a look is four numbers")
            }
            return .lookAt(rect)
        }
        if token.hasPrefix(knobPrefix) {
            let parts = token.dropFirst(knobPrefix.count).split(separator: " ")
            guard parts.count == 2, let value = Double(parts[1]) else {
                return .refused("a knob is a name and a number")
            }
            guard let knob = Adjustments.Knob(rawValue: String(parts[0])) else {
                return .refused("no knob called \(parts[0])")
            }
            guard Adjustments.Knob.range.contains(value) else {
                return .refused("a knob runs from \(Adjustments.Knob.range.lowerBound) "
                                + "to \(Adjustments.Knob.range.upperBound)")
            }
            return .knob(knob, value)
        }
        if token.hasPrefix(peekPrefix) {
            let rest = String(token.dropFirst(peekPrefix.count))
            if rest == "on" { return .peek(.option(true)) }
            if rest == "off" { return .peek(.option(false)) }
            guard let index = Int(rest), index >= 0 else {
                return .refused("a peek is a photograph's number, or on, or off")
            }
            return .peek(.hover(index))
        }
        if token.hasPrefix(sidebarPrefix) {
            let numbers = token.dropFirst(sidebarPrefix.count)
                .split(separator: " ").compactMap { Double($0) }
            guard numbers.count == 3, numbers[2] > 0 else {
                return .refused("a sidebar sweep is a start, an end and a step")
            }
            return .sidebar(from: numbers[0], to: numbers[1], by: numbers[2])
        }
        if token == "wait" { return .rest(milliseconds: nil) }
        if token.hasPrefix(restPrefix) {
            // A rest that cannot be read is refused rather than quietly given
            // the default step. `wait:1s` used to rest for however long the
            // gap between commands happened to be, and the clip came out
            // shorter than the one it was cut against with nothing said.
            guard let milliseconds = Int(token.dropFirst(restPrefix.count)), milliseconds >= 0 else {
                return .refused("a wait is a whole number of milliseconds")
            }
            return .rest(milliseconds: milliseconds)
        }
        guard let command = Command(rawValue: token) else {
            return .refused("no command called that")
        }
        return .run(command)
    }

    /// Four numbers after a prefix, in normalized image coordinates. Both boxes
    /// are read the same way because they are the same token with a different
    /// destination, and the count check was written twice before it was shared.
    private static func rect(after prefix: String, in token: String) -> CGRect? {
        let numbers = token.dropFirst(prefix.count)
            .split(separator: " ").compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}
