import SwiftUI

/// The pieces every chrome control in the app is built from: the icon-and-name
/// pairing, and the ground a control stands on under the pointer.
///
/// This file used to be the gallery's action bar as well — the six file
/// commands, drawn as a row inside the hand-built header. The toolbar draws
/// those now, with the system's own buttons, so what is left here is what the
/// preview bar, the sidebar and the cells still share (D-208).

/// An icon with its name under it, and the only definition of that pairing in
/// the app (D-160).
///
/// Both halves of the header draw through this: the file actions on the left
/// and the four view controls on the right. They used to be two scales — 20pt
/// icons in a 36pt box beside 14pt icons in a 28pt box — sitting on two
/// different centers in one row, which is what made the right-hand group look
/// slightly dropped and slightly faint next to the left.
struct HeaderIcon<S: GlyphShape>: View {
    let shape: S
    /// Whether this control is *on*, which is the only thing that makes an
    /// outlined glyph solid. Whether the shape is a silhouette to begin with
    /// is the shape's own business now (D-177).
    var on = false
    /// The word under the icon. An icon on screen always has one; the type is
    /// optional because the peek panel and the sidebar draw bare glyphs
    /// through the same wrapper (D-180).
    var caption: String?

    var body: some View {
        // The word sits under the icon. Beside it, at the same size as
        // everything else in the header, it read as a control of its own and
        // the row read as ten things rather than six (D-139). Under it, at the
        // caption size, the pair reads as one control with a name.
        VStack(spacing: Tokens.Space.s4) {
            Group {
                Glyph.draw(shape, size: Tokens.Layout.glyphAction, on: on)
            }
            .frame(width: Tokens.Layout.glyphActionButton, height: Tokens.Layout.glyphAction)
            if let caption {
                Text(caption)
                    .textStyle(.caption)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        // The icon's own center, not the center of icon-plus-caption, and
        // measured from the top rather than read back out of the stack: the
        // icon is the first thing in it, so this is `glyphAction/2` whether or
        // not a caption hangs below. Every icon in the header pins here, which
        // is what puts them all on one line.
        .alignmentGuide(.headerLine) { _ in Tokens.Layout.glyphAction / 2 }
    }
}

/// The fill behind a chrome control: nothing at rest, a tint under the
/// pointer, a stronger one while the control is on (D-184).
///
/// One definition, applied by every button in the header, the sidebar and the
/// action bar, because six copies of `if hovering` drawing six slightly
/// different rectangles is how a row stops looking like a row. The color
/// change on the glyph stays: the fill says *this is a control*, the ink says
/// *the pointer is here*, and on a 14pt icon one of those on its own is easy
/// to miss.
///
/// Not for a control drawn on a photograph. Those already sit on a scrim, and
/// a second ground on top of it is two edges for one control.
private struct ControlFill: ViewModifier {
    let hovering: Bool
    let on: Bool

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .animation(Tokens.Motion.fast, value: hovering)
            .animation(Tokens.Motion.fast, value: on)
    }

    private var fill: Color {
        if on { return Tokens.Surface.controlOn }
        if hovering { return Tokens.Surface.controlHover }
        return .clear
    }
}

extension View {
    /// The pointer and the state, drawn the way the platform draws them.
    ///
    /// `padded` is for a control whose glyph already fills its box: the
    /// header's icons are 20pt in a 20pt-tall stack, so a fill drawn tight to
    /// them touches the ink. `GlyphButton` carries a 14pt glyph in a 28pt box
    /// and is its own margin, so it asks for `false` rather than growing by
    /// eight points everywhere it appears.
    func controlFill(hovering: Bool, on: Bool = false, padded: Bool = true) -> some View {
        padding(.horizontal, padded ? Tokens.Space.s4 : 0)
            .padding(.vertical, padded ? Tokens.Space.s4 : 0)
            .modifier(ControlFill(hovering: hovering, on: on))
    }
}
