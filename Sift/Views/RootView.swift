import SwiftUI

/// The gallery window: breadcrumb, grid, and the sheets that act on a selection.
struct RootView: View {
    /// The gallery's own coordinate space, shared by the grid cells and the
    /// peek that is drawn beside one of them.
    nonisolated static let gallerySpace = "gallery"

    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var store = store
        // The help panel is over the *window*, not over the column of
        // photographs. It used to sit in the `ZStack` beside the sidebar, so
        // the room it had to lay itself out in was the window minus whatever
        // the sidebar was taking — and a wide sidebar on a small window left
        // it a panel narrow enough to wrap "Next photo" one letter to a line.
        // It is a modal with a scrim that eats clicks; what it covers should
        // be everything (D-320, D-334).
        ZStack {
        VStack(spacing: 0) {
            // Bare: the photographs and nothing else, in this window alone
            // (D-150). The header, the rail, the sidebar and the clipboard bar
            // are the gallery's chrome the way the panels are the preview's.
            if store.folder != nil, !bare {
                // Under the toolbar rather than in it, and both for the same
                // reason: each draws only once there is something to report,
                // and a toolbar item that comes and goes reshuffles the row
                // around it (D-65, D-208).
                GalleryBand()
                DecisionRail()
            }
            HStack(spacing: 0) {
                if store.showSidebar, store.folder != nil, !bare {
                    FolderSidebar()
                    SidebarDivider()
                }
                VStack(spacing: 0) {
                // Absence is a state: nothing here until `⌘C` has been used,
                // and then the bar arrives with what it is about (D-135).
                if !store.clipboard.isEmpty, !bare { ClipboardBar() }
                ZStack {
                // The same dark ground the preview goes to, for the same
                // reason: with nothing else on screen the surround is doing
                // the whole job of saying what a photograph's tones are (D-62).
                bare ? Tokens.Surface.judging : Tokens.Surface.canvas
                if let refused = store.refused {
                    NoAccess(folder: refused)
                } else if store.folder == nil {
                    EmptyState()
                } else if store.photos.isEmpty {
                    EmptyFolder()
                } else {
                    GridView()
                }
                // A full-size photograph arriving in one frame is a flinch, so
                // the panel fades the 120ms every hover state in the app fades
                // (D-298). Keyed on whether there is a peek at all rather than
                // on which photograph it is: a sweep along a row with `⌥` down
                // has to cut from one frame to the next, and animating the
                // identity would dissolve them into each other instead (D-130).
                if let peeked = store.peeked {
                    PeekOverlay(ref: peeked, anchor: store.hoveredFrame)
                        .transition(.opacity)
                }
                if store.showSummary { SummaryOverlay() }
                StatusOverlay(window: .gallery)
                }
                .animation(Tokens.Motion.fast, value: store.peeked == nil)
                // The space the peek measures a thumbnail against (D-131).
                // Named rather than `.local`, because the cell reporting the
                // frame and the overlay drawing beside it are in different
                // parts of the tree and `.local` would answer differently in
                // each.
                .coordinateSpace(.named(Self.gallerySpace))
                }
            }
        }
            if store.showHelp { HelpOverlay() }
        }
        // The gallery's chrome is the platform's toolbar now (D-208). `bare`
        // takes it away the way it used to take the header away: a window with
        // nothing but photographs in it (D-150).
        .toolbar(id: "gallery") { GalleryToolbar() }
        .toolbar(bare ? .hidden : .visible, for: .windowToolbar)
        .background(ToolbarConfigurator())
        .background(WindowFocusReporter(focus: .gallery) { store.focus = $0 })
        .onAppear {
            // Only a view can open a window, so the router borrows these.
            // The preview shows whichever gallery asked for it last.
            router.openPreviewWindow = {
                AppModel.shared.previewID = AppModel.shared.activeID
                openWindow(id: SiftApp.previewWindowID)
            }
            router.closePreviewWindow = { dismissWindow(id: SiftApp.previewWindowID) }
            router.openGalleryWindow = { folder in
                let id = UUID()
                AppModel.shared.pending[id] = folder
                openWindow(id: SiftApp.galleryID, value: id)
            }
            // The same call, plus the window the new one should join. The host
            // is the active session's window rather than `NSApp.keyWindow`:
            // the model already knows which gallery the command came from,
            // and a sheet or a panel can be key while the gallery under it is
            // the one being talked to (D-370).
            router.openGalleryTab = { folder in
                let id = UUID()
                let model = AppModel.shared
                model.pending[id] = folder
                if let active = model.activeID, model.window(of: active) != nil {
                    model.tabHost[id] = active
                }
                openWindow(id: SiftApp.galleryID, value: id)
            }
        }
        .frame(minWidth: Tokens.Layout.galleryMinWidth, minHeight: Tokens.Layout.galleryMinHeight)
        // The window keeps a title — the Window menu, Mission Control and
        // `SIFT_WINDOW_REPORT` all read it — and stops drawing it. The
        // breadcrumb two inches to its right is the answer to "where am I",
        // and the folder name in both places is the second readout for one
        // fact that D-202 spent a session taking out (D-208).
        .navigationTitle(store.folder?.lastPathComponent ?? "Sift")
        .plainWindowChrome()
        .withoutRestoration()
        .sheet(isPresented: $store.showTrashPanel) { TrashPanel() }
        .sheet(isPresented: $store.goToPath) { GoToPathSheet { router.openPath($0) } }
        .sheet(isPresented: $store.jumping) {
            JumpSheet(candidates: router.jumpCandidates) { router.open($0) }
        }
        .sheet(item: Binding(get: { store.trashConfirm?.window == .gallery ? store.trashConfirm : nil },
                             set: { if $0 == nil { store.trashConfirm = nil } })) { confirm in
            TrashConfirmSheet(confirm: confirm,
                              trash: { router.performTrash(confirm.refs) },
                              cancel: { store.trashConfirm = nil })
        }
        .sheet(isPresented: paletteHere) {
            CommandPalette(focus: .gallery) { router.perform($0) }
        }
        .sheet(isPresented: $store.reviewingRejects) { RejectReview() }
        .sheet(item: Binding(get: { store.ingesting.map(IngestSource.init) },
                             set: { if $0 == nil { store.ingesting = nil } })) { source in
            IngestSheet(source: source.url)
        }
        .sheet(item: $store.renameTarget) { ref in
            RenameSheet(ref: ref) { newName in router.rename(ref, to: newName) }
        }
        .sheet(isPresented: Binding(get: { store.batchRenameTargets != nil }, set: { if !$0 { store.batchRenameTargets = nil } })) {
            BatchRenameSheet(refs: store.batchRenameTargets ?? []) { pattern in
                router.batchRename(store.batchRenameTargets ?? [], pattern: pattern)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            // The third door. A drop from the Finder extends the sandbox to
            // what was dropped, so it is a grant and is kept as one (D-324).
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            FolderAccess.remember(isDir ? url : url.deletingLastPathComponent())
            router.open(url)
            return true
        }
    }

    private var bare: Bool { store.isBare(.gallery) }

    /// One palette over one store, presented by whichever window asked for it
    /// (D-67).
    private var paletteHere: Binding<Bool> {
        Binding(get: { store.palette == .gallery }, set: { if !$0 { store.palette = nil } })
    }
}

/// A URL is not `Identifiable`, and `.sheet(item:)` wants one.
private struct IngestSource: Identifiable {
    let url: URL
    var id: URL { url }
    init(_ url: URL) { self.url = url }
}

private struct EmptyState: View {
    @Environment(CommandRouter.self) private var router
    var body: some View {
        VStack(spacing: Tokens.Space.s16) {
            Text("Open a folder of photos")
                .textStyle(.title)
            Text("Press ⌘O, or drop a folder here.")
                .textStyle(.body, color: Tokens.Text.secondary)
            Button("Open Folder…") { router.perform(.openFolder) }
                .textStyle(.label)
                .padding(.top, Tokens.Space.s8)
        }
        .padding(Tokens.Space.s48)
    }
}

/// A folder Sift is not allowed to read (D-324).
///
/// Ahead of every other empty state, because it is not one: there is no
/// folder here to be empty, and the reason the grid is blank is a permission
/// rather than a shoot nobody has filled. Before the sandbox this screen had
/// nothing to say, because the app could read everything; now it is the one
/// place a reader meets the fence, and meeting a fence with no gate in it is
/// how a permission model gets switched off.
///
/// The path is drawn the way the breadcrumb draws one, from `Home` down, so
/// the screen that reports a privacy boundary is not itself the screen that
/// prints `/Users/<name>` (D-311).
private struct NoAccess: View {
    @Environment(CommandRouter.self) private var router
    let folder: URL

    var body: some View {
        VStack(spacing: Tokens.Space.s8) {
            Text("Sift cannot read this folder")
                .textStyle(.title)
            Text(SettingsWindow.shown(folder))
                .textStyle(.data, color: Tokens.Text.secondary)
            // What the button does that its label cannot say: which folder
            // the panel will land on, and that choosing it is permanent
            // rather than for this sitting.
            Text("Choose it in the panel to hand it over. Sift keeps it until you revoke it in Settings.")
                .textStyle(.body, color: Tokens.Text.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Tokens.Layout.proseMax)
                .padding(.top, Tokens.Space.s8)
            Button("Choose This Folder…") { router.grantAccess(to: folder) }
                .padding(.top, Tokens.Space.s8)
        }
        .padding(Tokens.Space.s48)
    }
}

private struct EmptyFolder: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router
    var body: some View {
        VStack(spacing: Tokens.Space.s8) {
            Text(headline)
                .textStyle(.title)
            Text(store.folder?.path ?? "")
                .textStyle(.data, color: Tokens.Text.secondary)
            // An empty folder and a folder emptied by a filter look identical
            // otherwise, and only one of them is fixed by clearing something.
            if narrowed {
                Button("Show all photos") {
                    store.filter = .all
                    store.searchText = ""
                }
                .textStyle(.label)
                .padding(.top, Tokens.Space.s8)
            }
            // A folder of folders is the common case on an SD card. Without this the
            // only way on is the breadcrumb, which is a long way from where the
            // eye is (D-31).
            //
            // Drawn with the filter on, too. It used to go when anything was
            // narrowed, which was right while the filter only knew photographs
            // and wrong the moment it reached folder names: on a directory of
            // thousands, filtering is the way to the one you want, and hiding
            // the grid took it away at exactly that moment (D-318).
            if !store.shownSubfolders.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                    Text("The photos are in one of these:")
                        .textStyle(.readout)
                    // Above the tiles, not under them: five hundred tiles is
                    // several screens, and a line at the bottom of that is a
                    // line nobody reaches (D-318).
                    FolderOverflowNote(shown: store.shownSubfolders.count,
                                       leftOut: store.subfoldersLeftOut)
                    FolderGrid(folders: store.shownSubfolders,
                               size: store.cellSize,
                               openInTab: { router.openInNewTab($0) }) { router.open($0) }
                }
                .padding(.top, Tokens.Space.s32)
            }
        }
        .padding(Tokens.Space.s48)
    }

    /// Whether what is on screen is the folder or only the part of it left by a
    /// filter. The two need different sentences and different offers.
    private var narrowed: Bool { store.filter != .all || !store.searchText.isEmpty }

    private var headline: String {
        if !store.searchText.isEmpty { return "Nothing matches \"\(store.searchText)\"" }
        if store.filter != .all { return "Nothing is flagged \"\(store.filter.label)\"" }
        return "No photos here"
    }
}
