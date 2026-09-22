import SwiftUI

/// What is true about the folder on screen: the filters that are narrowing it
/// and the settings that are not the defaults.
///
/// These were two slots in the old header, and they do not belong in a toolbar
/// (D-208). A toolbar is a row of controls with fixed widths that the system
/// arranges and a reader may rearrange; a chip arrives and leaves on its own,
/// and a chip arriving inside `ViewThatFits` was indistinguishable from the
/// window narrowing — favoriting a photograph shrank a header nobody had
/// touched (D-179). Moving them out of the chrome is what actually fixes that,
/// rather than carrying it across.
///
/// Absence is a state (D-65). Nothing here is drawn while the folder is whole,
/// in its default order and with the defaults in force, which is most of the
/// time — so the band says something by being there at all.
@MainActor
struct GalleryBand: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some View {
        @Bindable var store = store
        let status = Self.status(of: store)
        // Asked before anything is drawn, so an empty band takes no height and
        // no padding rather than a hairline of both.
        if HeaderChips.specs(store: store, router: router).isEmpty, status.isEmpty,
           !store.searching, HeaderChips.nameFilter(store) == nil {
            EmptyView()
        } else {
            HStack(spacing: Tokens.Space.s16) {
                HeaderChips()
                if !status.isEmpty {
                    Text(status)
                        .textStyle(.readout)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                // Under the magnifier that opens it. The field is in the band
                // rather than the toolbar because the system put a toolbar
                // text field in the overflow at the first narrow width, and
                // `/` opened a focused field behind a chevron (D-208). That
                // fixed where it lives and left it at the wrong end: the
                // control was opened from the trailing edge of the toolbar and
                // appeared at the leading edge of the window, the full width
                // of the screen away from the button pressed (D-220).
                NameFilter()
            }
            .padding(.horizontal, Tokens.Layout.windowEdge)
            .padding(.vertical, Tokens.Space.s8)
        }
    }

    /// Where you are in the folder, and the two settings that have no chip
    /// because neither is cleared in one click. The filter, the name filter and
    /// the sort left this string for chips of their own (D-50), and the photo
    /// the next command will act on is named by the toolbar.
    ///
    /// Static, so the band says the same sentence a test can ask for rather
    /// than a second version of it: a rule inside a view is a rule with no test
    /// on it.
    static func status(of store: LibraryStore) -> String {
        var parts: [String] = []
        // The count is not here. It is in the toolbar, next to the controls
        // that will use it, which is where the rule about naming a target puts
        // it; this slot carried the same sentence in weaker ink two inches to
        // the left, and a row reading "4 selected of 8  ·  4 selected" makes
        // the reader check whether the two numbers agree (D-202).
        if store.photos.isEmpty { parts.append("empty") }
        if store.includeSubfolders { parts.append("subfolders") }
        // Caps Lock overrides the setting, so this says which one is actually
        // in force rather than which one was chosen.
        if store.capsLockAdvances, !store.autoAdvance { parts.append("caps: auto-advance") }
        else if !store.autoAdvance { parts.append("no auto-advance") }
        return parts.joined(separator: "  ·  ")
    }
}

/// The filename filter, while it is open. Esc throws the query away and closes
/// it; Return keeps the query and closes it, which is what leaves a chip
/// behind.
@MainActor
/// The name filter's one slot: the field while it is open, the chip while a
/// filter is running, and nothing at all otherwise (D-220).
private struct NameFilter: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        if store.searching {
            FilterField()
        } else if let spec = HeaderChips.nameFilter(store) {
            Chip(text: spec.text, hint: spec.hint, act: spec.act, clear: spec.clear)
        }
    }
}

private struct FilterField: View {
    @Environment(LibraryStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var store = store
        TextField("Filter by name", text: $store.searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: Tokens.Layout.searchField)
            .focused($focused)
            .onAppear { focused = true }
            .onExitCommand { store.searchText = ""; store.searching = false }
            .onSubmit { store.searching = false }
    }
}
