import SwiftUI

/// Ten sliders beside the photograph, in the two groups Lightroom names them
/// in (D-161, D-230).
///
/// The rows are built from `Adjustments.Knob.Group` rather than written out, so
/// an eleventh knob is a case in that enum and a line in the design document. Nothing
/// here knows what a knob means or which group it belongs to.
///
/// Each row's number is that row's reset: the readout is the control (D-154),
/// which is what keeps a per-slider "back to zero" from being ten more buttons.
///
/// The sliders scroll and the heading and the saves do not. Ten rows do not fit
/// a 360pt window, which is as short as the preview goes, and a panel whose
/// `Save changes` button is below the bottom edge is a panel with no way to
/// finish (D-230). Six rows did not fit either; the scroll is a fix for what
/// was already there.
@MainActor
struct AdjustPanel: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s24) {
            // Reset sits on the heading's row rather than with the saves. It
            // belongs to the sliders as a group, which is what a control at the
            // end of a section heading says, and the row underneath is then the
            // two ways of saving rather than three things of three different
            // weights.
            //
            // No sentence under the heading. It said what the two buttons at
            // the foot of the panel already say on themselves and in their
            // tooltips, and instructions that repeat the controls are what a
            // reader learns to skip (D-166).
            HStack(spacing: Tokens.Space.s8) {
                Text("Adjust")
                    .textStyle(.heading)
                Spacer()
                WordButton(title: "Reset", hint: "Every slider back to 0") {
                    store.adjustments = .neutral
                }
                .disabled(store.adjustments.isNeutral)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Tokens.Space.s24) {
                    ForEach(Adjustments.Knob.Group.allCases) { group in
                        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
                            // A group name is a heading for the block under it,
                            // not a label over the panel's own heading, so it
                            // is set in `label` at the panel's ink rather than
                            // as small uppercase over `Adjust`.
                            Text(group.rawValue)
                                .textStyle(.strong)
                            VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                                ForEach(group.knobs) { knob in
                                    row(knob)
                                }
                            }
                        }
                    }
                }
                // The scroll view clips at its own edge, so the column needs
                // the panel's inset back on the side the indicator lands on.
                .padding(.trailing, Tokens.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)

            // Under the sliders rather than at the foot of the window. Pushed
            // to the bottom by a spacer it sat level with the filmstrip and
            // read as belonging to it: space is the hierarchy, and the two
            // things these buttons act on are directly above them.
            // On its own row rather than in with the two saves. Only for a
            // photograph that has an original kept beside it — absence is a
            // state, and a permanently grayed Revert would say nothing about
            // which photographs can be put back (D-165) — and three buttons
            // across 248 points wrapped "Save a copy" onto two lines.
            if store.adjustRevertable {
                WordButton(title: "Revert",
                           hint: "Show the original of \(name), before the adjustment (⇧R)") {
                    router.perform(.revertToOriginal)
                }
            }

            HStack(spacing: Tokens.Space.s12) {
                Spacer()
                // The copy is the occasional one now, so it is a plain word.
                // It used to be the boxed one because it was the save that
                // could not lose anything; since D-165 neither can, and the
                // weighting follows what people actually reach for rather than
                // what used to be the safer bet.
                WordButton(title: "Save a copy",
                           hint: store.adjustments.isNeutral
                               ? "Move a slider first"
                               : "Write an adjusted copy beside \(name) (Return)") {
                    router.perform(.confirm)
                }
                .disabled(store.adjustments.isNeutral)
                // Enabled against what the photograph already carries rather
                // than against zero: reopening an adjusted frame and writing
                // the same six numbers over it again is work with no result,
                // and zeroing them is a revert rather than nothing (D-165).
                BoxedButton(title: "Save changes",
                            hint: saveChangesHint,
                            enabled: store.adjustments != store.adjustBaseline) {
                    router.perform(.saveOverOriginal)
                }
            }
        }
        .padding(Tokens.Space.s16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tokens.Surface.chrome)
        .accessibilityElement(children: .contain)
        // The summary as well as the word, so a screen reader landing on the
        // panel is told what is set without walking six rows to find out —
        // and as the value, so moving a slider says the new one (D-343).
        .accessibilityLabel("Adjust")
        .accessibilityValue(store.adjustments.summary)
    }

    /// The file the two save buttons are about, so the tooltip names it rather
    /// than saying "the original" about a photograph nobody has to guess at.
    private var name: String { store.current?.name ?? "this photo" }

    /// What ⇧Return means right now. Zeroed sliders on a photograph with an
    /// original kept take the adjustment off rather than writing a seventh
    /// copy of nothing.
    private var saveChangesHint: String {
        if store.adjustments == store.adjustBaseline {
            return store.adjustments.isNeutral ? "Move a slider first"
                                               : "That is already what is on the file"
        }
        if store.adjustRevertable && store.adjustments.isNeutral {
            return "Take the adjustment off \(name) and put the original back (⇧Return)"
        }
        return "Save the adjustment into \(name), keeping its name and its flags (⇧Return). ⌘Z undoes it, and Revert still does in a later session"
    }

    @ViewBuilder
    private func row(_ knob: Adjustments.Knob) -> some View {
        let value = store.adjustments[knob]
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            HStack(spacing: Tokens.Space.s8) {
                Text(knob.label)
                    .textStyle(.label)
                // The one knob with something to paint. It sits on the row of
                // the slider that acts on what it shows rather than in the bar
                // over the photograph, where it was a word among nine and a
                // long way from the control it belongs to (D-166).
                if knob == .highlights, AppModel.shared.features.isOn(.highlights) {
                    PillToggle(title: "Show blown", isOn: store.showClipping,
                               hint: store.showClipping
                                   ? "Stop painting the blown highlights (h)"
                                   : "Paint the blown highlights on the photo (h)") {
                        router.perform(.toggleClipping)
                    }
                }
                Spacer()
                // Monospaced, because it is a number that changes under a drag
                // and a proportional one would shift the row as it went from
                // +9 to +10. Set, it leads; at 0 it is punctuation.
                Button {
                    store.adjustments[knob] = 0
                } label: {
                    Text(Adjustments.readout(value))
                        .textStyle(.data, color: value == 0 ? Tokens.Text.tertiary : Tokens.Text.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .linkCursor()
                .disabled(value == 0)
                .help("\(knob.label) back to 0")
                .accessibilityLabel("Reset \(knob.label.lowercased())")
            }
            Slider(value: binding(knob), in: Adjustments.Knob.range)
                .controlSize(.small)
                .help(knob.hint)
                .accessibilityLabel(knob.label)
                .accessibilityValue(Adjustments.readout(value))
        }
    }

    /// Written out rather than taken off `@Bindable`, because what a slider
    /// writes goes through `Adjustments`' own subscript, which is where the
    /// clamp to ±100 lives.
    private func binding(_ knob: Adjustments.Knob) -> Binding<Double> {
        Binding(get: { store.adjustments[knob] },
                set: { store.adjustments[knob] = $0 })
    }
}

/// A switch that sits inside a row, drawn as a pill so it reads as pressable.
/// It was a plain word first and read as a label beside a label: two pieces of
/// text on one line, one of them secretly a control (D-166).
///
/// On is a filled pill in the selection tone with the title in the ground's
/// color, off is the panel's own step-up tone — the state is the fill, and
/// the tooltip says what a press would do.
private struct PillToggle: View {
    let title: String
    let isOn: Bool
    let hint: String
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Text(title)
                .textStyle(.label, color: isOn ? Tokens.Surface.chrome : Tokens.Text.secondary)
                .fixedSize()
                .padding(.horizontal, Tokens.Space.s8)
                .padding(.vertical, Tokens.Space.s4)
                .background(isOn ? Tokens.Border.selected : Tokens.Surface.cursor,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .background(Tokens.Surface.raised.opacity(!isOn && hovering ? 1 : 0),
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .linkCursor()
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .help(hint)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
