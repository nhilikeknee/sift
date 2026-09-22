import SwiftUI

/// The controls that act on a photo, in the three places a photo appears: a
/// grid cell, the preview bar, and a context menu. One definition each, because
/// a keep button that behaves differently in the grid and the preview is two
/// features wearing one name (D-47).

// MARK: buttons

/// A drawn icon in a hit target. Muted until the pointer arrives, which is the
/// rule for every icon in the app. A button that is already in the state it
/// sets wears its own color without waiting for the pointer, so the row reads
/// as a state as well as a set of actions.
@MainActor
struct GlyphButton<S: GlyphShape>: View {
    let shape: S
    var size: CGFloat = Tokens.Layout.glyphButton
    var glyphSize: CGFloat = Tokens.Layout.glyph
    let label: String
    let hint: String
    /// The color this control means: keep green, reject red. Nil is a plain
    /// action, which goes to `text.primary` on hover like everything else.
    var tint: Color?
    var isOn = false
    var destructive = false
    /// A control at the end of its range stays in the row and goes quiet, the
    /// way the back arrow does: one that disappears moves everything beside it.
    var enabled = true
    /// Drawn on a photograph rather than on chrome, so the resting and hover
    /// inks come from the over-photo pair instead of the text roles. A
    /// `text.primary` glyph on a near-black scrim is invisible in light mode,
    /// and the scrim is near-black in both themes on purpose (D-120).
    var onPhoto = false
    /// Whether the bar's own keyboard ring is on this control (D-157). Only
    /// the preview bar sets it: a grid of four hundred thumbnails, each with a
    /// heart and a pair of flags, would be twelve hundred stops in a walk
    /// nobody could get through.
    var focused = false
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Group {
                Glyph.draw(shape, size: glyphSize, on: isOn)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            // Not over a photograph: those already sit on a scrim, and a
            // second ground on top of it is two edges for one control (D-184).
            // Not while disabled either, for the reason the back arrow has no
            // fill with nowhere to go.
            .controlFill(hovering: hovering && enabled && !onPhoto,
                         on: isOn && !onPhoto,
                         padded: false)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(color)
        // The pointer says it is a control, the way it already does over a
        // thumbnail (D-75). An icon with no border and no fill is relying on
        // the cursor to say so, and the arrow says nothing (D-137). Not while
        // disabled: a control at the end of its range stays in the row and
        // goes quiet, and a hand over it would promise something.
        .linkCursor(enabled)
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .animation(Tokens.Motion.fast, value: isOn)
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
        .overlay { if focused { ring } }
    }

    private var color: Color {
        guard enabled else { return Tokens.Text.disabled }
        if isOn { return tint ?? (onPhoto ? Tokens.Text.onPhoto : Tokens.Text.primary) }
        if destructive { return hovering ? Tokens.State.reject : restingInk }
        if hovering { return tint ?? (onPhoto ? Tokens.Text.onPhoto : Tokens.Text.primary) }
        return restingInk
    }

    private var restingInk: Color {
        onPhoto ? Tokens.Text.onPhotoQuiet : Tokens.Text.secondary
    }

    /// The bar's keyboard ring. Drawn by the control rather than by AppKit,
    /// for the reason in `CommandRouter.stepBar` (D-157).
    private var ring: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.sm)
            .strokeBorder(Tokens.Border.focus, lineWidth: Tokens.Border.ringWidth)
    }
}

/// An action wanted often enough to name but not often enough for an icon: no
/// border, no fill, just the word. A word that carries a state says so by going
/// to `text.primary` and staying there.
@MainActor
struct WordButton: View {
    let title: String
    let hint: String
    var isOn = false
    /// See `GlyphButton.focused` (D-157).
    var focused = false
    /// A word that destroys something wears the reject red rather than the
    /// ink every other control wears. Red at rest and not only on hover,
    /// unlike the glyph version: a word sitting in a column of paths is read
    /// before it is pointed at, and the pointer arriving is too late to warn
    /// anybody (D-321).
    var destructive = false
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Text(title)
                .textStyle(.label, color: color)
                .fixedSize()
                .padding(.horizontal, Tokens.Space.s4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .linkCursor()
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .help(hint)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
        .overlay { if focused { ring } }
    }

    private var color: Color {
        // Red in both states, with no second red to step up to: the hand the
        // pointer already takes is what says it is a control, and a new token
        // for one word is a token the design document has to carry forever.
        if destructive { return Tokens.State.reject }
        return isOn || hovering ? Tokens.Text.primary : Tokens.Text.secondary
    }

    /// See `GlyphButton.ring` (D-157).
    private var ring: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.sm)
            .strokeBorder(Tokens.Border.focus, lineWidth: Tokens.Border.ringWidth)
    }
}

/// The favorite, as it appears *on* a photograph rather than in a control.
///
/// Set, it is the rose shape and nothing else. The ring it used to wear made a
/// sticker of it, and a color is a stronger separator than an outline anywhere
/// the photograph is not already rose (D-127, amending D-58).
///
/// Not set, it is two keylines and no fill, because an outline is all it has:
/// a near-white one for the photograph and a near-black hairline outside that,
/// for the cell's own letterbox band, which is white in light mode (D-112).
struct FavoriteMark: View {
    var size: CGFloat = Tokens.Layout.favoriteMarkMin
    /// Set: the rose fill, alone. Not set: the keylines alone, the same shape
    /// in the same place, waiting to be filled in (D-73). The control's state,
    /// which is what `on` means everywhere else now (D-177).
    var on = true

    var body: some View {
        Glyph.favoriteMark(size: size, on: on)
            .accessibilityLabel("Favorite")
    }
}

/// The mark, as the control that sets it (D-73). One heart on a photograph: the
/// thing that says a photo is a favorite is the thing you press to make it one.
///
/// Set, it is there at all times, because a favorite has to be findable by
/// sweeping a grid. Not set, it comes up with the pointer — an empty heart on
/// every unfavorited thumbnail is a grid of empty hearts.
struct FavoriteMarkButton: View {
    let ref: PhotoRef
    let subject: String
    var size: CGFloat = Tokens.Layout.favoriteMarkMin
    /// Whether this photo is the one being offered the mark: the pointer is on
    /// it, or the keyboard is (D-105). The mark keeps its own hover for the fill
    /// preview; this one decides whether it is drawn at all.
    var revealed: Bool
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        if ref.favorite || revealed {
            Button(action: act) {
                // The hover fill is the answer to "what will this do", drawn in
                // the place and the color the answer will be.
                FavoriteMark(size: size, on: ref.favorite || hovering)
                    .opacity(ref.favorite || hovering ? 1 : Self.restingOpacity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .linkCursor()
            .onHover { hovering = $0 }
            .animation(Tokens.Motion.fast, value: hovering)
            .animation(Tokens.Motion.fast, value: ref.favorite)
            .transition(.opacity)
            .help(ref.favorite ? "Remove \(subject) from favorites (.)" : "Favorite \(subject) (.)")
            .accessibilityLabel("Favorite")
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(ref.favorite ? "on" : "off")
        }
    }

    /// The empty heart sits back until the pointer is on it, so a hovered cell
    /// is a photograph with an offer on it rather than a photograph with a
    /// white heart stamped on the corner.
    private static let restingOpacity: Double = 0.65
}

/// Who is offered a cell's mark: the photo under the pointer, and the photo
/// the cursor is on, so neither way of moving through a folder has to know the
/// mark exists to find it (D-105).
///
/// Its own type because keep and reject answered to it too, until their pill
/// left the cell (D-170). The heart is the only caller for now, and this stays
/// a type of its own because the pair is coming back to one rule rather than
/// to two.
enum CellOffer {
    /// The heart, which answers at every cell size (D-142). A set heart
    /// is drawn at 96px and always has been, so gating the empty one there
    /// made a control that could be pressed once: clicking it cleared the
    /// favorite, and nothing on the cell could set it again.
    static func offeredMark(hovering: Bool, isCursor: Bool) -> Bool {
        hovering || isCursor
    }
}

// MARK: context menu

/// Right-click on a photo, wherever the photo is drawn. The store and router
/// arrive as properties rather than through the environment, because a menu is
/// presented outside the view tree that would carry them.
struct PhotoMenu: View {
    let ref: PhotoRef
    let store: LibraryStore
    let router: CommandRouter

    /// "3 Photos" when the photo is part of a selection, so a menu item never
    /// understates what it is about to do.
    private var count: Int { store.targets(for: ref).count }
    private var subject: String { count == 1 ? "" : " \(count) Photos" }

    private func command(for color: ColorLabel) -> Command {
        switch color {
        case .red: .labelRed
        case .yellow: .labelYellow
        case .green: .labelGreen
        case .blue: .labelBlue
        case .purple: .labelPurple
        }
    }

    var body: some View {
        Group {
            Button("Open in Preview") { router.perform(.enterSingle, on: ref) }
            Divider()
            Button(ref.flag == .keep ? "Clear Flag" : "Flag Keep") {
                router.perform(ref.flag == .keep ? .unflag : .flagKeep, on: ref)
            }
            Button(ref.flag == .reject ? "Clear Flag" : "Flag Reject") {
                router.perform(ref.flag == .reject ? .unflag : .flagReject, on: ref)
            }
            Button(ref.favorite ? "Remove\(subject) from Favorites" : "Favorite\(subject)") {
                router.perform(.toggleFavorite, on: ref)
            }
            Menu("Color Label") {
                ForEach(ColorLabel.allCases, id: \.self) { color in
                    Button(ref.label == color ? "\(color.rawValue) ✓" : color.rawValue) {
                        router.perform(command(for: color), on: ref)
                    }
                }
                Divider()
                Button("None") { router.perform(.clearLabel, on: ref) }
            }
            Divider()
            Button("Rotate\(subject) Clockwise") { router.perform(.rotateCW, on: ref) }
            Button("Rotate\(subject) Counterclockwise") { router.perform(.rotateCCW, on: ref) }
            Button(count == 1 ? "Rename…" : "Batch Rename \(count) Photos…") {
                router.perform(count == 1 ? .rename : .batchRename, on: ref)
            }
            Button("Move\(subject) to Folder…") { router.perform(.moveToFolder, on: ref) }
            // Beside Move, because the two are a pair and Move has been here
            // since D-72 while this one had only a key and the toolbar. With
            // the toolbar icon gone by default that left `⇧C` as the whole of
            // it, which is the rule about a shortcut never being the only way
            // in, broken by a decision about a different control (D-347).
            Button("Copy\(subject) to Folder…") { router.perform(.copyToFolder, on: ref) }
            // Beside Move, because the two are a pair and Move has been here
            // since D-72 while this one had only a key and the toolbar. With
            // the toolbar icon gone by default that left `⇧C` as the whole of
            // it, which is the rule about a shortcut never being the only way
            // in, broken by a decision about a different control (D-347).
            if let last = Preferences.lastMoveFolder {
                Button("Move\(subject) to \(last.lastPathComponent)") { router.perform(.moveToLastFolder, on: ref) }
            }
            Divider()
            // The platform's own share sheet: AirDrop, Messages, Mail, Add to
            // Photos, and whatever else the reader has turned on in Settings.
            // A photo app without one is the gap a Mac user notices first
            // (D-211).
            ShareLink(items: store.targets(for: ref).map(\.url)) {
                Text(count == 1 ? "Share…" : "Share \(count) Photos…")
            }
            Button("Reveal in Finder") { router.perform(.revealInFinder, on: ref) }
            Button("Copy") { router.perform(.copy, on: ref) }
            // The file, the picture and the name are three different things to
            // want out of a photograph, and Copy only ever answered the first
            // (D-281).
            Button(count == 1 ? "Copy Image" : "Copy \(count) Images") { router.perform(.copyImage, on: ref) }
            Button(count == 1 ? "Copy Image Name" : "Copy \(count) Image Names") {
                router.perform(.copyName, on: ref)
            }
            Button("Open in Default App") { router.perform(.openWith, on: ref) }
            Divider()
            Button("Move\(subject) to Trash") { router.perform(.trash, on: ref) }
        }
    }

}

/// The keep / reject mark, in the four places a flag appears: the grid cell,
/// the filmstrip frame, the preview's tag row and its bar (D-192).
///
/// It used to be `Circle().fill(flag == .keep ? keep : reject)`, written out at
/// each of them — a disc whose only difference was hue. Green against red is
/// the one pair roughly six percent of men cannot separate, spent on the single
/// fact this app exists to record, and macOS has a setting called Differentiate
/// Without Color precisely because a mark like that is not a mark. It was also
/// the same disc a green color label draws, sitting four points away from it.
///
/// Every culler worth copying carries a shape: Lightroom a flag and a flag with
/// an X, Photo Mechanic a number. So the shape says which it is and the hue
/// agrees with the shape — a check in the disc for keep, a cross for reject —
/// and the color labels keep the plain disc to themselves.
///
/// The disc and the mark in it are one symbol, drawn by `Glyph.flagMark`. This
/// view is where it goes and how big; nothing here draws it (D-226).
struct FlagMark: View {
    let flag: Flag
    /// The disc's edge. The mark takes its size from the surface it is drawn
    /// on, the way the heart already did: 12 beside a filename or on a
    /// thumbnail, 20 on the photograph that fills the preview window, where
    /// the heart is 32 and a 12pt disc was a full stop next to it (D-225).
    var size: CGFloat = Tokens.Layout.flagBadgeMin

    var body: some View {
        Glyph.flagMark(size: size, keep: flag == .keep)
            // The mark is the flag; keep and reject are the two it can say.
            // A branching label is a value wearing the wrong name (D-343).
            .accessibilityLabel("Flag")
            .accessibilityValue(flag == .keep ? "Keep" : "Reject")
    }
}

/// The color label, drawn as the disc Finder draws for the same tag.
///
/// One view rather than the two copies the grid and the preview each kept,
/// which is what let the same wrong label sit in both: the color was the
/// whole of what the mark says and it was said as an identity (D-343).
struct LabelDot: View {
    let label: ColorLabel

    var body: some View {
        Circle()
            .fill(Tokens.State.label(label))
            .frame(width: Tokens.Space.s12, height: Tokens.Space.s12)
            .accessibilityLabel("Label")
            .accessibilityValue(label.rawValue)
    }
}

/// The action a panel or a bar is for, drawn as a button rather than as a word.
/// One box, never two in the same place: a second one beside it would make the
/// reader price both before choosing (D-165). The adjust panel's **Save
/// changes**, the crop bar's and the revert bar's are the ones that have earned one
/// (D-238).
@MainActor
struct BoxedButton: View {
    let title: String
    let hint: String
    let enabled: Bool
    /// Whether a bar's keyboard ring is on this control (D-157, D-245).
    var focused = false
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Text(title)
                .textStyle(.strong, color: enabled ? Tokens.Text.primary : Tokens.Text.tertiary)
                .padding(.horizontal, Tokens.Space.s12)
                .padding(.vertical, Tokens.Space.s8)
                // `bg.cursor`, which is the tone this app already uses for
                // "the thing the keyboard is on", and a step off the panel's
                // ground in both palettes: 13 below `bg.chrome` in light, 18
                // above it in dark. `bg.canvas` was the first try and is white
                // in light, which is the same white as the letterbox band
                // behind the photograph on the other side of the panel edge.
                // Hover lights it with the reader's own accent rather than
                // with a second gray (D-115).
                .background(Tokens.Surface.cursor, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .background(Tokens.Surface.selected.opacity(enabled && hovering ? 1 : 0),
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .linkCursor()
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .help(hint)
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .strokeBorder(Tokens.Border.focus, lineWidth: Tokens.Border.ringWidth)
            }
        }
    }
}
