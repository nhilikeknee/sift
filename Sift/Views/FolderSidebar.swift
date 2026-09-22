import SwiftUI

/// The folders Sift can read, on the left, the way every photo tool has a
/// tree. One root per folder you have handed over, expandable downward;
/// pinned folders sit above as the subset you starred (D-35, D-327).
@MainActor
struct FolderSidebar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    /// Children per folder, read once and kept while the sidebar is up.
    @State private var children: [URL: [URL]] = [:]
    /// How many folders each one really holds, which is what `children` stops
    /// counting once the cap has cut it (D-318).
    @State private var childCounts: [URL: Int] = [:]
    @State private var counts: [URL: FolderPreview] = [:]
    @State private var expanded: Set<URL> = []

    var body: some View {
        // The list scrolls; the floor does not. Two controls that are about
        // the app rather than about the folder, in the corner a Mac keeps them
        // (D-183).
        VStack(spacing: 0) {
            list
            SidebarFooter()
        }
        .frame(width: store.sidebarWidth)
        .panelBackground(.sidebar)
        .task(id: store.folder) { await load() }
        .task(id: store.pinned) { await loadCounts(for: store.pinned) }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                // No `+` here any more. Pinned is a subset of Folders, and
                // a control that added straight to it could put a folder in
                // this section that the one below did not have — two lists
                // disagreeing about the same folder, which is the thing this
                // sidebar has now been caught by three times. Adding a
                // folder happens once, under Folders; pinning is a
                // right-click on a folder that is already there (D-327).
                // Gone when empty. It used to stay because the `+` in its
                // heading was the only way to pin a folder that was not on
                // screen, and a control that appears once you no longer
                // need it is no control at all (D-60). That `+` has gone,
                // so what is left is a heading over nothing — chrome that
                // stops being read. Pinning is now a mark at the edge of
                // any folder row (D-327).
                if !pinnedRows.isEmpty {
                    SectionLabel("Pinned")
                }
                // No empty state under it. The label and the `+` beside it say
                // what the section is and how to fill it, and a sentence
                // explaining a heading is a sentence the reader reads once and
                // then has to look past on every launch after that.
                // Only the pinned folders Sift can still read. A pin whose
                // grant has gone is not a row here, because a row here that
                // is not also a root below would be the invariant broken
                // (D-327). `Remove` unpins as well, so this filter is a belt
                // rather than the rule.
                ForEach(pinnedRows, id: \.self) { folder in
                    Row(folder: folder,
                        depth: 0,
                        expandable: false,
                        expanded: false,
                        count: counts[folder],
                        isCurrent: isCurrent(folder),
                        progress: progress(for: folder),
                        toggle: {},
                        open: { router.open(folder) },
                        openInTab: { router.openInNewTab(folder) },
                        drop: { router.drop($0, on: folder) },
                        setPin: { router.togglePin(folder) },
                        pinned: true,
                        isPinned: true)
                }
                // The one way in. It goes through the open panel, which is
                // what hands Sift the folder in the first place (D-324), so
                // "add a folder" and "grant a folder" are one act with one
                // control rather than two that can disagree.
                SectionLabel("Folders",
                             actionLabel: "Add a folder",
                             hint: "Give Sift another folder to read") {
                    router.addFolders()
                }
                .padding(.top, Tokens.Space.s12)
                ForEach(rows, id: \.folder) { row in
                    Row(folder: row.folder,
                        hint: FolderSidebar.tooltip(for: row.folder,
                                                    shown: (children[row.folder] ?? []).count,
                                                    of: childCounts[row.folder] ?? 0),
                        depth: row.depth,
                        expandable: !(children[row.folder] ?? []).isEmpty,
                        expanded: expanded.contains(row.folder),
                        count: counts[row.folder],
                        isCurrent: isCurrent(row.folder),
                        progress: progress(for: row.folder),
                        toggle: { toggle(row.folder) },
                        open: { router.open(row.folder) },
                        openInTab: { router.openInNewTab(row.folder) },
                        drop: { router.drop($0, on: row.folder) },
                        setPin: { router.togglePin(row.folder) },
                        isPinned: store.pinned.contains { $0.path == row.folder.path })
                }
            }
            .padding(Tokens.Space.s12)
        }
    }

    // MARK: the tree, flattened

    private struct TreeRow { let folder: URL; let depth: Int }

    /// Only the pinned folders Sift can still read. A pin whose grant has
    /// gone is not a row here, because a row here with no root below it is
    /// the invariant broken. `Remove` unpins as well, so this is a belt
    /// rather than the rule (D-327).
    private var pinnedRows: [URL] { store.pinned.filter(FolderAccess.isReachable) }

    /// One root per folder Sift has been handed (D-327).
    ///
    /// This used to be a single root that the store held still — the open
    /// folder's parent on arrival, raised by one step on the way up
    /// (D-319). Three rules, two bugs in a day, and a section that could not
    /// contain a folder somebody had pinned from another disk. The sandbox
    /// made the honest answer available: a grant *is* a root, the set of
    /// them is exactly what Sift can read, and "show me the siblings" stops
    /// being a rule about parents and becomes "you handed over the card, so
    /// the card is the root".
    ///
    /// It is also the same list Settings draws, so the two screens that say
    /// what Sift can reach cannot disagree.
    private var roots: [URL] { FolderAccess.granted }

    private var rows: [TreeRow] {
        var out: [TreeRow] = []
        func walk(_ folder: URL, depth: Int) {
            out.append(TreeRow(folder: folder, depth: depth))
            guard expanded.contains(folder) else { return }
            for kid in children[folder] ?? [] { walk(kid, depth: depth + 1) }
        }
        // A grant under another grant is drawn once, inside the one above
        // it: two roots for one folder is the duplicate row this section is
        // supposed to have stopped having.
        for root in roots where !roots.contains(where: { $0 != root && FolderScanner.contains($0, root) }) {
            walk(root, depth: 0)
        }
        return out
    }

    private func isCurrent(_ folder: URL) -> Bool {
        store.folder?.standardizedFileURL == folder.standardizedFileURL
    }

    /// Only the open folder has its flags read, so only it can show progress.
    /// Reading tags for every file in every folder on screen would be a scan
    /// per row (D-35).
    private func progress(for folder: URL) -> Double? {
        guard isCurrent(folder), !store.allPhotos.isEmpty else { return nil }
        let counts = store.folderCounts
        return Double(counts.keep + counts.reject) / Double(store.allPhotos.count)
    }

    private func toggle(_ folder: URL) {
        if expanded.contains(folder) { expanded.remove(folder) } else { expanded.insert(folder) }
        Task { await loadChildren(of: folder) }
    }

    /// Every folder from the root down to the open one, root first. The open
    /// folder is no longer the root's child — that is what holding the root
    /// still buys — so the rows between them have to be read and opened or the
    /// folder you are in is not on screen at all.
    private var pathFromRoot: [URL] {
        guard let folder = store.folder,
              let root = roots.first(where: { FolderScanner.contains($0, folder) })
        else { return [] }
        var chain: [URL] = []
        var walk = folder.standardizedFileURL
        while FolderScanner.contains(root, walk) {
            chain.append(walk)
            let parent = walk.deletingLastPathComponent()
            if parent == walk { break }
            walk = parent
        }
        return chain.reversed()
    }

    private func load() async {
        // Every root's own children, so a collapsed root still shows its
        // triangle and a root with nothing under it does not pretend to.
        for root in roots { await loadChildren(of: root) }
        let chain = pathFromRoot
        guard !chain.isEmpty else { return }
        // What was open stays open, minus anything no root covers any more.
        // Expanding a sibling and then walking into a shoot must not collapse
        // the sibling under you: the tree rearranging itself is a thing
        // nobody asked for.
        expanded = expanded
            .filter { folder in roots.contains { FolderScanner.contains($0, folder) } }
            .union(chain)
        // In order, so the tree is drawable at every step of a deep walk
        // instead of only once the last read lands.
        for folder in chain { await loadChildren(of: folder) }
    }

    /// The same ceiling the grid takes, for the same reason: a tree with
    /// nineteen thousand rows in it is a main thread that never comes back
    /// (D-318). What was left out is in the parent row's tooltip, because the
    /// panel has no room for a sentence and the grid beside it is the screen
    /// that carries the filter.
    private func loadChildren(of folder: URL) async {
        let kids = await Task.detached(priority: .userInitiated) { FolderScanner.subfolders(of: folder) }.value
        children[folder] = Array(kids.prefix(LibraryStore.folderTileMax))
        childCounts[folder] = kids.count
        await loadCounts(for: (children[folder] ?? []) + [folder])
    }

    private func loadCounts(for folders: [URL]) async {
        let wanted = folders.filter { counts[$0] == nil }
        guard !wanted.isEmpty else { return }
        let found = await Task.detached(priority: .utility) {
            wanted.reduce(into: [URL: FolderPreview]()) { $0[$1] = FolderScanner.preview(of: $1) }
        }.value
        counts.merge(found) { _, new in new }
    }
}

/// A heading in the sidebar, and optionally the one thing that section can do.
/// The control sits on the heading rather than under the list, so it stays put
/// as the list grows.
/// The name first and the path under it (D-145). It used to be the path
/// alone, which contains the name and buries it: the row is 220pt wide, a
/// shoot is called "2025-06-12 San Francisco", and the answer to "which folder
/// is this" was a line of home directory with the answer at the end of it. The
/// path stays because two shoots a year apart can share a name.
///
/// Static and out here rather than a computed property on the private row, for
/// the reason `HeaderBar.status(of:)` is: a rule inside a view is a rule with
/// no test on it.
extension FolderSidebar {
    static func tooltip(for folder: URL) -> String {
        "\(folder.lastPathComponent)\n\(folder.path)"
    }

    /// The same line with what the list is not showing on the end of it.
    static func tooltip(for folder: URL, shown: Int, of total: Int) -> String {
        guard total > shown else { return tooltip(for: folder) }
        return tooltip(for: folder) + "\nShowing \(shown) of \(total) folders"
    }
}

/// Settings and the keyboard map, at the bottom of the folder list.
///
/// They were two of five icons at the top right of the header, which is where
/// a Mac puts the controls that change what is on screen. Neither of these
/// does: one opens a window, the other an overlay, and they are about the app.
/// Sitting with the filter and the sort they made the reader price five
/// options where there are really two groups (D-183).
///
/// Right-aligned and icon-only, with the names in the tooltips the way the
/// `+` and the unpin cross in this panel already are. The header's icons keep
/// their words because the header is a row of six things read left to right;
/// two in a corner are not a row (D-180).
///
/// Settings first and Help last, because Help is the rightmost thing in every
/// Mac menu bar and this is the same reflex.
private struct SidebarFooter: View {
    @Environment(CommandRouter.self) private var router

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Spacer(minLength: 0)
            // Settings is where the switched-off features live, so a reader
            // looking for a feature the app does not appear to have has to be
            // able to find the room it is kept in (D-124).
            GlyphButton(shape: Glyph.Gear(),
                        label: "Settings",
                        hint: "Settings (\u{2318},)") { SettingsWindow.open() }
            // `?` is a keystroke you have to already know about to find the
            // list of keystrokes.
            GlyphButton(shape: Glyph.Question(),
                        label: "Keyboard shortcuts",
                        hint: "What every key does (?)") { router.perform(.toggleHelp) }
        }
        // No rule above it. The list runs out and the gap says the floor is a
        // different thing, which is the whole separation this needs.
        .padding(.horizontal, Tokens.Space.s12)
        .padding(.top, Tokens.Space.s8)
        .padding(.bottom, Tokens.Space.s12)
    }
}

private struct SectionLabel: View {
    let text: String
    var actionLabel: String?
    var hint: String = ""
    var act: (() -> Void)?

    init(_ text: String, actionLabel: String? = nil, hint: String = "", act: (() -> Void)? = nil) {
        self.text = text
        self.actionLabel = actionLabel
        self.hint = hint
        self.act = act
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Text(text)
                .textStyle(.quiet)
            Spacer(minLength: Tokens.Space.s8)
            if let act, let actionLabel {
                GlyphButton(shape: Glyph.Plus(), label: actionLabel, hint: hint, act: act)
            }
        }
        // The same inner edge the rows under it use, on both sides: leading
        // only is what let the `+` sit flush while the count beside it did not.
        .padding(.horizontal, Tokens.Space.s8)
        .padding(.bottom, Tokens.Space.s4)
    }
}

/// One folder. The disclosure triangle is its own hit target, so opening a
/// folder and looking inside it are two different clicks.
private struct Row: View {
    let folder: URL
    /// The row's tooltip, passed in rather than built here: only the sidebar
    /// knows how many of this folder's children the cap left out (D-318).
    var hint: String? = nil
    let depth: Int
    let expandable: Bool
    let expanded: Bool
    let count: FolderPreview?
    let isCurrent: Bool
    let progress: Double?
    let toggle: () -> Void
    let open: () -> Void
    /// The same folder in a tab of this window (D-370).
    let openInTab: () -> Void
    let drop: ([URL]) -> Void
    /// Flips this folder's pin. Owned by the sidebar, because the sidebar
    /// draws `store.pinned` and a write that only reached `Preferences` left
    /// the row on screen until the next launch (D-137).
    let setPin: () -> Void
    /// True on the rows in the Pinned section, which are the only rows that
    /// draw a control for it. Everywhere else the context menu is enough.
    var pinned = false
    /// Whether this folder is on the pinned list, which the control at the
    /// row's edge reads rather than the section the row happens to be in.
    var isPinned = false

    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Button(action: toggle) {
                Glyph.draw(Glyph.Chevron())
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .opacity(expandable ? 1 : 0)
                    .frame(width: Tokens.Layout.glyph, height: Tokens.Layout.glyphButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .disabled(!expandable)
            .accessibilityLabel(expanded ? "Collapse" : "Expand")

            Button(action: open) {
                HStack(spacing: Tokens.Space.s8) {
                    Glyph.draw(Glyph.Folder())
                    // Middle, not the tail Finder's sidebar uses. A
                    // shoot folder is named by whoever shot it, and they
                    // put what tells it apart at either end: a date in
                    // front, a client or a location behind. Tail
                    // truncation makes every folder from one day read the
                    // same. Neither end fits everything, which is what the
                    // tooltip is for (D-145).
                    Text(folder.lastPathComponent)
                        .textStyle(.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Tokens.Space.s4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            // The count is drawn as a bare number beside the name, so without
            // this the row reads "Harbor Weekend 60" and the reader is left to
            // guess what sixty of (D-343).
            .accessibilityLabel(folder.lastPathComponent)
            .accessibilityValue(count.map { $0.count > 0 ? "\($0.count) photos" : "" } ?? "")
            // On the name itself as well as on the row (D-145). The row's
            // own `.help` sits on the `VStack`, and this button is the
            // thing the pointer is actually over when somebody is trying
            // to read a name that does not fit.
            .help(hint ?? FolderSidebar.tooltip(for: folder))

            // On and off the pinned list without a right-click (D-42,
            // D-137, D-327). At the far edge, away from the name, and only
            // under the pointer: a mark on every row at all times is a
            // column of marks down the sidebar.
            //
            // The glyph is the row's state rather than the section it is
            // in — a pin to add, a slashed pin to take away — which is the
            // same folder answering the same question in both places. It has
            // to be the state, because a pinned folder is now also a root in
            // Folders and would otherwise offer to pin what is already
            // pinned. Not red and no confirmation: a pin is a bookmark, and
            // putting it back is this control again.
            //
            // It was `Cross`, and a cross in this app rejects a frame and
            // clears a filter. Sitting at the end of a folder row beside a
            // photo count, it read as "delete this folder", which is the one
            // thing the sidebar cannot do. Both rows draw a pin now and the
            // stroke is the verb (D-331).
            //
            // One slot at the trailing edge, not two. The count and the pin
            // were side by side and the pin was drawn at zero opacity the
            // rest of the time, so every row in the sidebar paid 30 points
            // for a control that was on screen in one of them. A 220pt
            // sidebar left the name about seventy, which is why a shoot
            // called `Day 1 Dawn Patrol` read as `Day…atrol`. The count is
            // the readout and the pin is the control, and the control takes
            // the readout's place while somebody is reaching for it (D-348).
            ZStack(alignment: .trailing) {
                if let count, count.count > 0 {
                    Text("\(count.count)")
                        .textStyle(.quiet)
                        .opacity(hovering ? 0 : 1)
                        .accessibilityHidden(hovering)
                }
                Group {
                    if isPinned {
                        GlyphButton(shape: Glyph.Unpin(),
                                    label: "Unpin \(folder.lastPathComponent)",
                                    hint: "Unpin \(folder.lastPathComponent)",
                                    act: setPin)
                    } else {
                        GlyphButton(shape: Glyph.Pin(),
                                    label: "Pin \(folder.lastPathComponent)",
                                    hint: "Pin \(folder.lastPathComponent)",
                                    act: setPin)
                    }
                }
                .opacity(hovering ? 1 : 0)
                .accessibilityHidden(!hovering)
            }
            .animation(Tokens.Motion.fast, value: hovering)
        }
        .foregroundStyle(isCurrent ? Tokens.Text.primary : (hovering ? Tokens.Text.primary : Tokens.Text.secondary))
        .padding(.vertical, Tokens.Space.s4)
        // The column has one inner edge and everything in it lands on that
        // edge. It was `s4`, which put the photo count 16pt from the panel's
        // own edge — the closest thing in the sidebar to it, and the only one
        // that is bare text rather than a glyph with a box's margin around it,
        // so it read as falling off (D-199).
        .padding(.horizontal, Tokens.Space.s8)
        .padding(.leading, CGFloat(depth) * Tokens.Space.s12)
        // The fill and the rail are one rectangle, clipped together: the rail
        // is the row's own base rather than a line floating inside it (D-317).
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(selectionFill)
                if let progress { ProgressBar(value: progress) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        }
        .onHover { hovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter(FolderScanner.isImage)
            guard !images.isEmpty else { return false }
            drop(images)
            return true
        } isTargeted: { targeted = $0 }
        // Not on the row. It was `.help` on everything below, which covers the
        // pin control at the far edge too, and an outer tooltip wins over the
        // one the control sets: hovering Unpin said where the folder was
        // instead of what the press would do (D-331). The name button carries
        // the path now — it is what the pointer is over when somebody is
        // reading a name that does not fit — and the control carries its verb.
        .contextMenu {
            // Through the router, not `Preferences` directly. The sidebar
            // draws `store.pinned`, and a write that only reached UserDefaults
            // left the row on screen until the next launch: an Unpin that
            // reported success and did nothing (D-137).
            Button(Preferences.isPinned(folder) ? "Unpin" : "Pin", action: setPin)
            Button("Open Folder") { open() }
            Button("Open in New Tab", action: openInTab)
            Button("Reveal in Finder") { FileOps.revealInFinder([folder]) }
        }
    }



    /// The row's own fill, drawn so it belongs to the panel it sits on.
    ///
    /// It was `Surface.raised`, an opaque gray, and the sidebar is drawn on a
    /// blur — `Surface.chrome` exists as the color to use *when the blur cannot
    /// be drawn*. So the panel took its tone from whatever was behind the
    /// window and the selected row did not: over a photograph the sidebar went
    /// green and the selection stayed a flat gray patch pasted on top of it.
    ///
    /// `.quaternary` is what the platform draws for an unemphasized sidebar
    /// selection. It is a vibrant fill rather than a color, so it blends with
    /// the material underneath the way every other part of the panel does, and
    /// it stays achromatic, which the rest of this app's chrome is on purpose
    /// (D-284).
    private var selectionFill: AnyShapeStyle {
        targeted || isCurrent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear)
    }
}

/// A hairline of how far a cull has got. Achromatic like the rest of the
/// chrome; the keep green would claim these were all keepers.
///
/// Vibrant rather than opaque, for the reason the row it sits in is: this draws
/// on the sidebar's blur, and an opaque `Surface.sunken` track over a window
/// with a photograph behind it is a black bar under the selected folder rather
/// than a hairline in it (D-284).
private struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.tertiary)
                .frame(width: geo.size.width * min(max(value, 0), 1))
        }
        .frame(height: Tokens.Border.ringWidth)
        // How far along is the bar's value, and it moves on every decision.
        // In the label it moved silently (D-343).
        .accessibilityLabel("Decided")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// The drag between the sidebar and the grid.
///
/// A sidebar that cannot be dragged is the one thing every Mac app with a
/// sidebar can do, and Sift's was 220 points whatever was in it: a shoot called
/// `2026-09-14 Marlow wedding` truncated to `20…vent` while a third of the
/// sidebar sat empty below it (D-229).
///
/// Nothing at rest. The material already says where the sidebar ends, and a
/// hairline drawn down the window for a control nobody is reaching for is the
/// same line the header is not allowed. It arrives with the pointer, which is
/// also when the cursor becomes the resize arrows: the platform's own answer to
/// "can I drag this", and the reason no label is needed.
struct SidebarDivider: View {
    @Environment(LibraryStore.self) private var store

    @State private var hovering = false
    /// The width the drag started from. A drag reports its total translation,
    /// so without this the second event of a drag measures from a width the
    /// first one already moved.
    @State private var startWidth: CGFloat?

    /// Where the drag puts the edge: whole points, clamped to the two ends.
    /// Its own function because the pointer cannot be driven from outside this
    /// process, so the arithmetic is the part a test can reach (D-229).
    ///
    /// It used to round to the 4pt scale, and that was the wrong scale to
    /// reach for. The scale is for measurements this project writes down; a
    /// width somebody drags is their number, not one of ours, and rounding it
    /// cost four points of stutter on every drag — the divider hopped while
    /// the grid behind it, centered in what was left, slid two points the
    /// other way (D-344).
    static func width(from start: CGFloat, by translation: CGFloat) -> CGFloat {
        let want = (start + translation).rounded()
        return min(max(want, Tokens.Layout.sidebarMin), Tokens.Layout.sidebarMax)
    }

    var body: some View {
        Rectangle()
            .fill(hovering || startWidth != nil ? Tokens.Border.hairline : .clear)
            .frame(width: Tokens.Border.hoverWidth)
            .frame(width: Tokens.Layout.dividerGrab)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .trailing))
            .onHover { hovering = $0 }
            .animation(Tokens.Motion.fast, value: hovering)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let from = startWidth ?? store.sidebarWidth
                        if startWidth == nil { startWidth = from }
                        store.sidebarWidth = Self.width(from: from, by: drag.translation.width)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            // Double-click on a divider puts it back, which is what Finder,
            // Mail and Xcode all do.
            .onTapGesture(count: 2) { store.sidebarWidth = Tokens.Layout.sidebar }
            .accessibilityLabel("Sidebar width")
            .accessibilityValue("\(Int(store.sidebarWidth)) points")
    }
}
