import SwiftUI

/// Reads KeyMap.standard so it can never drift from the real bindings (D-7).
/// The whole map at once is a list you read rather than search, so there is a
/// field at the top that narrows it by command or by key (D-52). It said
/// "fifty-three bindings" until a hygiene pass counted 89: a sentence naming
/// the size of a set is a second copy of that set, and it was the copy that
/// went stale. The number is gone rather than corrected.
@MainActor
struct HelpOverlay: View {
    @Environment(LibraryStore.self) private var store

    // The live table, not the shipped one: a reassigned key has to show up
    // here too, or the overlay is a second list of the bindings (D-7, D-175).
    private let bindings = KeyBindings.shared
    private var map: KeyMap { bindings.map }

    @State private var query = ""
    @FocusState private var focused: Bool

    private var needle: String { query.trimmingCharacters(in: .whitespaces) }


    /// A switched-off feature has no line here. The overlay is the app's
    /// index of itself, and an index that lists a key which does nothing is
    /// worse than one that is short (D-123).
    private var groups: [(String, [Command])] {
        let features = AppModel.shared.features
        return Command.groups
            .map { g in (g, Command.allCases.filter { $0.group == g && features.allows($0) && map.matches($0, query: needle) }) }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        // Three ways out, because this is the screen people reach by pressing
        // `?` while looking for something else: Esc, the Close word, and a
        // click on the window behind it. A panel over the whole window that
        // only a named control dismisses is a panel people close by guessing
        // (D-320).
        // The panel is measured against the window rather than given a width.
        // `maxWidth` is a ceiling and not a limit: when the content's own
        // minimum is wider — a fixed search field and two key columns come to
        // more than 700pt — SwiftUI grows past the ceiling, the layer grows
        // with it, and the sidebar is pushed out of the window while the panel
        // runs off the right edge (D-333).
        // Worked out once, above the `GeometryReader`. It walks every command
        // in every group, fuzzy-matching each against the query, and it does
        // not depend on the window at all — inside the reader it was doing
        // that work again on every layout pass, which is every frame of a
        // window drag.
        let groups = groups
        return GeometryReader { geo in
            ZStack {
                Color.clear // design-system:allow — not a color, a hit area: the window behind the panel, catching the click that closes it.
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                panel(groups, inWindowOf: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// What the window leaves for the panel: its size, and how many columns of
    /// bindings fit in it.
    ///
    /// Arithmetic rather than a modifier, so it can be checked. The bug this
    /// replaces was invisible to the suite and to the build — the panel simply
    /// grew past its own ceiling and pushed the sidebar out of the window —
    /// and the only reason it was ever found is that somebody made the window
    /// small and pressed `?` (D-333).
    struct Room: Equatable {
        var width: CGFloat
        var height: CGFloat
        var columns: Int
        /// `margin` is subtracted rather than applied as padding outside the
        /// frame. The two agree while the panel is smaller than the window and
        /// disagree exactly when it is not, which is the case that broke.
        init(window: CGSize, margin: CGFloat = Tokens.Space.s32) {
            width = min(Tokens.Layout.helpMaxWidth, max(0, window.width - margin * 2))
            height = min(Tokens.Layout.helpMaxHeight, max(0, window.height - margin * 2))
            let inner = width - margin * 2
            columns = inner >= Tokens.Layout.helpColumn * 2 + Tokens.Space.s24 ? 2 : 1
        }
    }

    private func panel(_ groups: [(String, [Command])], inWindowOf window: CGSize) -> some View {
        let room = Room(window: window)
        return VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            // One row, always. It was two rows on a narrow panel while a
            // second word button sat here (D-333); with only Close left, the
            // title, the field and the word come to about 450 inside a panel
            // that is never narrower than 512 — `layout.galleryMinWidth` less
            // the margins and the padding — so the wrap could not fire and was
            // a state the code carried for nothing (D-336).
            HStack(spacing: Tokens.Space.s16) { title; Spacer(minLength: Tokens.Space.s16); searchField; closeButton }

            content(groups: groups, columns: room.columns)
        }
        .padding(Tokens.Space.s32)
        .frame(width: room.width)
        // A ceiling rather than an exact height, unlike the width: a panel
        // with four rows in it should be four rows tall. But the ceiling is
        // the window's, not the token's — 720 in a 560pt window is a panel
        // with no margin at the top or the bottom, floating against two edges
        // it is meant to float away from.
        .frame(maxHeight: room.height)
        .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .shadow(color: Tokens.Elevation.overlay.color, radius: Tokens.Elevation.overlay.radius, y: Tokens.Elevation.overlay.y)
        // The panel eats its own clicks. Without this, a click on the paper
        // between two rows falls through to the layer underneath and closes
        // the thing you were reading: a view with no gesture on it does not
        // win a hit test against one that has.
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .onTapGesture {}
        // A scrim stops a mouse and not a screen reader. Without this the
        // VoiceOver cursor walks straight past an open panel into the grid
        // behind it and acts on a photograph the reader cannot see — D-320's
        // three ways out are three ways out for a pointer and a keyboard
        // (D-339).
        .accessibilityAddTraits(.isModal)
    }

    private var title: some View {
        Text("Keyboard")
            .textStyle(.title)
    }

    /// Its width is a ceiling now rather than a fixed size: a field that
    /// cannot give any of its 260 back is most of why the header would not fit
    /// (D-333).
    private var searchField: some View {
        TextField("Find a command or a key", text: $query)
            .textFieldStyle(.plain)
            .textStyle(.label)
            .frame(maxWidth: Tokens.Layout.searchField)
            .padding(.horizontal, Tokens.Space.s8)
            .padding(.vertical, Tokens.Space.s4)
            .background(Tokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .focused($focused)
            .onAppear { focused = true }
            .onExitCommand { close() }
    }

    /// Close, and nothing beside it.
    ///
    /// A **Find a command** button sat here from D-68 until D-336, opening the
    /// palette. Two controls in one row, both labeled with the same verb, and
    /// only one of them did anything: the field narrows the list you are
    /// reading and the button ran a command in another sheet. Reported as
    /// exactly that — "why is there a Find a command button and a search bar
    /// that looks like it does the same thing".
    private var closeButton: some View {
        WordButton(title: "Close", hint: "Close this (Esc)", act: close)
    }

    private func content(groups: [(String, [Command])], columns: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s24) {
                if groups.isEmpty {
                    Text("Nothing matches \"\(needle)\"")
                        .textStyle(.body, color: Tokens.Text.secondary)
                }
                // One column or two, from the room the window gave. Two
                // `.flexible()` columns have a minimum of their own, and below
                // it the grid stops shrinking and starts pushing (D-333).
                let cols = Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columns)
                LazyVGrid(columns: cols, alignment: .leading, spacing: Tokens.Space.s24) {
                    ForEach(groups, id: \.0) { group, commands in
                        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                            Text(group)
                                .textStyle(.heading)
                            ForEach(commands, id: \.self) { command in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(map.keys(for: command).map(\.display).joined(separator: "  "))
                                        .textStyle(.data)
                                        .frame(width: Tokens.Layout.keyColumn, alignment: .leading)
                                    Text(command.label)
                                        .textStyle(.readout)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                if needle.isEmpty {
                    Text("⌘1 to ⌘9 open recent folders (File > Open Recent). Hold Z to peek at 1:1; tap it to stay. Hold ⌥ over a thumbnail for a large look at the photograph, gone when the pointer moves off it.")
                        .textStyle(.readout)
                    Text("Every command here also has a control on screen: the toolbar, the controls on a thumbnail, the bar in the preview, or a right-click.")
                        .textStyle(.quiet)
                    // Share has no key and so no row above. It is a real
                    // capability with three controls, and this overlay is
                    // the app's index of itself, so leaving it out entirely
                    // would be the index lying by omission (D-216).
                    Text("Sharing has no key: it is in the toolbar, the Photo menu, and a right-click on a photograph.")
                        .textStyle(.quiet)
                    // This list is short because some features start
                    // switched off, and a reader looking for one of them
                    // would otherwise conclude the app does not have it
                    // (D-124).
                    //
                    // Built from `Feature.offByDefault` rather than typed
                    // out. It was typed out, and when crop came on by
                    // default (D-236) this sentence went on telling people
                    // it was off — a sentence that names a set is a second
                    // copy of that set, and the second copy is the one that
                    // goes stale.
                    Text("Some features start switched off and are not listed here until they are on: \(Feature.offByDefaultSentence). Settings (⌘,) has all of them.")
                        .textStyle(.quiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func close() {
        query = ""
        store.showHelp = false
    }
}
