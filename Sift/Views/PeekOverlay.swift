import SwiftUI

/// A look at one photograph, held open with `⌥` and gone when the pointer
/// moves off the thumbnail (D-130). No window opens, the cursor does not move
/// and the selection does not change: this is a look, not a place you are.
///
/// It sits beside the thumbnail rather than in the middle of the window
/// (D-131). The grid stays where it was and the cell stays visible, so the
/// answer to "which one is this" is the thing next to it rather than a
/// position you have to remember.
@MainActor
struct PeekOverlay: View {
    let ref: PhotoRef
    /// The thumbnail's frame, in the same space this overlay is laid out in.
    let anchor: CGRect

    /// The gap between the thumbnail and the panel.
    private static let gap = Tokens.Space.s12

    var body: some View {
        GeometryReader { geo in
            let place: (side: CGFloat, x: CGFloat, y: CGFloat) = placement(in: geo.size)
            panel(side: place.side).offset(x: place.x, y: place.y)
        }
        // The pointer has to stay on the thumbnail underneath. An overlay that
        // took the hover would end the hover that is holding it open, which
        // closes it, which hands the hover back: a photograph flickering at
        // the frame rate. Nothing here is clickable anyway.
        .allowsHitTesting(false)
    }

    private func panel(side: CGFloat) -> some View {
        PhotoImage(ref: ref, full: true)
            .padding(Tokens.Space.s12)
            .frame(width: side, height: side)
            // `judging`'s ground, for `judging`'s reason: a photograph is
            // looked at against a neutral dark surround. One edge treatment,
            // the shadow, because the panel genuinely floats over the grid and
            // a hairline as well would be two definitions of the same edge.
            .background(Tokens.Surface.judging, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .shadow(color: Tokens.Elevation.overlay.color,
                    radius: Tokens.Elevation.overlay.radius,
                    y: Tokens.Elevation.overlay.y)
    }

    /// How big the panel is and where it goes.
    ///
    /// Horizontally: right of the thumbnail when it fits, left when it does
    /// not. Preferring one side and flipping only at the edge keeps the panel
    /// still while the pointer sweeps a row; picking the roomier side each
    /// time would have it jumping across the cell halfway along.
    ///
    /// **The size comes from the side it lands on** (D-235). It used to come
    /// from the window's width less one cell, which is the room a thumbnail
    /// flush against an edge would have and more than any other thumbnail
    /// has. A cell in the middle of a row then got a panel too wide for either
    /// side, the `max(gap, …)` clamp pinned it to the left margin, and it drew
    /// straight across the thumbnail it was previewing — the one thing the
    /// placement exists to prevent. A narrow window gets a smaller panel now,
    /// which is the honest answer to not having the room.
    ///
    /// Vertically: centered on the thumbnail, then pushed back inside the
    /// window, because a panel centered on a cell in the top row hangs off the
    /// top otherwise.
    func placement(in container: CGSize) -> (side: CGFloat, x: CGFloat, y: CGFloat) {
        let gap: CGFloat = Self.gap
        let tall: CGFloat = container.height - gap * 2
        let wanted: CGFloat = min(Tokens.Layout.peekPanel, tall)

        // What each side actually has, measured from the thumbnail's own edges
        // rather than from the window's.
        let roomRight: CGFloat = container.width - anchor.maxX - gap * 2
        let roomLeft: CGFloat = anchor.minX - gap * 2

        // Right if the panel fits there whole. Otherwise left if it fits there
        // whole. Otherwise the roomier of the two, and the panel shrinks to it.
        let onRight: Bool = roomRight >= wanted || roomRight >= roomLeft
        let side: CGFloat = max(0, min(wanted, onRight ? roomRight : roomLeft))
        let x: CGFloat = onRight ? anchor.maxX + gap : anchor.minX - gap - side

        let centered: CGFloat = anchor.midY - side / 2
        let lowest: CGFloat = max(gap, container.height - side - gap)
        let y: CGFloat = min(max(gap, centered), lowest)
        return (side, x, y)
    }
}
