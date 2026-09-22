import SwiftUI

/// What is on screen while a crop is being dragged (D-238).
///
/// The preview bar is away for as long as the mode runs — it always has been,
/// because its twelve controls are about the photograph and this is about the
/// box — and until now nothing took its place: the shape the box was held to
/// could not be chosen at all, and the two keys that finish a crop were written
/// into a tag in the corner. A bar that arrives with the state it belongs to is
/// the pattern the rest of the window already uses.
///
/// Two rows rather than one. The preview goes down to 640pt wide and the row of
/// ratios alone is most of that, so a single row would need a ladder of its own
/// to say the same six words; the ratios are what the mode is for and the saves
/// are how it ends, which is a division the reader can see.
@MainActor
struct CropBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some View {
        FloatingBar(label: "Crop controls") {
            // Centered, not leading: the saves are a shorter row than the six
            // ratios above them, and a ragged right edge on a floating pill
            // reads as an accident. Stretching the second row to match would
            // stretch the bar to the window.
            VStack(alignment: .center, spacing: Tokens.Space.s8) {
                // `layout.glyphButton` tall whether the turn control is drawn
                // or not. The words are shorter than a 28pt hit target, so the
                // bar grew and shrank by six points as the ratio changed — a
                // control moving under the pointer that is about to press it
                // (D-241).
                HStack(spacing: Tokens.Space.s4) {
                    ForEach(CropRatio.allCases) { ratio in
                        WordButton(title: ratio.label,
                                   hint: hint(for: ratio),
                                   isOn: store.cropRatio == ratio,
                                   focused: store.modeBarCursor == .ratio(ratio)) {
                            router.pressModeBar(.ratio(ratio))
                        }
                    }
                    // The mark is the state: a box lying down while the ratio
                    // is, standing up while it is stood up. Pressing it turns
                    // the ratio over, which is the one thing it can do (D-238).
                    //
                    // Away entirely for the two shapes that cannot be turned —
                    // a square is a square both ways up and a free crop has no
                    // shape to turn — rather than grayed. Absence is a state,
                    // and a permanently disabled mark in a row of words reads
                    // as a stray one.
                    if store.cropRatio.canTurn {
                        GlyphButton(shape: Glyph.Standing(turned: store.cropRatioTurned),
                                    size: Tokens.Layout.glyphButton,
                                    glyphSize: Tokens.Layout.glyph,
                                    label: store.cropRatioTurned ? "Ratio standing up" : "Ratio lying down",
                                    hint: store.cropRatioTurned
                                        ? "Lay the ratio back down"
                                        : "Stand the ratio up for a portrait crop",
                                    focused: store.modeBarCursor == .turn) {
                            router.pressModeBar(.turn)
                        }
                        .padding(.leading, Tokens.Space.s4)
                    } else {
                        // The slot stays. The mark goes, because a permanently
                        // disabled one reads as a stray — but a row that
                        // changes width as the ratio changes walks the words
                        // under the pointer that is choosing between them
                        // (D-241).
                        Spacer()
                            .frame(width: Tokens.Layout.glyphButton + Tokens.Space.s4)
                    }
                }
                .frame(height: Tokens.Layout.glyphButton)

                // Hugging its content, like the preview bar it stands in for:
                // a `Spacer` here stretched the whole bar to the window and
                // made a floating control read as a band across the bottom.
                HStack(spacing: Tokens.Space.s12) {
                    // Only for a photograph with an original kept beside it.
                    // Absence is a state: a permanently grayed Revert would say
                    // nothing about which photographs can be put back (D-165).
                    if store.adjustRevertable {
                        WordButton(title: "Revert",
                                   hint: "Show the original of \(name), before anything was written into it (⇧R)",
                                   focused: store.modeBarCursor == .revert) {
                            router.pressModeBar(.revert)
                        }
                    }
                    // Esc is the key, and a mode with no visible way out is a
                    // mode somebody is stuck in. The occasional one, so no box
                    // around it (DESIGN, weighting a row of actions).
                    WordButton(title: "Cancel", hint: "Leave the crop and change nothing (Esc)",
                               focused: store.modeBarCursor == .cancel) {
                        router.pressModeBar(.cancel)
                    }
                    WordButton(title: "Save a copy",
                               hint: hasBox
                                   ? "Write the cropped copy beside \(name) (Return)"
                                   : "Drag a box first",
                               isOn: false,
                               focused: store.modeBarCursor == .saveCopy) {
                        router.pressModeBar(.saveCopy)
                    }
                    .disabled(!hasBox)
                    // The same words the adjust panel's primary carries. The
                    // two modes write into the photograph the same way, and
                    // two names for one thing makes the reader work out
                    // whether they are the same thing (D-240).
                    BoxedButton(title: "Save changes",
                                hint: hasBox
                                    ? "Write the crop into \(name), keeping its name and its flags (⇧Return). ⌘Z undoes it, and Revert still does in a later session"
                                    : "Drag a box first",
                                enabled: hasBox,
                                focused: store.modeBarCursor == .saveOver) {
                        router.pressModeBar(.saveOver)
                    }
                }
            }
        }
    }

    private var hasBox: Bool {
        guard let r = store.cropRect else { return false }
        return r.width > 0.01 && r.height > 0.01
    }

    private var name: String { store.current?.name ?? "this photo" }

    /// What each shape does, said as a shape rather than as a pair of numbers
    /// the label already carries.
    private func hint(for ratio: CropRatio) -> String {
        switch ratio {
        case .free: "Any shape the drag draws"
        case .original: "The photograph's own shape"
        default: "Hold the box to \(ratio.label)"
        }
    }
}
