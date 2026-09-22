import SwiftUI

/// The app's icons, named rather than drawn. Every one of them is an SF Symbol,
/// which is to say a glyph in a font macOS already has: nothing is imported,
/// nothing is vendored, and the build stays dependency-free (D-198).
///
/// They were hand-drawn for most of the app's life, and the reason given was
/// that twenty-two shapes did not justify a symbol set. That was the wrong
/// measure. Sift sits in a row with Finder, Preview and Photos, and a folder
/// that is nearly the system's folder is worse than either the system's folder
/// or something plainly its own. The set also brings what hand-drawing kept
/// costing: one optical size per point size, a weight axis that tracks the text
/// beside it, a filled twin for the marks that have a state, and a name a
/// screen reader already knows.
///
/// A mark is a name plus, where the control has a state, the name it takes
/// while that state is on. Nothing here is a `Shape` any more, so no call site
/// can choose a stroke, a weight or a fill: it asks for the mark and the system
/// draws it (D-177 kept, by a different mechanism).
protocol GlyphShape: Sendable {
    /// The symbol this mark is, as the system names it.
    var symbol: String { get }
    /// The symbol the same mark becomes while its control is *on*. The filled
    /// twin where the set has one. Most marks have no state and return their
    /// own name, which is what makes `on:` a no-op rather than a second icon.
    var onSymbol: String { get }
}

extension GlyphShape {
    /// Unchanged by state unless the mark says otherwise.
    var onSymbol: String { symbol }
}

enum Glyph {
    /// Points into the folder below this crumb. Rotated by the caller when it
    /// needs to point down.
    struct Chevron: GlyphShape { let symbol = "chevron.right" }

    /// Copy the path: the pasteboard's own picture of itself.
    struct Copy: GlyphShape { let symbol = "doc.on.doc" }

    /// A folder, for the places a folder stands in for a photo.
    struct Folder: GlyphShape { let symbol = "folder" }

    /// The photo turning. `rotate.right` and `rotate.left` are a real pair in
    /// the set, so the counterclockwise twin is its own symbol rather than the
    /// clockwise one flipped: mirroring a symbol that has a counterpart is the
    /// one thing Apple asks you not to do with them, and it used to be a
    /// `mirrored: true` carried through three view types to reach a
    /// `scaleEffect` (D-198).
    struct Rotate: GlyphShape {
        var clockwise = true
        var symbol: String { clockwise ? "rotate.right" : "rotate.left" }
    }

    /// The crop box: the set's own mark for it, two corner brackets crossing.
    /// It was the word "Crop" alone in a row of icons with captions under them,
    /// which made one control in the bar look like a different kind of thing
    /// from the two rotations beside it. `crop.rotate` is the other candidate
    /// and is the wrong one here: it carries a turning arrow, and the two
    /// controls immediately to its left are the turns.
    struct Crop: GlyphShape { let symbol = "crop" }

    /// Which way up the crop ratio stands, and the control that turns it: a
    /// landscape box while it is lying down, a portrait one while it is
    /// standing up. The state is in the mark rather than in `on:`, the way the
    /// sidebar's is — the shape *is* the fact, so the mark you look at is the
    /// thing you press (D-183, D-238).
    struct Standing: GlyphShape {
        var turned: Bool
        var symbol: String { turned ? "rectangle.portrait" : "rectangle" }
    }

    /// Move: into a folder. The set has no folder-with-an-arrow — `folder.badge`
    /// exists in five variants and none of them is a move — so this is the
    /// badge that says something arrives in the folder. The caption under it
    /// says "Move", and the caption is never optional here.
    struct MoveToFolder: GlyphShape { let symbol = "folder.badge.plus" }

    /// Rename.
    struct Pencil: GlyphShape { let symbol = "pencil" }

    /// Add.
    struct Plus: GlyphShape { let symbol = "plus" }

    /// Move to Trash. The system's bin, which is the one the reader has already
    /// been taught by the Dock.
    struct Trash: GlyphShape { let symbol = "trash" }

    /// The adjust panel, as a picture.
    struct Sliders: GlyphShape { let symbol = "slider.horizontal.3" }

    /// The file facts.
    struct Info: GlyphShape { let symbol = "info.circle" }

    /// Back and forward, and deliberately not the chevron the breadcrumb uses:
    /// the two sit a few pixels apart in the same row, and one mark for both
    /// made the path look like it had four separators (D-138). Points left; the
    /// caller rotates it for forward.
    struct Arrow: GlyphShape { let symbol = "arrow.left" }

    /// Settings. `gearshape` rather than `gear`: it is the one the platform's
    /// own settings windows use.
    struct Gear: GlyphShape { let symbol = "gearshape" }

    /// Help. Circled, because that is what a help control is on this platform,
    /// and the row it sits in has the gear beside it for company.
    struct Question: GlyphShape { let symbol = "questionmark.circle" }

    /// Keep. A tick, not a filled badge: the cell already carries a colored dot
    /// for the flag, and a second filled mark beside it would read as two states.
    struct Check: GlyphShape { let symbol = "checkmark" }

    /// Reject, and the clear mark on a chip. One shape for both: dismissing a
    /// filter and rejecting a frame are the same gesture at two sizes.
    struct Cross: GlyphShape { let symbol = "xmark" }

    /// Put this folder on the pinned list. The cross beside it takes one off,
    /// and the pair is what makes pinning reachable without a right-click now
    /// that the Pinned section has no `+` of its own (D-327).
    struct Pin: GlyphShape { let symbol = "pin" }

    /// Take this folder off the pinned list. A pin with a stroke through it,
    /// and not `Cross`, which is what it used to be: a cross in this app
    /// rejects a frame and clears a filter, and one sitting at the end of a
    /// folder row beside a photo count reads as "delete this folder" — which
    /// is the one thing the sidebar cannot do. Both rows draw a pin now, and
    /// the stroke is the verb.
    ///
    /// The verb rather than the state: the mark says what the press will do,
    /// which is what makes `Pin` and `Unpin` one pair of controls instead of
    /// one control with a fill on it.
    struct Unpin: GlyphShape { let symbol = "pin.slash" }

    /// The decision as a mark on a photograph: the tick or the cross in its own
    /// disc. `Check` and `Cross` are the bare marks, for a chip and a menu; this
    /// is the badge, and it is one symbol rather than the two stacked on a
    /// `Circle()` that it used to be (D-226).
    struct FlagBadge: GlyphShape {
        var keep = true
        var symbol: String { keep ? "checkmark.circle.fill" : "xmark.circle.fill" }
    }

    /// Favorite: hollow while the folder is whole, solid while it is narrowed
    /// to the favorites. The fill is the set's own twin rather than this shape
    /// painted in (D-177). It was the only mark with a state until `AnchorA`
    /// joined it (D-268).
    struct Heart: GlyphShape {
        let symbol = "heart"
        let onSymbol = "heart.fill"
    }

    /// Compare's anchor, and whether this photograph is it. The letter, because
    /// the grid already badges the anchored cell with an `A` and the bar has to
    /// agree with it; the square rather than the circle, because `info.circle`
    /// sits two controls away and a circled letter joins that family instead of
    /// this one. Hollow until this frame is A, solid once it is: the set's own
    /// twin, the way `Heart` does it (D-268).
    struct AnchorA: GlyphShape {
        let symbol = "a.square"
        let onSymbol = "a.square.fill"
    }

    /// The flip between A and whatever the cursor is on. Two arrows passing,
    /// which is the one candidate that reads as a swap: the looping ones say
    /// repeat, and a reader guesses refresh before they guess compare (D-268).
    struct Flip: GlyphShape { let symbol = "arrow.left.arrow.right" }

    /// Both frames at once: a frame divided down the middle. Landscape rather
    /// than the portrait split, because the mark says *two panes* and must not
    /// also claim which way up the photographs are (D-268).
    struct SideBySide: GlyphShape { let symbol = "rectangle.split.2x1" }

    /// The thumbnail size control: the same square count the grid is about to
    /// show. Three across means smaller cells, two across means larger, so the
    /// icon is a picture of the result rather than a plus and a minus.
    struct Thumbs: GlyphShape {
        var across = 3
        var symbol: String { across >= 3 ? "square.grid.3x3" : "square.grid.2x2" }
    }

    /// Sort. The vertical pair, which is the platform's sort mark; the
    /// horizontal `Arrow` beside it in the same row is the history, and the two
    /// do not read as each other at 20pt.
    /// Sort. Lines of decreasing length with an arrow beside them, rather
    /// than the bare `arrow.up.arrow.down` it was: two loose arrows say
    /// "swap" as readily as "sort", and the rows are what make it a list
    /// being ordered. The arrow also gives the control somewhere to say which
    /// way round it currently is, if that is ever wanted (D-358).
    struct SortBars: GlyphShape { let symbol = "arrow.up.and.down.text.horizontal" }

    /// Light is on.
    struct Sun: GlyphShape { let symbol = "sun.max" }

    /// Dark is on.
    struct Moon: GlyphShape { let symbol = "moon" }

    /// Undo, and put a reassigned key back. It was the rotation arrow flipped,
    /// which was defensible while the rotation was a bare curved arrow drawn
    /// here. It is not any more: `rotate.left` has a picture frame in it,
    /// rotating a photograph left is a real command in this app, and the undo
    /// control would have started saying it (D-198).
    struct Revert: GlyphShape { let symbol = "arrow.uturn.backward" }

    /// Search.
    struct Magnifier: GlyphShape { let symbol = "magnifyingglass" }

    /// The folder list, and whether it is up. The state is in the mark rather
    /// than in `on:`, because the set has no filled `sidebar.left` and filling
    /// the whole box would say nothing anyway: the leading column is a block of
    /// ink while the list is on screen and a stack of rules while it is away,
    /// so the mark you look at is the thing you press (D-183). Three quarters
    /// ink against a half, measured, because "it looks different" is not a
    /// readout.
    struct Sidebar: GlyphShape {
        var showing: Bool
        var symbol: String {
            showing ? "rectangle.leadingthird.inset.filled" : "sidebar.left"
        }
    }

    /// Every mark in the set, once each, and both settings of the two that
    /// take one. A name is a string, and a string that stops resolving draws
    /// nothing rather than failing: an icon that has silently become an empty
    /// box is invisible to every test that looks at layout. This is the list
    /// the suite walks, and a second test counts the declarations in this file
    /// against it so a mark added below cannot skip it.
    static let everyMark: [any GlyphShape & Sendable] = [
        Chevron(), Copy(), Folder(), Rotate(clockwise: true), Rotate(clockwise: false),
        MoveToFolder(), Pencil(), Plus(), Trash(), Sliders(), Info(), Arrow(),
        Crop(), Standing(turned: true), Standing(turned: false),
        Gear(), Question(), Check(), Cross(), Pin(), Unpin(), FlagBadge(keep: true), FlagBadge(keep: false),
        Heart(), AnchorA(), Flip(), SideBySide(), Thumbs(across: 2),
        Thumbs(across: 3), SortBars(), Sun(), Moon(), Revert(), Magnifier(),
        Sidebar(showing: true), Sidebar(showing: false),
    ]

    /// The names those marks resolve to, in both states, with the duplicates
    /// the state-less ones contribute removed.
    static var everySymbol: [String] {
        Array(Set(everyMark.flatMap { [$0.symbol, $0.onSymbol] })).sorted()
    }

    /// The favorite over a photograph, which is the one mark that cannot be
    /// drawn the way the rest are (D-73). It is not in a control's box, it
    /// lands on whatever the photograph happens to be, and a fill alone will
    /// vanish against something — so the empty mark carries its own keyline in
    /// a color no photograph can match.
    ///
    /// It was a traced Instagram heart stroked twice, at 3 under 4.5, because
    /// there was no other way to get two widths out of one path. It is the same
    /// two strokes: `heart` in the near-black, `favoriteKeylineScale` bigger,
    /// under `heart` in the near-white, and the rim is what the bigger one
    /// leaves showing. Set, it is `heart.fill` in the rose and no ring at all,
    /// which is the same D-127 as before — that red is its own separation from
    /// almost any photograph, and a white edge around it read as a sticker
    /// laid on the picture (D-200).
    static func favoriteMark(size: CGFloat, on: Bool) -> some View {
        ZStack {
            if on {
                Image(systemName: "heart.fill")
                    // design-system:allow — the step through the same extent
                    // table every other mark goes through.
                    .font(.system(size: pointSize(for: "heart.fill", at: size)))
                    .foregroundStyle(Tokens.State.favorite)
            } else {
                Image(systemName: "heart")
                    // design-system:allow — as above.
                    .font(.system(size: pointSize(for: "heart", at: size)))
                    .foregroundStyle(Tokens.State.favoriteKeylineShadow)
                    .scaleEffect(Tokens.Layout.favoriteKeylineScale)
                Image(systemName: "heart")
                    // design-system:allow — as above.
                    .font(.system(size: pointSize(for: "heart", at: size)))
                    .foregroundStyle(Tokens.State.favoriteKeyline)
            }
        }
        .frame(width: size, height: size)
    }

    /// The decision over a photograph, and the other mark that cannot be drawn
    /// the way the rest are: it lands on the picture rather than in a control's
    /// box, so it is the disc that carries it and not a box around it.
    ///
    /// One symbol. It was a `Circle().fill` with `checkmark` laid over it at two
    /// thirds and a white ring drawn round the outside, which is three parts
    /// fitted to each other by hand: the tick's weight and its center were ours
    /// to pick and we picked them, so it sat high and thin in a disc it was
    /// never cut for. `checkmark.circle.fill` is the same two shapes cut
    /// together by the people who drew both, at every optical size.
    ///
    /// The ring is gone with the stacking. It is the sticker D-127 took off the
    /// heart, for the same reason: keep-green and reject-red are their own
    /// separation from almost any photograph, and a white edge round a
    /// saturated disc reads as something laid on the picture rather than
    /// something said about it (D-226).
    static func flagMark(size: CGFloat, keep: Bool) -> some View {
        let name = FlagBadge(keep: keep).symbol
        return Image(systemName: name)
            // design-system:allow — the step through the same extent table
            // every other mark goes through.
            .font(.system(size: pointSize(for: name, at: size)))
            // The tick and the disc are two layers of one symbol, which is what
            // lets the mark be knocked out of the color rather than drawn on
            // top of it.
            .symbolRenderingMode(.palette)
            .foregroundStyle(Tokens.State.favoriteKeyline,
                             keep ? Tokens.State.keep : Tokens.State.reject)
            .frame(width: size, height: size)
    }

    /// How much of its own point size each symbol's ink actually takes, on its
    /// larger side. This is the number that makes a row of them read as one
    /// size, and it is a fact about the set rather than a decision: `xmark`
    /// covers 0.81 of its point size and `folder.badge.plus` covers 1.35, so a
    /// row drawn at one point size is a row of marks whose drawn sizes differ
    /// by two thirds. Dividing the step by this puts every mark's bounding box
    /// on the step, which is what the hand-drawn glyphs did by construction —
    /// each one was a path in a unit rect — and what the three-step scale has
    /// always claimed (D-201).
    ///
    /// Measured, not guessed: `GlyphExtentTests` renders each symbol and fails
    /// if a number here is wrong by more than a fortieth, which is also what
    /// catches the set changing under a macOS update.
    private static let extent: [String: CGFloat] = [
        "a.square": 0.94,
        "a.square.fill": 0.94,
        "arrow.left": 0.94,
        "arrow.left.arrow.right": 1.21,
        "arrow.up.arrow.down": 1.15,
        "arrow.up.and.down.text.horizontal": 1.3083,
        "arrow.uturn.backward": 0.96,
        "checkmark": 0.88,
        "checkmark.circle.fill": 1.03,
        "chevron.right": 0.87,
        "crop": 1.11,
        "doc.on.doc": 1.28,
        "folder": 1.15,
        "folder.badge.plus": 1.35,
        "gearshape": 1.09,
        "heart": 1.00,
        "heart.fill": 1.00,
        "info.circle": 1.03,
        "magnifyingglass": 1.00,
        "moon": 1.03,
        "pencil": 0.83,
        "pin": 1.16,
        "pin.slash": 1.16,
        "plus": 0.87,
        "questionmark.circle": 1.03,
        "rectangle": 1.20,
        "rectangle.leadingthird.inset.filled": 1.20,
        "rectangle.portrait": 1.08,
        "rectangle.split.2x1": 1.20,
        "rotate.left": 1.12,
        "rotate.right": 1.12,
        "sidebar.left": 1.20,
        "slider.horizontal.3": 1.00,
        "square.grid.2x2": 0.94,
        "square.grid.3x3": 1.01,
        "sun.max": 1.11,
        "trash": 1.13,
        "xmark": 0.81,
        "xmark.circle.fill": 1.03,
    ]

    /// The point size that draws `name` at `size`. A mark the table has never
    /// heard of falls back to its own point size, which is the old behavior
    /// and is wrong by at most a fifth — a missing row is caught by a test, not
    /// by a blank space on screen.
    static func pointSize(for name: String, at size: CGFloat) -> CGFloat {
        size / (extent[name] ?? 1)
    }

    /// The one way a mark is drawn. `size` is the step: the box the mark's ink
    /// fills, not the point size it is asked for. Those were the same number
    /// until 2026-09-17, and the row went ragged — the centers all agreed and
    /// nothing else did, because at one point size these symbols are drawn at
    /// sizes that differ by two thirds (D-201).
    ///
    /// `on` is the control's state, and the only thing that can swap a mark for
    /// its filled twin. A mark with no twin ignores it (D-177).
    static func draw<S: GlyphShape>(_ shape: S, size: CGFloat = Tokens.Layout.glyph,
                                    on: Bool = false) -> some View {
        let name = on ? shape.onSymbol : shape.symbol
        return Image(systemName: name)
            // design-system:allow — a symbol's point size, which is the step
            // divided by how much of it that symbol's ink covers. No text role
            // applies to a symbol.
            .font(.system(size: pointSize(for: name, at: size)))
            .frame(width: size, height: size)
    }
}
