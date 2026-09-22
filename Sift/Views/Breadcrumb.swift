import SwiftUI
import AppKit

/// The path, walkable in both directions. Ancestors are muted, the open folder
/// is not. A chevron after every crumb lists that folder's subfolders, so the
/// path goes down as well as up (D-31). Long paths keep the last three
/// segments behind an ellipsis menu, because the tail is what tells you where
/// you are.
@MainActor
struct Breadcrumb: View {
    let url: URL?
    let open: (URL) -> Void
    let copyPath: (URL) -> Void
    /// Photographs dropped on an ancestor. The sidebar has taken drops since
    /// D-35 and the path had not, which left the commonest move of a cull —
    /// put this one back a level — reachable only by finding the same folder
    /// in the tree (D-187).
    let drop: ([URL], URL) -> Void

    /// Subfolders of every folder on the path, read once per folder rather than
    /// on every header render — the header redraws on each cursor move.
    @State private var children: [URL: [URL]] = [:]
    /// What each crumb really holds, which `children` stops saying once the
    /// cap has cut it (D-318).
    @State private var counts: [URL: Int] = [:]
    /// The copy control is drawn with the pointer in the path and not before.
    /// A permanent icon for something `⌘⇧C` and the context menu already do is
    /// chrome that stops being read (D-187).
    @State private var hovering = false

    struct Segment: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
    }

    /// The path as crumbs, root first. Pure, so a test can ask it rather than
    /// rendering a header: which folders a reader is offered is the whole
    /// behavior here, and it is the only way out of a folder on screen (D-111).
    /// `reachable` is the sandbox boundary, injected so this stays the pure
    /// function a test can ask (D-324).
    static func pathSegments(for url: URL?,
                             home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             reachable: @MainActor (URL) -> Bool = FolderAccess.isReachable) -> [Segment] {
        guard let url else { return [] }
        var urls: [URL] = []
        var u = url.standardizedFileURL
        while u.path != "/" {
            urls.append(u)
            let parent = u.deletingLastPathComponent()
            if parent == u { break }
            u = parent
        }
        urls.append(URL(fileURLWithPath: "/"))
        urls.reverse()

        let home = home.standardizedFileURL
        if let i = urls.firstIndex(where: { $0 == home }) {
            urls.removeFirst(i)
        }

        // And the same trim again at the sandbox boundary: the path bar stops
        // at the highest folder Sift was actually handed (D-324).
        //
        // It used to name every ancestor, because it was built from the path
        // and a path has always been readable. Since the sandbox most of
        // those are folders the app cannot list, and the sidebar had already
        // stopped showing them — so the header said the parent was there to
        // walk into while the sidebar said it did not exist, about the same
        // folder, a few inches apart. Drawing the crumb quietly and changing
        // its tooltip did not fix that: the disagreement a reader sees is
        // whether the folder is named at all, not how brightly.
        //
        // A grant covers what is under it, so reachability only ever turns on
        // as the path goes down and the first hit is the right place to cut.
        if let start = urls.firstIndex(where: { reachable($0) }) {
            urls.removeFirst(start)
        }

        // A path trimmed to one crumb — Home itself, or `/tmp` — gets its
        // parent back, so there is always somewhere above to click. The top of
        // the disk is the one folder that shows a single name, because it is
        // the one with nowhere above it.
        //
        // Not when the parent is outside the grant: that is the rule above,
        // undone one line later, and it is how the parent crumb survived the
        // first attempt at this.
        if urls.count == 1,
           case let parent = urls[0].deletingLastPathComponent().standardizedFileURL,
           parent != urls[0].standardizedFileURL,
           reachable(parent) {
            urls.insert(parent, at: 0)
        }
        return urls.map { Segment(name: $0 == home ? "Home" : name(of: $0), url: $0) }
    }

    /// `/` has no last path component, and "/" is what a reader of a path bar
    /// expects to see for it.
    private static func name(of url: URL) -> String {
        url.path == "/" ? "/" : url.lastPathComponent
    }

    private var ancestors: [Segment] { Self.pathSegments(for: url) }

    /// The most crumbs this will draw before the rest go in the `…` menu. A
    /// path deeper than this is a path nobody reads left to right anyway, and
    /// `ViewThatFits` needs a fixed list of arrangements to choose from.
    static let maxCrumbs = 6
    /// The fewest. The enclosing folder is the way out and the open folder is
    /// the answer to "where am I", so neither is ever given up — this rung is
    /// the one allowed to truncate (D-111, D-121).
    static let minCrumbs = 2

    var body: some View {
        let all = ancestors
        // As many as fit, not two whatever the room. It used to be
        // `suffix(2)` flat, so a wide window with 320pt of cap put four
        // ancestors behind an ellipsis for nothing (D-187).
        //
        // The header's own ladder, one level down (D-113): arrangements widest
        // first, each giving up one more crumb, and `ViewThatFits` compares
        // each one's *ideal* width — which for a row of truncatable names is
        // the width at which every name is whole. So a crumb is shown only
        // when it can be read, and the last rung, the one that fits nothing,
        // is the one that truncates.
        ViewThatFits(in: .horizontal) {
            row(all, keep: 6)
            row(all, keep: 5)
            row(all, keep: 4)
            row(all, keep: 3)
            row(all, keep: 2)
        }
        // Middle, not tail. The sidebar switched for this reason on D-145 and
        // the path did not: a folder of shoots is "2025-06-12 San Francisco"
        // beside "2025-06-13 San Francisco", and tail truncation renders both
        // as the same eleven characters (D-187).
        .lineLimit(1)
        .truncationMode(.middle)
        .onHover { hovering = $0 }
        .task(id: url) { await loadChildren(for: all.map(\.url)) }
    }

    /// Which crumbs a rung draws and which it hides. Pure, so the rule can be
    /// tested without rendering a header — the same reason `pathSegments` is
    /// (D-111).
    static func arrangement(_ all: [Segment], keep: Int) -> (hidden: [Segment], shown: [Segment]) {
        let n = min(max(keep, minCrumbs), all.count)
        return (Array(all.dropLast(n)), Array(all.suffix(n)))
    }

    @ViewBuilder
    private func row(_ all: [Segment], keep: Int) -> some View {
        let (hidden, shown) = Self.arrangement(all, keep: keep)
        HStack(spacing: Tokens.Space.s4) {
            if !hidden.isEmpty { elision(hidden) }
            // Six slots drawn now, not a `ForEach` handed over to be called
            // later. `maxCrumbs` is why there are six, and D-195 is why they
            // are written out: a `ForEach` keeps its content closure, and
            // SwiftUI calls it again whenever it rebuilds the list — including
            // from the display-link thread, where a main-actor closure is a
            // dead process.
            crumbSlot(shown, 0)
            crumbSlot(shown, 1)
            crumbSlot(shown, 2)
            crumbSlot(shown, 3)
            crumbSlot(shown, 4)
            crumbSlot(shown, 5)
            if let url {
                copyButton(url)
                    .padding(.leading, Tokens.Space.s4)
                    // Opacity rather than presence, so the path does not move
                    // sideways under the pointer that just arrived.
                    .opacity(hovering ? 1 : 0)
                    .animation(Tokens.Motion.fast, value: hovering)
            }
        }
    }

    /// One place in the row, or nothing if the path is shorter than that. The
    /// last crumb is the open folder and outranks the rest for room; every
    /// other one brings the chevron that opens its subfolders.
    ///
    /// A slot rather than an element of a `ForEach`, so the whole row is
    /// assembled while `body` runs and SwiftUI is left holding views rather
    /// than a closure it can call anywhere (D-195).
    @ViewBuilder
    private func crumbSlot(_ shown: [Segment], _ i: Int) -> some View {
        if i < shown.count {
            let seg = shown[i]
            if i == shown.count - 1 { here(seg).layoutPriority(1) } else { crumb(seg); separator(seg.url) }
        }
    }

    /// Every crumb here can be entered. `pathSegments` cuts the path at the
    /// sandbox boundary, so an ancestor Sift was not handed never becomes a
    /// crumb in the first place (D-324).
    private func crumb(_ seg: Segment) -> some View {
        Crumb(seg: seg,
              open: { open(seg.url) },
              copyPath: { copyPath(seg.url) },
              drop: { drop($0, seg.url) })
    }

    /// The folder you are in, and the way down out of it. The heading is the
    /// menu button, because a bare chevron between two crumbs reads as a
    /// separator and nobody clicks a separator.
    ///
    /// First in line for the room the crumb row has: this is the answer to
    /// "where am I", and the ancestor above it can say the same thing with
    /// fewer letters (D-121).
    @ViewBuilder
    private func here(_ seg: Segment) -> some View {
        let kids = children[seg.url] ?? []
        Group {
            if kids.isEmpty {
                Text(seg.name)
                    .textStyle(.strong)
            } else {
                PopMenuButton(hint: "Go into a subfolder (⌘↓)",
                              accessibilityLabel: seg.name,
                              accessibilityValue: "\(counts[seg.url] ?? kids.count) subfolders") {
                    kids.map { kid in PopMenuItem(title: kid.lastPathComponent) { open(kid) } }
                } label: {
                    HStack(spacing: Tokens.Space.s4) {
                        Text(seg.name)
                            .textStyle(.strong)
                        Glyph.draw(Glyph.Chevron())
                            .rotationEffect(.degrees(90))
                            .foregroundStyle(Tokens.Text.tertiary)
                    }
                }
                .fixedSize()
            }
        }
        .contextMenu {
            Button("Copy Path") { copyPath(seg.url) }
        }
    }

    /// The ancestors a long path drops. Without this they would be unreachable
    /// except by ⌘↑, one step at a time.
    ///
    private func elision(_ hidden: [Segment]) -> some View {
        PopMenuButton(hint: "Folders above this one",
                      accessibilityLabel: "Folders above this one") {
            hidden.map { seg in PopMenuItem(title: seg.name) { open(seg.url) } }
        } label: {
            Text("…")
                .textStyle(.quiet)
        }
        .fixedSize()
    }

    /// Between two crumbs: the separator, and the branch switch. An ancestor's
    /// other children hang off it, which is how you step sideways into the
    /// folder next to the one you are in.
    @ViewBuilder
    private func separator(_ folder: URL) -> some View {
        let kids = children[folder] ?? []
        if kids.isEmpty {
            Glyph.draw(Glyph.Chevron())
                .foregroundStyle(Tokens.Text.tertiary)
                .frame(width: Tokens.Layout.glyphButton, height: Tokens.Layout.glyphButton)
                .accessibilityHidden(true)
        } else {
            PopMenuButton(hint: "Subfolders of \(folder.lastPathComponent)",
                          accessibilityLabel: "Subfolders of \(folder.lastPathComponent)") {
                // A check marks the branch the path already runs through, which
                // is how you find your way back down after ⌘↑.
                kids.map { kid in
                    PopMenuItem(title: kid.lastPathComponent, checked: onPath(kid)) { open(kid) }
                }
            } label: {
                Glyph.draw(Glyph.Chevron())
                    .frame(width: Tokens.Layout.glyphButton, height: Tokens.Layout.glyphButton)
            }
            .hoverGlyph()
            .fixedSize()
        }
    }

    /// The same hover the arrows and the selection bar use, rather than the
    /// dimmer one the separators wear: this is an action, not punctuation.
    private func copyButton(_ folder: URL) -> some View {
        GlyphButton(shape: Glyph.Copy(),
                    label: "Copy folder path",
                    hint: "Copy \(folder.path) (⌘⇧C)") {
            copyPath(folder)
        }
    }

    private func onPath(_ folder: URL) -> Bool {
        guard let url else { return false }
        return FolderScanner.contains(folder, url)
    }

    /// One directory read per folder on the path, off the main actor.
    ///
    /// Cut to `folderTileMax` on the way in. A menu is built in one pass with
    /// no laziness at all, so the directory that hung the grid would hang it
    /// harder here; the real count stays in the button's accessibility label
    /// (D-318).
    private func loadChildren(for folders: [URL]) async {
        let found = await Task.detached(priority: .userInitiated) {
            folders.reduce(into: [URL: [URL]]()) { $0[$1] = FolderScanner.subfolders(of: $1) }
        }.value
        counts = found.mapValues(\.count)
        children = found.mapValues { Array($0.prefix(LibraryStore.folderTileMax)) }
    }
}

/// An ancestor: click it to go back up to it, or drop photographs on it to put
/// them there.
///
/// It used to be `fixedSize`, on the theory that a crumb squeezed to nothing is
/// a missing way out. Narrowing the header's cap showed what that actually
/// cost: the parent held its full name and the *open folder* was clipped to
/// "sh", so the one crumb that says where you are was the one destroyed. A
/// parent truncated to "tmp.lsO…GUq" is still a button and still the way out;
/// "sh" is not a folder name (D-121). The open folder takes the width first
/// now, and this truncates.
///
/// Its own view rather than a function on `Breadcrumb`, because it has two
/// pieces of state of its own: the pointer and the drag (D-187). A `@State` on
/// the parent would be one flag for every crumb in the path.
private struct Crumb: View {
    let seg: Breadcrumb.Segment
    let open: () -> Void
    let copyPath: () -> Void
    let drop: ([URL]) -> Void

    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        Button(action: open) {
            Text(seg.name)
                .textStyle(.readout)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
                // The same pill every other control in the app wears, and the
                // drag lands on the `on` step rather than inventing a third
                // color for "let go here" (D-184).
                .controlFill(hovering: hovering, on: targeted)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help("Open \(seg.url.path)")
        // Photographs only. A folder dropped on a crumb is a move nobody meant
        // and the sidebar refuses it for the same reason (D-35).
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter(FolderScanner.isImage)
            guard !images.isEmpty else { return false }
            drop(images)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Copy Path", action: copyPath)
            Button("Open Folder", action: open)
        }
        .accessibilityLabel(seg.name)
    }
}

/// The pair every file browser has. Back is the one people reach for, so it
/// leads; forward earns its place only because back exists. Both stay in the
/// row when they have nothing to do — an arrow that comes and goes moves the
/// path sideways under the pointer.
/// Muted until the pointer arrives. An icon that is always at full contrast
/// competes with the folder name it sits beside.
private struct HoverGlyph: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .foregroundStyle(hovering ? Tokens.Text.primary : Tokens.Text.tertiary)
            .onHover { hovering = $0 }
    }
}

private extension View {
    func hoverGlyph() -> some View { modifier(HoverGlyph()) }
}

/// Everything the header could not fit, in the order it gave it up. `»` rather
/// than `…`: the ellipsis in this header already means "folders above this
/// one", and two ellipses in one row that open different menus is one mark
/// doing two jobs (D-113).
@MainActor
/// The line every item in the header shares, so a control with a caption
/// hanging under it does not drag single-line text down to the middle of the
/// two. Anything that does not set it falls back to its own center, which is
/// right for every one-line piece in the row (D-139).
extension VerticalAlignment {
    private enum HeaderLine: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let headerLine = VerticalAlignment(HeaderLine.self)
}
