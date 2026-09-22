import SwiftUI

/// What a piece of text *is*, rather than how big it is.
///
/// `Tokens.Font.ui` was one 14pt size used at 65 call sites in three different
/// colors, which is a size pretending to be a style: nothing in the code said
/// whether a given 14pt string was a control's own word, a fact about the
/// folder, or punctuation, so nothing could keep those three consistent as the
/// app grew. A role pairs the size, the weight and the resting color, and it is
/// the only way text is styled here — `HeaderDriftTests` fails the build on a
/// bare `.font(` in a view (D-114).
///
/// Eight roles, and adding a ninth is a decision that goes in the design document
/// first. Four sizes carry them: 22 and 17 for the two headings, 16 for
/// prose, 14 for everything in the chrome, and 11 for the one thing that is
/// recognized rather than read (D-139).
enum TextRole: String, CaseIterable, Sendable {
    /// 22/semibold. The one line that names a screen: an empty state, an
    /// overlay's heading.
    case title
    /// 17/semibold. A section inside one of those.
    case heading
    /// 16/regular. Prose meant to be read as sentences. Nothing in the chrome
    /// uses it; 16 is the body floor and the chrome is not body.
    case body
    /// 14/regular, primary. A control's own word: a caption under an icon, a
    /// row in a list, a chip's text. The thing you click or the thing it says
    /// it will do.
    case label
    /// 14/regular, secondary. A fact the app is reporting and nobody clicks:
    /// "1 of 8", the name of what the next command will act on, a photo count.
    case readout
    /// 14/regular, tertiary. Punctuation and the edges of the range: a
    /// separator between crumbs, a disabled control, the key column in the info
    /// panel. Never a sentence.
    case quiet
    /// 14/semibold, primary. One thing at a time leads its row — the open
    /// folder in the path. Weight rather than size, so the row keeps its height.
    case strong
    /// 14/monospaced, primary. Values that line up in a column or that a person
    /// will compare character by character: a path, an exposure, a filename in
    /// a list of filenames. Monospace is for data, never for prose (DESIGN).
    case data
    /// 11/regular, secondary. The word under an action icon, and the only
    /// text in the app under the 14pt readability floor. It names the drawing
    /// above it once; the tooltip and the accessibility label carry the same
    /// word, so nothing depends on reading it. Never a sentence, never a
    /// control's only name (D-139).
    case caption

    var font: Font {
        switch self {
        case .title: Tokens.Font.title
        case .heading: Tokens.Font.heading
        case .body: Tokens.Font.body
        case .label, .readout, .quiet: Tokens.Font.ui
        case .strong: Tokens.Font.uiStrong
        case .data: Tokens.Font.data
        case .caption: Tokens.Font.caption
        }
    }

    /// What the text is when nothing is hovering it and nothing has disabled
    /// it. A control that changes color on hover passes the hovered color to
    /// `textStyle(_:color:)` rather than reaching for a second role.
    var color: Color {
        switch self {
        case .title, .heading, .body, .label, .strong, .data: Tokens.Text.primary
        case .readout, .caption: Tokens.Text.secondary
        case .quiet: Tokens.Text.tertiary
        }
    }
}

extension View {
    /// The only way text gets a size in this app. `color` overrides the role's
    /// resting color for a control that reacts to the pointer; it does not
    /// change what the text *is*, which is why the role is still named.
    /// `.heading` also carries the trait, rather than each call site
    /// remembering to. The eleven headings in the app had a size and a weight
    /// and nothing a screen reader could find: VoiceOver's rotor and its
    /// heading jump look for `.isHeader`, and in a list of 89 bindings that
    /// jump is how somebody gets around. A role that says "this is a heading"
    /// is the place to say it once — the twelfth heading inherits it, which a
    /// convention would not have given it (D-338).
    func textStyle(_ role: TextRole, color: Color? = nil) -> some View {
        font(role.font)
            .foregroundStyle(color ?? role.color)
            .accessibilityAddTraits(role == .heading ? [.isHeader] : [])
    }
}
