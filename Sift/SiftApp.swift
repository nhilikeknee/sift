import SwiftUI

/// One gallery window's worth of state: a folder, a cursor, and the router that
/// moves them. A second window is a second session, not a second view of the
/// first (D-40).
@MainActor
final class Session: Identifiable {
    let id: UUID
    let store: LibraryStore
    let router: CommandRouter

    init(id: UUID = UUID()) {
        self.id = id
        store = LibraryStore()
        router = CommandRouter(store: store)
    }
}

/// Every open session, and which one the keyboard is talking to. The key
/// monitor, the menus and the Finder "open with" handler all ask here rather
/// than holding a store of their own.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    private(set) var sessions: [UUID: Session] = [:]
    /// The gallery window that is key, and the one whose store the preview shows.
    var activeID: UUID?
    var previewID: UUID?

    /// Where a window opened by `⌘N` should start. Read once, by the window
    /// itself, because the folder is known before the window exists.
    @ObservationIgnored var pending: [UUID: URL?] = [:]

    /// Each open gallery's `NSWindow`, filed by session and held weakly.
    /// `openWindow` gives back no handle, so the window files itself the
    /// moment its view tree reaches it, and nothing has to ask AppKit which
    /// window is key. Weak, so a closed window is gone from here whether or
    /// not `close` has run (D-370).
    @ObservationIgnored var windows: [UUID: WeakWindow] = [:]

    /// Sessions whose window should arrive as a tab, and the session whose
    /// window it joins. Read once, by the window itself, for the reason
    /// `pending` is: the request is made before the window exists.
    @ObservationIgnored var tabHost: [UUID: UUID] = [:]

    /// The window a session is showing in, if it still has one.
    func window(of id: UUID) -> NSWindow? { windows[id]?.window }

    /// Drops the entries whose window has gone. Called when one is added,
    /// which is the only moment the dictionary grows, because nothing else
    /// can be trusted to run when a window closes (D-372).
    func forgetClosedWindows() { windows = windows.filter { $0.value.window != nil } }

    @ObservationIgnored let monitor = KeyMonitor()
    @ObservationIgnored let volumes = VolumeWatcher()

    /// Light, dark or the desktop's choice. App-wide rather than per-session:
    /// two gallery windows in two palettes is not a thing anybody wants, and
    /// `NSApp.appearance` is one property for the whole process anyway (D-112).
    var appearance = Appearance.atLaunch {
        didSet {
            Preferences.appearance = appearance
            NSApp.appearance = appearance.nsAppearance
        }
    }

    /// Which features are switched off. App-wide for the same reason the
    /// appearance is (D-112): two windows disagreeing about whether crop
    /// exists is not a thing anybody wants, and the key map is one table.
    var features = FeatureSet.atLaunch {
        didSet {
            guard features != oldValue else { return }
            Preferences.featuresOff = features.off
            // Switching a feature off while it is running has to put it away
            // too. Otherwise the highlights stay painted on the photograph
            // with no control left to clear them, which is the state the
            // switch was pressed to get out of — a mutation whose inverse
            // only half happened (D-5, D-123).
            for session in sessions.values { session.store.standDown(features) }
        }
    }

    /// Puts the stored choice on the application. Called once the app has
    /// finished launching and not from `init`: `AppModel.shared` is built by
    /// `SiftApp.init`, which runs before there is an `NSApplication` to set it
    /// on, and `NSApp` is an implicitly unwrapped optional that crashes rather
    /// than saying so. The launch check is what caught it (D-110).
    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    /// Empty, and private so `shared` is the only way to one. The observer that
    /// used to sit here watched the desktop for light and dark so a header
    /// glyph could read out which one was on screen; D-134 moved appearance to
    /// a three-state picker in Settings, which sets and shows the same fact, and
    /// nothing has needed telling since (D-306).
    private init() {}

    /// Whether the one named window id has been handed out. A `WindowGroup`
    /// value is a request, not an identity: every window that arrives without
    /// one takes `defaultValue`, and macOS has two ways to make such a window.
    /// The launch window is the first, and it has to be `firstWindowID` by
    /// name, because `SiftApp.init` puts the launch folder into `pending`
    /// under that id before any window exists. The second is the window macOS
    /// opens when it hands a running app a folder, and it used to take the
    /// same id and so the same `Session`: two windows, one folder, one cursor,
    /// one sidebar width, moving together (D-363).
    @ObservationIgnored private var firstWindowTaken = false

    /// The id a window with no value should carry. Once.
    func nextWindowID() -> UUID {
        defer { firstWindowTaken = true }
        return firstWindowTaken ? UUID() : SiftApp.firstWindowID
    }

    func session(_ id: UUID) -> Session {
        if let existing = sessions[id] { return existing }
        let session = Session(id: id)
        sessions[id] = session
        if activeID == nil { activeID = id }
        return session
    }

    /// The session every command lands on. Falls back to any open one, and then
    /// to a fresh one, so there is never a moment with nothing to talk to.
    var active: Session {
        if let activeID, let session = sessions[activeID] { return session }
        if let first = sessions.values.first { return first }
        return session(UUID())
    }

    var preview: Session {
        if let previewID, let session = sessions[previewID] { return session }
        return active
    }

    /// Whether the launch sequence has run. One launch, one scan, one
    /// `SIFT_SHOW`, one scripted replay.
    ///
    /// Two doors can both think they are the launch. `SiftApp.init` puts the
    /// last folder into `pending` before anything knows whether a document
    /// open is coming, and one arrives a moment later when the app was
    /// started on a folder — which is now every launch the tooling makes
    /// (D-324). Without this the folder was scanned twice and a scripted
    /// recording replayed its keys twice over the same photographs.
    var launchHandled = false

    func close(_ id: UUID) {
        sessions[id] = nil
        // `windows` and `tabHost` are deliberately *not* cleared here.
        // SwiftUI calls `onDisappear` on a gallery window moments after it
        // appears — the launch window's arrives before the reader has
        // touched anything — so this runs for windows that are still on
        // screen. A tab request cleared by that never reaches the window it
        // was for, and the tab opened as a window instead (D-372). The window
        // reference is weak and goes on its own; the request is consumed by
        // the window that collects it.
        if activeID == id { activeID = sessions.keys.first }
        if previewID == id { previewID = nil }
    }

    // MARK: taking a folder back (D-324)

    /// Drops the grant and shuts the door in every window at once.
    ///
    /// Two windows can be showing folders under one grant, so this cannot sit
    /// on a store: revoking in the Settings window while a gallery holds a
    /// started scope on the same card would drop the bookmark and leave the
    /// folder readable until the quit, which is the whole failure the sandbox
    /// was adopted to end. It lives here because here is the only place that
    /// knows about every session.
    func revokeFolder(_ url: URL) {
        FolderAccess.revoke(url)
        reconsiderAccess()
    }

    /// Every grant, pins included.
    ///
    /// Distinct from **Forget Recent Folders**, which keeps the pins, because
    /// the two answer different questions: that one is "stop remembering
    /// where I have been", this one is "Sift reads nothing until I say so".
    /// A pin is a place on a list and survives; what it loses is the reach.
    @discardableResult
    func revokeAllFolders() -> [String: Data] {
        let dropped = FolderAccess.revokeAll(keeping: [])
        reconsiderAccess()
        return dropped
    }

    /// The same, for the whole trail. Pinned folders keep their grants.
    func forgetHistory() {
        FolderAccess.forgetHistory()
        reconsiderAccess()
    }

    /// One row of the list: everything Sift holds about that folder, gone
    /// (D-325). The record and the grant are one act, because from the
    /// reader's side they were always one question.
    func removeFolder(_ url: URL) {
        FolderAccess.forget(path: url)
        reconsiderAccess()
    }

    /// Every folder at once. Pins keep their place in the sidebar and lose
    /// their access with everything else: a pin is a choice about where a
    /// folder sits, not a claim on what Sift may read.
    func removeAllFolders() {
        FolderAccess.revokeAll(keeping: [])
        Preferences.forget(Preferences.historyKeys)
        reconsiderAccess()
    }

    /// Asks every open folder whether it is still allowed, now that the
    /// grants have changed. One that is not closes its door and draws the
    /// refusal, which is what makes the press visible: the folder goes away
    /// rather than staying on screen and being reported as the button not
    /// working.
    private func reconsiderAccess() {
        for session in sessions.values { session.store.recheckAccess() }
    }
}

/// One gallery window. Owns nothing: it hands its session to the views and
/// tells the model when it becomes the window the keyboard is talking to.
struct GalleryWindow: View {
    let session: Session
    private let model = AppModel.shared

    /// Puts panels and overlays up at launch, named by `SIFT_SHOW`. It exists
    /// because this machine has no Accessibility permission, so nothing can
    /// send the app a keystroke from outside: without it, every screen that
    /// needs a key or a click to reach can only be checked by reasoning, which
    /// is how a whole theme ships unlooked-at (D-112).
    ///
    /// `SIFT_SHOW=info,filmstrip,help` and so on. Unset, which is every launch
    /// that is not a screenshot, it reads one environment variable and returns.
    ///
    /// A debug-build tool, and folded out of the download the way the scripted
    /// replay is (D-300, D-302). It had been the other kind of variable: the
    /// one that only shapes a window. Two of its screens do not. `confirm`
    /// favorites the photograph under the cursor and then presses trash,
    /// because the question the app asks needs a loved frame to ask about; a
    /// frame that is *already* loved is unfavorited by that press instead, so
    /// `trashTargets` finds nothing loved, skips the sheet it was assembling,
    /// and trashes the file. `undo` favorites twice, which is two tag writes
    /// and, with sidecars on, an `.xmp` written into the shoot and taken out.
    ///
    /// That is the D-300 argument one variable across, and the reason it is
    /// not "already game over": TCC grants attach to Sift rather than to
    /// whatever launched it, so a shipped build honoring this lets a process
    /// holding none of the reader's grants run `open -n --env
    /// SIFT_SHOW=confirm --args ~/Desktop` and have Sift do the trashing under
    /// Sift's own consent. A stale `export` in a shell profile is the other
    /// route, and unlike D-302's it costs a photograph rather than a keyboard.
    ///
    /// It costs the tooling nothing. `contact-sheet.sh`, `launch-check.sh`,
    /// `record-demo.sh` and the `make` default all build with `bundle.sh
    /// debug`; `dmg.sh` is the one that builds release, and it is the one that
    /// should not be able to be driven (D-308).
    /// Opening the first folder, with everything a launch does around it.
    ///
    /// Two doors reach this: the path `--args` used to hand to `main`, and a
    /// document open from Launch Services, which is how the tooling opens a
    /// folder now that the app is sandboxed (D-324). It is one function
    /// because the second door skipped `openOnLaunch` for a while and every
    /// screenshot came out as a plain gallery — the rig ran, the build was
    /// green, and nothing it produced was what it was asked for.
    @MainActor
    static func openAsLaunch(_ folder: URL, in session: Session, asked: Bool = true) {
        // The launch runs once. Both doors can think they are it: `SiftApp`'s
        // init puts the last folder into `pending` before anything knows
        // whether a document open is coming, and one arrives a moment later
        // whenever the app was started on a folder — which is every launch
        // the tooling makes since D-324. The document open lands first, and
        // the remembered folder is then dropped rather than opened, because
        // it is the answer to a question the reader has already answered.
        guard !AppModel.shared.launchHandled else { return }
        AppModel.shared.launchHandled = true

        let folder = startIn(folder)
        session.router.open(folder, asked: asked)
        // A refusal is not an empty folder, and the report must not call it
        // one: "opened harbor with 0 photos" is what a sandboxed launch with
        // no grant used to say, which reads as a folder that lost its
        // photographs rather than one the app was not allowed to look in
        // (D-324).
        if let refused = session.store.refused {
            AppDelegate.reportWindows("refused \(refused.lastPathComponent): no grant")
        } else {
            AppDelegate.reportWindows(
                "opened \(folder.lastPathComponent) with \(session.store.photos.count) photos")
        }
        openOnLaunch(session)
        // Before the script runs, not only at the settle below. The window had
        // been coming up at the size the last launch left it, because macOS
        // restored the frame; D-361 stopped restoring windows, so it now opens
        // at `defaultSize` and reached `SIFT_WIDTH` two seconds in, which is
        // after the scripted run has started. The recording is cropped to the
        // window's final bounds, so the opening second of every clip was a
        // 900pt window inside a 1024pt crop with the desktop showing around two
        // of its edges (D-362).
        //
        // Idempotent, and the settle still calls it: the preview window is made
        // a turn later than this and cannot be sized until it exists.
        AppDelegate.resizeForScreenshot()
        runScriptOnLaunch(session)

        // A second report, after the panels and the preview window are up.
        // The first one cannot name them: the preview is its own window and
        // `SIFT_SHOW=preview` makes it one turn later. The contact sheet
        // captures by window id, so it needs the list as it stands once the
        // screen is actually assembled (D-118).
        //
        // A turn is not enough. AppKit makes a new window key on its own
        // schedule, and one turn later it sometimes still is not: the report
        // then named the gallery as the key window and the sheet captioned a
        // picture of the grid "filmstrip". A second is long inside the
        // script's six and is the difference between a deterministic sheet
        // and a flaky one.
        //
        // This sits here rather than beside the `pending` handoff it grew up
        // in, because that handoff is now one door of two: left there, a
        // launch through the document door photographed a plain gallery and
        // never reported itself settled, and the contact sheet captures on
        // the settled report (D-324).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            AppDelegate.resizeForScreenshot()
#if DEBUG
            reportScreens(session.store)
#endif
            AppDelegate.reportWindows("settled")
        }
    }

    /// `SIFT_START_IN="Golden Hills"` opens that subfolder of the folder the
    /// launch was handed, rather than the folder itself.
    ///
    /// It exists for the sandbox. A grant covers the folder Launch Services
    /// handed over and everything under it, so a launch given one folder can
    /// read only that one, and the sidebar lists only that one: the README's
    /// clips showed a card with one folder on it where the card has two. Handed
    /// the card and told which shoot to open, the app reads both and the
    /// sidebar says so, while the clip is of the same folder as before (D-364).
    ///
    /// A debug-build tool, folded out of the download the way `SIFT_SHOW` and
    /// the scripted replay are (D-300, D-302).
    @MainActor
    static func startIn(_ folder: URL) -> URL {
#if !DEBUG
        if ProcessInfo.processInfo.environment["SIFT_START_IN"] != nil {
            note("SIFT_START_IN is a debug-build tool and this is a release build; ignoring it")
        }
        return folder
#else
        guard let name = Launch.asked(ProcessInfo.processInfo.environment["SIFT_START_IN"]) else {
            return folder
        }
        // One component, downward, and it has to be there. A path with a slash
        // in it, `..`, or a name that is not a folder on this card is a silent
        // plain-gallery launch otherwise — the failure D-324 spent three
        // sessions on. `..` was the one the first version let through, and the
        // comment claimed otherwise (S-34): no cost, because the variable is
        // compiled out of the download and a grant reaches downward only, so
        // the parent is a folder the app is refused anyway. A comment that
        // says what the guard does not is how S-20 started.
        let child = folder.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard !name.contains("/"), name != "..",
              FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            note("SIFT_START_IN=\(name): no such subfolder of \(folder.lastPathComponent)")
            return folder
        }
        return child
#endif
    }

    @MainActor
    static func openOnLaunch(_ session: Session) {
#if !DEBUG
        // The read is inside the branch, not above it, for the reason
        // `runScriptOnLaunch` gives: what ships should contain no code that
        // acts on the variable at all, and a test can see the difference
        // between "ignored" and "not there" (D-302).
        if ProcessInfo.processInfo.environment["SIFT_SHOW"] != nil {
            note("SIFT_SHOW is a debug-build tool and this is a release build; ignoring it")
        }
#else
        // `SIFT_CURSOR=6` lands the cursor on a chosen photograph before
        // anything is drawn. The marks a cell puts *on* a picture — the heart,
        // the keep/reject pill — only appear on the cursor's cell, so without
        // this the contact sheet can only ever show them over whatever photo
        // happens to be first. The fixture's near-white and near-black frames
        // exist precisely to break a mark that has no contrast of its own, and
        // nothing could point at them (D-58, D-120).
        if let index = Launch.index(ProcessInfo.processInfo.environment["SIFT_CURSOR"],
                                    within: session.store.photos.count,
                                    named: "SIFT_CURSOR") {
            session.store.cursor = index
        }
        guard let list = ProcessInfo.processInfo.environment["SIFT_SHOW"] else { return }
        for name in Launch.list(list) {
            switch name {
            // Every one of these goes through the router rather than setting
            // the store flag beside it. Four of them live in the preview
            // window, and the router is what knows to open it: setting
            // `showInfo` directly gave a launch that reported success and
            // drew a plain gallery, which is the failure mode this whole
            // mechanism exists to catch (D-118).
            case "info": session.router.perform(.toggleInfo)
            // Asked for by name, so it is turned on rather than toggled: the
            // strip is on by default now (D-122), and a toggle would have
            // photographed the screen without it.
            case "filmstrip":
                if !session.store.showFilmstrip { session.router.perform(.toggleFilmstrip) }
                session.router.openPreview()
            case "help": session.router.perform(.toggleHelp)
            case "summary": session.router.perform(.showSummary)
            // The peek has no command: it is a modifier and a pointer, and
            // neither is something a launch can press. The two halves are set
            // directly instead, which is the same screen a reader gets and the
            // only way this one can be photographed (D-130).
            case "peek":
                session.store.optionHeld = true
                session.store.hovered = session.store.current
            // The field and a query in it: `/` opens an empty field, which is
            // the screen without the half that matters (D-143).
            case "search":
                session.router.perform(.search)
                session.store.searchText = "frame-0"
            case "clipping": session.router.perform(.toggleClipping)
            // The folder narrowed to what was loved. A screen worth
            // photographing, and nothing more: it does not reproduce the crash
            // the heart used to cause, because that needed SwiftUI to be
            // rendering from the display link and a launch never is (D-195).
            case "favorites": session.router.perform(.filterFavorites)
            // The one question the app asks, which needs a loved photograph
            // under the cursor before it will appear (D-193). Setting the
            // favorite and then pressing trash is the reader's own route, and
            // a launch that set `trashConfirm` directly would photograph a
            // sheet the router might never raise.
            case "confirm":
                session.store.cursor = 0
                session.router.perform(.toggleFavorite)
                session.router.perform(.trash)
            // Crop is a drag, and a launch has no pointer. The rectangle is
            // the store's alone since D-159, so asking for one is setting it:
            // the grips, the scrim and the pixel readout all draw from it.
            case "crop":
                session.router.openPreview()
                session.router.perform(.crop)
                session.store.cropRect = CGRect(x: 0.18, y: 0.18, width: 0.55, height: 0.5)
            // The same mode with a shape on it: a ratio lit in the bar, the
            // turn control drawn beside it because a 16:9 box can be stood up,
            // and a rectangle that is 16:9 rather than whatever a drag left.
            // `crop` keeps the free box, so the two screens are the two states
            // the bar has (D-238).
            case "ratio":
                session.router.openPreview()
                session.router.perform(.crop)
                session.store.cropRatio = .sixteenNine
                // A true 16:9 of the fixture's 4:3 frame, planted rather than
                // snapped: the snap needs the file's own dimensions, which come
                // back off the decoder a beat after a launch sets this.
                session.store.cropRect = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
                // And the keyboard's ring, on the stop after the lit one, so
                // the shot shows the two states a control in this bar can be
                // in at once: the shape in force, and where Tab has got to
                // (D-245). Tab cannot be sent to the app from a script.
                session.store.modeBarCursor = .turn
            // The panel opens empty, which is the screen without the half that
            // matters, so the launch sets the sliders as well (the same reason
            // `search` types a query and `crop` plants a rectangle).
            case "adjust":
                session.router.openPreview()
                session.router.perform(.adjust)
                // Both groups, and two knobs left at 0 in each, so the shot
                // shows a lit readout and a quiet one side by side.
                session.store.adjustments = Adjustments([.exposure: 35, .contrast: 15, .highlights: -40,
                                                         .shadows: 25, .whites: 20,
                                                         .warmth: 20, .tint: -10, .vibrance: 30])
            // The revert preview. The bar and the tag are the screen; the
            // photograph behind them is the photograph itself rather than a
            // kept original, because keeping one means writing a second
            // full-size file into the folder and a launch writes nothing
            // (D-240).
            case "revert":
                session.router.openPreview()
                session.store.reverting = true
            // The rename sheet, which opens with the name selected and the
            // extension outside the selection (D-379). What is highlighted is
            // the whole screen here, and nothing outside the app can press
            // `n`.
            case "rename":
                session.store.cursor = 0
                session.router.perform(.rename)
                expect("rename") {
                    $0.renameTarget == nil ? "the rename sheet is not up" : nil
                }
            // The batch sheet, which is a different screen: a pattern field,
            // the token legend, and the count on the button. Nothing outside
            // the app can press `⇧N` either, and it cannot photograph the
            // banner, which needs a run in flight.
            case "batchrename":
                session.store.selectAll()
                session.router.perform(.batchRename)
                expect("batchrename") {
                    $0.batchRenameTargets == nil ? "the batch rename sheet is not up" : nil
                }
            case "trash": session.router.perform(.toggleTrashPanel)
            case "palette": session.router.perform(.commandPalette)
            case "jump": session.router.perform(.jumpToFolder)
            case "path": session.router.perform(.goToPath)
            case "rejects": session.router.perform(.reviewRejects)
            // The folder Sift is not allowed to read (D-324). The launch
            // itself came through the Launch Services door and so is granted;
            // this takes that grant back, which is the only way to see the
            // refusal from outside the app — nothing here can click Revoke in
            // Settings, and the screen exists to be looked at.
            case "revoked":
                if let open = session.store.folder {
                    AppModel.shared.revokeFolder(open)
                }
            case "preview": session.router.openPreview()
            // The photograph's own corner, with everything that can appear in
            // it at once: the zoom readout, a color label, a flag and the
            // heart. The zoom is a gesture and the marks are keys, so this is
            // the one screen no launch could reach, and it is the screen where
            // the order of that cluster is the thing being looked at (D-222).
            // The marks are set in the store rather than written to the files:
            // what is being photographed is the row, not the tag writer.
            case "zoom":
                session.router.openPreview()
                session.store.focus = .preview
                session.store.zoom = 2
                session.store.zoomIsActual = false
                guard let current = session.store.current else {
                    complain("zoom", "there is no photograph to mark")
                    break
                }
                session.store.update(current.url) {
                    $0.flag = .keep
                    $0.label = .red
                    $0.favorite = true
                }
                expect("zoom") { zoomScreenProblem($0) }
            // The corner undo, which had never been photographable: it draws
            // only when there is something on the undo stack and no toast over
            // it, and the label it draws is the top operation's. Favoriting
            // twice is the shortest route to a stack whose top is an
            // unfavorite, which is the case D-232 is about — the label used to
            // read "Undo favorite" there and put a favorite back.
            case "undo":
                session.store.cursor = 0
                session.router.perform(.toggleFavorite)
                session.router.perform(.toggleFavorite)
                expect("undo") { undoScreenProblem($0) }
            // The longest message the app can put in a toast: the toast sizes to
            // its content with no wrap and no ceiling, so the longest sentence
            // is the one that finds the right edge of a narrow window if
            // anything does. It was the save-over sentence until D-240 took
            // that toast away; the refusal a crop into a GIF gets is the
            // longest one left. Nothing is written to put it there.
            case "toast":
                session.store.cursor = 0
                session.store.showError("Writing a cropped GIF over the original would re-encode it into a format it cannot hold. Save a copy instead.")
                expect("toast") { $0.toast == nil ? "no toast on screen" : nil }
            // Focus mode is now the name of a window rather than a flag both
            // of them read (D-150), so the launch has to say which one. The
            // keyboard is in the gallery at launch, and `focus` is the
            // preview's bare mode: the screen this has always photographed.
            case "focus":
                session.router.openPreview()
                session.store.focus = .preview
                session.router.perform(.toggleFocusMode)
            // The other half, which is new: the gallery with its header, rail,
            // sidebar and clipboard bar put away (D-150).
            case "bare":
                session.store.focus = .gallery
                session.router.perform(.toggleFocusMode)
            case "select": session.router.perform(.selectAll)
            // The settings window is AppKit's to open, not the router's.
            // Both selectors, because the one macOS answers to changed and
            // the sheet has to work on whichever this machine is (D-123).
            case "settings":
                // One turn later: the Settings scene installs its responder
                // while the app finishes launching, and sending the action
                // from inside the first window's `onAppear` is too early for
                // it to be answered.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    Self.openSettingsFromTheMenu()
                }
            default: complain(name, "no screen called that")
            }
        }
#endif
    }

    /// Replays a run of commands through the router on a timer, named by
    /// `SIFT_SCRIPT`. `SIFT_SHOW` assembles one screen at launch; this is the
    /// other half, and it exists for the same reason: nothing can send this app
    /// a keystroke from outside, so a screen recording of somebody culling a
    /// folder cannot be driven from a script the way a web page can (D-112,
    /// D-250). Drawing the cull instead would have been a picture of an app
    /// that stops matching the app; driving it from inside is the real thing.
    ///
    /// `SIFT_SCRIPT=up,enterSingle,next,flagKeep,flagReject,wait:1200,cancel`.
    /// `SIFT_SCRIPT_SETUP` runs first and fast, and is how a clip of one action
    /// starts from the state that action needs: the sheet of rejected frames
    /// needs frames already rejected, and watching them be rejected is the
    /// clip before it, not this one.
    /// The tokens are `Command` raw values, so the recording is made out of the
    /// same table the help overlay and the palette read, and a rebound key
    /// cannot break it. `wait` rests one step and `wait:1200` rests that many
    /// milliseconds. `SIFT_SCRIPT_STEP` is the gap between commands and
    /// `SIFT_SCRIPT_LEAD` how long to wait before the first one, both in
    /// milliseconds.
    ///
    /// Every step is announced on stderr before it runs, so whatever is holding
    /// the recorder knows where the run is and when it ended. A token that is
    /// not a command stops the run and says so: a recording that quietly skips
    /// the step it was made for is worse than no recording.
    ///
    /// **Debug builds only** (D-299). Every other `SIFT_*` variable shapes a
    /// window; this one presses keys, and `trash` is one of them. TCC grants
    /// attach to Sift and not to whatever launched it, so in a shipped build a
    /// process holding none of the reader's folder grants could `open --env
    /// SIFT_SCRIPT=trash,next,trash --args ~/Desktop` and have Sift do the
    /// reading and the trashing under Sift's own consent (D-260 is the list of
    /// grants). It is narrow — a script sends argument-less commands, `trash`
    /// is `trashItem` so it is recoverable, an overwrite keeps the arrival
    /// frame, and there is no network anywhere in the app, so nothing can be
    /// taken — but it is free to close. The only thing that drives a script is
    /// the author's recorder, which builds with `bundle.sh debug`; `dmg.sh`
    /// builds release, so the download does not carry this at all.
    @MainActor
    static func runScriptOnLaunch(_ session: Session) {
#if !DEBUG
        // The read is inside the branch, not above it. It used to sit above,
        // so a release build reached for the variable and then refused it,
        // which is the same behavior and a weaker statement: what ships should
        // contain no code that reads a run at all, and a test can see the
        // difference between "ignored" and "not there" (D-302).
        if ProcessInfo.processInfo.environment["SIFT_SCRIPT"] != nil {
            note("SIFT_SCRIPT is a debug-build tool and this is a release build; ignoring it")
        }
#else
        let environment = ProcessInfo.processInfo.environment
        guard let list = environment["SIFT_SCRIPT"] else { return }
        // One run per process, not one per window. `.onAppear` is per window,
        // and `newWindow` is a `Command` a script may hold, so without this a
        // run that opens a window replayed itself in it (D-264).
        guard Launch.claim("SIFT_SCRIPT") else {
            note("a script is already running; this window is not starting another")
            return
        }
        // Refused rather than quietly given the default, because the recorder
        // computes how long to film from the same two numbers: a step the app
        // replaced with 650 is a clip cut against a length nothing ran to. This
        // is the `wait:1s` rule one layer up (D-264).
        guard let step = Launch.milliseconds(environment["SIFT_SCRIPT_STEP"],
                                             or: 650, named: "SIFT_SCRIPT_STEP"),
              let lead = Launch.milliseconds(environment["SIFT_SCRIPT_LEAD"],
                                             or: 1500, named: "SIFT_SCRIPT_LEAD")
        else { return }
        let tokens = Launch.list(list)
        let setup = Launch.list(environment["SIFT_SCRIPT_SETUP"])
        Task { @MainActor in
            for token in setup {
                guard await take(token, in: session, resting: 60, saying: nil) else { return }
            }
            if !setup.isEmpty { note("set up with \(setup.count) commands") }
            try? await Task.sleep(for: .milliseconds(lead))
            note("start \(tokens.count) steps, \(step)ms apart")
            for (index, token) in tokens.enumerated() {
                let label = "\(index + 1)/\(tokens.count) \(token)"
                guard await take(token, in: session, resting: step, saying: label) else { return }
            }
            note("done")
        }
#endif
    }

    /// One step, whatever kind it is, answering whether the run may go on. The
    /// setup pass and the take differ in how long they rest afterwards and in
    /// whether they are counted out loud, and in nothing else, so the grammar is
    /// walked in one place: two copies of it is how `wait` came to mean a rest
    /// in one and a stopped run in the other.
    @MainActor
    private static func take(_ token: String, in session: Session,
                             resting: Int, saying label: String?) async -> Bool {
        let step = ScriptStep.parse(token)
        if case .refused(let why) = step {
            note("\(token): \(why)")
            return false
        }
        if let label { note(label) }
        switch step {
        case .run(let command): session.router.perform(command)
        case .cropBox(let rect): session.store.cropRect = rect
        case .sidebar(let from, let to, let by):
            await sweepSidebar(from: from, to: to, by: by, in: session)
        case .lookAt(let rect): session.store.focusRequest = rect
        case .knob(let knob, let value): session.store.adjustments[knob] = value
        case .peek(.option(let held)): session.store.optionHeld = held
        case .peek(.hover(let index)):
            guard index < session.store.photos.count else {
                note("peek:\(index): the folder has \(session.store.photos.count) photographs")
                return false
            }
            session.store.hovered = session.store.photos[index]
            // The cell publishes `hoveredFrame` in answer to the claim above
            // (D-130), so the warp waits a tick for geometry that does not
            // exist yet when this line runs.
            try? await Task.sleep(for: .milliseconds(120))
            await glideCursorToHoveredCell(in: session)
        case .rest(let milliseconds):
            try? await Task.sleep(for: .milliseconds(milliseconds ?? resting))
            return true
        // Taken above, and here because the switch has to be whole.
        case .refused: return false
        }
        try? await Task.sleep(for: .milliseconds(resting))
        return true
    }

    /// Walks the real pointer to the cell the peek is about.
    ///
    /// One warp is a jump cut: at the twelve frames a second a GIF is written
    /// at, the pointer is on one side of the grid in one frame and the other
    /// side in the next, which reads as an edit rather than as a hand (D-298).
    /// Twenty warps over 400ms on an ease-out is five frames of travel that
    /// bunch up as they arrive, which is what a hand does.
    ///
    /// **Only from inside the window.** Every take starts with the pointer
    /// parked in the corner of the display, outside the crop, and a glide from
    /// there crosses the whole screen in the same 400ms: three frames of streak
    /// and two of them off the edge of the picture. The first arrival is a
    /// warp, so the clip opens with the pointer on a thumbnail the way a
    /// reader's own would be, and the hop between the two cells — which is the
    /// one move with both ends in frame — is the one that moves.
    /// A sidebar resize, one point at a time, which is what a hand does with
    /// the divider. Sixteen milliseconds between steps, so a sweep asks the app
    /// for about what a 60Hz drag asks for.
    ///
    /// It reports how long each step really took as well as running, because
    /// that is the number the report was about: a step that asks for 16ms and
    /// comes back in 90 says the main thread spent 74ms laying the grid out
    /// again, and no amount of reading the view code says that (D-345).
    @MainActor
    private static func sweepSidebar(from: CGFloat, to: CGFloat, by: CGFloat,
                                     in session: Session) async {
        let up = to >= from
        var width = from
        var worst: Double = 0
        var total: Double = 0
        var steps = 0
        session.store.sidebarWidth = width
        while up ? width <= to : width >= to {
            let began = CFAbsoluteTimeGetCurrent()
            session.store.sidebarWidth = width
            try? await Task.sleep(for: .milliseconds(16))
            let took = (CFAbsoluteTimeGetCurrent() - began) * 1000
            worst = max(worst, took)
            total += took
            steps += 1
            width += up ? by : -by
        }
        let mean = steps > 0 ? total / Double(steps) : 0
        note(String(format: "sidebar %.0f to %.0f: %d steps, mean %.1fms, worst %.1fms (asked 16)",
                    from, to, steps, mean, worst))
    }

    @MainActor
    private static func glideCursorToHoveredCell(in session: Session) async {
        guard let target = hoveredCellOnScreen(in: session) else { return }
        let from = CGPoint(x: NSEvent.mouseLocation.x,
                           y: Double(CGDisplayPixelsHigh(CGMainDisplayID())) - NSEvent.mouseLocation.y)
        guard galleryWindowOnScreen()?.contains(from) == true else {
            note("peek warp to \(target) from \(from), which is outside the window")
            CGWarpMouseCursorPosition(target)
            CGAssociateMouseAndMouseCursorPosition(1)
            return
        }
        note("peek glide to \(target) from \(from)")
        let steps = 20
        for index in 1...steps {
            let time = Double(index) / Double(steps)
            // Ease out: fast off the mark, settling onto the cell. The curve
            // `Tokens.Motion` names, written out because this is a warp loop
            // and not a SwiftUI animation.
            let eased = 1 - pow(1 - time, 3)
            CGWarpMouseCursorPosition(CGPoint(x: from.x + (target.x - from.x) * eased,
                                              y: from.y + (target.y - from.y) * eased))
            try? await Task.sleep(for: .milliseconds(20))
        }
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// The gallery window's frame, in the same top-left-origin display space
    /// the warps are given in.
    @MainActor
    private static func galleryWindowOnScreen() -> CGRect? {
        guard let window = galleryWindow() else { return nil }
        let frame = window.frame
        let high = Double(CGDisplayPixelsHigh(CGMainDisplayID()))
        return CGRect(x: frame.minX, y: high - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The one window a scripted peek is about.
    @MainActor
    private static func galleryWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("gallery") == true }
    }

    /// Where on the display the hovered cell's middle is.
    ///
    /// `store.hoveredFrame` is in the gallery's own coordinate space, which is
    /// the root view's, so its origin is the window's content view and its y
    /// runs down. A window's frame runs up from the bottom of the main screen,
    /// and `CGWarpMouseCursorPosition` runs down from the top of it, so the
    /// point is flipped twice on the way out. Warping is not an event tap and
    /// needs no Accessibility grant, which is why the recording can have a
    /// cursor in it at all (D-252, D-297).
    @MainActor
    private static func hoveredCellOnScreen(in session: Session) -> CGPoint? {
        let cell = session.store.hoveredWindowFrame
        guard cell != .zero, let window = galleryWindow(), let content = window.contentView
        else { return nil }
        let inContent = CGPoint(x: cell.midX, y: content.bounds.height - cell.midY)
        let onScreen = window.convertPoint(toScreen: inContent)
        return CGPoint(x: onScreen.x,
                       y: Double(CGDisplayPixelsHigh(CGMainDisplayID())) - onScreen.y)
    }

    /// Every line carries the wall clock, because the one thing a recorder
    /// cannot work out for itself is how long this launch took: trimming the
    /// head off by a guess at it put the first keystroke a second inside one
    /// clip and a second outside the next.
    static func note(_ message: String) {
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        Launch.say("SIFT-SCRIPT \(stamp) \(message)")
    }

    // Everything from here to the end of `reportScreens` and its two screen
    // checks is the screenshot
    // mechanism's own support: the refusals a failed capture prints, the
    // checks a screen registers about itself, and the menu click that opens
    // Settings. Every caller is inside `openOnLaunch`, so in a release build
    // this was unreachable code holding the string `SIFT_SHOW` — which
    // `SecurityClaimTests` reported, and correctly: a name still in the
    // binary is a name somebody can find and go looking for a way to reach.
    // The gate is D-308's, and this is the third reader of that variable it
    // turned up after two were fixed by hand.
#if DEBUG

    /// A screen said out loud that it could not be set up. A script driving the
    /// app for a picture reads these as a failed capture, which is the point: a
    /// launch that cannot assemble the screen it was asked for must not hand
    /// back a photograph of something else (D-227).
    static func complain(_ screen: String, _ why: String) {
        Launch.refuse("SIFT_SHOW", "\(screen), \(why)")
    }

    /// What a screen asked for, kept so it can be read back off the store once
    /// the window has settled rather than only at the moment it was asked for.
    /// Setting a mark and drawing it are not the same event, and the sheet's
    /// only guard until now was whether the picture came out identical to the
    /// grid — which a preview window with no marks on it is not (D-227).
    @MainActor private static var screenChecks: [(screen: String, problem: @MainActor (LibraryStore) -> String?)] = []

    @MainActor
    static func expect(_ screen: String, _ problem: @escaping @MainActor (LibraryStore) -> String?) {
        screenChecks.append((screen, problem))
    }

    /// Runs those checks. Called with the settled window report, which is the
    /// latest moment the process knows about: the capture is a few seconds
    /// later still, so this catches a screen that never assembled and not one
    /// that comes apart afterwards.
    @MainActor
    static func reportScreens(_ store: LibraryStore) {
        for (screen, problem) in screenChecks {
            if let why = problem(store) { complain(screen, why) }
        }
        screenChecks = []
    }

    /// The `zoom` screen, read back: the photograph's corner with all four
    /// marks in it (D-222). Its own function, and over the store rather than
    /// the session, so `ScreenCheckTests` can put a store in each state and
    /// assert on what comes back.
    static func zoomScreenProblem(_ store: LibraryStore) -> String? {
        guard let ref = store.current else { return "no photograph on screen" }
        if store.zoom == nil { return "the zoom went back to fit" }
        if ref.flag != .keep { return "\(ref.name) is not flagged keep" }
        if ref.label != .red { return "\(ref.name) has no red label" }
        if !ref.favorite { return "\(ref.name) is not a favorite" }
        return nil
    }

    /// The `undo` screen, read back: the corner control is drawn from the top
    /// of the stack and from there being no toast over it, so both are what
    /// this asserts. The label is checked as well as its presence, because a
    /// control naming the wrong operation is exactly the defect the screen
    /// exists to show (D-232).
    static func undoScreenProblem(_ store: LibraryStore) -> String? {
        guard store.undo.canUndo else { return "nothing on the undo stack to offer" }
        if store.toast != nil { return "a toast is over the corner control" }
        guard let label = store.undo.topLabel else { return "the top operation has no label" }
        if label != "Unfavorite" { return "the top operation is \(label), not the unfavorite" }
        if store.current?.favorite != false { return "the photograph is still a favorite" }
        return nil
    }

#endif

    /// Clicks `Sift > Settings…` rather than sending `showSettingsWindow:`.
    /// The selector is answered — it returns true — and no window appears,
    /// which is the difference between asserting on the call and asserting on
    /// the outcome. Going through the menu item also checks the thing that
    /// matters for discoverability: that there is a menu item at all, and
    /// that `⌘,` is not the only way in (D-42, D-123).
    @MainActor
    static func openSettingsFromTheMenu() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let item = appMenu.items.first(where: { $0.title.hasPrefix("Settings") || $0.title.hasPrefix("Preferences") })
        else {
            // The refusal is the screenshot mechanism's, not the menu's: a
            // reader who picks Settings and finds no item gets nothing from a
            // line on stderr. It stays with the rest of that mechanism, and
            // this function does not, because `SettingsWindow.open()` is how
            // the app itself opens Settings (D-42, D-308).
#if DEBUG
            complain("settings", "no Settings item in the app menu")
#endif
            return
        }
        appMenu.performActionForItem(at: appMenu.index(of: item))
    }

    var body: some View {
        RootView()
            .environment(session.store)
            .environment(session.router)
            .onAppear {
                model.activeID = session.id
                if let folder = model.pending.removeValue(forKey: session.id) ?? nil,
                   session.store.folder == nil {
                    // One turn later, so the window is on screen with its empty
                    // state before the scan takes the main actor (D-100). A
                    // thousand-file folder used to mean seconds of no window at
                    // all, which reads as a failure to launch.
                    // `asked: false`: this is `Preferences.lastFolder`,
                    // the app resuming where it was, not a folder anybody
                    // named this launch. A grant that has gone since then
                    // lands on the empty state rather than on a wall about a
                    // path the reader never typed (D-324).
                    Task { @MainActor in
                        // Two kinds of folder arrive this way and they are
                        // not the same act. The launch folder goes through
                        // `openAsLaunch`, which is latched to run once and
                        // carries the scan, `SIFT_SHOW`, the scripted replay
                        // and the settled report with it. A folder from `⌘N`
                        // or `⌘T` arrives after that latch has closed, so
                        // sending it the same way opened a window on nothing
                        // with the app's own name in its title bar — which is
                        // what `⌘N` had been doing since the latch went in
                        // (D-371).
                        if AppModel.shared.launchHandled {
                            session.router.open(folder)
                        } else {
                            Self.openAsLaunch(folder, in: session, asked: false)
                        }
                    }
                }
                model.monitor.install(model: model)
                model.volumes.start { folder, name in
                    // Offering to copy rather than to open: a card is the only
                    // copy of a shoot, and culling off one is culling over a
                    // bus you can unplug (D-89).
                    model.active.store.showToast("\(name) is in",
                                                 undoable: false,
                                                 offer: FolderOffer(label: "Copy the photos off",
                                                                    folder: folder,
                                                                    ingests: true))
                }
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            }
            .onDisappear { model.close(session.id) }
            .background(WindowKeyReporter { model.activeID = session.id })
            .background(GalleryTabbing(id: session.id))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// AppKit reads any process argument as "this launch is about opening
    /// something" and skips the untitled window it would otherwise ask the
    /// delegate for. `open Sift.app --args /some/folder` therefore came up as a
    /// running app with no window, and nothing inside could make one: the
    /// window openers are handed to the router by `RootView`, which needs a
    /// window to exist first (D-110).
    ///
    /// One turn later, because AppKit asks for the untitled window after this
    /// returns. By then a normal launch already has its window and a restored
    /// session has its windows, so the ask only happens when nothing came up.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The backups of every session that ended without reaching
        // `applicationWillTerminate` (D-299). That delegate is the only thing
        // that swept them and it does not run for a crash, a force-quit, a
        // `kill`, or a logout that takes a hung app, so full-size copies of
        // somebody's photographs sat in the temporary area until the system's
        // own sweep got to them — days, for an item-replacement directory. A
        // launch is the one moment guaranteed to come after a crash.
        FileOps.forgetEndedSessions()
        AppModel.shared.applyAppearance()
        // `SIFT_HINTS=off` spends every first-time hint before anything is
        // drawn. A filmed launch runs on a throwaway preferences domain, so it
        // is always somebody's first sitting and every hint fires over the
        // thing being filmed (D-271). Read once, and nothing otherwise.
        if Launch.asked(ProcessInfo.processInfo.environment["SIFT_HINTS"])?.lowercased() == "off" {
            Preferences.spendHints()
        }
        DispatchQueue.main.async {
            Self.reportWindows("launched")
            guard NSApp.windows.isEmpty else { return }
            _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
            Self.reportWindows("asked for the launch window")
        }
    }

    /// The session's undo backups go with the session (D-242).
    ///
    /// They are full-size copies of the reader's photographs, and the stack
    /// that points at them is this sitting's and does not survive a quit
    /// (D-108). Left behind they sit in the temporary area with nothing able to
    /// reach them until the machine reboots.
    func applicationWillTerminate(_ notification: Notification) {
        FileOps.forgetSessionBackups()
    }

    /// `SIFT_WIDTH=900` sets the gallery window's content width for one
    /// launch. The header's ladder has no breakpoints — it offers AppKit seven
    /// arrangements and takes the first that fits (D-113) — so the only way to
    /// find out which rung a given width lands on is to open a window that
    /// wide and look. Without this the sheet could only ever photograph the
    /// one width `defaultSize` happens to give (D-121).
    ///
    /// `SIFT_PREVIEW_WIDTH=760` does the same for the preview window, which
    /// grew a ladder of its own at D-158 and for the same reason could only
    /// ever be photographed at one width.
    ///
    /// `SIFT_PREVIEW_HEIGHT=360` is the same argument turned on its side, and
    /// the adjust panel is what asked for it: with ten sliders the panel's
    /// behavior depends on how tall the window is, and there was no way to
    /// photograph a short one (D-230). A window's height was never worth
    /// setting before, because nothing changed with it.
    @MainActor
    static func resizeForScreenshot() {
        setSize(width: "SIFT_WIDTH", height: "SIFT_HEIGHT", ofWindowWithPrefix: "gallery")
        setSize(width: "SIFT_PREVIEW_WIDTH", height: "SIFT_PREVIEW_HEIGHT", ofWindowWithPrefix: "preview")
        floatForRecording()
    }

    /// `SIFT_FLOAT=1` puts every window above the ordinary ones for the length
    /// of a screen recording.
    ///
    /// `screencapture -v` films a rectangle of the display and has no window
    /// option, so whatever is drawn over Sift is filmed in Sift's place. The
    /// recorder has raised Sift and then checked who was in front since D-252,
    /// which catches the problem and cannot fix it: the app driving the
    /// recording took the front back one second after every raise and held it,
    /// and six takes in a row came out as pictures of that app. Raising Sift
    /// harder is a race. Taking it out of the z-order argument is not (D-278).
    ///
    /// Read once, at the same settle the sizes are read at, and does nothing
    /// otherwise — the same bargain every launch variable here makes (D-265).
    @MainActor
    private static func floatForRecording() {
        guard Launch.isOn(ProcessInfo.processInfo.environment["SIFT_FLOAT"]) else { return }
        for window in NSApp.windows where window.isVisible {
            // `.floating` is one step above ordinary windows, and another app's
            // panel sits on that same step: a tie, and the other app wins it by
            // being raised later. That is how a session's own interface came to
            // be filmed in the middle of the longest clip, with the guard
            // reporting the intruder and keeping the take because the float was
            // supposed to have covered it. A recording flag can take the level
            // nothing ordinary reaches instead of the one that ties (D-294).
            window.level = .screenSaver
        }
    }

    /// Either dimension, both, or neither: a launch that names only a width
    /// leaves the height where the window put it, which is what every caller
    /// before this one expects.
    @MainActor
    private static func setSize(width: String, height: String, ofWindowWithPrefix prefix: String) {
        let env = ProcessInfo.processInfo.environment
        // Through `Launch.measurement`, not a second hand-rolled `Double.init`:
        // `SIFT_WIDTH=big` used to fall through to whatever width `defaultSize`
        // gave, and the sheet filed the result under `at-780` (D-266).
        let w = Launch.measurement(env[width], named: width)
        let h = Launch.measurement(env[height], named: height)
        guard w != nil || h != nil,
              let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(prefix) == true })
        else { return }
        var frame = window.frame
        // From the top-left, because that is the corner a Mac window is pinned
        // by: shrinking from the bottom-left would walk the title bar up the
        // screen and off it.
        let top = frame.maxY
        frame.size.width = w ?? frame.size.width
        frame.size.height = h ?? frame.size.height
        frame.origin.y = top - frame.size.height
        window.setFrame(frame, display: true)
    }

    /// What is on screen, in a form a script can read. `SIFT_WINDOW_REPORT=1`
    /// is how a smoke test tells a launch that drew a window from one that
    /// drew nothing. Whether AppKit put anything on screen is not a
    /// question the app can ask itself in a test, so it says it out loud and
    /// something outside the process decides.
    @MainActor
    static func reportWindows(_ note: String) {
        guard Launch.isOn(ProcessInfo.processInfo.environment["SIFT_WINDOW_REPORT"]) else { return }
        var out = "SIFT-WINDOWS \(note): \(NSApp.windows.count)\n"
        for w in NSApp.windows {
            // `windowNumber` is the CGWindowID, which is what `screencapture
            // -l` takes. Reporting it is the whole reason the contact sheet
            // needs no screen coordinates: no converting an AppKit frame with
            // its origin at the bottom into a capture rect with its origin at
            // the top, and no guessing which display the window landed on
            // (D-118).
            // `key` matters as much as `id`. `SIFT_SHOW=preview` leaves two
            // windows up, and the one the screen name means is the one in
            // front; a script that took the last visible window in the list
            // shot the gallery and captioned it "preview" (D-118).
            out += "  \(w.identifier?.rawValue ?? "-") title=\(w.title) frame=\(w.frame) visible=\(w.isVisible) key=\(w.isKeyWindow) id=\(w.windowNumber)\n"
        }
        // The menu bar, on the same line-per-launch principle. SwiftUI will
        // happily hand you two top-level menus with one name: `CommandMenu`
        // makes a new menu whatever it is called, so a menu called View sits
        // beside the View macOS supplies, and the commands are in whichever
        // one you did not open. Nothing in the process can tell it went wrong,
        // so it says the titles out loud and the launch check compares them
        // (D-218).
        let titles = (NSApp.mainMenu?.items ?? []).map(\.title)
        // No newline on the last line: `Launch.say` ends every message, and
        // the blank line a second one leaves is what a `grep -c` counts.
        out += "SIFT-MENUS: \(titles.joined(separator: ", "))"
        Launch.say(out)
    }

    /// The Finder's door, and the one `open -a Sift <folder>` comes through.
    ///
    /// Launch Services extends the sandbox to what it hands over, so this is
    /// a grant and is recorded as one (D-324). A file rather than a folder
    /// grants the file; the folder around it is what the app is about to
    /// show, so that is what gets bookmarked — Launch Services extends the
    /// enclosing directory for a document open, and a grant on a photograph
    /// alone would open a gallery of one.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        FolderAccess.remember(isDir ? url : url.deletingLastPathComponent())

        // A document open that arrives before any window has a folder is a
        // launch, and it goes through the same handoff `--args` used to: the
        // window appears empty first (D-100), then the scan, then the report,
        // `SIFT_SHOW` and the scripted replay.
        //
        // Not a nicety. Since D-324 the tooling opens the folder this way
        // rather than with `--args`, because a sandboxed app cannot open a
        // path handed to `main`. Routing straight to `router.open` here left
        // `pending` unset, so `openOnLaunch` never ran and every screenshot
        // and every recording came out as a plain gallery — a whole rig
        // quietly doing nothing, with the build green and the launch check
        // passing.
        // Nothing open yet means this is the launch, and a launch runs the
        // whole sequence rather than only the scan. `pending` is no use here:
        // this arrives after the window's `onAppear` has already read it.
        let model = AppModel.shared
        let session = model.active
        if !model.launchHandled {
            GalleryWindow.openAsLaunch(url, in: session)
        } else {
            session.router.open(url)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared
    private var store: LibraryStore { model.active.store }
    private var router: CommandRouter { model.active.router }

    init() {
        // `open build/Sift.app --args /some/folder` skips the open panel. The
        // folder has to land in the session the first window will show, which
        // is the one keyed on `firstWindowID`. Asking for `active` here makes a
        // session of its own, and the launch folder opens into a store nothing
        // is looking at.
        //
        // Only the decision is made here. The scan happens once the window is
        // up (D-100), through the same `pending` handoff `⌘N` uses.
        // Every grant opened before anything asks to read one (D-324). Here
        // rather than in `applicationDidFinishLaunching`, because a document
        // open from Launch Services lands between the two delegate calls and
        // would otherwise scan a folder whose ancestor's door was still shut.
        FolderAccess.openGranted()

        let first = AppModel.shared.session(Self.firstWindowID)
        if let start = Self.launchFolder(arguments: CommandLine.arguments,
                                         lastFolder: Preferences.lastFolder) {
            AppModel.shared.pending[first.id] = start
        }
    }

    /// Where the first window should land: a path handed to the binary, or the
    /// folder from the last sitting. Pure, so a test can ask it rather than
    /// launching the app.
    static func launchFolder(arguments: [String],
                             lastFolder: URL?,
                             exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        if let path = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }), exists(path) {
            return URL(fileURLWithPath: path)
        }
        if let last = lastFolder, exists(last.path) { return last }
        return nil
    }

    var body: some Scene {
        WindowGroup("Sift", id: Self.galleryID, for: UUID.self) { $id in
            // `⌘N` opens with a fresh `UUID`, and SwiftUI persists that value
            // per window, so a restored window comes back to the session it
            // had. `defaultValue` below is for the one window opened without a
            // value: the launch window, which is `firstWindowID` by name in
            // `openOnLaunch` too. Two windows that both arrived without a value
            // would share a session — hence one id, named, rather than a
            // fallback per call site.
            let session = model.session(id)
            GalleryWindow(session: session)
        } defaultValue: {
            // Not the constant. The launch window needs that name and nothing
            // else does: handing it to the window macOS opens for a second
            // folder put two windows on one session (D-363).
            AppModel.shared.nextWindowID()
        }
        // macOS reopens the windows an app had when it last quit, and every one
        // it reopens arrives with no value, so all of them take `firstWindowID`
        // and draw one session N times. That is how a bare launch had grown to
        // four windows on one folder, each launch adding another.
        //
        // Nothing here is worth restoring anyway: a `Session` is built empty and
        // a folder is not stored per window, so a restored window can only come
        // back blank, while the app already resumes `Preferences.lastFolder`
        // into the first window by itself. Owner's call, asked and answered:
        // one window on the last folder (D-361).
        .restorationBehavior(.disabled)
        // A titled window, because a toolbar needs a title bar to live in
        // (D-208). It was `.hiddenTitleBar` for as long as the app drew its
        // own header; the title itself is hidden in `ToolbarConfigurator`,
        // since the breadcrumb is the answer to "where am I".
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") { router.perform(.newWindow) }.keyboardShortcut("n")
                Button("New Tab") { router.perform(.newTab) }
                    .keyboardShortcut("t")
                    .disabled(store.folder == nil)
                Button("Open Folder…") { router.perform(.openFolder) }.keyboardShortcut("o")
                Button("Copy Photos Off a Card…") { router.perform(.ingest) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(store.folder == nil)
                Menu("Open Recent") {
                    let recents = Preferences.recentFolders
                    ForEach(Array(recents.prefix(9).enumerated()), id: \.offset) { i, url in
                        Button(url.lastPathComponent) { router.openRecent(i) }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                            .help(url.path)
                    }
                    if recents.isEmpty { Text("No recent folders") }
                }
                Button("Open Enclosing Folder") { router.perform(.openParent) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(store.folder == nil)
                Button("Back") { router.perform(.back) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!router.canGoBack)
                Button("Forward") { router.perform(.forward) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!router.canGoForward)
                Button("Jump to Folder…") { router.perform(.jumpToFolder) }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Find a Command…") { router.perform(.commandPalette) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Go to Folder…") { router.perform(.goToPath) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Open Subfolder…") { router.perform(.openSubfolder) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(store.subfolders.isEmpty)
                Toggle("Include Subfolders", isOn: Bindable(store).includeSubfolders)
                Divider()
                Toggle("Write XMP Sidecars", isOn: Binding(
                    get: { Preferences.writeSidecars },
                    set: { router.setSidecars($0) }
                ))
                .help("An .xmp beside each flagged photo, so Lightroom and Bridge read what you decided")
            }
            // `⌘Z`, `⌘C` and `⌘A` are the app's until something on screen is
            // taking typing, and then they are the field editor's. A menu
            // shortcut fires before the responder chain, so a menu item that
            // stays enabled takes the keystroke out of a rename field's hands:
            // `⌘C` copied the photograph rather than the selected text (D-281).
            CommandGroup(replacing: .undoRedo) {
                Button("Undo \(store.undo.topLabel ?? "")") { router.perform(.undo) }
                    .keyboardShortcut("z")
                    .disabled(!store.undo.canUndo || store.sheetHasTheKeyboard)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") { router.perform(.copy) }
                    .keyboardShortcut("c")
                    .disabled(store.current == nil || store.sheetHasTheKeyboard)
                Button("Copy Image") { router.perform(.copyImage) }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                    .disabled(store.current == nil || store.sheetHasTheKeyboard)
                Button("Copy Image Name") { router.perform(.copyName) }
                    .keyboardShortcut("n", modifiers: [.command, .control])
                    .disabled(store.current == nil || store.sheetHasTheKeyboard)
                Button("Copy Folder Path") { router.perform(.copyPath) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(store.folder == nil)
                Button("Select All") { router.perform(.selectAll) }
                    .keyboardShortcut("a")
                    .disabled(store.sheetHasTheKeyboard)
            }
            CommandMenu("Photo") {
                Button("Flag Keep") { router.perform(.flagKeep) }
                Button("Flag Reject") { router.perform(.flagReject) }
                Button("Clear Flag") { router.perform(.unflag) }
                Button(favoriteTitle) { router.perform(.toggleFavorite) }
                    .disabled(store.current == nil)
                Menu("Color Label") {
                    Button("Red") { router.perform(.labelRed) }.keyboardShortcut("1", modifiers: [])
                    Button("Yellow") { router.perform(.labelYellow) }.keyboardShortcut("2", modifiers: [])
                    Button("Green") { router.perform(.labelGreen) }.keyboardShortcut("3", modifiers: [])
                    Button("Blue") { router.perform(.labelBlue) }.keyboardShortcut("4", modifiers: [])
                    Button("Purple") { router.perform(.labelPurple) }.keyboardShortcut("5", modifiers: [])
                    Divider()
                    Button("None") { router.perform(.clearLabel) }.keyboardShortcut("0", modifiers: [])
                }
                .disabled(store.current == nil)
                Divider()
                // The count is the whole point: this menu is where you find out
                // that rotation applies to everything selected.
                Button(store.targets.count > 1 ? "Rotate \(store.targets.count) Photos Clockwise" : "Rotate Clockwise") {
                    router.perform(.rotateCW)
                }
                Button(store.targets.count > 1 ? "Rotate \(store.targets.count) Photos Counterclockwise" : "Rotate Counterclockwise") {
                    router.perform(.rotateCCW)
                }
                // The three edits a kept frame gets, together, because that is
                // what they are (D-236). Crop and adjust can each be switched
                // off; Revert is here whichever of them wrote into the file,
                // and it is the only way back to an original that a window
                // does not have to be in a mode to reach (D-239).
                if model.features.isOn(.crop) {
                    Button("Crop") { router.perform(.crop) }
                        .disabled(store.current == nil)
                }
                if model.features.isOn(.adjust) {
                    Button("Adjust") { router.perform(.adjust) }
                        .disabled(store.current == nil)
                }
                if model.features.isOn(.crop) || model.features.isOn(.adjust) {
                    Button("Revert to Original") { router.perform(.revertToOriginal) }
                        .disabled(!store.adjustRevertable)
                }
                Divider()
                Button("Move to Folder…") { router.perform(.moveToFolder) }
                Button("Copy to Folder…") { router.perform(.copyToFolder) }
                Button(editorTitle) { router.perform(.openInEditor) }
                    .disabled(store.current == nil)
                if Preferences.lastEditor != nil {
                    Button("Choose a Different Editor…") { router.forgetEditor() }
                }
                Button("Rename…") { router.perform(.rename) }
                Button("Batch Rename…") { router.perform(.batchRename) }
                Button("Move to Trash") { router.perform(.trash) }
                Button(reviewTitle) { router.perform(.reviewRejects) }
                    .disabled(store.folderCounts.reject == 0)
                Button("Move Rejected to \(CommandRouter.rejectFolderName)") { router.moveRejectsAside() }
                    .disabled(store.folderCounts.reject == 0)
                Button("Trashed This Sitting…") { router.perform(.toggleTrashPanel) }
                Divider()
                // The toolbar's share control has to be here too: a toolbar
                // item can be dragged out of the bar, and the menu bar is the
                // place a command cannot be taken from (D-205, D-211).
                ShareLink(items: store.targets.map(\.url)) {
                    Text(store.targets.count > 1 ? "Share \(store.targets.count) Photos…" : "Share…")
                }
                .disabled(store.targets.isEmpty)
                Button("Reveal in Finder") { router.perform(.revealInFinder) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Open in Default App") { router.perform(.openWith) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(store.previewOpen ? "Close Preview" : "Open Preview") {
                    store.previewOpen ? router.closePreview() : router.openPreview()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(store.current == nil)
                Divider()
                Toggle("Auto-Advance After Decision", isOn: Bindable(store).autoAdvance)
            }
            // Into the standard View menu, not beside it. `CommandMenu("View")`
            // always makes a new top-level menu, so the menu bar carried two
            // menus with the same name: macOS's own (Tab Bar, Full Screen) and
            // this one. Somebody looking for Show opens the first, finds three
            // window commands, and concludes the filter is not there. A
            // duplicate name is a menu bar lying about where a command lives.
            //
            // The "Folder Sidebar" toggle went with it: "Show Folder List"
            // lower down is the same fact on the same key, and D-205 is the
            // one with the reason written next to it (D-218).
            CommandGroup(after: .sidebar) {
                Button(store.folder.map { Preferences.isPinned($0) } == true ? "Unpin Folder" : "Pin Folder") {
                    router.perform(.togglePin)
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.folder == nil)
                Button("Pin Folders…") { router.addPinnedFolders() }
                Divider()
                Picker("Sort By", selection: Bindable(store).sort) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Sort Order", selection: Bindable(store).sortDirection) {
                    ForEach(SortDirection.allCases, id: \.self) { Text(store.sort.label($0)).tag($0) }
                }
                Picker("Show", selection: Bindable(store).filter) {
                    ForEach(PhotoFilter.menuCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Stack Bursts", isOn: Bindable(store).stackBursts)
                Toggle("Group by Scene", isOn: Bindable(store).groupByScene)
                Divider()
                Button("Larger Thumbnails") { router.perform(.thumbsLarger) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(store.cellSize >= (Tokens.Layout.gridCellSteps.last ?? 0))
                Button("Smaller Thumbnails") { router.perform(.thumbsSmaller) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(store.cellSize <= (Tokens.Layout.gridCellSteps.first ?? 0))
                Divider()
                if model.features.isOn(.bare) {
                    Button(store.bareWindow != nil ? "Leave Focus Mode" : "Focus Mode") { router.perform(.toggleFocusMode) }
                }
                // A switched-off feature has no menu item either. Grayed out
                // would be the feature still taking the room it was turned
                // off for (D-123).
                if model.features.isOn(.compare) {
                    // All three, in the order compare is used. The menu listed
                    // only the last one, so the two commands that get you there
                    // were keys and the command palette alone (D-268).
                    Button(store.compareAnchor == store.current?.url ? "Clear A" : "Mark A") {
                        router.perform(.setCompareAnchor)
                    }
                    .keyboardShortcut("a", modifiers: [])
                    .disabled(store.current == nil)
                    Button(store.showingCompare ? "Back to This Photo" : "Flip to A") {
                        router.perform(.toggleCompare)
                    }
                    .disabled(store.compareAnchor == nil || store.compareAnchor == store.current?.url)
                    Button(store.sideBySide ? "Stop Comparing Side by Side" : "Compare Side by Side") {
                        router.perform(.compareSideBySide)
                    }
                    .disabled(store.current == nil)
                }
                if model.features.isOn(.survey) {
                    Button(store.surveying ? "Leave Survey" : "Survey") { router.perform(.survey) }
                        .disabled(store.current == nil)
                }
                if model.features.isOn(.tournament) {
                    Button(store.tournament ? "End Tournament" : "Start Tournament") { router.perform(.tournament) }
                        .disabled(store.photos.count < 2)
                }
                Divider()
                // Every control in the header is a command in the menu bar as
                // well. The folder list was the one that was not: it had a
                // button, a key and nothing under View, which is the half of
                // the reach rule that runs the other way — a toolbar can be
                // hidden or customized, so it cannot be the only place a
                // command lives (D-205).
                Button(store.showSidebar ? "Hide Folder List" : "Show Folder List") {
                    router.perform(.toggleSidebar)
                }
                .keyboardShortcut("\\", modifiers: .command)
                Toggle("Info Panel", isOn: Bindable(store).showInfo).keyboardShortcut("i", modifiers: .command)
                Toggle("Filmstrip", isOn: Bindable(store).showFilmstrip)
                if model.features.isOn(.highlights) {
                    Toggle("Blown Highlights", isOn: Bindable(store).showClipping)
                }
                if model.features.isOn(.focusPeaking) {
                    Toggle("Focus Peaking", isOn: Bindable(store).showFocusPeaking)
                }
                if model.features.isOn(.faces) {
                    Button(store.faces.isEmpty ? "Zoom to Face" : "Zoom to Face (\(store.faces.count) found)") {
                        router.perform(.zoomToFace)
                    }
                    .disabled(store.faces.isEmpty)
                }
                Divider()
                if model.features.isOn(.slideshow) {
                    Button(store.slideshow ? "Stop Slideshow" : "Slideshow") { router.perform(.slideshow) }
                        .disabled(store.current == nil)
                }
                Button("Move Preview to the Other Display") { router.perform(.previewOnOtherScreen) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(!store.previewOpen)
                Divider()
                Picker("Appearance", selection: Binding(
                    get: { model.appearance },
                    set: { router.setAppearance($0) }
                )) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if model.features.isOn(.summary) {
                    Divider()
                    Button("Summary of This Sitting") { router.perform(.showSummary) }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                }
            }
            // Replaced rather than added to, because the item it replaces —
            // "Sift Help" — opens a help book this app does not ship, and a
            // menu item that opens nothing is worse than one that is absent.
            // The palette joins it: the Help menu is where somebody looks for
            // a command they cannot find, and the palette is this app's answer
            // to that (D-215).
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { router.perform(.toggleHelp) }
                    .keyboardShortcut("/", modifiers: .command)
                Button("Find a Command…") { router.perform(.commandPalette) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        // One preview at a time, so `Window` rather than `WindowGroup`. SwiftUI
        // remembers its frame across launches under this id.
        Window("Preview", id: Self.previewWindowID) {
            let session = model.preview
            PreviewWindow()
                .environment(session.store)
                .environment(session.router)
        }
        .defaultSize(width: 1100, height: 800)
        .keyboardShortcut("p", modifiers: [.command, .shift])
        // Its frame is still remembered; the window itself is not reopened. A
        // preview restored at launch comes up on no photograph and says "No
        // photo", because the session it reads is built empty. The recorder
        // already carried a comment about filming exactly that, and a
        // screenshot run inherited it from whichever scene last pressed `p`
        // (D-361).
        .restorationBehavior(.disabled)

        // `⌘,` and `Sift > Settings…`. SwiftUI puts the menu item in for us,
        // which is what keeps the shortcut from being the only way in (D-42).
        Settings {
            SettingsWindow()
        }
    }

    /// Names the editor once there is one, so the menu item is the answer
    /// rather than a question.
    private var editorTitle: String {
        guard let app = Preferences.lastEditor else { return "Open in Editor…" }
        let n = store.targets.count
        return n > 1 ? "Open \(n) Photos in \(FileOps.appName(app))" : "Open in \(FileOps.appName(app))"
    }

    /// Says how many are waiting, so the menu is also the place you find out
    /// that there are rejects to look at.
    private var reviewTitle: String {
        let n = store.folderCounts.reject
        return n == 0 ? "Review Rejected…" : "Review \(n) Rejected…"
    }

    /// Named for what the command will do to the targets, not for what they
    /// are: with a mixed selection it makes them all favorites.
    private var favoriteTitle: String {
        let targets = store.targets
        guard !targets.isEmpty else { return "Favorite" }
        let noun = targets.count == 1 ? "" : " \(targets.count) Photos"
        return targets.allSatisfy(\.favorite) ? "Remove\(noun) from Favorites" : "Favorite\(noun)"
    }

    static let galleryID = "gallery"
    static let previewWindowID = "preview"
    /// The session the app opens with, and the one a restored window falls back
    /// to. Stable so that reopening does not strand the launch folder.
    static let firstWindowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

