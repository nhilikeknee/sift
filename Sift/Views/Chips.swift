import SwiftUI

/// What the view is doing to the folder, written down where it can be undone.
/// A filter that hides half the photos used to read as one word in a run of
/// status text, which is indistinguishable from an empty folder (D-50).
@MainActor
struct Chip: View {
    let text: String
    let hint: String
    /// What the chip's own label does. Nil means the label is not a control.
    var act: (() -> Void)?
    /// What the clear mark does. Nil means this chip cannot be cleared.
    var clear: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            if let act {
                Button(action: act) { paddedLabel }
                    .buttonStyle(.plain)
                    .linkCursor()
                    .help(hint)
            } else {
                paddedLabel.help(hint)
            }
            if let clear {
                GlyphButton(shape: Glyph.Cross(), size: Tokens.Layout.glyph + Tokens.Space.s4,
                            label: "Clear \(text)", hint: "Clear \(text)", act: clear)
                    .padding(.vertical, Tokens.Space.s4)
            }
        }
        .padding(.trailing, clear == nil ? 0 : Tokens.Space.s4)
        // A chip whose label does something lifts under the pointer, the way
        // every other button in the app says it is one. `hovering` had been
        // declared here and never read since D-50, so the only thing saying
        // the chip was pressable was the cursor changing shape once the
        // pointer was already on it (D-376).
        .background(ground, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .onHover { hovering = act != nil && $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .fixedSize()
    }

    private var ground: Color { hovering ? Tokens.Surface.raised : Tokens.Surface.canvas }

    /// The chip's padding belongs to the button, not to the row around it.
    ///
    /// It used to sit on the `HStack`, so the ground that lifts under the
    /// pointer was larger on every side than the part that answered a click,
    /// and what answered was one line of text about 17pt tall against a floor
    /// of 24 (WCAG 2.2 AA 2.5.8). The clear mark keeps the vertical padding of
    /// its own so the row is the height it always was (A-10).
    private var paddedLabel: some View {
        label
            .padding(.leading, Tokens.Space.s8)
            .padding(.trailing, clear == nil ? Tokens.Space.s8 : 0)
            .padding(.vertical, Tokens.Space.s4)
            .contentShape(Rectangle())
    }

    private var label: some View {
        Text(text)
            .textStyle(.label)
            .lineLimit(1)
    }
}

/// One chip's worth of facts, so the row and the overflow menu are built from
/// one list rather than two (D-113). A chip is a state the view is in, what
/// clicking its label does, and what clearing it does.
struct ChipSpec: Identifiable {
    let id: String
    let text: String
    let hint: String
    var act: (() -> Void)?
    var clear: (() -> Void)?
}

/// Every chip the band can show, in a fixed order so they do not swap places
/// as they come and go: what is filtered out, and how many are rejected.
@MainActor
struct HeaderChips: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    /// The most chips `specs` can return: what is filtered out, and how many
    /// are rejected. The row below is written out to this many, so a third
    /// chip is a decision made here first; `theChipRowHasASlotForEveryChip`
    /// fails until it is.
    ///
    /// The name filter is not one of them. It is `nameFilter` instead, and it
    /// is drawn at the other end of the band, under the magnifier that opens
    /// it (D-220).
    static let maxChips = 2

    var body: some View {
        let specs = Self.specs(store: store, router: router)
        // Slots drawn now, not a `ForEach` handed over to be called later. A
        // `ForEach` keeps its content closure and SwiftUI calls it again
        // whenever it rebuilds the list — and this row sits inside the header's
        // `ViewThatFits`, which rebuilds it during measurement, on whatever
        // thread the render is on (D-195).
        HStack(spacing: Tokens.Space.s8) {
            chipSlot(specs, 0)
            chipSlot(specs, 1)
        }
    }

    /// One place in the row, or nothing if fewer chips are showing than that.
    @ViewBuilder
    private func chipSlot(_ specs: [ChipSpec], _ i: Int) -> some View {
        if i < specs.count {
            let spec = specs[i]
            Chip(text: spec.text, hint: spec.hint, act: spec.act, clear: spec.clear)
        }
    }

    /// What the name filter is showing while its field is closed. The chip and
    /// the field are one control in two states, so they are one slot: the chip
    /// says what is being filtered by and clicking it opens the field, and the
    /// field is what the chip becomes. The slot is at the trailing end of the
    /// band because the magnifier that opens it is at the trailing end of the
    /// toolbar, directly above (D-220).
    static func nameFilter(_ store: LibraryStore) -> ChipSpec? {
        guard !store.searchText.isEmpty, !store.searching else { return nil }
        return ChipSpec(id: "search", text: "\"\(store.searchText)\"",
                        hint: "Filtering by name. Click to edit (/)",
                        act: { store.searching = true },
                        clear: { store.searchText = "" })
    }

    static func specs(store: LibraryStore, router: CommandRouter) -> [ChipSpec] {
        var specs: [ChipSpec] = []
        // Every filter state but one has no control of its own, so the chip is
        // its only readout. Favorites has the heart in the header, which is
        // already the readout and already clears it, and two controls for one
        // fact is the thing the heart was added to stop (D-176). It is also
        // what made pressing the heart re-lay the whole header: the chip it
        // put on screen was wide enough to cost the row a rung (D-179).
        if store.filter != .all, store.filter != .favorite {
            specs.append(ChipSpec(id: "filter", text: store.filter.label,
                                  hint: "Showing only \(store.filter.label.lowercased()). Click to change",
                                  act: { cycleFilter(store) },
                                  clear: { store.filter = .all }))
        }
        // No chip for the sort. The sort menu in the toolbar is the readout:
        // it checks the field the grid is on and heads its direction rows with
        // that field's name, so a chip under it saying "Date taken" was the
        // same fact in a second place, two inches away and in weaker ink
        // (D-373).
        // The rejects, and the one screen that looks them over before any of
        // them goes. A cull that never gets reviewed is a cull nobody trusts
        // (D-69).
        // The verb is in the label. It always opened the review on a click,
        // and it said "6 rejected", which is a status: a reader on their
        // first cull read the number, took it for a tag, and had no reason
        // to guess that the second pass was behind it or that a key existed
        // (D-376). The count stays in the same words, so this is still one
        // control for one fact rather than a button beside a readout.
        if store.folderCounts.reject > 0 {
            specs.append(ChipSpec(id: "rejects",
                                  text: "Review \(store.folderCounts.reject) rejected",
                                  hint: "Look them over before they go to the Trash (⇧X)",
                                  act: { router.perform(.reviewRejects) }))
        }
        // The undo used to be a chip here. It outlives the toast the way D-48
        // asked, but in the corner of the gallery rather than in the header:
        // the undo for a photograph belongs near the photographs, and a chip
        // that comes and goes with every file operation was the widest thing
        // the header's ladder had to negotiate around (D-182).
        return specs
    }

    /// The filter has four states and lives in the View menu. A chip that is
    /// already on screen is a cheaper way through them than reopening the menu.
    private static func cycleFilter(_ store: LibraryStore) {
        let cases = PhotoFilter.menuCases
        guard let i = cases.firstIndex(of: store.filter) else { return }
        store.filter = cases[(i + 1) % cases.count]
    }
}
