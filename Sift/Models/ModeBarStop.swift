import Foundation

/// One stop on the keyboard's walk through a mode's own bar (D-245).
///
/// The preview bar's ring is named by the command each control runs (D-157),
/// because every control there *is* a command. These bars are not all commands:
/// choosing 16:9 and standing the ratio up are settings on the store, and
/// naming them as commands would mean six commands in the key map, the help
/// overlay and the palette for a thing that only exists while a box is being
/// dragged. So the ring is named by the stop.
///
/// The list is a function of what the bar draws, and the bar draws from the
/// same list. One list, or Tab walks a row somebody else is looking at (D-157).
enum ModeBarStop: Hashable, Sendable {
    case ratio(CropRatio)
    /// The mark that stands the ratio on its side. Only a stop when the shape
    /// has two ways up.
    case turn
    /// Only a stop when the photograph has an original kept beside it.
    case revert
    case cancel
    /// Only stops once there is a box to save.
    case saveCopy
    case saveOver

    /// The crop bar, left to right, top row then bottom, which is the order a
    /// reader's eye takes and therefore the order Tab takes.
    static func cropBar(ratio: CropRatio, hasBox: Bool, revertable: Bool) -> [ModeBarStop] {
        var out: [ModeBarStop] = CropRatio.allCases.map { .ratio($0) }
        if ratio.canTurn { out.append(.turn) }
        if revertable { out.append(.revert) }
        out.append(.cancel)
        if hasBox { out.append(contentsOf: [.saveCopy, .saveOver]) }
        return out
    }

    /// The revert bar, which is the two answers to its own question.
    static let revertBar: [ModeBarStop] = [.cancel, .saveOver]

    /// What a screen reader says, and what the help overlay would say if it
    /// listed these. The ratio's own label carries the shape.
    var label: String {
        switch self {
        case .ratio(let r): r.label
        case .turn: "Turn the ratio"
        case .revert: "Revert"
        case .cancel: "Cancel"
        case .saveCopy: "Save a copy"
        case .saveOver: "Save changes"
        }
    }
}
