import AppKit
import Observation

/// Command -> store mutation or file operation. The only place file ops are invoked.
@MainActor @Observable
final class CommandRouter {
    let store: LibraryStore
    @ObservationIgnored let prefetcher = Prefetcher()
    /// Injected by the scenes, which are the only things that can open a window.
    ///
    /// A request can arrive before the view that serves it has appeared:
    /// `RootView.onAppear` installs this, and the launch folder's
    /// `SIFT_SHOW` runs from the gallery's own `onAppear`, in no guaranteed
    /// order. It used to be `openPreviewWindow?()`, so one launch in three
    /// set `previewOpen` to true and put no window on screen — a command that
    /// reported success and did nothing (D-120).
    @ObservationIgnored var openPreviewWindow: (() -> Void)? {
        didSet {
            guard wantedPreview, let open = openPreviewWindow else { return }
            wantedPreview = false
            open()
        }
    }
    /// Somebody asked for the preview before there was anything able to open
    /// one. Cleared by the opener arriving, above.
    @ObservationIgnored private var wantedPreview = false
    @ObservationIgnored var closePreviewWindow: (() -> Void)?
    /// Injected by the gallery scene, for the same reason: only a view can open
    /// a window. Carries the folder the new window should start on.
    @ObservationIgnored var openGalleryWindow: ((URL?) -> Void)?
    /// The same thing, joined to this window's tab group instead of standing
    /// on its own. A tab is a whole window on macOS, so this differs from
    /// `openGalleryWindow` only in where the window lands (D-370).
    @ObservationIgnored var openGalleryTab: ((URL?) -> Void)?
    /// Injected by the preview scene, which is the only thing that can reach
    /// its own `NSWindow` (D-91).
    @ObservationIgnored var movePreviewToOtherScreen: (() -> Void)?
    /// A folder opened in a tab of this window rather than in place. The
    /// pointer's way to it is ⌘ held on the click that opens, and the context
    /// menu's is **Open in New Tab**; both land here (D-370).
    func openInNewTab(_ folder: URL) { openGalleryTab?(folder) }

    /// The folder ⌘↑ just left, if the current folder is still its parent.
    @ObservationIgnored private var cameUpFrom: URL?
    /// Folders visited before this one, and the ones stepped back out of.
    /// Observed, because the header's two arrows are lit by them.
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    /// Holds the target of a popped-up subfolder menu while it is on screen.
    /// Panels and menus. Injected rather than reached for, because what it
    /// stands on — `NSApp.keyWindow` — belongs to the process, and a test that
    /// touches the real one is at the mercy of whatever window is up (D-197).
    @ObservationIgnored var presenter: Presenter = AppKitPresenter()

    init(store: LibraryStore) { self.store = store }

    func perform(_ command: Command) {
        // The folder row is a second place the cursor can be, so the keys that
        // move it answer there first (D-33).
        if store.folderCursor != nil, let handled = performInFolderRow(command), handled { return }
        switch command {
        case .next:
            if store.isAtLastPhoto, !store.photos.isEmpty {
                let offer = nextSibling.map { FolderOffer(label: "Open \($0.lastPathComponent)", folder: $0) }
                store.showToast(endOfFolderSummary(), undoable: false, offer: offer, endsOnMove: true)
            }
            else { store.move(by: 1) }
        case .previous: store.move(by: -1)
        case .up:
            // Off the top row and into the folders, if there are any.
            if let c = store.cursor, c < store.gridColumns, store.enterFolderRow(fromColumn: c) {}
            else { store.move(by: -store.gridColumns) }
        case .down: store.move(by: store.gridColumns)
        case .first: store.moveToFirst()
        case .last: store.moveToLast()
        case .extendNext: store.move(by: 1, extendingSelection: true)
        case .extendPrevious: store.move(by: -1, extendingSelection: true)

        case .enterSingle: openPreview()
        case .confirm:
            // Return presses what the bar's own ring is on, before anything
            // else Return means here (D-157). A ring you can move and not
            // press is the thing this walk exists to avoid.
            if let control = store.barCursor {
                store.barCursor = nil
                perform(control)
            }
            // The mode bar's ring is the innermost thing on screen while a mode
            // is running, the same way the preview bar's is otherwise (D-245).
            else if let stop = store.modeBarCursor { pressModeBar(stop) }
            else if store.cropping { commitCrop() }
            else if store.reverting { commitRevert() }
            else if store.adjusting { commitAdjust() }
            else { closePreview() }
        case .cancel:
            // Esc leaves the bar before it leaves anything else: the ring is
            // the innermost thing on screen when it is up.
            if store.barCursor != nil { store.barCursor = nil }
            else if store.modeBarCursor != nil { store.modeBarCursor = nil }
            else if store.progress != nil { store.cancelProgress() }
            else if store.cropping { store.cropping = false; store.cropRect = nil }
            // Esc puts the photograph back the way it is on disk, which is what
            // leaving a preview means (D-240).
            else if store.reverting { store.reverting = false }
            // Esc throws the sliders away. The panel goes with them: leaving a
            // mode should not leave its furniture behind.
            else if store.adjusting { store.adjusting = false; store.adjustments = .neutral }
            // Esc walks back out of the modes it walked into, innermost first,
            // before it starts closing windows.
            // The zoom now outlives a cursor move (D-79), so Esc is what ends
            // it. It goes before the modes: a zoomed photo is the innermost
            // thing on screen.
            else if store.zoom != nil { store.resetZoom() }
            else if store.tournament { endTournament() }
            else if store.surveying { store.surveying = false }
            else if store.sideBySide { store.sideBySide = false }
            // The reject review is a sheet over the gallery, and a sheet is the
            // innermost thing on screen while it is up: it closes before the
            // window under it does. Its own button already promises "(Esc)",
            // and the sheet asks for the key itself with `onExitCommand`, but
            // the one key monitor (D-7) swallows Esc before the responder
            // chain sees it, so the promise has to be kept here (D-253).
            else if store.reviewingRejects { store.reviewingRejects = false }
            else if store.bareWindow != nil { store.leaveFocusMode() }
            else if store.focus == .preview { closePreview() }
            else { store.clearSelection() }
        case .zoomToggle:
            if store.zoom == nil {
                store.zoom = store.oneToOneScale
                store.zoomIsActual = true
                store.peekBegan = Date()
            } else {
                store.resetZoom()
                store.peekBegan = nil
            }
        case .zoomIn:
            store.zoom = (store.zoom ?? 1) * Self.zoomStep
            store.zoomIsActual = false
        case .zoomOut:
            let z = (store.zoom ?? 1) / Self.zoomStep
            if z <= 1.02 { store.resetZoom() } else { store.zoom = z; store.zoomIsActual = false }
        case .zoomToFace: zoomToFace()
        case .barNext: stepBar(by: 1)
        case .barPrevious: stepBar(by: -1)
        case .toggleFocusPeaking:
            store.showFocusPeaking.toggle()
            if store.showFocusPeaking {
                openPreview()
                store.hintOnce("focusPeaking",
                               "The painted edges are what the lens actually resolved. Hold 1:1 and arrow through the burst.")
            }
        case .setCompareAnchor:
            store.compareAnchor = store.compareAnchor == store.current?.url ? nil : store.current?.url
            store.showingCompare = false
            store.sideBySide = false
        case .toggleCompare:
            if let a = store.compareAnchor, a != store.current?.url {
                store.sideBySide = false
                store.showingCompare.toggle()
            }
        case .compareSideBySide: toggleSideBySide()
        case .survey:
            store.surveying.toggle()
            if store.surveying {
                store.sideBySide = false
                openPreview()
                store.hintOnce("survey", "Click the one that wins, or arrow to it. Esc goes back to one frame.")
            }
        case .tournament: toggleTournament()
        case .toggleFocusMode:
            // The window the keyboard is in is the one that goes bare (D-150).
            // It used to open the preview whichever window asked, so the one
            // command for taking chrome away could not be used on the window
            // carrying the most of it.
            if store.bareWindow != nil { store.leaveFocusMode() }
            else {
                let window = store.focus
                store.enterFocusMode(in: window)
                if window == .preview { openPreview() }
            }
        case .toggleInfo:
            store.showInfo.toggle()
            // The panel lives in the preview, so asking for it there opens it.
            if store.showInfo { openPreview() }
        case .toggleFilmstrip:
            store.showFilmstrip.toggle()
            // Same reason as the info panel above: the filmstrip draws in the
            // preview window, and `f` is bound there, but the command palette
            // offers it from the gallery where turning it on did nothing
            // anybody could see. Found by the contact sheet (D-118).
            if store.showFilmstrip { openPreview() }
        case .toggleClipping:
            store.showClipping.toggle()
            if store.showClipping { openPreview() }
        case .toggleTrashPanel: store.showTrashPanel.toggle()
        case .showSummary: store.showSummary.toggle()
        case .search: store.searching = true
        case .toggleHelp: store.showHelp.toggle()

        case .flagKeep:
            // In a tournament, keep does not flag: it says "this one is better
            // than the one it is beside", which is a different sentence (D-83).
            if store.tournament { promoteChallenger() } else { setFlag(.keep) }
        case .flagReject: setFlag(.reject)
        case .unflag: setFlag(nil)
        case .toggleFavorite: toggleFavorite()
        case .labelRed: setLabel(.red)
        case .labelYellow: setLabel(.yellow)
        case .labelGreen: setLabel(.green)
        case .labelBlue: setLabel(.blue)
        case .labelPurple: setLabel(.purple)
        case .clearLabel: setLabel(nil)
        case .toggleAutoAdvance: store.autoAdvance.toggle()
        // A toggle and not a cycle: two states, reversed by the same press,
        // so no menu in front of it and nothing to confirm (D-176). A filter
        // already on something else is replaced rather than added to, because
        // "only the favorites" is the whole of what this says.
        case .filterFavorites: store.filter = store.filter == .favorite ? .all : .favorite

        case .trash: trashTargets()
        case .reviewRejects: openRejectReview()
        case .undo: undo()
        case .rotateCW: rotate(clockwise: true)
        case .rotateCCW: rotate(clockwise: false)
        case .crop:
            store.cropping.toggle()
            if !store.cropping { store.cropRect = nil }
        case .adjust:
            store.adjusting.toggle()
            if store.adjusting {
                // The panel draws in the preview window, so asking for it
                // anywhere else opens that window first (D-118).
                openPreview()
                // The sliders come up where an earlier overwrite left them
                // (D-165), so this has to run before the panel is looked at.
                store.loadAdjustRecord()
            } else {
                store.adjustments = .neutral
                store.adjustBaseline = .neutral
            }
        case .saveOverOriginal:
            // The revert preview's own save, because ⇧Return is the key that
            // writes into the photograph and a revert is a write into it.
            if store.reverting {
                commitRevert()
                return
            }
            // Crop first, because the two modes cannot both be on and the crop
            // is the one with a box on screen saying what ⇧Return will do.
            if store.cropping {
                commitCrop(overwriting: true)
                return
            }
            guard store.adjusting else {
                store.showToast("Open the sliders first", undoable: false)
                return
            }
            // Every slider back to 0 on a photograph that was overwritten is
            // not "nothing to do": it is the edit taken off, which is exactly
            // what Revert does (D-165).
            if store.adjustments.isNeutral, store.adjustRevertable {
                revertToOriginal()
                return
            }
            guard store.adjustments != store.adjustBaseline else {
                store.showToast(store.adjustments.isNeutral ? "Move a slider first"
                                                            : "That is already what is on the file", undoable: false)
                return
            }
            commitAdjust(overwriting: true)
        case .revertToOriginal: revertToOriginal()
        case .moveToFolder: moveTargets(to: nil)
        case .moveToLastFolder: moveTargets(to: Preferences.lastMoveFolder)
        case .copyToFolder: copyTargets()
        case .openInEditor: openInEditor()
        case .ingest: store.ingesting = store.folder
        case .slideshow:
            store.slideshow.toggle()
            if store.slideshow {
                openPreview()
                store.hintOnce("slideshow", "Any key stops it. The arrows still work if you want to drive.")
            }
        case .previewOnOtherScreen: movePreviewToOtherScreen?()
        case .rename: store.renameTarget = store.current
        case .batchRename: store.batchRenameTargets = store.targets
        case .revealInFinder: FileOps.revealInFinder(store.targets.map(\.url))
        case .copy: loadClipboard()
        case .copyImage: copyImages()
        case .copyName: copyNames()
        case .pasteHere: pasteHere()
        case .clearClipboard:
            store.clipboard = []
            store.showToast("Clipboard emptied", undoable: false)
        case .copyPath: if let folder = store.folder { copyPath(of: folder) }
        case .openWith: FileOps.openWithDefaultApp(store.targets.map(\.url))

        case .toggleSelect: store.toggleSelectCurrent()
        case .selectAll: store.selectAll()
        case .openFolder: openFolderPanel()
        case .openParent:
            if let child = store.folder, case let parent = child.deletingLastPathComponent(), parent != child {
                open(parent)
                // Remembered so ⌘↓ comes straight back down to where you were,
                // instead of landing on whichever subfolder sorts first.
                cameUpFrom = child
            }
        case .openSubfolder: descend()
        case .back: goBack()
        case .forward: goForward()
        case .goToPath: store.goToPath = true
        case .toggleSidebar: store.showSidebar.toggle()
        case .jumpToFolder: store.jumping = true
        case .commandPalette: store.palette = store.focus
        case .newWindow: openGalleryWindow?(store.folder)
        case .newTab: openGalleryTab?(store.folder)
        case .togglePin: togglePin()
        case .nextFolder: stepSibling(by: 1)
        case .previousFolder: stepSibling(by: -1)
        case .thumbsLarger: stepCellSize(by: 1)
        case .thumbsSmaller: stepCellSize(by: -1)
        }
        refreshPrefetch()
        // A command, while the preview has the keyboard, brings its controls up
        // for a moment. Without this the bar is invisible to someone who never
        // touches the trackpad (D-64).
        //
        // Moving to another photo is the exception, and it is the whole point:
        // walking a folder with the arrow keys is the app's main gesture, and a
        // bar that reappears on every press is a bar that is always up during
        // the one thing somebody came here to do (D-199).
        if store.focus == .preview, !Command.navigation.contains(command) {
            store.barPulse &+= 1
        }
    }

    /// The same commands, aimed at one photo rather than at the cursor: a
    /// control drawn on a cell, a context menu, the preview bar (D-47). A photo
    /// inside the selection brings the selection with it, the way a drop does.
    func perform(_ command: Command, on ref: PhotoRef) {
        store.aiming(at: store.targets(for: ref)) {
            switch command {
            // Two commands read the cursor rather than the target list, so they
            // are pointed at the photo by hand instead.
            case .rename: store.renameTarget = ref
            case .enterSingle:
                if let i = store.photos.firstIndex(where: { $0.url == ref.url }) { store.cursor = i }
                openPreview()
            default: perform(command)
            }
        }
    }

    /// One press of the zoom keys. A quarter each way, so four presses is
    /// roughly a doubling and no press is a jump.
    private static let zoomStep: CGFloat = 1.25

    /// Rejects in the folder before the app mentions that they can be looked
    /// over. Below a handful the review is more ceremony than the decision
    /// deserves.
    private static let rejectHintFloor = 5

    /// Steps through the cell sizes in `Tokens`, stopping at either end rather
    /// than wrapping: a size control that jumps from largest to smallest on one
    /// more press is a size control you stop trusting.
    private func stepCellSize(by delta: Int) {
        let steps = Tokens.Layout.gridCellSteps
        let here = steps.firstIndex(of: store.cellSize) ?? steps.firstIndex(of: Tokens.Layout.gridCell) ?? 0
        let next = min(max(here + delta, 0), steps.count - 1)
        store.cellSize = steps[next]
    }

    /// What the arrow keys mean while the cursor is up in the folder row.
    /// Returns nil for a command the row has no opinion about, which then runs
    /// as usual on the photos below.
    private func performInFolderRow(_ command: Command) -> Bool? {
        switch command {
        case .next: store.moveInFolderRow(by: 1); return true
        case .previous: store.moveInFolderRow(by: -1); return true
        case .down: store.leaveFolderRow(); return true
        case .up: return true                                   // already at the top
        case .enterSingle:
            if let entry = store.currentFolderEntry { open(entry.url) }
            return true
        case .cancel: store.leaveFolderRow(); return true
        case .first: store.folderCursor = 0; return true
        case .last: store.folderCursor = max(0, store.folderRow.count - 1); return true
        default:
            // Anything else is about a photo. Drop back to the photo cursor and
            // let it run there, so no keystroke acts on something off screen.
            store.leaveFolderRow()
            return nil
        }
    }

    /// `⌘⇧→`: the next shoot on the card, without climbing to the card and back
    /// down. Siblings are the parent's subfolders, in the order the breadcrumb
    /// lists them.
    private func stepSibling(by delta: Int) {
        guard let folder = store.folder else { return }
        let parent = folder.deletingLastPathComponent()
        guard parent != folder else { return }
        let siblings = Self.worthOffering(FolderScanner.subfolders(of: parent), keeping: folder)
        guard let i = siblings.firstIndex(where: { $0.standardizedFileURL == folder.standardizedFileURL }) else {
            store.showToast("No folders beside \(folder.lastPathComponent)", undoable: false)
            return
        }
        let target = i + delta
        guard siblings.indices.contains(target) else {
            store.showToast(delta > 0 ? "Last folder in \(parent.lastPathComponent)" : "First folder in \(parent.lastPathComponent)",
                            undoable: false)
            return
        }
        open(siblings[target])
    }

    /// The folder after this one, for the end-of-folder handoff.
    var nextSibling: URL? {
        guard let folder = store.folder else { return nil }
        let parent = folder.deletingLastPathComponent()
        guard parent != folder else { return nil }
        let siblings = Self.worthOffering(FolderScanner.subfolders(of: parent), keeping: folder)
        guard let i = siblings.firstIndex(where: { $0.standardizedFileURL == folder.standardizedFileURL }),
              siblings.indices.contains(i + 1) else { return nil }
        return siblings[i + 1]
    }

    /// Two frames at once, which needs two frames: without an A marked there is
    /// nothing to put beside the photo, so the command marks one rather than
    /// failing at the person pressing it.
    private func toggleSideBySide() {
        if store.sideBySide { store.sideBySide = false; return }
        guard let current = store.current else { return }
        if store.compareAnchor == nil || store.compareAnchor == current.url {
            // Marking A on the photo you are looking at and then asking to see
            // it beside itself is the one case this cannot answer.
            guard let other = neighborForCompare(of: current) else {
                store.showToast("Mark a photo with B first, then press | on the one to compare it with",
                                undoable: false)
                return
            }
            store.compareAnchor = other.url
        }
        store.sideBySide = true
        store.hintOnce("sideBySide", "Both frames zoom and pan together. Click the other one to decide about it instead.")
    }

    /// A tournament: hold the best frame so far and put every other one beside
    /// it (D-83). Keep promotes the challenger, reject flags it and moves on,
    /// and Esc ends it by flagging whatever survived.
    ///
    /// It is the shape a cull already has in the head — "is this better than
    /// the one I liked?" — and none of the four apps researched does it.
    private func toggleTournament() {
        if store.tournament { endTournament(); return }
        guard let current = store.current, store.photos.count > 1 else {
            store.showToast("A tournament needs more than one photo", undoable: false)
            return
        }
        store.champion = current.url
        store.compareAnchor = current.url
        store.tournament = true
        store.surveying = false
        store.sideBySide = true
        openPreview()
        store.move(by: 1)
        store.hintOnce("tournament",
                       "Keep promotes the frame on the right. Reject drops it. Esc ends it and keeps whatever is left standing.")
    }

    /// The challenger won. It becomes the one everything else is measured
    /// against, and the cursor moves on to the next contender.
    private func promoteChallenger() {
        guard let current = store.current else { return }
        store.champion = current.url
        store.compareAnchor = current.url
        if store.isAtLastPhoto { endTournament() } else { store.move(by: 1) }
    }

    /// The end of a tournament is a decision, so it writes one: the survivor is
    /// flagged keep. Ending it without that would be a comparison nobody
    /// recorded.
    private func endTournament() {
        store.tournament = false
        store.sideBySide = false
        store.compareAnchor = nil
        defer { store.champion = nil }
        guard let champ = store.championRef else { return }
        store.aiming(at: [champ]) { setFlag(.keep) }
        store.showToast("Kept \(champ.name)")
    }

    /// The photo before this one, or after it at the top of the folder. What A
    /// would be if you had marked it a moment ago, which is what you meant.
    private func neighborForCompare(of ref: PhotoRef) -> PhotoRef? {
        guard let i = store.photos.firstIndex(where: { $0.url == ref.url }) else { return nil }
        if i > 0 { return store.photos[i - 1] }
        return store.photos.indices.contains(i + 1) ? store.photos[i + 1] : nil
    }

    /// `⇧X`. The rejects of the whole folder, in one place, before the one
    /// action in the app that a click cannot bring back.
    private func openRejectReview() {
        guard !store.rejected.isEmpty else {
            store.showToast("Nothing is flagged reject in \(store.folder?.lastPathComponent ?? "this folder")",
                            undoable: false)
            return
        }
        store.reviewingRejects = true
    }

    /// Clearing one photo's flag from the review. Deliberately not
    /// `perform(.unflag, on:)`: that carries the selection along, and a click on
    /// one face in a wall of rejects is about that face.
    func takeBack(_ ref: PhotoRef) {
        store.aiming(at: [ref]) { perform(.unflag) }
    }

    /// The other button at the foot of the review (D-81). FastRawViewer's
    /// answer, and the safer of the two: the rejects go into a folder beside
    /// the photos rather than into a system Trash that anything on the machine
    /// can empty. They are still there tomorrow, still in order, still openable
    /// in Sift by walking into them.
    func moveRejectsAside() {
        let refs = store.rejected
        guard !refs.isEmpty, let folder = store.folder else { store.reviewingRejects = false; return }
        store.reviewingRejects = false
        let dest = folder.appendingPathComponent(Self.rejectFolderName)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            store.showError("Could not make \(Self.rejectFolderName): \(error.localizedDescription)")
            return
        }
        var moved: Set<URL> = []
        // `over:` is the refs the sheet listed rather than `store.targets`, so
        // this no longer needs to borrow the aim — the run carries what it acts
        // on, which is the same reason a confirmed trash does (D-193).
        runBatch("Move aside", banner: "Moving aside", over: refs,
                 io: { ref in BatchStep(undo: try FileOps.move(ref.url, into: dest).1) },
                 each: { ref, _ in
                     moved.insert(ref.url)
                     store.session.moved += 1
                 },
                 report: { self.batchReport($0, verb: "Moved", whereTo: Self.rejectFolderName,
                                            cannot: "could not be moved") },
                 finish: { _ in store.remove(moved) })
    }

    /// Where the rejects go. A leading underscore so it sorts to the top of the
    /// folder and reads as not-a-shoot, which is the convention FRV set.
    static let rejectFolderName = "_Rejected"

    /// The button at the foot of the review. One batch, one undo, and the
    /// review closes because what it was about is gone.
    func trashRejects() {
        let refs = store.rejected
        guard !refs.isEmpty else { store.reviewingRejects = false; return }
        store.reviewingRejects = false
        store.aiming(at: refs) { trashTargets() }
    }

    func openPreview() {
        guard store.current != nil else { return }
        store.previewOpen = true
        guard let open = openPreviewWindow else { wantedPreview = true; return }
        open()
    }

    func closePreview() {
        store.previewOpen = false
        store.focus = .gallery
        closePreviewWindow?()
    }

    /// Key-up half of hold-to-peek. A press shorter than 250 ms is a tap and stays
    /// zoomed; anything longer was a hold, so release snaps back to fit.
    func releasePeek() {
        guard let began = store.peekBegan else { return }
        store.peekBegan = nil
        if Date().timeIntervalSince(began) >= 0.25 { store.resetZoom() }
    }

    // MARK: session

    private func endOfFolderSummary() -> String {
        let s = store.session
        var parts = ["Last photo"]
        if s.kept > 0 { parts.append("\(s.kept) kept") }
        if s.rejected > 0 { parts.append("\(s.rejected) rejected") }
        if s.trashed > 0 {
            parts.append("\(s.trashed) trashed (\(s.trashedBytes.formatted(.byteCount(style: .file))))")
        }
        return parts.joined(separator: "  ·  ")
    }

    func restoreFromTrash(_ entry: TrashEntry) {
        do {
            if FileManager.default.fileExists(atPath: entry.original.path) {
                throw FileOps.Failure(message: "\(entry.name) already exists there.")
            }
            try FileManager.default.moveItem(at: entry.trashed, to: entry.original)
            if let i = store.trashLog.firstIndex(of: entry) { store.trashLog[i].restored = true }
            store.session.trashed -= 1
            store.session.trashedBytes -= entry.size
            store.reload()
            if let i = store.photos.firstIndex(where: { $0.url == entry.original }) { store.cursor = i }
        } catch { store.showError(error.localizedDescription) }
    }

    /// Copies a folder's path as text and says so, since the pasteboard is invisible.
    func copyPath(of folder: URL) {
        FileOps.copyText(folder.path)
        store.showToast("Copied \(folder.lastPathComponent) path", undoable: false)
    }

    func openRecent(_ index: Int) {
        let list = Preferences.recentFolders
        guard list.indices.contains(index) else { return }
        open(list[index])
    }

    // MARK: batches

    /// Runs `op` over every target, collecting one undo that reverses all of them (D-15).
    /// `toast` is given the count and the first target's name; returning nil means no toast.
    @discardableResult
    private func batch(_ label: String,
                       over: [PhotoRef]? = nil,
                       toast: ((Int, String) -> String)? = nil,
                       _ op: (PhotoRef) throws -> UndoableOp?) -> Int {
        // `over` is for the one path that answers a question asked earlier: the
        // aim is restored when `perform` returns (D-104), so a confirmed trash
        // has to act on what the question named rather than on the aim it finds
        // when the yes arrives (D-193).
        let targets = over ?? store.targets
        var undos: [UndoableOp] = []
        for ref in targets {
            do { if let u = try op(ref) { undos.append(u) } } catch { store.showError(error.localizedDescription); break }
        }
        guard !undos.isEmpty else { return 0 }
        store.pushUndo(UndoableOp(label: label, inverse: .all(undos.map(\.inverse))))
        if let toast { store.showToast(toast(undos.count, targets.first?.name ?? "")) }
        return undos.count
    }

    /// What one file's operation produced: the undo, and where the file ended
    /// up when the bookkeeping needs to know. The trash log walks the landing
    /// site, and nothing else does.
    struct BatchStep {
        let undo: UndoableOp
        var landed: URL?
    }

    /// What a batch managed, for the sentence at the end. A run can be all
    /// three at once: forty moved, two that would not move, and a stop.
    struct BatchOutcome {
        var done = 0
        var skipped = 0
        var cancelled = false
        var firstName = ""
    }

    /// Every command that moves bytes: trash, move, move aside, copy, rotate.
    ///
    /// One file at a time off the main actor, so a five-hundred frame move
    /// reports where it has got to and can be stopped, instead of freezing the
    /// window with nothing on screen (D-196). The metadata commands do not come
    /// through here: a tag write is fast enough that a banner would only flash,
    /// and they keep `batch` below.
    ///
    /// `io` is the file operation and is the only part that leaves the main
    /// actor. `each` is the bookkeeping for a file that succeeded — evicting a
    /// cache, counting a session, remembering what to take out of the grid —
    /// and runs on the main actor between files, so nothing it touches needs to
    /// be `Sendable`. `finish` runs once, after the banner is down, with the
    /// outcome and the undo already pushed.
    ///
    /// Returns false without starting when another batch holds the banner,
    /// which is what stops `⌘Z` colliding with a run in flight (D-189).
    @discardableResult
    private func runBatch(_ label: String,
                          banner: String,
                          over targets: [PhotoRef],
                          showing: Bool = true,
                          io: @escaping @Sendable (PhotoRef) throws -> BatchStep,
                          // The same attribute `runWithProgress` carries, for
                          // the same reason: these three run on the main actor
                          // between files and read half the router, and a
                          // `self.` on every line of them says nothing.
                          @_implicitSelfCapture each: @escaping (PhotoRef, BatchStep) -> Void = { _, _ in },
                          @_implicitSelfCapture report: @escaping (BatchOutcome) -> String,
                          @_implicitSelfCapture finish: @escaping (BatchOutcome) -> Void = { _ in }) -> Bool {
        guard !targets.isEmpty else { return true }
        let started = store.runWithProgress(banner, total: showing ? targets.count : 0) { run in
            var undos: [UndoableOp] = []
            var outcome = BatchOutcome(firstName: targets.first?.name ?? "")
            for ref in targets {
                if run.cancelled { break }
                // One file at a time rather than a wide fan-out: this is disk
                // work, and going wider queues writes against each other for no
                // gain (D-41).
                let result = await Task.detached(priority: .userInitiated) { () -> Result<BatchStep, any Error> in
                    do { return .success(try io(ref)) } catch { return .failure(error) }
                }.value
                switch result {
                case .success(let step): undos.append(step.undo); outcome.done += 1; each(ref, step)
                // Counted rather than fatal. A run that stops on the third of
                // five hundred leaves the other four hundred and ninety-seven
                // undone and says nothing about why (D-41).
                case .failure: outcome.skipped += 1
                }
                run.step()
            }
            // Read before the banner goes, and taken down here so the toast is
            // not stacked under it.
            outcome.cancelled = run.cancelled
            run.end()

            if !undos.isEmpty {
                store.pushUndo(UndoableOp(label: label, inverse: .all(undos.map(\.inverse))))
            }
            finish(outcome)
            // A clean batch says nothing: the pill in the corner names what it
            // will take back, which is the whole report (D-283). A batch that
            // skipped or was cancelled says more than the pill can, so it
            // reports, and decays into the pill six seconds later the way every
            // message does.
            let partial = outcome.skipped > 0 || outcome.cancelled
            store.showToast(report(outcome), undoable: !undos.isEmpty && !partial)
        }
        // A second batch is refused by the progress claim (D-189), and the
        // refusal has to be said out loud: the file commands were synchronous
        // before D-196 and always ran, so a `d` that quietly did nothing during
        // a rotation would be a new silence rather than an old one.
        if !started { refuse() }
        return started
    }

    /// One sentence covering done, skipped and stopped, because a batch can be
    /// all three at once. `verb` is the past tense — "Moved", "Copied".
    private func batchReport(_ outcome: BatchOutcome, verb: String, whereTo: String = "",
                             cannot: String) -> String {
        let tail = whereTo.isEmpty ? "" : " to \(whereTo)"
        // Stopping is the first thing to say, even when it stopped before the
        // first file: "nothing moved" alone reads as a failure.
        if outcome.cancelled {
            return outcome.done == 0
                ? "Stopped. Nothing \(verb.lowercased())"
                : "Stopped after \(subject(outcome.done, outcome.firstName))\(tail)"
        }
        if outcome.done == 0 && outcome.skipped > 0 {
            return "Nothing \(verb.lowercased()): \(subject(outcome.skipped, outcome.firstName)) \(cannot)"
        }
        if outcome.done == 0 { return "Nothing \(verb.lowercased())" }
        var text = "\(verb) \(subject(outcome.done, outcome.firstName))\(tail)"
        if outcome.skipped > 0 { text += ", skipped \(outcome.skipped)" }
        return text
    }

    /// "a.jpg" for one, "3 photos" for more. Keeps every toast message one shape.
    private func subject(_ count: Int, _ name: String) -> String {
        count == 1 ? name : "\(count) photos"
    }

    private func setFlag(_ flag: Flag?) {
        // Named for what it did, not for which command did it (D-232). One
        // label across all three would mean that clearing a flag offered
        // "Undo flag", and pressing that puts a flag back.
        batch(flag?.rawValue ?? "Clear flag") { ref in
            let u = try FileOps.setFlag(flag, on: ref)
            if ref.flag != flag {
                switch flag { case .keep: store.session.kept += 1; case .reject: store.session.rejected += 1; case nil: break }
            }
            store.update(ref.url) { $0.flag = flag }
            return u
        }
        if flag == .reject, store.rejected.count >= Self.rejectHintFloor {
            // Names the key, because the button beside it says the rest. A
            // hint that repeated what the control already reads would be a
            // wall in front of the work (D-376).
            store.hintOnce("reviewRejects",
                           "⇧X opens Review rejected, which is also the button under the toolbar. "
                           + "Nothing goes to the Trash until you say so there.")
        }
        store.advanceIfEnabled()
    }

    /// A color says where a photo is going, which is a different question from
    /// whether it is any good (D-96). Pressing the color a photo already wears
    /// clears it, the way the flags do.
    private func setLabel(_ label: ColorLabel?) {
        let wanted = label != nil && store.targets.allSatisfy { $0.label == label } ? nil : label
        batch(wanted == nil ? "Clear label" : "Label") { ref in
            let u = try FileOps.setLabel(wanted, on: ref)
            store.update(ref.url) { $0.label = wanted }
            return u
        }
        store.advanceIfEnabled()
    }

    /// One state, so the command is a toggle. A mixed selection goes all-on
    /// rather than inverting photo by photo: pressing it on twelve photos where
    /// three are already favorites means "make these favorites", not "flip each
    /// of them" (D-55).
    private func toggleFavorite() {
        let wanted = !store.targets.allSatisfy(\.favorite)
        batch(wanted ? "Favorite" : "Unfavorite") { ref in
            let u = try FileOps.setFavorite(wanted, on: ref)
            store.update(ref.url) { $0.favorite = wanted }
            return u
        }
        // No advance, unlike every other decision (D-144). A favorite is not
        // one: it is a mark made while looking, usually on a photograph that
        // is also being flagged, and it is a toggle. Moving away from it took
        // the result of the press off screen and put the correcting second
        // press on the next photograph.
    }

    /// A favorite is the one mark somebody set on purpose, one photograph at a
    /// time, and the undo that covers a trash is in memory only (tech debt 3):
    /// quit after trashing a loved frame and the way back is Finder's Trash,
    /// not this app's. That is the ladder's top rung — a review in front of the
    /// action undo cannot reach — so it asks, and only then (D-193).
    ///
    /// Nothing else gets a dialog. A trash with no favorite in it is restorable
    /// by a keystroke and stays a plain action with an undo in the toast.
    private func trashTargets() {
        let targets = store.targets
        guard !targets.isEmpty else { return }
        // One question at a time: the key monitor stands down while it is up,
        // but a control on a photograph does not.
        guard store.trashConfirm == nil else { return }
        if targets.contains(where: \.favorite) {
            store.trashConfirm = TrashConfirm(refs: targets, window: store.focus)
            return
        }
        performTrash(targets)
    }

    /// The trash itself, past whatever asked. Called by `trashTargets` when
    /// nothing was loved, and by the sheet's yes when something was.
    @discardableResult
    func performTrash(_ targets: [PhotoRef]) -> Bool {
        store.trashConfirm = nil
        var removed: Set<URL> = []
        return runBatch("Move to Trash", banner: "Moving to Trash", over: targets,
                        io: { ref in
                            let (trashed, u) = try FileOps.trashReturningLocation(ref.url)
                            return BatchStep(undo: u, landed: trashed)
                        },
                        each: { ref, step in
                            removed.insert(ref.url)
                            evict(ref.url)
                            store.trashLog.insert(TrashEntry(original: ref.url,
                                                             trashed: step.landed ?? ref.url,
                                                             size: ref.fileSize, at: Date()), at: 0)
                            store.session.trashed += 1
                            store.session.trashedBytes += ref.fileSize
                        },
                        report: { self.batchReport($0, verb: "Moved", whereTo: "Trash",
                                                   cannot: "could not be moved") },
                        finish: { _ in
                            if !removed.isEmpty {
                                store.hintOnce("undo", "⌘Z takes it back. The offer stays in the bottom corner after the toast has gone.")
                            }
                            store.remove(removed)
                        })
    }

    /// Rotation is the one cull operation people do to a whole take at once: a
    /// camera held the wrong way for a hundred frames. So it runs off the main
    /// actor, reports where it has got to, and a file it cannot turn is counted
    /// rather than ending the run (D-41).
    private func rotate(clockwise: Bool) {
        let targets = store.targets
        guard !targets.isEmpty else { return }
        runBatch("Rotate", banner: "Rotating", over: targets,
                 io: { ref in BatchStep(undo: try FileOps.rotate(ref.url, clockwise: clockwise)) },
                 each: { ref, _ in evict(ref.url) },
                 report: { self.batchReport($0, verb: "Rotated", cannot: "cannot be turned") },
                 // The turn is written into the file, so the grid has to read
                 // it again; nothing left the folder.
                 finish: { _ in store.reload() })
    }

    /// A drop on a folder tile. Dropping a photo that is part of the selection
    /// moves the whole selection, the way Finder does; dropping any other photo
    /// moves that one and leaves the selection alone.
    @discardableResult
    func drop(_ dropped: [URL], on folder: URL) -> Int {
        // A URL that has been out to AppKit and back comes home with its
        // symlinks resolved (/var becomes /private/var), so nothing matches on
        // URL equality. Every comparison here is on the resolved path.
        let key = { (url: URL) in url.resolvingSymlinksInPath().path }
        let droppedKeys = Set(dropped.map(key))
        let inSelection = store.selected.contains { droppedKeys.contains(key($0)) }
        let wanted = Set((inSelection ? store.targets.map(\.url) : dropped).map(key))
        let refs = store.photos.filter { wanted.contains(key($0.url)) }
        guard !refs.isEmpty, key(folder) != store.folder.map(key) else { return 0 }
        var moved: Set<URL> = []
        var undos: [UndoableOp] = []
        for ref in refs {
            do {
                let (_, u) = try FileOps.move(ref.url, into: folder)
                undos.append(u)
                moved.insert(ref.url)
                store.session.moved += 1
                evict(ref.url)
            } catch { store.showError(error.localizedDescription); break }
        }
        guard !undos.isEmpty else { return 0 }
        let all = undos
        store.pushUndo(UndoableOp(label: "Move", inverse: .all(undos.map(\.inverse))))
        Preferences.lastMoveFolder = folder
        store.showToast("Moved \(subject(all.count, refs.first?.name ?? "")) to \(folder.lastPathComponent)")
        store.remove(moved)
        return all.count
    }

    /// The copy half of the move (D-87). A keeper can leave the folder without
    /// leaving the folder.
    /// `⌘C`. Loads the clipboard and leaves it loaded, so one set of
    /// photographs can be dropped into several folders (D-135). The system
    /// pasteboard is written too, for Finder.
    private func loadClipboard() {
        let urls = store.targets.map(\.url)
        guard !urls.isEmpty else { return }
        store.clipboard = urls
        FileOps.copyToPasteboard(urls)
        store.showToast("\(subject(urls.count, store.current?.name ?? "")) on the clipboard",
                        undoable: false)
    }

    /// `⌃⌘C`. The picture, not the file (D-281).
    ///
    /// It does not touch `store.clipboard`, which is the app's own and is what
    /// `⌘V` pastes: putting a photograph on the system pasteboard is a handoff
    /// to another app, and loading Sift's clipboard as well would mean one
    /// keystroke quietly arming a paste the reader did not ask for.
    private func copyImages() {
        let urls = store.targets.map(\.url)
        guard !urls.isEmpty else { return }
        FileOps.copyImagesToPasteboard(urls)
        store.showToast(urls.count == 1 ? "Picture copied" : "\(urls.count) pictures copied",
                        undoable: false)
    }

    /// `⌃⌘N`. The filename as the grid draws it, extension and all, one per
    /// line when a selection is copied (D-281).
    private func copyNames() {
        let names = store.targets.map(\.name)
        guard !names.isEmpty else { return }
        FileOps.copyText(names.joined(separator: "\n"))
        store.showToast(names.count == 1 ? "Name copied" : "\(names.count) names copied",
                        undoable: false)
    }

    /// `⌘V`. A copy of everything on the clipboard, into the folder on screen.
    /// Copies and never moves, for D-87's reason and one more: a move would
    /// empty the clipboard by consuming it, and the point of this one is that
    /// it does not.
    ///
    /// Each paste is its own undo. `batch` walks `store.targets`, which is the
    /// selection, and this walks the clipboard instead, so the inverse is
    /// assembled here rather than borrowed.
    private func pasteHere() {
        guard let folder = store.folder, !store.clipboard.isEmpty else { return }
        var undos: [UndoableOp] = []
        for url in store.clipboard {
            do {
                let (_, u) = try FileOps.copy(url, into: folder)
                undos.append(u)
            } catch {
                store.showError(error.localizedDescription)
                break
            }
        }
        guard !undos.isEmpty else { return }
        store.pushUndo(UndoableOp(label: "Paste", inverse: .all(undos.map(\.inverse))))
        let name = store.clipboard.first?.lastPathComponent ?? ""
        store.showToast("Pasted \(subject(undos.count, name)) into \(folder.lastPathComponent)")
        store.reload()
    }

    private func copyTargets() {
        guard !store.targets.isEmpty else { return }
        let asked = presenter.chooseFolders(
            prompt: "Copy",
            message: "Copy \(subject(store.targets.count, store.current?.name ?? "1 photo")) to…",
            multiple: false)
        guard let dest = asked.first else { return }
        // Nothing leaves the folder, so nothing leaves the grid: no `each` and
        // no `finish`.
        runBatch("Copy", banner: "Copying", over: store.targets,
                 io: { ref in BatchStep(undo: try FileOps.copy(ref.url, into: dest).1) },
                 report: { self.batchReport($0, verb: "Copied", whereTo: dest.lastPathComponent,
                                            cannot: "could not be copied") })
    }

    /// Photo Mechanic's actual value: cull fast, then hand the keepers on
    /// (D-88). Named applications rather than whatever owns the extension, and
    /// the whole selection in one of them rather than one file each.
    private func openInEditor() {
        let urls = store.targets.map(\.url)
        guard let first = urls.first else { return }
        let apps = FileOps.editors(for: first)
        guard !apps.isEmpty else {
            store.showError("Nothing on this Mac says it can open \(first.lastPathComponent).")
            return
        }
        // One editor, and it is the one you used last: the second time is the
        // one that has to be fast.
        if let last = Preferences.lastEditor, apps.contains(where: { $0.standardizedFileURL == last.standardizedFileURL }) {
            FileOps.open(urls, with: last)
            store.showToast("Opened \(subject(urls.count, first.lastPathComponent)) in \(FileOps.appName(last))",
                            undoable: false)
            return
        }
        presentEditorMenu(apps, for: urls)
    }

    private func presentEditorMenu(_ apps: [URL], for urls: [URL]) {
        let shown = presenter.menu(apps.map { (FileOps.appName($0), $0) },
                                   x: nil, drop: store.headerHeight) { [weak self] chosen in
            self?.chooseEditor(chosen, for: urls)
        }
        // No window to hang a menu on, which is the test's world: take the
        // first, which is the system's own idea of the right answer.
        if !shown, let choice = apps.first { chooseEditor(choice, for: urls) }
    }

    func chooseEditor(_ app: URL, for urls: [URL]) {
        Preferences.lastEditor = app
        FileOps.open(urls, with: app)
        store.showToast("Opened \(subject(urls.count, urls.first?.lastPathComponent ?? "")) in \(FileOps.appName(app))",
                        undoable: false)
    }

    /// Forgets which editor to use next time, so the menu comes back.
    func forgetEditor() {
        Preferences.lastEditor = nil
        store.showToast("Sift will ask which editor next time", undoable: false)
    }

    /// Turning sidecars on is a promise about a folder, not about the next
    /// photo: everything already flagged gets one, or the promise is a lie
    /// about most of the shoot (D-94).
    /// Light, dark, or the desktop's choice. App-wide, so it does not go through
    /// the store the way a view setting does (D-112).
    func setAppearance(_ appearance: Appearance) {
        guard AppModel.shared.appearance != appearance else { return }
        AppModel.shared.appearance = appearance
        store.showToast(appearance == .system ? "Matching the system" : "\(appearance.label) appearance",
                        undoable: false)
    }

    func setSidecars(_ on: Bool) {
        Preferences.writeSidecars = on
        guard on else {
            store.showToast("Sift will stop writing .xmp files", undoable: false)
            return
        }
        let decided = store.allPhotos.filter { $0.flag != nil || $0.favorite }
        guard !decided.isEmpty else {
            store.showToast("Sift will write an .xmp beside every photo you flag", undoable: false)
            return
        }
        var written = 0
        for ref in decided {
            do {
                try XMPSidecar.write(flag: ref.flag, favorite: ref.favorite, for: ref.url)
                written += 1
            } catch { continue }
        }
        store.showToast("Wrote \(written) .xmp file\(written == 1 ? "" : "s") for what is already flagged",
                        undoable: false)
    }

    /// A folder chosen from a panel, for the sheets that need one.
    func chooseFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.message = message
        guard panel.runModal() == .OK else { return nil }
        // The other door of the same kind (D-324).
        if let url = panel.url { FolderAccess.remember(url) }
        return panel.url
    }

    /// The ingest (D-89): copy every photo under `source` into `destination`,
    /// renaming as it goes, then open what was copied. Copy only — a card is
    /// the only copy of a shoot until this finishes, and nothing here is
    /// undoable because nothing here destroys anything.
    func ingest(from source: URL, into destination: URL, subfolder: String, pattern: String) {
        // The sheet already refuses a name that is a path, and refuses it
        // before the Copy button is pressed rather than after. This is the
        // enforcement all the same: the sheet is one caller, and what an ingest
        // gets wrong it cannot take back (D-303, D-304).
        let dest: URL
        do {
            dest = try FileOps.ingestPlan(destination: destination,
                                          subfolder: subfolder, pattern: pattern)
        } catch {
            store.showError(error.message)
            return
        }
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespaces)
        Preferences.lastIngestFolder = destination

        Task { @MainActor in
            let files = await Task.detached { (try? FolderScanner.scan(source, recursive: true)) ?? [] }.value
            guard !files.isEmpty else {
                store.showError("No photos under \(source.lastPathComponent).")
                return
            }
            do {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            } catch {
                store.showError("Could not make \(dest.lastPathComponent): \(error.localizedDescription)")
                return
            }
            var copied = 0, failed = 0, keptCardName = 0
            // The claim waits for the scan: the total is the point of the
            // banner and there is nothing to say until the card has been read.
            let started = store.runWithProgress("Copying off \(source.lastPathComponent)",
                                                total: files.count) { run in
                for (i, ref) in files.enumerated() {
                    if run.cancelled { break }
                    let name = trimmedPattern.isEmpty ? ref.name : FileOps.expand(pattern: trimmedPattern, ref: ref, index: i + 1)
                    // Three outcomes and not two. A copy that lands and then
                    // cannot take the name it was asked for is not a failure —
                    // the photograph is off the card — and it is not what was
                    // asked for either, so it is counted and said out loud.
                    //
                    // `rename` refuses a collision, and a pattern with no
                    // counter in it collides on every frame after the first, so
                    // `Harbor` against a 60-frame card left one `Harbor.JPG`,
                    // 59 card names, and a toast reading "Copied 60 photos".
                    // The `try?` that swallowed it is the whole bug (D-304).
                    let outcome = await Task.detached(priority: .userInitiated) { () -> (landed: Bool, named: Bool) in
                        do {
                            let (written, _) = try FileOps.copy(ref.url, into: dest)
                            guard name != ref.name else { return (true, true) }
                            do { _ = try FileOps.rename(written, to: name); return (true, true) }
                            catch { return (true, false) }
                        } catch { return (false, true) }
                    }.value
                    if outcome.landed { copied += 1 } else { failed += 1 }
                    if !outcome.named { keptCardName += 1 }
                    run.advance(to: i + 1)
                }
                let stopped = run.cancelled
                run.end()
                store.showToast(Self.ingestReport(copied: copied, failed: failed,
                                                  keptCardName: keptCardName, stopped: stopped),
                                undoable: false)
                if copied > 0 { self.open(dest) }
            }
            if !started { refuse() }
        }
    }

    /// The sentence the toast shows when the copy finishes.
    ///
    /// `nonisolated static` so a test can read the sentence back. What the
    /// reader is told is the outcome of an ingest, the same way the files on
    /// disk are, and the count this used to drop is the one that mattered
    /// (D-304).
    nonisolated static func ingestReport(copied: Int, failed: Int,
                                         keptCardName: Int, stopped: Bool) -> String {
        if stopped { return copied == 0 ? "Stopped. Nothing copied" : "Stopped after \(copied)" }
        if copied == 0 { return "Nothing copied" }
        var text = "Copied \(copied) photo\(copied == 1 ? "" : "s")"
        if failed > 0 { text += ", \(failed) failed" }
        if keptCardName > 0 { text += ", \(keptCardName) kept the name on the card" }
        return text
    }

    private func moveTargets(to folder: URL?) {
        let dest: URL
        if let folder { dest = folder } else {
            let asked = presenter.chooseFolders(
                prompt: "Move",
                message: "Move \(subject(store.targets.count, store.current?.name ?? "1 photo")) to…",
                multiple: false)
            guard let url = asked.first else { return }
            dest = url
        }
        Preferences.lastMoveFolder = dest
        var moved: Set<URL> = []
        runBatch("Move", banner: "Moving", over: store.targets,
                 io: { ref in BatchStep(undo: try FileOps.move(ref.url, into: dest).1) },
                 each: { ref, _ in
                     moved.insert(ref.url)
                     store.session.moved += 1
                     evict(ref.url)
                 },
                 report: { self.batchReport($0, verb: "Moved", whereTo: dest.lastPathComponent,
                                            cannot: "could not be moved") },
                 // Taken out of the grid at the end rather than one at a time:
                 // the cursor moves with every removal, and a run of five
                 // hundred would walk it the length of the folder while it went.
                 finish: { _ in store.remove(moved) })
    }

    func rename(_ ref: PhotoRef, to newName: String) {
        do {
            let (dest, u) = try FileOps.rename(ref.url, to: newName)
            store.pushUndo(u)
            store.showToast("Renamed to \(newName)")
            evict(ref.url)
            store.reload()
            if let i = store.photos.firstIndex(where: { $0.url == dest }) { store.cursor = i }
        } catch { store.showError(error.localizedDescription) }
    }

    /// What one photograph's second hop did: took the new name, went back to
    /// its old one, or is still parked under neither.
    private enum Placed: Sendable {
        case renamed(Inverse.Hop)
        case putBack
        case left
    }

    /// Two phases, because a renumber is a permutation and no sequence of
    /// one-file renames can perform one: the set has to move out of the way
    /// first (D-380).
    ///
    /// Not `runBatch`: its `io` is one file and one hop, and a park pass over
    /// the whole set is neither. `runWithProgress` directly, the way the
    /// ingest writes its own loop, reusing `BatchOutcome` and `batchReport` so
    /// the sentence at the end is the one every other batch gives.
    func batchRename(_ refs: [PhotoRef], pattern: String) {
        let plan: FileOps.RenamePlan
        do { plan = try FileOps.renamePlan(pattern: pattern, refs: refs) }
        catch {
            // Nothing moved and nothing on the stack.
            store.showError(error.message)
            return
        }
        guard !plan.changing.isEmpty else {
            store.showToast("Every name already matches the pattern", undoable: false)
            store.clearSelection()
            return
        }

        // The photographs, not the hops. The banner reads "Renaming 3 of 40",
        // and a total of twice the selection would count something nobody can
        // see.
        let started = store.runWithProgress("Renaming", total: plan.changing.count) { run in
            var outcome = BatchOutcome(firstName: refs.first?.name ?? "")
            var parked: [(temp: URL, step: FileOps.RenamePlan.Step)] = []

            // Park. Nothing is renamed yet, so the bar does not move.
            for step in plan.changing {
                if run.cancelled { break }
                let temp = await Task.detached(priority: .userInitiated) { try? FileOps.park(step.source) }.value
                if let temp { parked.append((temp, step)) } else { outcome.skipped += 1 }
            }

            // Place. A destination still occupied here is a file nobody
            // selected, so the photograph goes back to its own name and is
            // counted, and the run carries on (D-41).
            var hops: [Inverse.Hop] = []
            var stranded: [Inverse] = []
            for (temp, step) in parked {
                guard !run.cancelled else {
                    _ = await Task.detached(priority: .userInitiated) { try? FileOps.unpark(temp, to: step.source) }.value
                    continue
                }
                let landed = await Task.detached(priority: .userInitiated) { () -> Placed in
                    do {
                        try FileOps.place(temp, at: step.dest)
                        return .renamed(Inverse.Hop(from: step.dest, to: step.source))
                    }
                    // Three outcomes and not two. `putBack` is the ordinary
                    // skip: the name belongs to a file nobody selected. `left`
                    // should be unreachable, and it is the one that would lose
                    // a photograph behind a hidden name, so it is the one that
                    // says something out loud.
                    catch { return (try? FileOps.unpark(temp, to: step.source)) != nil ? .putBack : .left }
                }.value
                switch landed {
                case let .renamed(hop): hops.append(hop); outcome.done += 1
                case .putBack: outcome.skipped += 1
                case .left:
                    outcome.skipped += 1
                    stranded.append(.moveBack(from: temp, to: step.source))
                    store.showError("\(step.source.lastPathComponent) is parked as \(temp.lastPathComponent). Undo puts it back.")
                }
                run.step()
            }

            // The ones already carrying the pattern were never going to move,
            // and saying "renamed 8" when twelve were selected reads as four
            // failures.
            outcome.done += plan.unchanged
            outcome.cancelled = run.cancelled
            run.end()

            // `.all` replays reversed, so `renameBack` has to go last to run
            // first: a stranded photograph's old name can be some other
            // photograph's new one, and it is only free once the batch is back.
            var inverses: [Inverse] = stranded
            if !hops.isEmpty { inverses.append(.renameBack(hops)) }
            if !inverses.isEmpty {
                store.pushUndo(UndoableOp(label: "Rename",
                                          inverse: inverses.count == 1 ? inverses[0] : .all(inverses)))
            }
            store.clearSelection()
            store.reload()
            let partial = outcome.skipped > 0 || outcome.cancelled
            store.showToast(batchReport(outcome, verb: "Renamed", cannot: "could not be renamed"),
                            undoable: !inverses.isEmpty && !partial)
        }
        if !started { refuse() }
    }

    /// Return writes a copy; ⇧Return writes into the photograph (D-239).
    ///
    /// The copy is quick enough to do here. The overwrite is not — it decodes
    /// the whole file, copies the original aside and re-encodes — and it is the
    /// operation that can lose a photograph, so it goes behind the progress
    /// banner off the main actor, the way `commitAdjust(overwriting:)` does.
    private func commitCrop(overwriting: Bool = false) {
        guard let ref = store.current, let rect = store.cropRect, rect.width > 0.01, rect.height > 0.01 else {
            store.cropping = false; store.cropRect = nil; return
        }
        let url = ref.url
        store.cropping = false
        store.cropRect = nil
        guard overwriting else {
            // Off the main actor and behind the banner, like every other write
            // of a whole file: this decodes the frame, re-encodes it and clones
            // the original beside it, which is not work to do between two
            // frames of the window server (D-243).
            let started = store.runWithProgress("Writing a cropped copy") { _ in
                do {
                    let (dest, op) = try await Task.detached { try FileOps.cropCopy(url, normalized: rect) }.value
                    store.pushUndo(op)
                    store.showToast("Saved \(dest.lastPathComponent)")
                    store.reload()
                    if let i = store.photos.firstIndex(where: { $0.url == dest }) { store.cursor = i }
                } catch { store.showError(error.localizedDescription) }
            }
            if !started { refuse() }
            return
        }
        let started = store.runWithProgress("Writing over \(url.lastPathComponent)") { _ in
            do {
                let op = try await Task.detached { try FileOps.cropInPlace(url, normalized: rect) }.value
                store.pushUndo(op)
                store.reload()
                // The crop took the recipe off the file, so the panel's idea of
                // what this photograph carries is now wrong (D-239). Still said
                // here and not left to the reload, because a reload with no
                // folder open returns without doing anything (D-286).
                store.loadAdjustRecord()
            } catch {
                store.showError(error.localizedDescription)
            }
        }
        if !started { refuse() }
    }

    /// Return, with sliders set. The render is the whole file rather than the
    /// 2048px preview the panel was moved against, so it runs off the main
    /// actor behind the progress banner: a 45-megapixel frame through four
    /// filters is not something to do between two frames of the window server.
    private func commitAdjust(overwriting: Bool = false) {
        guard let ref = store.current, !store.adjustments.isNeutral else {
            store.adjusting = false
            store.adjustments = .neutral
            store.adjustBaseline = .neutral
            return
        }
        let recipe = store.adjustments
        let url = ref.url
        store.adjusting = false
        store.adjustments = .neutral
        store.adjustBaseline = .neutral
        let started = store.runWithProgress(overwriting ? "Writing over \(url.lastPathComponent)"
                                                       : "Writing an adjusted copy") { _ in
            do {
                if overwriting {
                    let op = try await Task.detached { try FileOps.adjustInPlace(url, recipe) }.value
                    store.pushUndo(op)
                    store.reload()
                    // The record the write just left is what the panel will
                    // open at next time (D-165).
                    store.loadAdjustRecord()
                } else {
                    let (dest, op) = try await Task.detached { try FileOps.adjustCopy(url, recipe) }.value
                    store.pushUndo(op)
                    store.showToast("Saved \(dest.lastPathComponent)")
                    store.reload()
                    if let i = store.photos.firstIndex(where: { $0.url == dest }) { store.cursor = i }
                }
            } catch {
                store.showError(error.localizedDescription)
            }
        }
        if !started { refuse() }
    }


    /// Shows the kept original and waits (D-240).
    ///
    /// It used to write immediately and leave the undo to `⌘Z` and a toast,
    /// which is the wrong ladder for this one: a revert throws away an edit
    /// somebody may have made a week ago, and the thing that says whether they
    /// want it back is the photograph itself. So the mode puts the original on
    /// screen under the same bar the crop has — Cancel, and Save changes — and
    /// nothing is written until that button is pressed. Undo still covers the
    /// write afterwards.
    private func revertToOriginal() {
        guard let ref = store.current else { return }
        guard AdjustRecord.isRevertable(ref.url) else {
            store.showToast("No original is kept for this photo", undoable: false)
            return
        }
        // The original is drawn in the preview window, so asking for it
        // anywhere else opens that window first, the way the sliders do.
        openPreview()
        store.reverting = true
    }

    /// The write the preview was asking about. The panel is already closed —
    /// entering the preview closed it — and the sliders it would go back to are
    /// the ones about to be taken off.
    private func commitRevert() {
        guard let ref = store.current else { return }
        let url = ref.url
        guard AdjustRecord.isRevertable(url) else {
            store.reverting = false
            store.showToast("No original is kept for this photo", undoable: false)
            return
        }
        store.reverting = false
        let started = store.runWithProgress("Putting \(url.lastPathComponent) back") { _ in
                do {
                    let op = try await Task.detached { try FileOps.revertAdjust(url) }.value
                    store.pushUndo(op)
                    store.showToast("Reverted \(url.lastPathComponent)")
                    store.reload()
                    store.loadAdjustRecord()
                } catch {
                    store.showError(error.localizedDescription)
                }
        }
        if !started { refuse() }
    }

    private func undo() {
        guard let op = store.undo.pop() else {
            store.showToast("Nothing to undo", undoable: false)
            return
        }
        let label = op.label
            // A batch undo reverses every file in it behind one call, so there
            // is nothing to count — but there is something to say (D-49).
            //
            // It takes the banner or it does not run. Reversing a rotation
            // that is still being written is the collision this whole handle
            // exists for: it used to take the banner *from* the rotate, which
            // left the rotate incrementing a counter nobody was reading and
            // its stop button gone (D-189).
        let started = store.runWithProgress("Undoing \(label.lowercased())") { _ in
            do {
                try await op.undo()
                // Nothing to evict. The caches are keyed by content (D-45), so
                // a file the undo rewrote is a miss on its own and the old
                // entry ages out; emptying both threw away every other photo in
                // the folder to be sure about one (D-109).
                store.reload()
                store.showToast("Undid \(label.lowercased())", undoable: false)
            } catch {
                // Back on the stack. An undo that failed because the card is
                // out is one that works again when it is back in, and a way
                // back thrown away for being momentarily unreachable is the
                // opposite of what the stack is for (D-108).
                store.undo.push(op)
                store.showError(error.localizedDescription)
            }
        }
        if !started {
            // Back on the stack: it was popped before the claim was refused,
            // and a way back thrown away because something else was running is
            // the opposite of what the stack is for (D-108).
            store.undo.push(op)
            refuse()
        }
    }

    /// What to say when a second long operation is asked for while one is
    /// running. Naming the one in the way is the whole message: "nothing
    /// happened" is what the silent early return used to say (D-189).
    private func refuse() {
        guard let busy = store.runningLabel else { return }
        store.showToast("Still \(busy.lowercased())", undoable: false)
    }

    /// Tab walks the preview bar (D-157).
    ///
    /// The platform's own focus ring was the obvious answer and it does not
    /// work here: the key monitor takes Return and Space before any focused
    /// control sees them (D-7), so a ring drawn by AppKit could be moved and
    /// never pressed. A control that takes the keyboard and cannot be
    /// activated by it is worse than one that never takes it. So the walk goes
    /// through the key map like everything else, and the bar draws the ring
    /// itself.
    ///
    /// It wraps, because the row is short and the alternative is a Tab that
    /// does nothing at one end.
    private func stepBar(by delta: Int) {
        guard store.focus == .preview, let ref = store.current else { return }
        // Whichever bar is on screen. The preview bar is away while a mode is
        // running and the mode's own bar has that place, so Tab walks that one
        // — it used to walk the hidden preview bar, and Return presses the ring
        // before it means anything else, so Tab then Return moved the
        // photograph being cropped to the Trash (D-244, D-245).
        if store.cropping || store.reverting {
            stepModeBar(by: delta)
            return
        }
        let walk = PreviewBar.controls(putAway: store.barRung, ref: ref, store: store,
                                       features: AppModel.shared.features).map(\.command)
        guard !walk.isEmpty else { return }
        guard let here = store.barCursor, let i = walk.firstIndex(of: here) else {
            store.barCursor = delta > 0 ? walk.first : walk.last
            return
        }
        let next = (i + delta + walk.count) % walk.count
        store.barCursor = walk[next]
    }

    private func stepModeBar(by delta: Int) {
        let walk = store.modeBarStops
        guard !walk.isEmpty else { return }
        guard let here = store.modeBarCursor, let i = walk.firstIndex(of: here) else {
            store.modeBarCursor = delta > 0 ? walk.first : walk.last
            return
        }
        store.modeBarCursor = walk[(i + delta + walk.count) % walk.count]
    }

    /// Return on a stop, and the click on it: one path, so the ring presses what
    /// the pointer presses (D-157, D-245). It has to be this way round rather
    /// than through `.confirm` and `.cancel` — those are mode-aware commands
    /// and the ring is the innermost thing they act on, so a click on Cancel
    /// while the ring was up would have cleared the ring and stayed in the
    /// mode.
    ///
    /// The two that only change what the box is held to leave the ring where it
    /// is: choosing a shape is something you do *while* deciding, and the next
    /// Tab should carry on from the shape you just chose rather than from the
    /// start of the row.
    func pressModeBar(_ stop: ModeBarStop) {
        switch stop {
        case .ratio(let ratio): store.cropRatio = ratio
        case .turn: store.cropRatioTurned.toggle()
        case .revert:
            store.modeBarCursor = nil
            perform(.revertToOriginal)
        case .cancel:
            store.modeBarCursor = nil
            if store.cropping { store.cropping = false; store.cropRect = nil }
            else if store.reverting { store.reverting = false }
        case .saveCopy:
            store.modeBarCursor = nil
            commitCrop()
        case .saveOver:
            store.modeBarCursor = nil
            if store.cropping { commitCrop(overwriting: true) } else { commitRevert() }
        }
    }

    /// `⇧Z` with no faces on hand looks for them rather than saying there are
    /// none. Detection used to run only from the info panel, so the answer
    /// depended on whether a panel nobody needs for this had ever been open
    /// (D-151).
    private func zoomToFace() {
        guard let ref = store.current else { return }
        guard store.faces.isEmpty else { store.zoomToNextFace(); return }
        openPreview()
        // Said before the pass starts, not inside it: a key that goes quiet
        // while Vision runs has failed as far as the reader is concerned.
        store.showToast("Looking for faces", undoable: false)
        Task { @MainActor in
            await store.loadFaces(for: ref)
            guard store.current?.contentID == ref.contentID else { return }
            if store.faces.isEmpty {
                store.showToast("No faces in this one", undoable: false)
            } else {
                // The answer is the zoom itself, so the "looking" line goes
                // rather than sitting under a photograph that has moved on.
                store.toast = nil
                store.zoomToNextFace()
            }
        }
    }

    /// Nothing to evict: the caches are keyed by content (D-45), so a rewritten
    /// file is a cache miss on its own and the old entry ages out under NSCache's
    /// own cost limit. Kept as a named no-op because the call sites read as the
    /// intent — "this file just changed" — and a later cache that does need
    /// telling will want them.
    private func evict(_ url: URL) {}

    /// Opens the panel on a folder the app was refused, so the reader hands
    /// over the one they asked for rather than hunting for it (D-324).
    ///
    /// `directoryURL` on a folder the app cannot read still works: the panel
    /// runs outside the sandbox, which is the whole reason it is the door.
    func grantAccess(to folder: URL) {
        let chosen = presenter.chooseFolders(
            prompt: "Allow", message: "Sift will be able to read this folder and everything in it.",
            multiple: false, startingAt: folder)
        guard let url = chosen.first else { return }
        open(url)
    }

    func openFolderPanel() {
        if let url = presenter.chooseFolders(prompt: "Open", message: nil, multiple: false).first {
            open(url)
        }
    }

    /// Opens a folder, or an image's folder with the cursor on that image (Finder double-click).
    func open(_ url: URL, asked: Bool = true) {
        cameUpFrom = nil
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = FolderScanner.canonical(isDir ? url : url.deletingLastPathComponent())
        // A new destination ends the forward road, the way it does in a browser.
        if let current = store.folder, current.standardizedFileURL != folder.standardizedFileURL {
            backStack.append(current)
            forwardStack.removeAll()
        }
        load(folder, focusing: isDir ? nil : url, asked: asked)
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Back and forward are about where you have been, not where you are in the
    /// tree: back out of a subfolder and back lands on its parent, but so does
    /// back out of a folder you reached from the other side of the disk (D-32).
    func goBack() {
        guard let target = backStack.popLast() else {
            store.showToast("Nowhere back to go", undoable: false)
            return
        }
        if let current = store.folder { forwardStack.append(current) }
        cameUpFrom = nil
        load(target)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else {
            store.showToast("Nowhere forward to go", undoable: false)
            return
        }
        if let current = store.folder { backStack.append(current) }
        cameUpFrom = nil
        load(target)
    }

    /// Everything the jump sheet can reach, nearest reason first. Deduplicated
    /// by path, because a folder is often pinned and recent and a sibling.
    var jumpCandidates: [JumpCandidate] {
        var seen: Set<String> = []
        var out: [JumpCandidate] = []
        func add(_ folder: URL, _ source: String) {
            let key = folder.resolvingSymlinksInPath().path
            guard !seen.contains(key),
                  folder.standardizedFileURL != store.folder?.standardizedFileURL,
                  // A recent folder can have been renamed, moved or ejected
                  // since. Offering it would be offering an error message.
                  FileManager.default.fileExists(atPath: folder.path) else { return }
            seen.insert(key)
            out.append(JumpCandidate(folder: folder, source: source))
        }
        for f in store.pinned { add(f, "pinned") }
        for f in store.subfolders { add(f, "inside") }
        if let folder = store.folder {
            let parent = folder.deletingLastPathComponent()
            if parent != folder {
                add(parent, "enclosing")
                for f in FolderScanner.subfolders(of: parent) { add(f, "beside") }
            }
        }
        for f in Preferences.recentFolders { add(f, "recent") }
        return out
    }

    /// A pin is how a folder you cull into stays one click away all sitting.
    func togglePin(_ folder: URL? = nil) {
        guard let target = folder ?? store.folder else { return }
        let pinned = Preferences.togglePin(target)
        store.pinned = Preferences.pinnedFolders
        store.showToast(pinned ? "Pinned \(target.lastPathComponent)" : "Unpinned \(target.lastPathComponent)",
                        undoable: false)
    }

    /// The sidebar's `+`: pin folders from anywhere on disk, not only the one
    /// that happens to be open. Several at once, because adding the three
    /// folders you cull into is one trip to the panel (D-60).
    /// The sidebar's one way in: hand Sift another folder to read (D-327).
    ///
    /// The panel is what grants it (D-324), so adding a folder to the list
    /// and giving Sift access to it are one act. It does not pin: pinning is
    /// a right-click on a folder that is already in the list, which is what
    /// keeps Pinned a subset of Folders rather than a second way to put
    /// something in the sidebar.
    ///
    /// It opens the first one, because somebody who has just chosen a folder
    /// wants to be in it, and a control that adds a row and leaves you where
    /// you were makes you click twice to do one thing.
    func addFolders() {
        let picked = presenter.chooseFolders(prompt: "Add",
                                             message: "Sift will be able to read this folder and everything in it.",
                                             multiple: true)
        guard let first = picked.first else { return }
        open(first)
    }

    func addPinnedFolders() {
        let picked = presenter.chooseFolders(prompt: "Pin",
                                             message: "Pin folders to the sidebar",
                                             multiple: true)
        guard !picked.isEmpty else { return }
        var added: [String] = []
        var already = 0
        for url in picked.map(FolderScanner.canonical) {
            if Preferences.pin(url) { added.append(url.lastPathComponent) } else { already += 1 }
        }
        store.pinned = Preferences.pinnedFolders
        store.showToast(pinReport(added: added, already: already), undoable: false)
    }

    /// One sentence covering added and already-there, because a panel can
    /// return both at once.
    private func pinReport(added: [String], already: Int) -> String {
        if added.isEmpty {
            return already == 1 ? "Already pinned" : "All \(already) were already pinned"
        }
        let what = added.count == 1 ? "Pinned \(added[0])" : "Pinned \(added.count) folders"
        return already > 0 ? "\(what), \(already) already there" : what
    }

    /// Jumping several steps at once, for the list under the arrows. Each step
    /// keeps the stacks honest, so the other arrow ends up with the whole walk.
    func goBack(steps: Int) { for _ in 0..<max(1, steps) where canGoBack { goBack() } }
    func goForward(steps: Int) { for _ in 0..<max(1, steps) where canGoForward { goForward() } }

    /// Most recent first, which is the order a history menu reads in.
    var backList: [URL] { backStack.reversed() }
    var forwardList: [URL] { forwardStack.reversed() }

    /// A path typed or pasted into the go-to sheet. `~` and a trailing slash are
    /// the two things people paste that a `URL` does not take as given.
    func openPath(_ typed: String) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.showError("There is nothing at \(url.path).")
            return
        }
        open(url)
    }

    /// The neighbors of the cursor, kept decoded (D-6). `warm` cancels whatever
    /// is no longer wanted, so walking a folder needs nothing else; a folder
    /// with no photographs in it never reaches `warm` at all, and the decodes
    /// the last folder left in flight went on holding a megabyte each until
    /// they finished. That is the one call `cancelAll` was written for and
    /// never got (D-254).
    private func refreshPrefetch() {
        if let i = store.cursor { prefetcher.warm(store.photos, around: i) }
        else { prefetcher.cancelAll() }
    }

    /// The part of opening that both a click and the two arrows share.
    private func load(_ folder: URL, focusing file: URL? = nil, asked: Bool = true) {
        store.open(folder, focusing: file, asked: asked)
        refreshPrefetch()
    }

    /// Where ⌘↓ goes: nowhere, straight into one folder, or a menu to pick from.
    /// Which folders a menu or a sideways step offers: the ones that lead
    /// somewhere, plus the folder being stood in, which has to stay in the row
    /// for a step sideways to find its own place in it (D-152).
    static func worthOffering(_ folders: [URL], keeping here: URL? = nil) -> [URL] {
        folders.filter {
            $0.standardizedFileURL == here?.standardizedFileURL || FolderScanner.leadsSomewhere($0)
        }
    }

    enum Descent: Equatable {
        case none
        case go(URL)
        case choose([URL])
    }

    /// The mirror of ⌘↑. The folder you just came up from wins, so ⌘↑ and ⌘↓
    /// are a pair rather than two ways of losing your place (D-31).
    var descent: Descent {
        let kids = Self.worthOffering(store.subfolders)
        if kids.isEmpty { return .none }
        if let back = cameUpFrom,
           kids.contains(where: { $0.standardizedFileURL == back.standardizedFileURL }) { return .go(back) }
        if kids.count == 1 { return .go(kids[0]) }
        return .choose(kids)
    }

    func descend() {
        switch descent {
        case .none:
            let name = store.folder?.lastPathComponent ?? "this folder"
            store.showToast("No subfolders in \(name)", undoable: false)
        case .go(let url): open(url)
        case .choose(let kids): presentSubfolderMenu(kids)
        }
    }

    /// Just under the breadcrumb, aligned with its first crumb, so the menu
    /// comes out of the control that shows the same list. Nothing happens
    /// without a window, which is where the tests read `descent` instead.
    private func presentSubfolderMenu(_ kids: [URL]) {
        presenter.menu(kids.map { ($0.lastPathComponent, $0) },
                       x: store.breadcrumbX, drop: store.headerHeight) { [weak self] url in
            self?.open(url)
        }
    }
}
