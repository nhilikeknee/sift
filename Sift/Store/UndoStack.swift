import Foundation

/// A reversible file operation. The inverse is built before the operation runs (D-5).
/// `label` names what the operation was ("Move to Trash"), so the Edit menu reads
/// "Undo Move to Trash" and not "Undo Restore a.jpg".
struct UndoableOp: Sendable, Codable, Equatable {
    let label: String
    /// The folder the operation happened in, so an undo offered after walking
    /// into the next shoot can say which one it is about (D-93).
    var folder: URL?
    /// The photograph the cursor was on when this happened, so the way back can
    /// name it once the cursor is somewhere else. A pill reading "Undo keep"
    /// beside the photograph *after* the one that was kept is an offer to undo
    /// the thing in front of you, and it is not (D-283).
    var at: URL?
    /// What undoing it does, as a description rather than a closure (D-108).
    let inverse: Inverse

    init(label: String, folder: URL? = nil, at: URL? = nil, inverse: Inverse) {
        self.label = label
        self.folder = folder
        self.at = at
        self.inverse = inverse
    }

    /// Kept async because a reversal is file work and the call sites await it,
    /// which is where a progress banner gets its chance to draw.
    func undo() async throws { try inverse.run() }
}

@MainActor @Observable
final class UndoStack {
    private(set) var ops: [UndoableOp] = []
    let limit = 100

    var canUndo: Bool { !ops.isEmpty }
    var topLabel: String? { ops.last?.label }
    /// Where the top operation happened, when that is somewhere other than
    /// where you are now.
    var topFolder: URL? { ops.last?.folder }
    /// The photograph the top operation was about, when it named one.
    var topAt: URL? { ops.last?.at }

    func push(_ op: UndoableOp, in folder: URL? = nil, at: URL? = nil) {
        var op = op
        if op.folder == nil { op.folder = folder }
        if op.at == nil { op.at = at }
        ops.append(op)
        if ops.count > limit { ops.removeFirst(ops.count - limit) }
    }

    func pop() -> UndoableOp? { ops.popLast() }

    func clear() { ops.removeAll() }
}
