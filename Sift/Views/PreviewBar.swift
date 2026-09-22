import SwiftUI

/// One control in the preview bar, as data: what it runs, what it draws, and
/// how much air sits in front of it.
///
/// The row is built from these, the keyboard walks these, and the `»` menu
/// lists the ones a rung dropped (D-157, D-158). One list rather than three,
/// because a Tab order that disagrees with the row it is walking is worse than
/// no Tab order at all.
struct BarControl: Identifiable, Sendable {
    enum Glyphs: Sendable { case info, rotateCCW, rotateCW, crop, adjust, trash,
                                 anchorA, flip, sideBySide }
    enum Mark: Sendable {
        case word(String)
        /// An icon with its name under it, at the header's scale. The five
        /// controls the bar has whatever the settings say are drawn this way,
        /// and so is crop, which sits between the two turns and the sliders and
        /// read as another kind of control while it was a bare word (D-169).
        case glyph(Glyphs)
    }

    let command: Command
    let mark: Mark
    let hint: String
    var isOn = false
    /// Air in front of this control. The row's own spacing is zero, so every
    /// gap in the bar is stated here: 8 between controls, and 16 after the bin
    /// at the head of the row, which is what makes it an island (D-169).
    var leadingGap: CGFloat = Tokens.Space.s8
    var id: Command { command }
}

/// A band of the preview bar that can be put away into the overflow menu when
/// the window is too narrow to draw it. Ordered by what is given up first: the
/// modes you leave with Esc before the looks you toggle, the looks before the
/// things done *to* the file, and the file's own commands last (D-158).
///
/// Keep, reject and the bin are on no rung. They are what the window is for,
/// and a bar that gave them up would be a bar with nothing in it.
enum BarPiece: CaseIterable, Hashable {
    /// Survey, tournament, compare, side by side, slideshow: the ways of
    /// looking at more than one photograph, each of which is entered and left
    /// rather than read.
    case modes
    /// Highlights, focus peaking, faces: what is painted on the frame.
    case judging
    /// Crop and adjust: the two modes that end in a file being written. One
    /// band rather than two, because giving up one of them before the other
    /// would be an order nobody could predict — they are the same kind of
    /// thing at the same weight (D-161).
    case editing
    case rotations
    case info

    static let all = Set(BarPiece.allCases)

    /// Widest first. Each rung gives up everything the one before it did and
    /// one band more, so nothing comes back as the window narrows (D-113).
    static let ladder: [Set<BarPiece>] = [
        [],
        [.modes],
        [.modes, .judging],
        [.modes, .judging, .editing],
        [.modes, .judging, .editing, .rotations],
        all,
    ]
}

/// The preview window's controls, over the bottom of the photo, on only while
/// the pointer is in the window (DESIGN exception 2, D-47). Nine of the app's
/// commands lived nowhere but the keyboard before this, and all nine were the
/// ones about judging a frame, which is what the preview window is for.
///
/// Bare has no button here either, for a different reason than the
/// filmstrip: it is a mode you enter with `⇧F` and leave with Esc, so a word
/// saying so the rest of the time is the chrome the mode exists to remove.
/// Its menu item is the on-screen way in (D-126).
///
/// The filmstrip has no button here. It is on by default (D-122), so its
/// control was a word on every photograph saying what the reader could
/// already see at the bottom of the window; `f` and the switch in Settings
/// are the two ways to change it (D-125).
///
/// Cull leads: keep and reject. The favorite is not in the row — it is the
/// heart on the photograph above it, which is the mark and the control at once
/// (D-73). The view toggles follow as plain words,
/// because each carries a state and a word can say which state it is in. The
/// two rotations are glyphs, because they happen rather than persist. Trash is
/// last, past a gap, and red only under the pointer.
@MainActor
struct PreviewBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router
    private let model = AppModel.shared

    let ref: PhotoRef

    var body: some View {
        // Narrower and narrower arrangements, and AppKit takes the first that
        // fits (D-158). The bar used to be one row under
        // `.fixedSize(horizontal: true)`, which meant it kept its full ideal
        // width whatever the window was: eleven words ran off the right edge
        // with no overflow and nothing on screen saying there was more. The
        // fixed size is gone, and the two flexible gaps with it — a `Spacer`
        // would stretch the pill to the window, and a ladder cannot measure a
        // row that always fits.
        // The ground, the blur and the air around them are `FloatingBar`'s:
        // the crop bar is the second thing that floats over the photograph, and
        // two copies of that chrome is where the two start to differ (D-238).
        FloatingBar(label: "Photo controls") {
            ViewThatFits(in: .horizontal) {
                row(putAway: BarPiece.ladder[0])
                row(putAway: BarPiece.ladder[1])
                row(putAway: BarPiece.ladder[2])
                row(putAway: BarPiece.ladder[3])
                row(putAway: BarPiece.ladder[4])
                row(putAway: BarPiece.ladder[5])
            }
        }
    }

    /// The most controls `controls` can return, with every feature on and a
    /// face and an anchor to point at: the bin, the file's facts, focus and
    /// faces, compare's three, survey, tournament and slideshow, the two turns,
    /// and the two editors. The row above is written out to this many, so a
    /// fifteenth control is a decision made here first —
    /// `theBarHasASlotForEveryControl` fails until it is.
    ///
    /// Twelve until 2026-09-18, when compare stopped being one control and
    /// became the three it always had commands for (D-268).
    static let maxControls = 14

    /// One place in the row, or nothing if this rung is drawing fewer controls
    /// than that. The gap belongs to the control, not to the stack: the bin is
    /// an island and everything after it is a band (D-169).
    @ViewBuilder
    private func controlSlot(_ controls: [BarControl], _ i: Int) -> some View {
        if i < controls.count {
            let control = controls[i]
            button(control)
                .padding(.leading, control.leadingGap)
        }
    }

    /// One arrangement, drawn from the same table the keyboard walks and the
    /// `»` menu is built from (D-157, D-158). One list, so a control cannot be
    /// on screen in an order the Tab key disagrees with.
    @ViewBuilder
    private func row(putAway: Set<BarPiece>) -> some View {
        let controls = Self.controls(putAway: putAway, ref: ref, store: store, features: model.features)
        // `.headerLine`, because an icon with its name under it is taller than
        // a word on its own and the row holds both: every control pins the
        // center of its icon to that line, so the captions hang below without
        // dragging the words that have none off center (D-160, D-169).
        HStack(alignment: .headerLine, spacing: 0) {
            // Slots drawn now, not a `ForEach` handed over to be called later.
            // This row is a `ViewThatFits` candidate, and a ladder rebuilds
            // every candidate's list while it measures — a `ForEach` under one
            // is re-materialized on whatever thread the render is on, which on
            // the display link is a dead process (D-195).
            controlSlot(controls, 0)
            controlSlot(controls, 1)
            controlSlot(controls, 2)
            controlSlot(controls, 3)
            controlSlot(controls, 4)
            controlSlot(controls, 5)
            controlSlot(controls, 6)
            controlSlot(controls, 7)
            controlSlot(controls, 8)
            controlSlot(controls, 9)
            controlSlot(controls, 10)
            controlSlot(controls, 11)
            // What the row could not fit goes at the end, with the controls it
            // came from (D-158).
            if !putAway.isEmpty {
                PreviewBarOverflow(putAway: putAway, ref: ref)
                    .padding(.leading, Tokens.Space.s8)
            }
        }
        // The rung that actually drew, so the keyboard walks what is on screen
        // rather than what would be on screen in a wider window (D-157).
        .onAppear { store.barRung = putAway }
        .onChange(of: putAway) { _, now in store.barRung = now }
    }

    @ViewBuilder
    private func button(_ control: BarControl) -> some View {
        let focused = store.barCursor == control.command
        switch control.mark {
        case .word(let title):
            WordButton(title: title, hint: control.hint, isOn: control.isOn, focused: focused) {
                router.perform(control.command, on: ref)
            }
        case .glyph(let glyph):
            // The header's icons, at the header's scale, with the header's
            // caption under them: one definition of "an icon with its name
            // under it" in the app, and the bar reads as the same tool as the
            // window behind it (D-160, D-169).
            switch glyph {
            case .info:
                BarIcon(shape: Glyph.Info(), caption: "Info", label: "File and camera info",
                        hint: control.hint, isOn: control.isOn, focused: focused) {
                    router.perform(.toggleInfo, on: ref)
                }
            case .rotateCCW:
                BarIcon(shape: Glyph.Rotate(clockwise: false), caption: "Rotate",
                        label: "Rotate counterclockwise", hint: control.hint, focused: focused) {
                    router.perform(.rotateCCW, on: ref)
                }
            case .rotateCW:
                BarIcon(shape: Glyph.Rotate(), caption: "Rotate",
                        label: "Rotate clockwise", hint: control.hint, focused: focused) {
                    router.perform(.rotateCW, on: ref)
                }
            case .crop:
                BarIcon(shape: Glyph.Crop(), caption: "Crop",
                        label: "Crop", hint: control.hint, isOn: control.isOn, focused: focused) {
                    router.perform(.crop, on: ref)
                }
            case .adjust:
                BarIcon(shape: Glyph.Sliders(), caption: "Adjust",
                        label: "Adjust", hint: control.hint, isOn: control.isOn, focused: focused) {
                    router.perform(.adjust, on: ref)
                }
            case .trash:
                BarIcon(shape: Glyph.Trash(), caption: "Delete", label: "Move to Trash",
                        hint: control.hint, destructive: true, focused: focused) {
                    router.perform(.trash, on: ref)
                }
            // Compare's three. Icons rather than words, because compare is on
            // by default and three words in a row of icons read as a different
            // kind of control — the thing D-169 fixed for crop (D-268).
            case .anchorA:
                BarIcon(shape: Glyph.AnchorA(), caption: "Mark A",
                        label: control.isOn ? "Clear A" : "Mark this photo as A",
                        hint: control.hint, isOn: control.isOn, focused: focused) {
                    router.perform(.setCompareAnchor, on: ref)
                }
            case .flip:
                BarIcon(shape: Glyph.Flip(), caption: "Flip",
                        label: "Flip between A and this photo",
                        hint: control.hint, isOn: control.isOn, focused: focused) {
                    router.perform(.toggleCompare, on: ref)
                }
            case .sideBySide:
                BarIcon(shape: Glyph.SideBySide(), caption: "Side by side",
                        label: "Show A and this photo side by side",
                        hint: control.hint, isOn: control.isOn, focused: focused) {
                    router.perform(.compareSideBySide, on: ref)
                }
            }
        }
    }

}

/// One of the bar's five permanent controls: the header's icon and caption,
/// with the bar's own keyboard ring and its on-state (D-169).
///
/// Not `ActionButton` itself, which has neither a ring nor a state to be in.
/// The drawing is shared — both go through `HeaderIcon`, which is the only
/// definition of the pairing (D-160) — and what differs is what the preview
/// window's bar needs and the header's row does not.
private struct BarIcon<S: GlyphShape>: View {
    let shape: S
    let caption: String
    let label: String
    let hint: String
    /// A control that carries a state says so by staying lit, the way the
    /// words it replaced did.
    var isOn = false
    var destructive = false
    var focused = false
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            HeaderIcon(shape: shape, caption: caption)
                .foregroundStyle(color)
                .padding(.horizontal, Tokens.Space.s4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .animation(Tokens.Motion.fast, value: isOn)
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .strokeBorder(Tokens.Border.focus, lineWidth: Tokens.Border.ringWidth)
            }
        }
    }

    private var color: Color {
        if isOn { return Tokens.Text.primary }
        if destructive { return hovering ? Tokens.State.reject : Tokens.Text.tertiary }
        return hovering ? Tokens.Text.primary : Tokens.Text.secondary
    }
}

/// What the bar was too narrow to draw. Every band the row gave up comes out
/// of here with something to click, which is the whole promise of the ladder
/// and the thing a test can hold it to (D-158).
private struct PreviewBarOverflow: View {
    let putAway: Set<BarPiece>
    let ref: PhotoRef

    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router
    @State private var hovering = false

    var body: some View {
        if !items().isEmpty {
            PopMenuButton(hint: "What the window is too narrow to show",
                          accessibilityLabel: "More photo controls") {
                items()
            } label: {
                Text("»")
                    .textStyle(.label)
                    .frame(width: Tokens.Layout.glyphButton, height: Tokens.Layout.glyphButton)
                    .contentShape(Rectangle())
                    .foregroundStyle(hovering ? Tokens.Text.primary : Tokens.Text.secondary)
            }
            .onHover { hovering = $0 }
            .animation(Tokens.Motion.fast, value: hovering)
        }
    }

    private func items() -> [PopMenuItem] {
        PreviewBar.rows(putAway: putAway, ref: ref, store: store, router: router,
                        features: AppModel.shared.features)
    }
}

extension PreviewBar {
    /// The bar as it is drawn, left to right, for the rung that fitted. The
    /// keyboard walks exactly this (D-157).
    ///
    /// The bin opens the row and is on no rung, then the file's facts, then
    /// the bands the ladder gives up, then the two turns and the two editors
    /// (D-169). The five that are always there read in the order somebody
    /// works: throw it out, look at it, straighten it, develop it.
    ///
    /// Keep and reject used to lead it and are out for now (D-166), along with
    /// compare's Mark A. Both are keyboard and menu commands still, and both
    /// are coming back to the bar in some form: the PRD's "Known gaps" is
    /// where that is written down rather than here.
    static func controls(putAway: Set<BarPiece>,
                         ref: PhotoRef,
                         store: LibraryStore,
                         features: FeatureSet) -> [BarControl] {
        let subject = store.selected.contains(ref.url) && store.selected.count > 1
            ? "\(store.selected.count) photos" : ref.name
        var out: [BarControl] = [
            BarControl(command: .trash, mark: .glyph(.trash),
                       hint: "Move \(subject) to Trash (d)", leadingGap: 0),
        ]
        if !putAway.contains(.info) {
            out.append(BarControl(command: .toggleInfo, mark: .glyph(.info),
                                  hint: "File, camera and histogram (i)", isOn: store.showInfo))
        }
        if !putAway.contains(.judging) {
            // Highlights is in the adjust panel now, on the row of the slider
            // that acts on what it paints (D-166).
            if features.isOn(.focusPeaking) {
                out.append(BarControl(command: .toggleFocusPeaking, mark: .word("Focus"),
                                      hint: "Paint the edges that are sharp (g)",
                                      isOn: store.showFocusPeaking))
            }
            // Only there when there is a face to go to, because a control that
            // says "no faces in this one" is a control that wasted a press.
            // `⇧Z` looks for them whether or not this is drawn (D-151).
            if features.isOn(.faces), !store.faces.isEmpty {
                out.append(BarControl(command: .zoomToFace,
                                      mark: .word(store.faces.count == 1 ? "Face" : "Faces"),
                                      hint: "Zoom to each face in turn (⇧Z)"))
            }
        }
        if !putAway.contains(.modes) {
            // The Feature switch says whether compare exists at all; this
            // preference says whether it is drawn here, and it is off by
            // default (D-270). With it off the keys and the View menu are
            // the whole story, which is the discoverability rule spent on
            // purpose rather than by accident.
            if features.isOn(.compare), Preferences.compareControlsInBar {
                // All three of compare's commands, in the order they are used:
                // mark one, flip against it, then put the pair side by side.
                // Mark A came back on 2026-09-18 — D-166 took it out pending a
                // rethink and left compare's entry point keyboard-only, so the
                // feature was reachable and un-enterable at the same time.
                //
                // The anchor is always there, because it is how compare starts.
                // The other two appear only once a *second* photograph exists to
                // flip to or sit beside: a control that can only say "nothing
                // marked yet" is a control that wastes the press (D-268).
                let anchored = store.compareAnchor != nil && store.compareAnchor != ref.url
                out.append(BarControl(command: .setCompareAnchor, mark: .glyph(.anchorA),
                                      hint: store.compareAnchor == ref.url
                                          ? "This photo is A; press again to clear it (a)"
                                          : "Mark this photo as A to compare against (a)",
                                      isOn: store.compareAnchor == ref.url))
                if anchored {
                    out.append(BarControl(command: .toggleCompare, mark: .glyph(.flip),
                                          hint: "Flip between A and this photo in place (\\)",
                                          isOn: store.showingCompare))
                    out.append(BarControl(command: .compareSideBySide, mark: .glyph(.sideBySide),
                                          hint: "A and this photo at once, zoom and pan linked (|)",
                                          isOn: store.sideBySide))
                }
            }
            if features.isOn(.survey) {
                out.append(BarControl(command: .survey, mark: .word("Survey"),
                                      hint: "Several at once (v)", isOn: store.surveying))
            }
            if features.isOn(.tournament) {
                out.append(BarControl(command: .tournament, mark: .word("Tournament"),
                                      hint: "Hold the best so far and beat it (⇧B)",
                                      isOn: store.tournament))
            }
            if features.isOn(.slideshow) {
                out.append(BarControl(command: .slideshow, mark: .word("Slideshow"),
                                      hint: "Full screen, four seconds a frame (y)",
                                      isOn: store.slideshow))
            }
        }
        if !putAway.contains(.rotations) {
            out.append(BarControl(command: .rotateCCW, mark: .glyph(.rotateCCW),
                                  hint: "Rotate \(subject) counterclockwise ([)"))
            out.append(BarControl(command: .rotateCW, mark: .glyph(.rotateCW),
                                  hint: "Rotate \(subject) clockwise (])"))
        }
        if !putAway.contains(.editing) {
            if features.isOn(.crop) {
                out.append(BarControl(command: .crop, mark: .glyph(.crop),
                                      hint: "Drag a box; a ratio, a copy and a save-over are in the bar it opens (c)", isOn: store.cropping))
            }
            if features.isOn(.adjust) {
                out.append(BarControl(command: .adjust, mark: .glyph(.adjust),
                                      hint: "Six sliders beside the photo (⇧A)", isOn: store.adjusting))
            }
        }
        // The bin is an island at the head of the row rather than at its tail,
        // so the air goes after it rather than before it (D-169).
        if out.count > 1 { out[1].leadingGap = Tokens.Space.s16 }
        return out
    }

    /// The menu, as data, so a test can walk every rung and check that nothing
    /// a row put away has gone missing (D-158). A feature that is switched off
    /// has no row here for the same reason it has no button: off means gone
    /// (D-123).
    static func rows(putAway: Set<BarPiece>,
                     ref: PhotoRef,
                     store: LibraryStore,
                     router: CommandRouter,
                     features: FeatureSet) -> [PopMenuItem] {
        var items: [PopMenuItem] = []
        var first = true
        func band(_ rows: [PopMenuItem]) {
            guard !rows.isEmpty else { return }
            var rows = rows
            rows[0].separatorBefore = !first
            first = false
            items += rows
        }

        if putAway.contains(.info) {
            band([PopMenuItem(title: "Info", checked: store.showInfo) { router.perform(.toggleInfo) }])
        }
        if putAway.contains(.judging) {
            var rows: [PopMenuItem] = []
            if features.isOn(.focusPeaking) {
                rows.append(PopMenuItem(title: "Focus", checked: store.showFocusPeaking) {
                    router.perform(.toggleFocusPeaking)
                })
            }
            if features.isOn(.faces), !store.faces.isEmpty {
                rows.append(PopMenuItem(title: store.faces.count == 1 ? "Face" : "Faces") {
                    router.perform(.zoomToFace)
                })
            }
            band(rows)
        }
        if putAway.contains(.modes) {
            var rows: [PopMenuItem] = []
            if features.isOn(.compare), Preferences.compareControlsInBar {
                // The same three the row drew, under the same conditions: the
                // menu is what the row put away, not a second list (D-268).
                rows.append(PopMenuItem(title: store.compareAnchor == ref.url ? "Clear A" : "Mark A",
                                        checked: store.compareAnchor == ref.url) {
                    router.perform(.setCompareAnchor)
                })
                if store.compareAnchor != nil, store.compareAnchor != ref.url {
                    rows.append(PopMenuItem(title: "Flip A / This", checked: store.showingCompare) {
                        router.perform(.toggleCompare)
                    })
                    rows.append(PopMenuItem(title: "Side by Side", checked: store.sideBySide) {
                        router.perform(.compareSideBySide)
                    })
                }
            }
            if features.isOn(.survey) {
                rows.append(PopMenuItem(title: "Survey", checked: store.surveying) { router.perform(.survey) })
            }
            if features.isOn(.tournament) {
                rows.append(PopMenuItem(title: "Tournament", checked: store.tournament) {
                    router.perform(.tournament)
                })
            }
            if features.isOn(.slideshow) {
                rows.append(PopMenuItem(title: "Slideshow", checked: store.slideshow) {
                    router.perform(.slideshow)
                })
            }
            band(rows)
        }
        if putAway.contains(.editing) {
            var rows: [PopMenuItem] = []
            if features.isOn(.crop) {
                rows.append(PopMenuItem(title: "Crop", checked: store.cropping) { router.perform(.crop) })
            }
            if features.isOn(.adjust) {
                rows.append(PopMenuItem(title: "Adjust", checked: store.adjusting) { router.perform(.adjust) })
            }
            band(rows)
        }
        if putAway.contains(.rotations) {
            band([
                PopMenuItem(title: "Rotate Counterclockwise") { router.perform(.rotateCCW, on: ref) },
                PopMenuItem(title: "Rotate Clockwise") { router.perform(.rotateCW, on: ref) },
            ])
        }
        return items
    }

}
