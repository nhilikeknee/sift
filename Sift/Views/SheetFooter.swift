import SwiftUI

/// The row of actions at the foot of a sheet or a panel (D-355).
///
/// Two systems had grown up. The rename sheets used the platform's own buttons
/// and said the least they could: **Rename**, with no count and no mark. The
/// reject review drew its own — a glyph, a word and a number on a rounded
/// ground — and said the most: *Move 12 aside*, *Trash 12*. The first looked
/// like the Mac and the second told you what you were about to do.
///
/// This is both. The chrome is the platform's, so a button in Sift is a button
/// the reader has pressed ten thousand times elsewhere, and the label carries
/// the count and, where it earns one, a mark.
///
/// **The destructive action sits apart.** It leads the row and everything else
/// is pushed to the trailing edge behind a gap, which is the design rule about
/// matching the guardrail to the cost of being wrong: an action that loses
/// something a click cannot bring back does not stand shoulder to shoulder
/// with the one that does not. It also fixes a thing the reject review had
/// backwards — the Trash sat where the default button goes, nearest the hand.
struct SheetFooter<Destructive: View, Actions: View>: View {
    private let destructive: Destructive
    private let actions: Actions

    init(@ViewBuilder destructive: () -> Destructive,
         @ViewBuilder actions: () -> Actions) {
        self.destructive = destructive()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            destructive
            // The gap is the point, so it has a floor rather than only a
            // preference: a narrow sheet must still separate the two groups.
            Spacer(minLength: Tokens.Space.s24)
            actions
        }
        // Set once here rather than at every call site, which is the whole
        // point of there being one footer. The platform's default control is
        // sized for a dense inspector, and a sheet's answer to a question is
        // not that: `.large` is the platform's own name for the taller one,
        // so this asks for a size rather than inventing padding (D-356).
        .controlSize(.large)
        // The pointing hand, on the platform's buttons as well as this app's.
        // `GlyphButton`, `WordButton` and `BoxedButton` have carried it for a
        // long time, so a sheet's Cancel was the one control in Sift that a
        // pointer crossed without changing. Non-standard for a Mac, where the
        // hand means a link and a button keeps the arrow; the decision is
        // consistency inside one app over consistency with the platform, and
        // it was already made thirty-one times before this line (D-357).
        .pointerStyle(.link)
    }
}

extension SheetFooter where Destructive == EmptyView {
    /// A footer with nothing destructive in it, which is most of them.
    init(@ViewBuilder actions: () -> Actions) {
        self.init(destructive: { EmptyView() }, actions: actions)
    }
}

/// A button's label when the word alone does not say enough: a mark, then the
/// word and the count.
///
/// Not on every button. **Rename** is the only thing the rename sheet does and
/// the sheet is titled with it, so a pencil beside it is a picture of the word
/// above it. A mark earns its place where the row holds more than one action
/// of the same weight and the reader is choosing between them, which is what
/// the reject review's two are (D-355).
///
/// No `textStyle` on the word: inside the platform's button the platform sets
/// the font, and that is the whole point of using its chrome.
struct ActionLabel<S: GlyphShape>: View {
    let title: String
    let shape: S
    /// An ink for the mark and the word. Only a backgroundless button passes
    /// one: a bordered button draws its own fill, and a token measured against
    /// this app's grounds says nothing about the gray the system paints under
    /// a hovered control (D-356, D-357).
    var tint: Color?

    /// `Label`, not `Glyph.draw`. The extent table sizes a mark against this
    /// app's own steps (D-201), which is right in a bar this app lays out and
    /// wrong inside a button whose text the platform sets: the mark came out
    /// at its own size beside a `.large` control's word, sitting high against
    /// it. A `Label` hands both to the platform, which is what makes them one
    /// line of type (D-359).
    var body: some View {
        Label(title, systemImage: shape.symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint ?? Tokens.Text.primary)
    }
}
