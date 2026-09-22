import SwiftUI

/// `⌘,`, and `Sift > Settings…` for the reader who has not learned that yet.
///
/// One pane. Mostly one decision, which of the specialist features exist, plus
/// the appearance, which moved here off the header (D-134). The preview bar carries sixteen controls with all of them
/// on, which is more than a bar over a photograph should, and the eight a
/// given person never touches are not the same eight for everybody (D-123).
///
/// Every row says what the feature does, not just what it is called. A switch
/// with only a name on it makes the reader turn the thing on to find out
/// whether they wanted it.
@MainActor
struct SettingsWindow: View {
    /// The header's gear, `⌘,` and the menu item all arrive here. It clicks the
    /// menu item rather than sending `showSettingsWindow:`, because that
    /// selector is answered and puts no window on screen, which is the
    /// difference between asserting on the call and asserting on the outcome
    /// (D-123, D-138).
    @MainActor
    static func open() { GalleryWindow.openSettingsFromTheMenu() }

    private let model = AppModel.shared
    // The live table, not the shipped one: a reassigned key has to show up
    // here too, or the overlay is a second list of the bindings (D-7, D-175).
    private let bindings = KeyBindings.shared
    private var map: KeyMap { bindings.map }
    /// Whether the button has been pressed this time the window has been open.
    @State private var restored = false
    /// The same, for **Remove All**, which has its own readout.
    @State private var removedAll = false
    /// Whether the archive under the grants is open. Closed by default: the
    /// count answers "is there anything there", and two hundred resume
    /// positions is not a thing to put in front of somebody who came to
    /// Settings for a switch (D-311, D-325).
    @State private var showArchive = SettingsWindow.openTrail
    /// Re-read whenever this window appears, and after each control here
    /// changes it.
    ///
    /// It used to be read once, at init, on the reasoning that this window
    /// was the only thing that changed it. That stopped being true with the
    /// sandbox: opening a folder adds a grant (D-324), and the Settings
    /// scene is built once and kept, so a list read at init showed the
    /// folders from whenever the window was first made — often none at all,
    /// with **Remove All** disabled beside them. Reported as the button
    /// missing, which is what a disabled button in a section listing nothing
    /// looks like (D-325).
    @State private var trail = Preferences.folderTrail
    /// Three states and not a `Bool`: the pane can refuse to open, and a row
    /// that reported that as "not pressed yet" would leave the reader looking
    /// for a window that never came.
    @State private var opened = Opened.no
    private enum Opened { case no, yes, refused }

    /// Two tabs and grouped forms, which is what a Mac settings window is
    /// (D-212).
    ///
    /// It was one `ScrollView` of `VStack`s on a flat background with headings
    /// between them. Nothing was wrong with it except that no other window on
    /// this machine looks like that: since Ventura a setting sits in a rounded
    /// group with hairlines between its rows, and a window with more than one
    /// kind of setting splits them rather than stacking them.
    ///
    /// The split is the one the old file had already reasoned its way to and
    /// then not taken: the keyboard section is "the longest section by far",
    /// and it was put last so that a reader after a switch did not scroll past
    /// a hundred rows of keys. A tab is that argument finished — they do not
    /// scroll past it at all.
    private enum Tab: Hashable { case general, keyboard }
    /// Bound rather than left to SwiftUI, which remembers the tab across
    /// launches and was the reason `SIFT_SETTINGS_AT` could scroll a form
    /// nobody could see: a run that asked for `history` came up on **Keyboard**
    /// and photographed the key table, twice, with the launch reporting
    /// success both times. The variable names a section of the General form,
    /// so asking for one is asking for that tab (D-311).
    ///
    /// The cost is that Settings now always opens on General rather than on
    /// the tab it was last left on. Named rather than argued away: it is what
    /// System Settings and most of this platform do, and the tab that is worth
    /// coming back to is the one with the filter field, which empties itself
    /// anyway.
    @State private var tab = SettingsWindow.openAt == "keyboard" ? Tab.keyboard : Tab.general

    var body: some View {
        TabView(selection: $tab) {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            Form { KeyboardSettings() }
                .formStyle(.grouped)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(Tab.keyboard)
                // A section name like the five in the General form, so
                // `SIFT_SETTINGS_AT=keyboard` can photograph the key table.
                // Binding the tab took that away: before it, a launch reached
                // this tab by whichever one SwiftUI happened to remember,
                // which is not a way in (D-311).
                .id("keyboard")
        }
        .frame(width: Tokens.Layout.settingsWidth, height: Tokens.Layout.settingsHeight)
    }

    /// Which section a screenshot wants on screen. The General form is about
    /// twice the window's height and nothing outside this app can scroll it —
    /// no Accessibility permission, so a synthetic scroll event goes nowhere
    /// (D-112) — which meant every section below Features had never been
    /// photographed. `SIFT_SETTINGS_AT=panels` and the rest land one there
    /// (D-270). Read once, at launch, and nothing otherwise.
    private static let openAt = Launch.asked(
        ProcessInfo.processInfo.environment["SIFT_SETTINGS_AT"])?.lowercased()

    private var general: some View {
        ScrollViewReader { form in
            generalForm
                .onAppear {
                    // The grants change while this window is closed, so the
                    // list is re-read on the way in rather than at init.
                    trail = Preferences.folderTrail
                }
                .onAppear {
                    guard let at = Self.openAt, at != "keyboard" else { return }
                    guard Self.sections.contains(at) else {
                        Launch.refuse("SIFT_SETTINGS_AT",
                                      "\(at) is not a section. One of: \(Self.sections.joined(separator: ", "))")
                        return
                    }
                    // A turn later, for the reason the menu click waits
                    // (D-123): `onAppear` fires before the form's rows have
                    // been laid out, and a `scrollTo` with nothing to measure
                    // is a scroll that does not happen. It landed on Features
                    // and reported success, which is the failure D-118 is
                    // about, in the mechanism built to catch it (D-311).
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        // `history` is where the folder list used to be half
                        // of, and the anchor it left behind points at the
                        // section that absorbed it (D-325).
                        form.scrollTo(at == "history" ? "access" : at, anchor: .top)
                    }
                }
        }
    }

    /// Whether the History row's list of stored paths starts open.
    ///
    /// `SIFT_SETTINGS_TRAIL=1`. The list is behind a disclosure, and a
    /// disclosure is a click: no Accessibility permission, so nothing outside
    /// this app can press it, and the substance of D-311 is the list rather
    /// than the button that reveals it. The same argument as `SIFT_SETTINGS_AT`
    /// one control further in (D-270, D-311).
    ///
    /// Read once, at launch, and nothing otherwise. It opens a disclosure and
    /// writes nothing, which is what puts it on the list in
    /// `SecurityClaimTests` rather than behind the debug gate (D-308).
    static let openTrail = Launch.isOn(ProcessInfo.processInfo.environment["SIFT_SETTINGS_TRAIL"])

    /// The names `SIFT_SETTINGS_AT` takes, which are the `id`s below.
    /// `history` is kept as a name for `access`, which is the section that
    /// absorbed it (D-325): a script or a habit that asks for it lands on
    /// the folder list rather than on a refusal naming sections nobody has
    /// heard of.
    static let sections = ["features", "appearance", "panels", "hints", "access", "history",
                           "keyboard"]

    private var generalForm: some View {
        Form {
            // Unreleased features have no row: there is nothing to decide
            // about a feature that is not on offer (D-129).
            //
            // No paragraph under the heading. It explained that a switched-off
            // feature leaves nothing behind, which is true and is a thing you
            // find out by switching one off; the switches are right there and
            // each one names itself (D-204).
            Section("Features") {
                ForEach(Feature.allCases.filter { !Feature.unreleased.contains($0) },
                        id: \.self) { feature in
                    row(feature)
                }
            }
            .id("features")

            // Three states and not two, so a segmented control rather than a
            // switch: `system` is the default and is the whole reason a Mac
            // that goes dark at dusk takes Sift with it. The View menu sets
            // the same fact (D-134).
            Section("Appearance") {
                Picker("Palette", selection: Binding(
                    get: { model.appearance },
                    set: { model.appearance = $0 }
                )) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Which of the two palettes the app draws with. Match System follows the desktop; the other two are for when the surround a photograph is judged against matters more than the rest of the screen does.")
                    .textStyle(.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id("appearance")

            // Not a `Feature`: the filmstrip has a key, and a switch that took
            // the key away would be a switch you could not undo from the
            // keyboard. This row and `f` set the same fact, which is a
            // preference with a shortcut rather than two controls for one
            // thing (D-125).
            Section("Panels") { filmstripRow; compareControlsRow }.id("panels")

            // Acts rather than states, which is why each has a readout under
            // it instead of a switch beside it (D-153, D-173).
            Section("Hints") { hintsRow }.id("hints")
            // One section, not two. **Folder access** and **History** sat
            // one above the other answering two questions about mostly the
            // same folders, and the reader asked what the difference was —
            // which is the question a screen should never make somebody ask
            // (D-325).
            Section("Folders") { foldersRow }.id("access")
        }
        .formStyle(.grouped)
    }

    /// The one switch in the app that hides a control without taking the
    /// capability away. Off by default: compare's three controls are seven
    /// pieces of chrome over a photograph for a feature a given sitting may
    /// never open, and `a`, `\\` and `|` keep working with it off, as do the
    /// View menu's three items (D-270).
    ///
    /// It says what it costs. A reader who turns this on is opting into a
    /// wider bar, and a reader who leaves it off should be told plainly that
    /// the feature is still there and where to reach it, because a control
    /// that is not drawn is a control nobody finds by looking.
    private var compareControlsRow: some View {
        Toggle(isOn: Binding(
            get: { Preferences.compareControlsInBar },
            set: { Preferences.compareControlsInBar = $0 }
        )) {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s8) {
                    Text("Compare controls")
                        .textStyle(.label)
                    Text([Command.setCompareAnchor, .toggleCompare, .compareSideBySide]
                        .flatMap { map.keys(for: $0) }.map(\.display).joined(separator: "  "))
                        .textStyle(.data, color: Tokens.Text.tertiary)
                }
                Text("Mark A, Flip and Side by side in the bar over the photo. Off, the keys above and the View menu still compare.")
                    .textStyle(.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .disabled(!model.features.isOn(.compare))
    }

    /// Each first-time hint is shown once, ever (D-66), and until now the only
    /// way back was editing UserDefaults by hand — a state with no control,
    /// while `Preferences.forgetHints` sat there with a comment claiming the
    /// help overlay used it (D-153).
    ///
    /// A plain button and no confirmation: nothing is lost by pressing it, and
    /// pressing it twice does what pressing it once did. The line under it is
    /// the readout, so the press has an answer.
    private var hintsRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            // No `textStyle`. A push button is AppKit's, and the type on it is
            // the system's at the control's size — 13pt, with the control
            // color that dims when the button is disabled. The app's own
            // 14pt `.label` overrode both, so every button in this window was
            // a point larger than every other button on the Mac and stayed
            // full-strength while disabled (D-322).
            Button("Show Hints Again") {
                Preferences.forgetHints()
                restored = true
            }
            Text(restored
                 ? "They will come back as you meet each one again."
                 : "The short lines that appear the first time you trash a photo, select several, or open one of the specialist views. Each is shown once and then remembered as spent.")
                .textStyle(.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Everything Sift holds about folders: what it can read, and what it
    /// has written down (D-325).
    ///
    /// Two sections until now, **Folder access** and **History**, answering
    /// two questions about mostly the same folders a few inches apart. The
    /// reader asked what the difference was, which is the question a screen
    /// should never make somebody ask. Worse, the two red words did
    /// different amounts — Forget took the record and the grant, Revoke took
    /// only the grant — and nothing on screen said so.
    ///
    /// One row per folder, one control, one act: **Remove** takes away
    /// everything Sift holds about that folder. The groups carry the fact a
    /// reader wants at a glance, which is whether Sift can still read it.
    ///
    /// Not "Delete", and no bin, for the reason D-321 gave and which still
    /// holds: nothing here leaves the disk, and a bin beside a folder path
    /// says the opposite. "Remove" is the mildest word that covers both a
    /// permission and a record, and the sentence above the list says what it
    /// does and does not touch, because that is the part no label carries.
    private var foldersRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
            Text(message)
                .textStyle(.quiet)
                .fixedSize(horizontal: false, vertical: true)
            folderList
            HStack(spacing: Tokens.Space.s8) {
                Button("Open Privacy & Security") {
                    opened = AppModel.shared.active.router.presenter.openFolderAccessSettings()
                        ? .yes : .refused
                }
                Spacer(minLength: Tokens.Space.s16)
                // The destructive one at the far edge, away from the one
                // somebody presses on the way past. Plain, no dialog: the
                // ladder is matched to the cost, and the cost is opening
                // each folder again from the panel.
                Button("Remove All", role: .destructive) {
                    AppModel.shared.removeAllFolders()
                    removedAll = true
                    trail = Preferences.folderTrail
                }
                .disabled(trail.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The list, in the two states a folder can be in, plus the two things
    /// in here that are not folders.
    @ViewBuilder
    private var folderList: some View {
        if trail.isEmpty {
            Text("Sift holds nothing. Open a folder and it appears here.")
                .textStyle(.quiet)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s12) {
                // Always open. This is the short list and the one worth
                // reading: what Sift can reach right now, usually a handful.
                group("Sift can read these", trail.granted)
                if archived > 0 { archive }
            }
        }
    }

    /// Everything Sift remembers and cannot read, behind a count.
    ///
    /// The resume list holds two hundred folders, so this cannot be an open
    /// list: the section a reader opened for a switch would be a screen of
    /// paths. The split is by importance rather than by size, though —
    /// what Sift can read is the fact somebody came here for, and where it
    /// has been is the archive behind it.
    ///
    /// A triangle, not a button: showing and hiding nested content is what
    /// macOS has a disclosure for, and a push button that changes its own
    /// title was two labels for one state (D-322).
    private var archive: some View {
        DisclosureGroup(isExpanded: $showArchive) {
            VStack(alignment: .leading, spacing: Tokens.Space.s12) {
                // The group that answers the question this screen used to
                // raise: a folder can be remembered and unreadable at the
                // same time, and that is not a disagreement between two
                // lists — it is one fact about one folder.
                group("Remembered, no access", trail.remembered)
                // macOS's, not this app's. `NSOpenPanel` writes these into
                // whatever domain it is opened from, so they name folders
                // browsed to in a panel and perhaps never opened in Sift. No
                // control: a row dropped here is back on the next ⌘O (D-321).
                group("Written by macOS's open panel", trail.panel, removable: false)
                // Not a folder at all, and it sat in the folder list under
                // "Last targets" for as long as that list existed.
                if let editor = trail.editor {
                    group("Remembered application", [editor])
                }
            }
            .padding(.top, Tokens.Space.s8)
        } label: {
            Text("\(archived) remembered, not readable")
                .textStyle(.label)
        }
    }

    private var archived: Int {
        trail.remembered.count + trail.panel.count + (trail.editor == nil ? 0 : 1)
    }

    /// One heading and its rows, or nothing at all when the group is empty:
    /// a heading over no rows says a thing is stored that is not.
    @ViewBuilder
    private func group(_ title: String, _ rows: [URL], removable: Bool = true) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("\(title) (\(rows.count))")
                    .textStyle(.strong)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, url in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                        Text(Self.shown(url))
                            .textStyle(.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Tokens.Space.s8)
                        if removable { removeButton(url) }
                    }
                }
            }
        }
    }

    /// The word, in red, at the row's far edge.
    ///
    /// Red at rest rather than on hover, unlike the cross on a pinned row.
    /// That list is pointed at; this one is read down a column, and a
    /// warning that arrives with the pointer arrives after the decision.
    private func removeButton(_ url: URL) -> some View {
        WordButton(title: "Remove",
                   hint: "Sift forgets this folder and loses access to it",
                   destructive: true) {
            AppModel.shared.removeFolder(url)
            removedAll = false
            trail = Preferences.folderTrail
        }
        .accessibilityLabel("Remove \(Self.shown(url))")
    }

    /// The sentence above the list. What the press just did comes first,
    /// because a reader who pressed something is asking that question and
    /// not the standing one (D-323).
    private var message: String {
        if removedAll {
            return """
            Removed. Sift can read nothing and remembers nowhere until you open a \
            folder again. Pinned folders keep their place in the sidebar and lost \
            their access with the rest.
            """
        }
        return switch opened {
        case .no:
            """
            Sift reads the folders you have handed it and nothing else. A folder \
            arrives when you pick it in the open panel, drop it on the window, or \
            open it from the Finder, and everything inside it comes with it. \
            Remove takes away both what Sift remembers about a folder and what it \
            can read; nothing leaves your disk. macOS keeps its own switches over \
            Desktop, Documents, Downloads and volumes, which is a wider fence than \
            this one.
            """
        case .yes:
            "Opened. Files & Folders is macOS's own list, and a wider fence than the one above."
        case .refused:
            """
            System Settings would not open. Open it by hand: Privacy & Security, \
            then Files & Folders, then switch Sift off.
            """
        }
    }

    /// A path as the header would draw it: from `Home` down, never from
    /// `/Users`.
    ///
    /// `reachable: { _ in true }` because this list names folders Sift
    /// cannot read, and the crumb builder cuts the path at the grant
    /// (D-324). That cut belongs to the header, where it stops a control
    /// offering a folder it cannot open; here it would truncate the very
    /// rows this section exists to show.
    ///
    /// The root is its own segment and its name is already `/`, so joining
    /// every segment with a slash writes `//tmp/…` for anything outside the
    /// home directory. Found in the photograph and not by the suite, which is
    /// the whole of why a visual change gets looked at: the build was green,
    /// the test was green, and the row said `//tmp` (D-311).
    static func shown(_ url: URL) -> String {
        let names = Breadcrumb.pathSegments(for: url, reachable: { _ in true }).map(\.name)
        guard names.first == "/" else { return names.joined(separator: "/") }
        return "/" + names.dropFirst().joined(separator: "/")
    }

    /// Bound to the store the preview window is showing, because that is the
    /// window the strip is in and there is only ever one of it.
    private var filmstripRow: some View {
        let store = AppModel.shared.preview.store
        return Toggle(isOn: Binding(
            get: { store.showFilmstrip },
            set: { store.showFilmstrip = $0 }
        )) {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s8) {
                    Text("Filmstrip")
                        .textStyle(.label)
                    Text(map.keys(for: .toggleFilmstrip).map(\.display).joined(separator: "  "))
                        .textStyle(.data, color: Tokens.Text.tertiary)
                }
                Text("The rest of the folder along the bottom of the preview window.")
                    .textStyle(.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }

    private func row(_ feature: Feature) -> some View {
        Toggle(isOn: Binding(
            get: { model.features.isOn(feature) },
            set: { model.features.set(feature, on: $0) }
        )) {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s8) {
                    Text(feature.label)
                        .textStyle(.label)
                    // The keys it costs, so the switch says what it is taking
                    // away rather than only what it is named.
                    if !keys(for: feature).isEmpty {
                        Text(keys(for: feature))
                            .textStyle(.data, color: Tokens.Text.tertiary)
                    }
                }
                Text(feature.explanation)
                    .textStyle(.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The label takes the width so the switches line up in a column.
            // Left to itself a `Toggle` puts its switch right after whatever
            // the label happens to be, and eight of them made a ragged edge
            // that read as a mistake.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }

    /// Read off the key map rather than written out here, for the reason the
    /// help overlay is (D-7): two lists of the same bindings is one list that
    /// is wrong.
    private func keys(for feature: Feature) -> String {
        Command.allCases
            .filter { $0.features.contains(feature) }
            .flatMap { map.keys(for: $0) }
            .map(\.display)
            .joined(separator: "  ")
    }
}
