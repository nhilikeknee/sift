import SwiftUI
import AppKit

/// The gallery's toolbar, which is the platform's own rather than a row this
/// app draws (D-208).
///
/// What this buys, and what it cost, is argued in the architecture notes. The short
/// version: the header was a hand-built `HStack` with a seven-rung ladder, a
/// `»` menu and a caption under every icon, and all three existed to solve
/// problems a real `NSToolbar` solves on its own — running out of room,
/// naming what an icon does, and letting somebody keep the controls they use.
/// The system's overflow, its customization sheet, its materials and its hover
/// and selection states arrive with it.
///
/// Icon-only, which is the platform's default and the reversal of D-180. The
/// word under each icon is now the tooltip and the customization sheet's
/// label, which is where this platform keeps it.
///
/// **The path is a custom item, not the window's title.** A title and subtitle
/// would have been less code and it would have deleted four things the
/// breadcrumb does: walking to an ancestor, the subfolder menu on every
/// chevron, dropping photographs onto a crumb to move them, and copying the
/// path. Those are features, so the breadcrumb comes across as it is.
@MainActor
struct GalleryToolbar: CustomizableToolbarContent {
    /// Three groups, because `ToolbarContentBuilder` takes ten children and
    /// this toolbar has thirteen. The split is the same one the platform's
    /// guidance asks for: where you are, what acts on a photograph, and what
    /// the grid is showing.
    var body: some CustomizableToolbarContent {
        WhereYouAre()
        FileActions()
        WhatTheGridShows()
    }
}

/// The leading edge: get me somewhere, and here is where you are. None of it
/// is customizable — a toolbar somebody has emptied of the path is a window
/// with no way out of the folder (D-208).
@MainActor
private struct WhereYouAre: CustomizableToolbarContent {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "sidebar", placement: .navigation) {
            Button {
                router.perform(.toggleSidebar)
            } label: {
                Label("Folder List", systemImage: Glyph.Sidebar(showing: store.showSidebar).symbol)
            }
            .help(store.showSidebar ? "Hide the folder list (⌘\\)" : "Show the folder list (⌘\\)")
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(store.showSidebar ? "on" : "off")
        }
        .customizationBehavior(.disabled)

        ToolbarItem(id: "history", placement: .navigation) {
            HistoryArrows()
        }
        .customizationBehavior(.disabled)

        ToolbarItem(id: "path", placement: .navigation) {
            Breadcrumb(url: store.folder,
                       open: { router.open($0) },
                       copyPath: { router.copyPath(of: $0) },
                       drop: { router.drop($0, on: $1) })
                // The cap the header used to apply (D-121). A toolbar item is
                // given whatever width it asks for, and a path asked for all
                // of it: eight crumbs of a temporary folder took the bar and
                // pushed every command into the overflow.
                .frame(maxWidth: Tokens.Layout.breadcrumbMax, alignment: .leading)
                // Where the `⌘↓` menu comes out. Both numbers now come from
                // the control they describe rather than one from the crumb and
                // one from the row around it: the header used to be the
                // window's top-left, so its own height was the drop, and the
                // toolbar is in the title bar where that is no longer true
                // (D-208).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    store.breadcrumbX = $0.minX
                    store.headerHeight = $0.maxY
                }
        }
        .customizationBehavior(.disabled)
    }
}

/// What the next command acts on, and the six that act on it. The name is
/// still on screen before the controls that will use it, which is the rule the
/// toolbar does not change (D-47) — it is an item now rather than a slot in a
/// ladder.
@MainActor
private struct FileActions: CustomizableToolbarContent {
    @Environment(LibraryStore.self) private var store

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "target", placement: .primaryAction) {
            TargetName()
        }
        .customizationBehavior(.disabled)

        ToolbarItem(id: "rotateCCW", placement: .primaryAction) {
            ActionItem(command: .rotateCCW, symbol: Glyph.Rotate(clockwise: false).symbol,
                       title: "Rotate Left", hint: "Rotate \(subject) counterclockwise ([)")
        }
        ToolbarItem(id: "rotateCW", placement: .primaryAction) {
            ActionItem(command: .rotateCW, symbol: Glyph.Rotate().symbol,
                       title: "Rotate Right", hint: "Rotate \(subject) clockwise (])")
        }
        // Off the bar until somebody asks for them (D-347). Filing a
        // photograph somewhere else happens once a sitting; keep, reject and
        // trash happen all day, and eight icons in a row make the reader
        // price all eight before pressing one. Both keep their key, their
        // menu item and a line in the photo's own context menu, and
        // **View > Customize Toolbar** is where they come back — the sheet
        // this platform already puts behind a right-click on the bar.
        ToolbarItem(id: "move", placement: .primaryAction) {
            ActionItem(command: .moveToFolder, symbol: Glyph.MoveToFolder().symbol,
                       title: "Move", hint: "Move \(subject) to a folder (m)")
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: "copy", placement: .primaryAction) {
            ActionItem(command: .copyToFolder, symbol: Glyph.Copy().symbol,
                       title: "Copy", hint: "Copy \(subject) to a folder, leaving the original (⇧C)")
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: "rename", placement: .primaryAction) {
            ActionItem(command: store.targets.count == 1 ? .rename : .batchRename,
                       symbol: Glyph.Pencil().symbol,
                       title: "Rename", hint: renameHint)
        }
        ToolbarItem(id: "share", placement: .primaryAction) {
            ShareItem()
        }
        ToolbarItem(id: "trash", placement: .primaryAction) {
            ActionItem(command: .trash, symbol: Glyph.Trash().symbol,
                       title: "Move to Trash", hint: "Move \(subject) to Trash (d)")
        }
    }

    /// "12 photos" reads better than "the selection" in a tooltip, and the
    /// count is the thing a person checks before pressing a destructive button.
    private var subject: String {
        let count = store.targets.count
        return count == 1 ? (store.current?.name ?? "1 photo") : "\(count) photos"
    }

    private var renameHint: String {
        store.targets.count == 1 ? "Rename \(subject) (n)" : "Rename \(subject) with a pattern (⇧N)"
    }
}

/// The folder on screen, narrowed or reordered. Three controls saying one
/// sentence, which is why they travel together (D-183).
@MainActor
private struct WhatTheGridShows: CustomizableToolbarContent {
    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "favorites", placement: .primaryAction) { FavoritesItem() }
        ToolbarItem(id: "search", placement: .primaryAction) { SearchItem() }
        ToolbarItem(id: "sort", placement: .primaryAction) { SortItem() }
    }
}

/// One file command. Disabled rather than hidden when there is nothing to act
/// on: a control that vanishes with the selection is a control nobody learns
/// is there, which is the same reason the history arrows stay put (D-208).
private struct ActionItem: View {
    let command: Command
    let symbol: String
    let title: String
    let hint: String

    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some View {
        Button { router.perform(command) } label: {
            Label(title, systemImage: symbol)
        }
        .disabled(store.current == nil && store.selected.isEmpty)
        .help(hint)
    }
}

/// Back and forward. The control itself is `NavigationSegments`; this is the
/// wiring (D-209).
private struct HistoryArrows: View {
    @Environment(CommandRouter.self) private var router

    var body: some View {
        NavigationSegments(canGoBack: router.canGoBack,
                           canGoForward: router.canGoForward,
                           backList: router.backList,
                           forwardList: router.forwardList,
                           step: { back in router.perform(back ? .back : .forward) },
                           jump: { back, steps in
                               if back { router.goBack(steps: steps) }
                               else { router.goForward(steps: steps) }
                           })
        // No width. The control's own fitting size is two targets and the
        // divider between them, and forcing `navigationSegments` on it left
        // the two arrows further apart than the gap to the path beside them —
        // which is the leading edge reading as two groups again (D-205, D-209).
        .fixedSize()
    }
}

/// The name of what the next command will act on (D-47).
private struct TargetName: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        if let label = store.targetLabel {
            Text(label)
                .textStyle(.label, color: store.selected.isEmpty ? Tokens.Text.secondary : Tokens.Text.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Tokens.Layout.searchField, alignment: .trailing)
                .help(store.selected.isEmpty
                      ? "Every command here acts on this photo"
                      : "Every command here acts on these photos")
                // The one readout in the header that says what the next key
                // will hit, and it had no name at all: loose text the reader's
                // cursor walked over without being told what it was about. The
                // count is the value, and it moves with every click (D-343).
                .accessibilityLabel("Acting on")
                .accessibilityValue(label)
        }
    }
}

/// The platform's share sheet, which is the one thing a Mac photo app is
/// expected to have and this one did not (D-211).
///
/// `ShareLink` rather than an `NSSharingServicePicker` of our own: it is the
/// system's list, it follows what the reader has turned on in Settings, and it
/// puts the share mark in the toolbar without this app choosing one.
///
/// It is not an `ActionItem`, because it opens a menu rather than performing a
/// command, and `disabled` on a `ShareLink` with no items is the system's job
/// rather than a check here — but an empty share sheet is a worse answer than
/// a dimmed control, so the guard stays.
private struct ShareItem: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        ShareLink(items: store.targets.map(\.url))
            .disabled(store.targets.isEmpty)
            .help(store.targets.count == 1
                  ? "Share this photo"
                  : "Share these \(store.targets.count) photos")
    }
}

/// The folder narrowed to what was loved, and back (D-176). The mark is the
/// readout and the control at once: hollow while the whole folder shows, solid
/// while it is narrowed.
private struct FavoritesItem: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    private var narrowed: Bool { store.filter == .favorite }
    private var empty: Bool { store.folderCounts.favorite == 0 }

    var body: some View {
        Button { router.perform(.filterFavorites) } label: {
            Label("Favorites", systemImage: narrowed ? Glyph.Heart().onSymbol : Glyph.Heart().symbol)
        }
        .disabled(empty && !narrowed)
        .foregroundStyle(narrowed ? Tokens.State.favorite : Tokens.Text.secondary)
        .help(narrowed ? "Show every photo again (>)"
                       : empty ? "Nothing in this folder is a favorite yet"
                               : "Show only favorites (>)")
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(narrowed ? "on" : "off")
    }
}

/// The filename filter's way in that is not `/` (D-42, D-143). The button
/// only: the field itself is in the band under the toolbar (D-208).
///
/// It was a `TextField` in this item, and the system put the whole thing in
/// the overflow at the first width that needed one — so `/` opened a field
/// behind a chevron, and the chip that would have said a filter was running
/// suppresses itself while the field is open. A running filter with nothing on
/// screen saying so is the exact defect D-143 exists to prevent.
private struct SearchItem: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    private var filtering: Bool { !store.searchText.isEmpty }

    var body: some View {
        Button {
            // A toggle, because it costs nothing to be wrong either way: the
            // text survives the field closing, so a mis-click loses a focus
            // ring and not a query.
            if store.searching { store.searching = false } else { router.perform(.search) }
        } label: {
            Label("Filter by Name", systemImage: Glyph.Magnifier().symbol)
        }
        // Nothing to filter with no folder open. Disabled rather than
        // hidden, which is this toolbar's rule (D-208, D-326).
        .disabled(store.folder == nil)
        .help(filtering ? "Edit the filename filter (/)" : "Filter by filename (/)")
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(filtering || store.searching ? "on" : "off")
    }
}

/// How the folder is ordered. Six orders is more than a toggle can carry, so
/// it is a menu — and the toolbar gives it the platform's own pull-down.
private struct SortItem: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    store.sort = order
                } label: {
                    if order == store.sort {
                        Label(order.label, systemImage: "checkmark")
                    } else {
                        Text(order.label)
                    }
                }
                // The checkmark is a picture. It says which row is on to
                // anybody looking at the menu and nothing at all to a screen
                // reader, which reads the checked row exactly as it reads the
                // seven others (A-8). `PopMenu` has this right one file away,
                // where `NSMenuItem.state` is the platform's own.
                .accessibilityAddTraits(order == store.sort ? [.isSelected] : [])
            }
            // Which way round, named for the field rather than as "Ascending"
            // and "Descending": the reader is choosing between oldest and
            // newest, not between two words that need the field held in mind
            // to decode (D-349). Two rows rather than one flipping item,
            // because a menu that changes its own label as you use it is the
            // state and the control disagreeing.
            //
            // Under a heading that names the field, because without one the
            // two rows sit below six others and read as if they applied to
            // all of them: "A to Z" under a list containing Size and Date
            // taken was reported as exactly that. They describe the checked
            // field alone, and now they say so (D-358).
            Section(store.sort.label) {
                ForEach(SortDirection.allCases, id: \.self) { direction in
                    Button {
                        store.sortDirection = direction
                    } label: {
                        if direction == store.sortDirection {
                            Label(store.sort.label(direction), systemImage: "checkmark")
                        } else {
                            Text(store.sort.label(direction))
                        }
                    }
                    .accessibilityAddTraits(direction == store.sortDirection ? [.isSelected] : [])
                }
            }
        } label: {
            Label("Sort", systemImage: Glyph.SortBars().symbol)
        }
        .disabled(store.folder == nil)
        .help("Sorted by \(store.sort.label.lowercased()), \(store.sort.label(store.sortDirection).lowercased())")
    }
}

/// Everything about the window a `NSToolbar` needs and SwiftUI does not
/// expose, set once when the window arrives (D-208).
///
/// Icon-only is the whole point of the migration, and there is no SwiftUI
/// spelling for it. `autosavesConfiguration` is what makes customization
/// outlive the launch — without it the sheet lets somebody rearrange a toolbar
/// that resets the next morning, which is worse than not offering it.
///
/// The title goes: the breadcrumb is the answer to "where am I", and a window
/// title saying the same folder name two inches to its left is the second
/// readout for one fact that D-202 spent a session removing.
@MainActor
struct ToolbarConfigurator: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        // The selection's name is an item that comes and goes, so the row is
        // rebuilt underneath the space; `SplitTheToolbar` reads the same fact
        // and puts it back.
        SplitTheToolbar(hasTarget: store.targetLabel != nil)
        WindowReader { window in
            guard let window else { return }
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            // No hairline under the toolbar when the grid scrolls beneath it.
            // `.automatic` draws one, which is the divider the design rules
            // ban, arriving by default rather than by decision (D-205).
            window.titlebarSeparatorStyle = .none
            guard let toolbar = window.toolbar else { return }
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = true
            toolbar.autosavesConfiguration = true
            Self.pushActionsRight(toolbar)
            Self.watch(toolbar)
        }
    }

    /// The navigation cluster keeps the leading edge and everything that acts
    /// on a photograph goes to the trailing one, with the space between them.
    ///
    /// Without it the actions start wherever the breadcrumb happens to end, so
    /// the trash sat under the pointer in one folder and two inches further
    /// right in the next: a control whose position is a function of the folder
    /// name is a control you have to find again every time you navigate. The
    /// split is also what the platform's toolbars do, and what D-205 asked for
    /// when it made the leading edge one navigation cluster (D-219).
    ///
    /// `NSToolbar` has no alignment to set. A flexible space between the two
    /// groups is how this is spelled, and SwiftUI has no way to say it, so the
    /// item goes in by hand after SwiftUI has built the row.
    static func pushActionsRight(_ toolbar: NSToolbar) {
        guard !rearranging else { return }
        guard let plan = spacePlan(for: toolbar.items.map(\.itemIdentifier.rawValue)) else { return }
        rearranging = true
        defer { rearranging = false }
        for i in plan.remove { toolbar.removeItem(at: i) }
        toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: plan.insert)
    }

    /// True while `pushActionsRight` is rearranging a toolbar.
    ///
    /// Removing an item posts `didRemoveItem`, and a main-queue observer
    /// posted from the main thread runs straight through rather than after.
    /// Without this the removal loop calls itself and works from indices it
    /// has already invalidated.
    @MainActor private static var rearranging = false

    /// Which spaces to take out of a row and where the one that belongs goes,
    /// or nil when the row is already right and when it has nothing to push.
    ///
    /// Pure, because `NSToolbar` builds no items until it is on a window and
    /// so cannot be driven from the suite. `remove` is back to front, so the
    /// indices behind each one hold still while the caller walks it.
    ///
    /// Putting the space back only when there was none at all was the bug: a
    /// rebuild that moved it rather than dropping it left the actions in the
    /// middle of the bar and nothing looked again (D-381). Hence the whole
    /// list of spaces and not the first: one in the wrong slot and one in the
    /// right slot are the same row to a check that stops counting at one.
    static func spacePlan(for identifiers: [String]) -> (remove: [Int], insert: Int)? {
        guard let wanted = spaceBelongs(in: identifiers) else { return nil }
        let spaces = identifiers.enumerated()
            .filter { $0.element == NSToolbarItem.Identifier.flexibleSpace.rawValue }.map(\.offset)
        // The one space that belongs sits with only non-spaces before it, so
        // its index counts the same either way and this comparison is exact.
        guard spaces != [wanted] else { return nil }
        return (spaces.reversed(), wanted)
    }

    /// Puts the space back whenever AppKit takes it out.
    ///
    /// `SplitTheToolbar` reads the same condition SwiftUI does and runs a turn
    /// later, which is usually soon enough and sometimes is not: the removal
    /// can land after that turn, and then nothing looks again until the next
    /// selection change. "Sometimes the actions are not at the trailing edge"
    /// is what a race reads like from outside. This is the toolbar saying so
    /// itself rather than us guessing when to ask (D-381).
    ///
    /// The observation is held by the toolbar, so it goes when the window
    /// does. A token parked in a static would outlive every tab ever opened.
    static func watch(_ toolbar: NSToolbar) {
        guard objc_getAssociatedObject(toolbar, &Self.watchKey) == nil else { return }
        let token = NotificationCenter.default.addObserver(forName: NSToolbar.didRemoveItemNotification,
                                                           object: toolbar, queue: .main) { note in
            guard let toolbar = note.object as? NSToolbar else { return }
            MainActor.assumeIsolated { pushActionsRight(toolbar) }
        }
        objc_setAssociatedObject(toolbar, &Self.watchKey, SpaceWatch(token), .OBJC_ASSOCIATION_RETAIN)
    }

    private nonisolated(unsafe) static var watchKey = 0

    /// Owns the observation and takes it out when the toolbar is released.
    private final class SpaceWatch {
        private let token: any NSObjectProtocol
        init(_ token: any NSObjectProtocol) { self.token = token }
        deinit { NotificationCenter.default.removeObserver(token) }
    }

    /// Which slot the one flexible space belongs in, or nil when the row has
    /// no action group to push.
    ///
    /// Pure, and the whole rule: the space goes immediately before the first
    /// item that acts on a photograph, counting the identifiers as they would
    /// read with no space in them. `target` is the selection's name and is an
    /// item only while something is chosen, so the anchor is whichever of the
    /// two comes first.
    static func spaceBelongs(in identifiers: [String]) -> Int? {
        let anchors = ["target", "rotateCCW"]
        let withoutSpaces = identifiers.filter { $0 != NSToolbarItem.Identifier.flexibleSpace.rawValue }
        return withoutSpaces.firstIndex { anchors.contains($0) }
    }
}

/// Puts the flexible space back after SwiftUI rebuilds the row.
///
/// One-shot did not hold. `target` is an item only while something is
/// selected, so selecting rebuilds the identifier list and takes the space
/// with it, and the actions slide back into the middle of the bar. This reads
/// the same condition SwiftUI does, so it runs on the update that caused the
/// rebuild, and it is idempotent: a toolbar that already has its space is left
/// alone (D-219).
private struct SplitTheToolbar: NSViewRepresentable {
    let hasTarget: Bool

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        // A turn later: SwiftUI has not finished rebuilding the row while it
        // is still updating the views inside it.
        DispatchQueue.main.async {
            guard let toolbar = view.window?.toolbar else { return }
            ToolbarConfigurator.pushActionsRight(toolbar)
        }
    }
}
