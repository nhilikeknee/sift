import CoreGraphics
import Foundation

/// The shape the crop box is held to while it is dragged (D-238).
///
/// A posture rather than a property of the photograph: it stays as the cursor
/// moves down the folder, because cropping a shoot to one shape is the reason
/// to set one at all (DESIGN, item state and posture state). The turn is kept
/// beside it in the store for the same reason.
enum CropRatio: String, CaseIterable, Identifiable, Sendable {
    /// Whatever the drag draws. What crop has always done, and still the default.
    case free
    /// The photograph's own shape, so the crop is a reframing rather than a
    /// change of format.
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    var id: String { rawValue }

    /// What the chip says. The numbers are the ratio in landscape; which way up
    /// it is put belongs to the turn control beside them, not to this label,
    /// because one fact stated in two places is the reader checking whether
    /// they agree (DESIGN, one fact one place).
    var label: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    /// Whether turning it on its side changes anything. A square is a square
    /// both ways up, and free has no shape to turn.
    var canTurn: Bool {
        switch self {
        case .free, .square: false
        default: true
        }
    }

    /// Width over height for the box, or nil while the crop is free.
    ///
    /// `photo` is the photograph's own aspect as it is drawn — upright, after
    /// its orientation tag has been applied — which is the only thing
    /// `.original` can mean.
    func aspect(photo: CGFloat, turned: Bool) -> CGFloat? {
        let upright: CGFloat
        switch self {
        case .free: return nil
        case .original: upright = photo > 0 ? photo : 1
        case .square: return 1
        case .fourThree: upright = 4.0 / 3.0
        case .threeTwo: upright = 3.0 / 2.0
        case .sixteenNine: upright = 16.0 / 9.0
        }
        return turned ? 1 / upright : upright
    }
}
