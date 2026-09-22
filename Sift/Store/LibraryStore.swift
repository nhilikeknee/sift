import AppKit
import Foundation
import Observation

/// Which window the keyboard is talking to. The gallery and the preview are
/// separate windows over one cursor (D-28).
enum WindowFocus: Sendable { case gallery, preview }

/// What this sitting did to the open folder. Reset on open.
struct SessionStats: Equatable, Sendable {
    var kept = 0
    var rejected = 0
    var trashed = 0
    var trashedBytes = 0
    var moved = 0
}

/// One file sent to the Trash this sitting, so it can be brought back by name.
struct TrashEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let original: URL
    let trashed: URL
    let size: Int
    let at: Date
    var restored = false
    var name: String { original.lastPathComponent }
}

struct ToastState: Identifiable, Equatable, Sendable {
    let id = UUID()
    let message: String
    /// Said in the reject color and left up longer. An error is still a toast:
    /// a file that cannot be rotated does not deserve a dialog (D-48).
    var isError = false
    /// A folder the toast offers to open. The end of a cull is the moment the
    /// next folder is wanted, and it is the one moment Sift knows which it is.
    var offer: FolderOffer?
    /// True for a toast that describes where the cursor is rather than what
    /// just happened. "Last photo" is only true at the last photo, so arrowing
    /// back to the middle of the folder has to take it away rather than leave
    /// it up saying something false for the rest of its four seconds (D-221).
    ///
    /// Most toasts are the other kind and must survive a move: a trash with
    /// auto-advance on moves the cursor as part of doing the thing the toast is
    /// offering to undo.
    var endsOnMove = false
}

/// A trash that has to be agreed to, because a favorite is in it (D-193).
///
/// It carries the photographs rather than re-reading `store.targets` when the
/// answer comes back: the aim is restored the moment `perform` returns (D-104),
/// and the cursor can move while the sheet is up. Whatever was named in the
/// question is what the yes acts on.
struct TrashConfirm: Identifiable, Equatable {
    let id = UUID()
    let refs: [PhotoRef]
    /// The window that asked, so the question is put in front of the keyboard
    /// rather than on the gallery behind the preview (D-67).
    let window: WindowFocus

    var favorites: [PhotoRef] { refs.filter(\.favorite) }

    /// What the question says. Names the photograph when there is one, counts
    /// when there are more, and always says how many of them were loved —
    /// which is the fact that made this worth asking about.
    var question: String {
        refs.count == 1 ? "Move \(refs[0].name) to the Trash?"
                        : "Move \(refs.count) photos to the Trash?"
    }

    var because: String {
        let loved = favorites.count
        if refs.count == 1 { return "It is a favorite." }
        if loved == refs.count { return "All \(loved) of them are favorites." }
        return loved == 1 ? "One of them is a favorite." : "\(loved) of them are favorites."
    }

    /// What a yes actually costs, which is less than the word Trash suggests.
    /// Agreeing in number, because a question naming one photograph and then
    /// saying "they" reads as a question written for a different case.
    var reassurance: String {
        refs.count == 1 ? "It goes to the Trash, not away. ⌘Z brings it back while Sift is open."
                        : "They go to the Trash, not away. ⌘Z brings them back while Sift is open."
    }
}

/// How far a batch has got, and the way to stop it.
struct ProgressState: Equatable, Sendable {
    let label: String
    var done: Int
    var total: Int
    var cancelled = false
    /// Work with nothing to count: one undo of a batch, where the reversal is a
    /// single call. The banner draws a full bar rather than a lying empty one.
    var isIndeterminate: Bool { total == 0 }
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// A claim on the one progress banner, handed out by `LibraryStore.withProgress`
/// and valid only inside it (D-189).
///
/// Every call checks that this run still owns the banner, so a late `step` from
/// a superseded run writes nothing. `.silent` is a run with no banner at all:
/// the same calls, all of them no-ops, so a loop that sometimes reports and
/// sometimes does not is still one loop.
@MainActor
struct ProgressRun {
    private let store: LibraryStore?
    private let token: UUID?

    static let silent = ProgressRun(store: nil, token: nil)

    init(store: LibraryStore?, token: UUID?) {
        self.store = store
        self.token = token
    }

    /// Nothing happens through a run that has lost the banner, and nothing at
    /// all happens through a silent one.
    private var owns: Bool { token != nil && store?.holdsProgress(token) == true }

    /// Whether somebody pressed stop. False for a silent run, which has no
    /// button to press.
    var cancelled: Bool { owns && store?.progress?.cancelled == true }

    func advance(to done: Int) {
        guard owns else { return }
        store?.setProgressDone(done)
    }

    func step() {
        guard owns, let done = store?.progress?.done else { return }
        advance(to: done + 1)
    }

    /// Takes the banner down early, for a run with something to say after it.
    /// Idempotent, and a no-op for a run that no longer owns the banner, so it
    /// can never clear somebody else's — which is the whole reason the claim
    /// is a token and not a Bool.
    func end() {
        guard let token, owns else { return }
        store?.releaseProgress(token)
    }
}

/// What a folder-wide read can be asked to find out. One pass serves any
/// combination (D-101): the header answers dates and camera facts in the same
/// call, and sharpness is the one that costs a decode.
struct FolderFacts: OptionSet, Sendable {
    let rawValue: Int
    static let dates = FolderFacts(rawValue: 1 << 0)
    static let camera = FolderFacts(rawValue: 1 << 1)
    static let sharpness = FolderFacts(rawValue: 1 << 2)
}

/// One file's share of a pass: which of the two reads it still needs.
struct FactWork: Sendable {
    let url: URL
    let contentID: String
    let header: Bool
    let sharpness: Bool
}

/// One first-time hint. The id is what "once, ever" is counted against.
struct HintState: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
}

struct FolderOffer: Equatable, Sendable {
    let label: String
    let folder: URL
    /// True when the offer is to copy the folder's photos off rather than to
    /// open it where it sits. Culling straight off a card is culling over a USB
    /// bus, against the only copy of the shoot (D-89).
    var ingests = false
}

/// A run of photos under one heading in the grid: a folder when subfolders are
/// included, a scene when the shoot pauses (D-85).
struct GridSection: Identifiable, Sendable {
    let title: String
    let start: Int
    let count: Int
    /// Somewhere to go when the heading is clicked. Nil for a scene, which is
    /// not a place.
    let folder: URL?
    var id: Int { start }
}

/// One cell in the folder row: a folder inside the open one. The way *out* is
/// not here — it is the breadcrumb, the back arrow and `⌘↑`, all of them in the
/// header (D-111).
struct FolderEntry: Identifiable, Hashable, Sendable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// The open folder and everything derived from it. One per window (D-9).
@MainActor @Observable
final class LibraryStore {
    private(set) var folder: URL?
    /// The open door, held for as long as the folder is open (D-324).
    ///
    /// Access is process-wide once started, so the background decode never
    /// asks: it is granted because this token exists. Replacing it closes the
    /// last folder's door, which is the whole reason it is a stored property
    /// and not a local — a scope started and never ended leaves the folder
    /// readable for the rest of the launch, which is the bug the sandbox was
    /// adopted to fix, reintroduced one layer down.
    private var scope: FolderAccess.Scope?
    /// The folder Sift was asked for and is not allowed to read.
    ///
    /// A separate state from `lastError` because it is not an error: nothing
    /// went wrong, the reader simply has not handed this folder over, and the
    /// screen for it has a button rather than an apology. An empty folder and
    /// a forbidden one drew the same empty grid, and only one of them has a
    /// way forward (D-324).
    private(set) var refused: URL?
    /// Every image in the folder, unsorted and unfiltered.
    private(set) var allPhotos: [PhotoRef] = []
    /// What the views show: `allPhotos` filtered and sorted.
    private(set) var photos: [PhotoRef] = []
    /// Folders inside the open folder. Cached because ⌘↓ and the File menu both
    /// ask whether there is anywhere to go down to, and a directory read per
    /// keystroke is not free.
    private(set) var subfolders: [URL] = []
    /// The folders any screen actually draws: `subfolders` narrowed by the name
    /// filter, then cut to `folderTileMax`.
    ///
    /// A ceiling rather than a faster tile. The system temporary directory
    /// holds 19,176 folders, and handing that many to a `LazyVGrid` put the app
    /// at 99% of a core and 4.1GB with no window that answered: SwiftUI builds
    /// a pointer region per tile for the hover, and the main thread never got
    /// back to the run loop. Reading all 19,176 takes 1.4 seconds, so the
    /// scanning was never the problem and making it faster would have fixed
    /// nothing (D-318).
    private(set) var shownSubfolders: [URL] = []
    /// How many folders the cap left out. Zero unless the screen is saying so.
    private(set) var subfoldersLeftOut = 0
    /// The most folders a screen will draw at once. 500 fills a window several
    /// times over at any cell size, which makes it a scroll rather than a
    /// list anybody reads; past that the name filter is the way through, and
    /// the line under the grid says so.
    static let folderTileMax = 500

    var sort: SortOrder = Preferences.sort {
        didSet {
            Preferences.sort = sort
            rebuild()
            loadFolderFactsIfNeeded()
        }
    }
    /// Which way round `sort` runs (D-349). Its own property rather than six
    /// more cases on `SortOrder`, because it is one question asked of whichever
    /// field is chosen, and a stored order from an older build still reads.
    var sortDirection: SortDirection = Preferences.sortDirection {
        didSet {
            Preferences.sortDirection = sortDirection
            rebuild()
        }
    }
    var filter: PhotoFilter = .all { didSet { rebuild() } }
    /// Live filename filter from `/`. Case-insensitive substring.
    var searchText = "" { didSet { rebuild(); loadFolderFactsIfNeeded() } }
    var searching = false
    var includeSubfolders = Preferences.includeSubfolders { didSet { Preferences.includeSubfolders = includeSubfolders; reload() } }
    /// Collapse a continuous burst into one cell with a count (D-84). Not
    /// remembered across launches, like the other two view modes that change
    /// what a photo means on screen: opening a folder and finding 3,000 frames
    /// shown as 400 is a surprise nobody asked for that morning.
    var stackBursts = false {
        didSet {
            expandedStacks = []
            loadFolderFactsIfNeeded()
            rebuild()
        }
    }
    /// Break the grid where the shoot pauses (D-85). Not remembered, for the
    /// same reason.
    var groupByScene = false {
        didSet {
            loadFolderFactsIfNeeded()
            rebuild()
        }
    }
    /// Stacks the reader has opened. Cleared on a folder change and whenever
    /// stacking is switched off, because an expansion is about one sitting.
    var expandedStacks: Set<URL> = []
    /// How many photos each stack's leader stands for. Only leaders of a run
    /// longer than one appear.
    private(set) var stackCounts: [URL: Int] = [:]
    var autoAdvance = Preferences.autoAdvance { didSet { Preferences.autoAdvance = autoAdvance } }

    /// Index into `photos`, and nil for "nowhere". Nil is a real state, not
    /// just the empty folder: a folder opened for the first time has no cursor
    /// until somebody puts one somewhere, and a click on the canvas takes it
    /// away again (D-141). The gray tile is the only thing that draws it, so a
    /// cursor nobody asked for is a photo that looks chosen on arrival.
    var cursor: Int? {
        didSet {
            clampCursor()
            if oldValue != cursor {
                // Who moved it, decided here rather than at each of the
                // thirty places that assign it. Everything wants the cell
                // brought into view except the pointer, which put the cursor
                // on a cell that is already under the hand (D-374).
                revealCursor = pointerDepth > 0 ? nil : cursor
                if toast?.endsOnMove == true { toast = nil }
                undoLeftBehind = true
                resetViewState()
                if let folder { Preferences.setResume(current?.url, for: folder) }
            }
        }
    }

    /// The cell the grid should scroll to, or nil when nothing needs
    /// bringing into view. The grid watches this rather than `cursor`:
    /// scrolling on every cursor change centered the cell a click had just
    /// landed on, so the grid slid out from under the pointer and the next
    /// click hit whatever had moved into its place (D-374).
    private(set) var revealCursor: Int?

    /// How many pointer gestures are running. A count rather than a flag
    /// because a click sets the cursor and then extends a selection, which
    /// sets it again.
    @ObservationIgnored private var pointerDepth = 0

    /// Runs `body` with every cursor move inside it counted as the pointer's.
    /// One seam for the click, the band drag and the rail scrub, so a fourth
    /// pointer path cannot forget (D-374).
    func fromPointer(_ body: () -> Void) {
        pointerDepth += 1
        defer { pointerDepth -= 1 }
        body()
    }
    /// No hint fires here. Selecting a second photograph used to raise a toast
    /// saying the next command would act on all of them — a sentence that
    /// explained the action bar sitting two inches above it, at the moment
    /// somebody had just reached for the work (D-206).
    var selected: Set<URL> = []
    var selectionAnchor: Int?

    /// Where the keyboard cursor sits when it is in the folder row above the
    /// photos. Nil means it is down among the photos, which is the usual case.
    /// The folder row is navigation only: a folder is never selected, flagged
    /// or trashed, so `cursor` and `selected` stay about photos alone (D-33).
    var folderCursor: Int? {
        didSet { if let f = folderCursor, !folderRow.indices.contains(f) { folderCursor = folderRow.isEmpty ? nil : 0 } }
    }

    /// What the folder row holds: the ways into this folder, and nothing else.
    ///
    /// The drawn list, not the whole one: `folderCursor` is an index into this
    /// array, so anything the grid narrows or caps has to be narrowed and
    /// capped before the cursor is laid over it (D-318).
    var folderRow: [FolderEntry] { shownSubfolders.map(FolderEntry.init) }

    /// Which window is key. Set by `WindowFocusReporter`, read by the key map.
    var focus: WindowFocus = .gallery
    var previewOpen = false

    /// How many times the preview window has been opened this sitting.
    ///
    /// The photograph's view is deliberately kept across a cursor move, so one
    /// frame dissolves into the next (D-63). SwiftUI keeps it across a *close
    /// and reopen* too, and there the held frame is the last photograph
    /// somebody looked at: open A, close it, open B, and A is on screen for
    /// the moment before B decodes. Counting the openings gives that view an
    /// identity that changes when the window comes back and not when the
    /// cursor moves, which is the difference the crossfade rests on (D-375).
    private(set) var previewOpening = 0

    func notePreviewOpened() { previewOpening += 1 }
    var showInfo = false
    var showHelp = false
    var showSummary = false
    var showTrashPanel = false
    /// Where the breadcrumb's first crumb starts, in window coordinates, so
    /// the subfolder menu comes out of the control that lists the same folders
    /// (D-186). Reported by the header; nothing reads it before the header has
    /// drawn once, and the fallback is the window's left edge.
    var breadcrumbX = Tokens.Layout.windowEdge

    var showSidebar = Preferences.showSidebar { didSet { Preferences.showSidebar = showSidebar } }
    /// Mirrors `Preferences.pinnedFolders`. Held here so the sidebar redraws
    /// when a pin is added, which UserDefaults alone would not do.
    var pinned: [URL] = Preferences.pinnedFolders
    var showFilmstrip = Preferences.showFilmstrip { didSet { Preferences.showFilmstrip = showFilmstrip } }
    /// Thumbnail edge, stepped by `⌘=` and `⌘-` and the pair in the header.
    var cellSize = Preferences.gridCell { didSet { Preferences.gridCell = cellSize } }
    /// The sidebar's width, dragged by its divider and remembered (D-229).
    var sidebarWidth = Preferences.sidebarWidth { didSet { Preferences.sidebarWidth = sidebarWidth } }
    /// Paint blown highlights over the photo in single view.
    var showClipping = false

    /// The thumbnail the pointer is on. Set by the cell, cleared by the same
    /// cell on its way out, so two cells swapping cannot leave a claim behind.
    var hovered: PhotoRef?
    /// Where that thumbnail is, in the gallery's coordinate space. The peek is
    /// drawn beside it, so the frame travels with the hover rather than being
    /// looked up afterwards: the cell is the only thing that knows.
    var hoveredFrame: CGRect = .zero
    /// The same cell in the window's own coordinates, which is what a recording
    /// needs to put the real pointer on it (D-297). Kept beside the gallery-space
    /// one rather than replacing it: the peek is drawn in the gallery's space
    /// and a warp is a screen coordinate, and converting between them after the
    /// fact means knowing where the gallery sits, which is the thing nobody
    /// here knows. The cell knows both, so the cell publishes both.
    var hoveredWindowFrame: CGRect = .zero
    /// Whether `⌥` is down, from the one flags monitor in `KeyMonitor`.
    var optionHeld = false
    /// The peek is the two of them and nothing else (D-130). Not a third flag:
    /// a stored `peeking` would need clearing on pointer-exit, on key-up, on
    /// scroll, on the folder changing and on the window resigning key, and the
    /// bug is always the one of those that was missed. Read as a product, it
    /// cannot outlive either half.
    var peeked: PhotoRef? { optionHeld ? hovered : nil }

    /// The pointer arriving at or leaving one cell. A method rather than the
    /// cell assigning `hovered` itself, because the leaving half has a rule in
    /// it and a rule inside a view closure is a rule with no test on it.
    func pointer(_ inside: Bool, on ref: PhotoRef, frame: CGRect = .zero) {
        if inside {
            hovered = ref
            hoveredFrame = frame
        } else if hovered?.url == ref.url {
            hovered = nil
        }
    }

    /// What `⌘C` loaded, and it stays loaded (D-135). Not the system
    /// pasteboard: that is written too, so Finder can paste, but it is shared
    /// with every other app on the machine and a paste here has to mean the
    /// photographs *this* app was told about. One fact, one place, and the
    /// pasteboard write is a courtesy rather than the record.
    var clipboard: [URL] = []

    var session = SessionStats()
    var trashLog: [TrashEntry] = []
    var gridColumns = 1
    /// Measured by `HeaderBar`. The only thing that knows where the breadcrumb
    /// ends, which is where ⌘↓ drops its menu.
    var headerHeight: CGFloat = 0
    var lastError: String?

    // Single-view state. Reset on every cursor change, except the zoom.
    /// Nil means fit to window. Otherwise a multiplier over the fit size.
    var zoom: CGFloat? { didSet { if zoom == nil { lookingAt = CGPoint(x: 0.5, y: 0.5) } } }
    /// True while the zoom is "actual pixels" rather than a number someone
    /// pinched to. A multiplier means different magnifications on two photos of
    /// different dimensions, so 1:1 has to be remembered as an intent and
    /// resolved against each photo (D-79).
    var zoomIsActual = false
    /// Multiplier over the fit size that shows the image at 1:1. Published by
    /// SingleView once it knows the photo's pixel size.
    var oneToOneScale: CGFloat = 1 {
        didSet {
            // The next photo is a different shape, so "actual pixels" is a
            // different multiplier. Following it is what lets you sit at 100%
            // and arrow through a burst.
            if zoomIsActual, oneToOneScale != oldValue { zoom = oneToOneScale }
        }
    }
    /// Where in the photograph the window is centered, in normalized image
    /// coordinates, and the reason a zoomed walk down a burst holds still.
    ///
    /// The view's own `pan` is points of the *scaled* photo, so the same offset
    /// lands somewhere else on a frame of another shape, and it is `@State`, so
    /// it dies with the photo it was made for. That is the same problem `zoom`
    /// has and D-79 already answered for: hold the intent, resolve it against
    /// each photograph. Fit puts it back in the middle, because at fit there is
    /// nowhere else to look.
    var lookingAt = CGPoint(x: 0.5, y: 0.5)

    /// Where the window is centered, read off a pan in points of the scaled
    /// photograph. `pan` and `look` are inverses, and they are here rather than
    /// in the view so the round trip can be asserted on: the view's `pan` is
    /// `@State`, which nothing can see from outside (D-273).
    static func look(fromPan pan: CGSize, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: 0.5 - pan.width / size.width, y: 0.5 - pan.height / size.height)
    }

    /// And the pan that puts the window back there, on a photograph of whatever
    /// shape this one turns out to be.
    static func pan(lookingAt look: CGPoint, in size: CGSize) -> CGSize {
        CGSize(width: (0.5 - look.x) * size.width, height: (0.5 - look.y) * size.height)
    }
    /// What the single view is showing of the photo, in normalized image
    /// coordinates. Whole frame at fit; the visible part once zoomed. The
    /// histogram reads it (D-76).
    var visibleRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Paint the edges the lens resolved, over the photo.
    var showFocusPeaking = false
    /// Faces in the current photo, found by Vision. Advisory, never written to
    /// a file (D-99).
    var faces: [Face] = []
    /// A normalized rect the single view should zoom to and center on. Cleared
    /// once it has been acted on, which is what makes it a request rather than
    /// a piece of state two things have to agree about.
    var focusRequest: CGRect?
    /// Which face `⇧Z` will go to next.
    var faceCursor = 0
    var cropping = false {
        didSet {
            modeBarCursor = nil
            guard cropping else { return }
            adjusting = false
            adjustments = .neutral
            adjustBaseline = .neutral
            // The ring goes with the bar it was on (D-244).
            barCursor = nil
        }
    }
    var cropRect: CGRect?
    /// The shape the box is held to, and whether that shape is stood on its
    /// side. Posture, like `adjusting` and unlike `cropRect`: the box belongs
    /// to the photograph and goes when the cursor moves, the shape belongs to
    /// the person and stays, because cropping a shoot to one format is the
    /// reason to set one (D-238).
    var cropRatio = CropRatio.free
    var cropRatioTurned = false
    /// The panel of sliders, beside the photograph. Crop and adjust are two
    /// modes over the same frame and each would draw over the other, so turning
    /// one on turns the other off — the pattern `sideBySide` and
    /// `showingCompare` already use.
    ///
    /// This is posture, not item state: it is where somebody is working, and it
    /// survives a cursor move. The numbers below do not (D-161).
    var adjusting = false { didSet { if adjusting { cropping = false; cropRect = nil } } }
    /// What the sliders are set to, for the photograph the cursor is on. Thrown
    /// away by `resetViewState` when the cursor moves, because a recipe belongs
    /// to a frame and carrying it to the next one would silently apply it to a
    /// photograph nobody set it for.
    var adjustments = Adjustments.neutral
    /// What the sliders were at when this photograph came up: the recipe an
    /// earlier overwrite left on it, or neutral (D-165). It is what "changed"
    /// is measured against, so opening a photograph that was adjusted last
    /// week does not offer to write the same edit over it again.
    var adjustBaseline = Adjustments.neutral
    /// Looking at the kept original with a decision to make about it: the
    /// preview a Revert goes through rather than the write it used to be
    /// (D-240). The third mode over the same frame, so it turns the other two
    /// off the way they turn each other off.
    ///
    /// Item state, not posture: it is a question about one photograph, and the
    /// answer to it is on the next line rather than on the next frame.
    var reverting = false {
        didSet {
            modeBarCursor = nil
            guard reverting else { return }
            cropping = false
            cropRect = nil
            adjusting = false
            adjustments = .neutral
            adjustBaseline = .neutral
            barCursor = nil
        }
    }
    /// Whether the photograph under the cursor has an original kept beside it,
    /// which is what makes Revert a thing on screen rather than an error
    /// message. Read from disk when the cursor moves, not on every draw.
    var adjustRevertable = false

    /// Picks up the record the photograph under the cursor carries. Called
    /// when the cursor moves and when the panel opens, which are the two
    /// moments the sliders are about to mean a different file.
    func loadAdjustRecord() {
        guard let url = current?.url else {
            adjustments = .neutral; adjustBaseline = .neutral; adjustRevertable = false
            return
        }
        let stored = AdjustRecord.editable(for: url) ?? .neutral
        adjustments = stored
        adjustBaseline = stored
        adjustRevertable = AdjustRecord.isRevertable(url)
    }
    var compareAnchor: URL?
    var showingCompare = false
    /// A and the cursor's photo beside each other, zoom and pan linked. The
    /// flip (`showingCompare`) and this are two answers to the same question,
    /// so turning one on turns the other off.
    var sideBySide = false { didSet { if sideBySide { showingCompare = false } } }
    /// Several photos at once, the way Lightroom's survey does it. The
    /// selection when there is one, otherwise a run around the cursor.
    var surveying = false
    /// The best frame so far, while a tournament is running. Every other frame
    /// is shown against it and either takes its place or does not (D-83).
    var tournament = false
    var champion: URL?
    /// Focus mode: the photographs, and nothing else in the window it was asked
    /// for. Which window, rather than whether: a `Bool` here was read by both
    /// scenes, so the gallery could not have its own bare mode without
    /// stripping the preview at the same time (D-150). What the panels were
    /// doing before it is kept, so leaving puts them back rather than leaving
    /// a window permanently stripped.
    var bareWindow: WindowFocus?
    @ObservationIgnored var preFocus: (info: Bool, filmstrip: Bool, sidebar: Bool)?

    func isBare(_ window: WindowFocus) -> Bool { bareWindow == window }
    /// Set when `z` went down and zoom was at fit; cleared on release. Drives hold-to-peek.
    var peekBegan: Date?

    /// Bottom-of-window confirmation for a change you can't see on screen.
    var toast: ToastState?

    /// A long file operation, while it runs. Nil the rest of the time, which is
    /// almost always: one photo is a frame's work.
    ///
    /// Read-only from outside. It is one slot, and it used to be written by six
    /// places, two of which checked whether anybody else had it: a rotate and a
    /// `⌘Z` overlapping left the rotate incrementing the undo's counter and the
    /// undo taking the rotate's banner down mid-run (D-189). `withProgress` is
    /// the only way to put something in it now, and `cancelProgress` the only
    /// way to write it from a control.
    private(set) var progress: ProgressState?
    /// Who holds the banner. A token rather than a Bool, so a run that has been
    /// superseded cannot take down the banner of the run that superseded it.
    @ObservationIgnored private var progressToken: UUID?

    /// What is running, for a refusal that names what to wait for.
    var runningLabel: String? { progress?.label }

    /// The stop button, and `Esc`. The run itself decides what a cancellation
    /// means — every loop keeps what it has already done.
    func cancelProgress() { progress?.cancelled = true }

    private func claimProgress(_ label: String, total: Int) -> UUID? {
        guard progress == nil else { return nil }
        let token = UUID()
        progressToken = token
        progress = ProgressState(label: label, done: 0, total: total)
        return token
    }

    /// For `ProgressRun` only: whether this token still holds the banner.
    func holdsProgress(_ token: UUID?) -> Bool { token != nil && progressToken == token }

    /// For `ProgressRun` only. The run has already checked that it owns this.
    func setProgressDone(_ done: Int) { progress?.done = done }

    /// For `ProgressRun` only, and for the safety net in `runWithProgress`.
    func releaseProgress(_ token: UUID) {
        guard progressToken == token else { return }
        progress = nil
        progressToken = nil
    }

    /// Starts `body` holding the progress banner, and takes the banner down
    /// whichever way the body leaves — returned, thrown or cancelled (D-189).
    ///
    /// The claim is synchronous and the work is not: the banner is up in the
    /// same turn as the keystroke that asked for it, which is what a reader
    /// pressing a key on four hundred photographs needs, and what a test can
    /// assert without waiting.
    ///
    /// Returns false *without starting the body* when something else holds the
    /// banner. These are file mutations over the same folder, so refusing is
    /// the point: reversing a rotation that is still being written is the
    /// collision this exists for.
    /// The batch in flight, or nil. There is at most one — a second is refused
    /// by the progress claim (D-189) — so this is a handle rather than a list.
    /// It exists to be waited on: a run's effect is what there is to assert
    /// about, and the call that starts one returns before any of it happened.
    @ObservationIgnored private(set) var running: Task<Void, Never>?

    /// Waits for the batch in flight, if there is one.
    func settle() async { await running?.value }

    @discardableResult
    func runWithProgress(_ label: String,
                         total: Int = 0,
                         // `Task.init` carries the same attribute, and this
                         // stands in for a `Task { @MainActor in … }` at every
                         // call site. Without it the five bodies this replaces
                         // would each grow a `self.` on every line, which is
                         // churn that says nothing about what changed.
                         @_implicitSelfCapture _ body: @escaping @MainActor (ProgressRun) async -> Void) -> Bool {
        guard let token = claimProgress(label, total: total) else { return false }
        running = Task { @MainActor in
            // The safety net, not the usual path: a run that wants to report
            // after the banner is down calls `end()` itself, and this covers
            // the one that returns or throws without doing so.
            defer { releaseProgress(token) }
            await body(ProgressRun(store: self, token: token))
        }
        return true
    }

    /// The explicit claim, for work whose body is too large to sit in a
    /// trailing closure: a `ProgressRun` that is `.silent` when the banner is
    /// not wanted, and `.silent` again when something else already holds it.
    ///
    /// `showing: false` is for a pass short enough that a banner would only
    /// flash. A silent run takes the same calls and does nothing with them, so
    /// a loop that sometimes reports is still one loop.
    ///
    /// The pairing is not enforced here the way `runWithProgress` enforces it,
    /// so the one caller ends it in a `defer`. It is a read rather than a
    /// mutation: the worst a missed `end` does is leave a banner up, not
    /// corrupt another run's counter, because `end` and `advance` are both
    /// ownership-checked (D-189).
    func beginProgress(_ label: String, total: Int = 0, showing: Bool = true) -> ProgressRun {
        guard showing, let token = claimProgress(label, total: total) else { return .silent }
        return ProgressRun(store: self, token: token)
    }

    /// Open when `⇧⌘G` is pressed: the path sheet.
    var goToPath = false
    /// Open when `⌘K` is pressed: the jump sheet.
    var jumping = false
    /// Which window asked for the command palette, or nil when it is closed.
    /// The gallery and the preview are separate scenes over one store, so a
    /// plain Bool would present the same sheet in both (D-67).
    var palette: WindowFocus?

    /// Photographs waiting on a yes before they go to the Trash, and the window
    /// that asked for it (D-193). Nil the rest of the time, which is almost
    /// always: a trash with no favorite in it is a plain action with an undo.
    var trashConfirm: TrashConfirm?
    /// Open when `⇧X` is pressed: the rejects, before they go.
    var reviewingRejects = false
    /// Open when `⌘⇧I` is pressed, or when a card is offered: copy off a card
    /// with a rename, the way Photo Mechanic's ingest does (D-89).
    var ingesting: URL?
    /// Full screen, one photo, advancing on a timer (D-90).
    var slideshow = false
    /// Seconds a slide holds. Fixed rather than a preference: the only two
    /// useful values are "long enough to look" and "press the arrow yourself".
    let slideSeconds: Double = 4
    var renameTarget: PhotoRef?
    var batchRenameTargets: [PhotoRef]?

    /// True while something on screen has a claim on the keyboard that the
    /// app's own commands do not.
    ///
    /// The key monitor has stood aside for these since D-7, so `⌘C` typed into
    /// a rename field reaches the field editor. The menu bar did not, and a
    /// menu shortcut fires before the responder chain: selecting a filename and
    /// pressing `⌘C` copied the *photograph*, `⌘A` selected every photo in the
    /// folder, and `⌘Z` took back a file operation instead of the typing. The
    /// list lived in the monitor, so the menu had nothing to ask. Now both ask
    /// this (D-281).
    var sheetHasTheKeyboard: Bool {
        renameTarget != nil || batchRenameTargets != nil || showTrashPanel || trashConfirm != nil
    }

    /// Bumped by the router after any command performed while the preview has
    /// the keyboard. The preview bar watches it and shows itself, so someone
    /// who never touches the trackpad still learns the controls are there.
    var barPulse = 0

    /// Which control in the preview bar the keyboard is on, named by the
    /// command it runs rather than by its place in the row (D-157). A row
    /// changes shape as features are switched and as the window narrows, and
    /// an index into a list that reshapes points at the wrong control the
    /// moment it does.
    var barCursor: Command?
    /// The same thing for the bar a mode puts in the preview bar's place: the
    /// crop bar's ratios and saves, or the revert bar's two answers. Named by
    /// the stop rather than by a command, because not every stop is one
    /// (D-245).
    var modeBarCursor: ModeBarStop?

    /// The stops the bar that is up is actually drawing, which is what Tab
    /// walks and what Return presses. One list: the views build their controls
    /// from this same call (D-157).
    var modeBarStops: [ModeBarStop] {
        if cropping {
            let box = cropRect.map { $0.width > 0.01 && $0.height > 0.01 } ?? false
            return ModeBarStop.cropBar(ratio: cropRatio, hasBox: box, revertable: adjustRevertable)
        }
        if reverting { return ModeBarStop.revertBar }
        return []
    }
    /// The rung the bar actually drew, reported by the row that fitted, so the
    /// keyboard walks what is on screen rather than what a wider window would
    /// have shown.
    var barRung: Set<BarPiece> = []

    /// A sentence shown once in the life of the app, the first time the thing
    /// it is about happens (D-66).
    var hint: HintState?

    /// Shows a hint if it has never been shown before. Cheap to call from
    /// anywhere: the second call for an id does nothing.
    func hintOnce(_ id: String, _ text: String) {
        guard Preferences.claimHint(id) else { return }
        hint = HintState(id: id, text: text)
    }

    let undo = UndoStack()

    /// Pushes an undo, tagged with the folder and the photograph it was about.
    ///
    /// Pushing is also what re-arms the way back after an operation moved the
    /// cursor itself — a trash takes a photograph out from under it — because
    /// the push happens once the shuffling is done (D-283).
    func pushUndo(_ op: UndoableOp) {
        undo.push(op, in: folder, at: current?.url)
        undoLeftBehind = false
    }

    /// True once somebody has moved the cursor themselves since the last
    /// undoable thing they did.
    ///
    /// The way back goes off screen when it does, because a pill in the corner
    /// of a window showing one photograph is read as being about that
    /// photograph. `⌘Z` and Edit > Undo still reach it. Set by the cursor
    /// itself and cleared by `pushUndo`, so an operation that reshuffles the
    /// cursor does not count as navigating; `advanceIfEnabled` clears it again
    /// for the same reason, since stepping on after a decision is the decision
    /// moving you, not you moving (D-283).
    var undoLeftBehind = false

    /// The folder the last undoable operation happened in, when that is not the
    /// folder on screen. Nil the rest of the time, which is most of the time.
    var undoElsewhere: URL? {
        guard let top = undo.topFolder, let folder else { return nil }
        return top.standardizedFileURL == folder.standardizedFileURL ? nil : top
    }

    /// Reports something that is not on screen. An undoable operation raises no
    /// message at all: the way back is the message, and it says what happened
    /// by naming what it will take back (D-283).
    ///
    /// `undoable` therefore now means "the undo pill has this covered" rather
    /// than "put an Undo button on the toast". The call sites read the same and
    /// the rule lives here, in one place, instead of in twenty-five of them.
    func showToast(_ message: String, undoable: Bool = true, offer: FolderOffer? = nil,
                   endsOnMove: Bool = false) {
        guard !undoable || offer != nil else { return }
        toast = ToastState(message: message, offer: offer, endsOnMove: endsOnMove)
    }

    /// Every failure in the app comes through here. It sets `lastError` so a
    /// test can read what went wrong, and shows it where every other outcome is
    /// shown, rather than in a modal alert over the photo (D-48).
    func showError(_ message: String) {
        lastError = message
        toast = ToastState(message: message, isError: true)
        // The one outcome that has to reach somebody who cannot see the toast:
        // a command that refuses and says so only in pixels is a command that
        // did nothing, from the outside (A-11).
        Announcer.say(message, .interrupting)
    }

    /// The words on the corner undo control, or nil when it is not on offer.
    ///
    /// Here rather than in `StatusOverlay` because two things need them and
    /// they must not drift: the control draws them, and the overlay announces
    /// them when they arrive, which is the only thing that tells a reader the
    /// way back is there (A-11). It also makes the rule testable, which it was
    /// not while it lived in a view the suite cannot build (D-381's argument,
    /// one file across).
    ///
    /// Three shapes, in the order they are asked. The folder, when the last
    /// thing you did was in the one before this (D-93). The filename, when a
    /// decision stepped you on and the way back is about the frame behind you.
    /// And the bare action the rest of the time, which is most of the time
    /// (D-283).
    var undoOffer: String? {
        guard toast == nil, progress == nil, undo.canUndo, let label = undo.topLabel,
              !undoLeftBehind || undoElsewhere != nil
        else { return nil }
        if let elsewhere = undoElsewhere {
            return "Undo \(label.lowercased()) in \(elsewhere.lastPathComponent)"
        }
        if let at = undo.topAt, at != current?.url {
            return "Undo \(label.lowercased()) \(at.lastPathComponent)"
        }
        return "Undo \(label.lowercased())"
    }
    @ObservationIgnored private let watcher = FolderWatcher()
    /// What this folder's one pass has already read, and what it is reading
    /// now. `factsPass` is which pass owns the banner: a folder opened while a
    /// read is in flight starts its own, and the old one must not clear it.
    /// Internal rather than private so a test can ask what the folder knows
    /// and what it is in the middle of finding out.
    @ObservationIgnored var factsLoaded: FolderFacts = []
    @ObservationIgnored var factsRunning: FolderFacts = []
    @ObservationIgnored private var factsPass = 0

    var current: PhotoRef? {
        guard let cursor, photos.indices.contains(cursor) else { return nil }
        return photos[cursor]
    }

    /// Set while a control that names its own photo is acting — a cell's keep
    /// button, a context menu, the preview bar — so the batch runs on that
    /// photo instead of the cursor's (D-47). Only `aiming(at:)` sets it: an aim
    /// taken without the thing that puts it back is the bug this is private for
    /// (D-104).
    private(set) var actionScope: [PhotoRef]?

    /// Runs `body` with every command aimed at `refs`, and puts the aim back
    /// however `body` leaves — returning early, throwing, or reaching the end.
    /// Restores what was there rather than clearing, so a command that aims at
    /// one photo from inside another's scope gives the outer one back instead
    /// of leaving the rest of it aimed at the cursor.
    @discardableResult
    func aiming<T>(at refs: [PhotoRef], _ body: () throws -> T) rethrows -> T {
        let outer = actionScope
        actionScope = refs
        defer { actionScope = outer }
        return try body()
    }

    /// Batch commands act on the scope if a control set one, else the selection,
    /// else the cursor.
    var targets: [PhotoRef] {
        if let actionScope { return actionScope }
        if selected.isEmpty { return current.map { [$0] } ?? [] }
        return photos.filter { selected.contains($0.url) }
    }

    /// What a control drawn on one photo acts on. A photo that is part of the
    /// selection carries the whole selection with it, the way a drop does; any
    /// other photo goes alone.
    func targets(for ref: PhotoRef) -> [PhotoRef] {
        guard selected.contains(ref.url) else { return [ref] }
        return photos.filter { selected.contains($0.url) }
    }

    /// What the action bar is about to act on, in words, so no keystroke and no
    /// button is ever aimed at something the header has not named.
    /// What the action bar says it is about to act on. A count when there is a
    /// selection, and nothing at all for a single photo: the cell under the
    /// cursor carries its own name now, and naming it a second time at the far
    /// end of the header was two answers to one question (D-115).
    ///
    /// It says the whole sentence, because it is now the only place the count
    /// appears: the status slot beside it said "4 selected of 8" while this
    /// said "4 selected", which is one fact given twice in one row (D-202).
    var targetLabel: String? {
        selected.isEmpty ? nil : "\(selected.count) of \(photos.count) selected"
    }

    var compareRef: PhotoRef? {
        compareAnchor.flatMap { a in allPhotos.first { $0.url == a } }
    }

    var championRef: PhotoRef? {
        champion.flatMap { c in allPhotos.first { $0.url == c } }
    }

    /// What the survey shows: the selection when there is one, otherwise the
    /// run the cursor is in the middle of. Capped, because seven frames on one
    /// screen is seven thumbnails and the point is to see them.
    var surveyRefs: [PhotoRef] {
        if selected.count > 1 { return photos.filter { selected.contains($0.url) }.prefix(Self.surveyMax).map { $0 } }
        guard let c = cursor, !photos.isEmpty else { return [] }
        let half = Self.surveyMax / 2
        let start = max(0, min(c - half, photos.count - Self.surveyMax))
        let end = min(photos.count, start + Self.surveyMax)
        return Array(photos[max(0, start)..<end])
    }

    /// Six is where a survey stops being a comparison and becomes a grid.
    static let surveyMax = 6

    /// Everything flagged reject in the whole folder, not only what a filter
    /// happens to be showing. The review is about the folder's rejects, and a
    /// filter left on from earlier must not hide half of them.
    var rejected: [PhotoRef] { allPhotos.filter { $0.flag == .reject } }

    // MARK: opening

    func open(_ rawURL: URL, focusing rawFile: URL? = nil, asked: Bool = true) {
        let url = FolderScanner.canonical(rawURL)
        let file = rawFile.map(FolderScanner.canonical)
        // The door first, because the scan below is the thing the sandbox
        // refuses and a refusal here is a state rather than a failure
        // (D-324). Ending the last scope before starting the next one is
        // what keeps "open" from meaning "and everything before it stays
        // open too".
        scope?.end()
        guard let opened = FolderAccess.reach(url) else {
            scope = nil
            refused = asked ? url : nil
            clearFolder()
            return
        }
        scope = opened
        refused = nil
        do {
            let scanned = try FolderScanner.scan(url, recursive: includeSubfolders)
            folder = url
            allPhotos = scanned
            subfolders = FolderScanner.subfolders(of: url)
            factsLoaded = []
            factsRunning = []
            filter = .all
            selected = []
            expandedStacks = []
            compareAnchor = nil
            surveying = false
            slideshow = false
            tournament = false
            champion = nil
            resetZoom()
            showFocusPeaking = false
            sideBySide = false
            leaveFocusMode()
            reviewingRejects = false
            rebuild()
            previewOpen = false
            session = SessionStats()
            trashLog = []
            searchText = ""
            searching = false
            folderCursor = nil
            // Nowhere, until something says otherwise. The two things that say
            // otherwise are right below: a file double-clicked in Finder, and
            // a folder you have been in before (D-141).
            cursor = nil
            if let file, let i = photos.firstIndex(where: { FolderScanner.canonical($0.url) == file }) {
                cursor = i
                previewOpen = true
            } else {
                if let resume = Preferences.resumeFile(for: url),
                   let i = photos.firstIndex(where: { FolderScanner.canonical($0.url) == FolderScanner.canonical(resume) }) {
                    cursor = i
                }
            }
            // The undo stack is not cleared (D-93). Walking into the next
            // shoot used to throw away the way back out of the last thing you
            // did, which is the one thing a no-dialog delete cannot afford.
            lastError = nil
            Preferences.lastFolder = url
            Preferences.noteRecent(url)
            // With subfolders on, the shoots inside are part of what is shown,
            // so they are part of what is watched (D-38).
            watcher.watch(url, depth: includeSubfolders ? 1 : 0) { [weak self] in self?.reload() }
            loadFolderFactsIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-asks the sandbox whether the open folder is still allowed (D-324).
    ///
    /// Called when a grant is taken away, not on a timer: the answer only
    /// changes when somebody changes it, and polling a permission is how a
    /// gallery ends up flickering between two truths.
    ///
    /// The scope ends first. A started scope outlives its bookmark, so
    /// checking `isReachable` while still holding one would report the folder
    /// readable, which it is, and would be reporting on the door this call
    /// exists to close.
    func recheckAccess() {
        guard let open = folder else { return }
        guard !FolderAccess.isReachable(open) else { return }
        scope?.end()
        scope = nil
        // No refusal screen. The reader revoked this folder a moment ago, on
        // purpose, and answering that with a wall whose button offers to hand
        // it straight back is the app arguing with the decision it was just
        // given. Revoking everything and being shown the empty state is the
        // app agreeing: there is nothing open, because you asked for nothing
        // to be open (D-324).
        refused = nil
        clearFolder()
        selected = []
        cursor = nil
        previewOpen = false
    }

    /// Back to no folder at all, without deciding which screen says so.
    private func clearFolder() {
        folder = nil
        allPhotos = []
        subfolders = []
        rebuild()
    }

    func reload() {
        guard let folder else { return }
        let keepURL = current?.url
        let keepIndex = cursor
        let dates = Dictionary(allPhotos.compactMap { p in p.dateTaken.map { (p.url, $0) } }, uniquingKeysWith: { a, _ in a })
        var scanned = (try? FolderScanner.scan(folder, recursive: includeSubfolders)) ?? []
        for i in scanned.indices { scanned[i].dateTaken = dates[scanned[i].url] }
        allPhotos = scanned
        subfolders = FolderScanner.subfolders(of: folder)
        selected = selected.filter { u in allPhotos.contains { $0.url == u } }
        rebuild()
        if let keepURL, let i = photos.firstIndex(where: { $0.url == keepURL }) {
            cursor = i
        } else if let keepIndex {
            cursor = photos.isEmpty ? nil : min(keepIndex, photos.count - 1)
        } else {
            // No cursor before the reload, none after it. A rescan is not
            // somebody putting the keyboard somewhere (D-141).
            cursor = nil
        }
        if photos.isEmpty { previewOpen = false }
        // What the cursor's photograph carries, read again, and after the
        // cursor has been put back rather than before it: a reload happens
        // because something rewrote a file under the app, and it lands the
        // cursor on the same index, so `cursor.didSet` — the only other thing
        // that reads this — does not fire. Undoing a revert left the crop on
        // screen with the bar still saying there was nothing to revert to,
        // because the files came home and the flag did not (D-286).
        loadAdjustRecord()
    }

    private func rebuild() {
        let query = PhotoQuery(searchText.trimmingCharacters(in: .whitespaces))
        let kept = allPhotos.filter { p in
            filter.includes(p) && (query.isEmpty || query.matches(p))
        }
        // With subfolders on, the photos group by the folder they came from and
        // sort inside it, so a recursive view is a stack of folders rather than
        // one long run of everything (D-36). The cursor is an index into this
        // array, so the grouping has to happen here, not in the view.
        if includeSubfolders {
            let groups = Dictionary(grouping: kept) { $0.url.deletingLastPathComponent().path }
            photos = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .flatMap { sort.sort(groups[$0] ?? [], sortDirection) }
        } else {
            photos = sort.sort(kept, sortDirection)
        }
        if stackBursts { collapseBursts() } else { stackCounts = [:] }
        // The same query the photos went through. A folder is found by its
        // name the way a photograph is, and on a folder of folders the filter
        // is the only way through a list the cap has cut (D-318).
        let narrowed = query.isEmpty
            ? subfolders
            : subfolders.filter { query.matchesFolder(named: $0.lastPathComponent) }
        shownSubfolders = Array(narrowed.prefix(Self.folderTileMax))
        subfoldersLeftOut = narrowed.count - shownSubfolders.count
        if let f = folderCursor, !folderRow.indices.contains(f) {
            folderCursor = folderRow.isEmpty ? nil : 0
        }
        clampCursor()
    }

    /// Lightroom collapses a continuous burst into one cell (D-84). A run is
    /// frames taken within `burstGap` of each other, and the leader stands for
    /// the rest until somebody opens it.
    private func collapseBursts() {
        var out: [PhotoRef] = []
        var counts: [URL: Int] = [:]
        var i = 0
        while i < photos.count {
            var j = i + 1
            while j < photos.count, sameBurst(photos[j - 1], photos[j]) { j += 1 }
            let run = photos[i..<j]
            if run.count > 1 {
                counts[photos[i].url] = run.count
                if expandedStacks.contains(photos[i].url) { out.append(contentsOf: run) }
                else { out.append(photos[i]) }
            } else {
                out.append(photos[i])
            }
            i = j
        }
        photos = out
        stackCounts = counts
    }

    private func sameBurst(_ a: PhotoRef, _ b: PhotoRef) -> Bool {
        let ta = a.dateTaken ?? a.created, tb = b.dateTaken ?? b.created
        return abs(tb.timeIntervalSince(ta)) <= Self.burstGap
    }

    func toggleStack(_ url: URL) {
        if expandedStacks.contains(url) { expandedStacks.remove(url) } else { expandedStacks.insert(url) }
        let keep = current?.url
        rebuild()
        if let keep, let i = photos.firstIndex(where: { $0.url == keep }) { cursor = i }
    }

    /// Where each run of photos starts, for the headers over them: a folder
    /// when subfolders are included, a scene when the shoot pauses. Empty when
    /// there is only one run, because one heading over everything says nothing.
    var sections: [GridSection] {
        guard !photos.isEmpty else { return [] }
        if includeSubfolders { return folderSections() }
        if groupByScene { return sceneSections() }
        return []
    }

    private func folderSections() -> [GridSection] {
        var out: [(folder: URL, start: Int, count: Int)] = []
        for (i, photo) in photos.enumerated() {
            let folder = photo.url.deletingLastPathComponent()
            if var last = out.last, last.folder == folder {
                last.count += 1
                out[out.count - 1] = last
            } else {
                out.append((folder: folder, start: i, count: 1))
            }
        }
        guard out.count > 1 else { return [] }
        return out.map { GridSection(title: $0.folder.lastPathComponent, start: $0.start, count: $0.count, folder: $0.folder) }
    }

    /// Narrative groups by scene; this is the cheap version of the same idea.
    /// The grid breaks wherever the camera was put down for longer than
    /// `sceneGap`, and the heading is the time the next run started.
    private func sceneSections() -> [GridSection] {
        var out: [(start: Int, count: Int, at: Date)] = []
        for (i, photo) in photos.enumerated() {
            let t = photo.dateTaken ?? photo.created
            if let last = out.last, i > 0 {
                let prev = photos[i - 1].dateTaken ?? photos[i - 1].created
                if abs(t.timeIntervalSince(prev)) <= Self.sceneGap {
                    out[out.count - 1] = (last.start, last.count + 1, last.at)
                    continue
                }
            }
            out.append((start: i, count: 1, at: t))
        }
        guard out.count > 1 else { return [] }
        return out.map {
            GridSection(title: $0.at.formatted(date: .abbreviated, time: .shortened),
                        start: $0.start, count: $0.count, folder: nil)
        }
    }

    /// Frames this far apart or closer are one burst; a pause longer than
    /// `sceneGap` is a new scene. Two seconds is a camera held down; a minute
    /// is a camera put down.
    private static let burstGap: TimeInterval = 2
    private static let sceneGap: TimeInterval = 60

    /// Keep / reject / unflagged / favorite across the whole folder, not just
    /// what's shown. The favorite is counted here rather than beside it so the
    /// header's heart can say whether there is anything to narrow to without a
    /// second pass over the folder (D-176).
    var folderCounts: (keep: Int, reject: Int, unflagged: Int, favorite: Int) {
        var k = 0, r = 0, u = 0, f = 0
        for p in allPhotos {
            switch p.flag { case .keep: k += 1; case .reject: r += 1; case nil: u += 1 }
            if p.favorite { f += 1 }
        }
        return (k, r, u, f)
    }

    var isAtLastPhoto: Bool { cursor.map { $0 == photos.count - 1 } ?? false }

    /// One pass over the folder, for whatever it is currently being asked to
    /// know (D-101). A file is read at most twice: once for its header, which
    /// answers dates and camera facts together, and once for the thumbnail the
    /// sharpness score needs. One banner, one Esc, one flag per fact.
    private func loadFolderFactsIfNeeded() {
        guard let folder, factsRunning.isEmpty else { return }
        let needed = wantedFacts.subtracting(factsLoaded)
        guard !needed.isEmpty else { return }

        // The header read is the same call either way, so a pass asked only for
        // dates answers `camera:` too, and a later search over this folder has
        // nothing left to read.
        let header = !needed.isDisjoint(with: [.dates, .camera])
        let sharpness = needed.contains(.sharpness)
        let work = allPhotos.compactMap { ref -> FactWork? in
            let wantsHeader = header && ref.camera == nil
            let wantsSharpness = sharpness && ref.sharpness == nil
            guard wantsHeader || wantsSharpness else { return nil }
            return FactWork(url: ref.url, contentID: ref.contentID,
                            header: wantsHeader, sharpness: wantsSharpness)
        }
        var covered: FolderFacts = []
        if header { covered.formUnion([.dates, .camera]) }
        if sharpness { covered.insert(.sharpness) }
        guard !work.isEmpty else { factsLoaded.formUnion(covered); return }

        factsRunning = covered
        factsPass += 1
        let pass = factsPass
        // Sharpness is a decode and a convolution per file, so it reports from
        // the first one; a header read short enough to finish inside a frame or
        // two would only flash a banner.
        let chunkSize = sharpness ? Self.sharpnessChunk : Self.dateChunk

        // A read, not a mutation, so it runs whether or not it can have the
        // banner: a folder opened while a rotate is running still needs its
        // dates, and a run that cannot claim is simply silent (D-189).
        // Sharpness is a decode and a convolution per file, so it reports from
        // the first one; a header read short enough to finish inside a frame
        // or two would only flash a banner.
        let run = beginProgress(Self.factsLabel(needed), total: work.count,
                                showing: sharpness || work.count > Self.progressFloor)
        Task { @MainActor in
            defer { run.end() }
            var facts: [URL: (ExifInfo?, Double?)] = [:]
            var i = 0
            var stopped = false
            while i < work.count {
                if run.cancelled { stopped = true; break }
                let chunk = Array(work[i..<min(i + chunkSize, work.count)])
                let read = await Task.detached(priority: .userInitiated) { () -> [(URL, ExifInfo?, Double?)] in
                    var out: [(URL, ExifInfo?, Double?)] = []
                    for item in chunk {
                        let info = item.header ? EXIFReader.read(item.url) : nil
                        var score: Double?
                        if item.sharpness {
                            var img = ImageCache.thumbnails[item.contentID]
                            if img == nil { img = await ImageLoader.shared.decode(item.url, maxPixels: Tokens.Layout.thumbnailPixels) }
                            score = img.flatMap { PixelStats.sharpness(of: $0.cgImage) }
                        }
                        out.append((item.url, info, score))
                    }
                    return out
                }.value
                for (url, info, score) in read { facts[url] = (info, score) }
                i += chunk.count
                // Only the pass that put the banner up may move it, and the
                // run checks that for itself now — a folder opened mid-read
                // starts its own, and its handle owns nothing.
                if factsPass == pass { run.advance(to: i) }
            }
            // A cancelled pass keeps what it read and leaves the fact unloaded,
            // so asking again starts it over rather than showing half a folder
            // as having no date.
            if factsPass == pass {
                factsRunning = []
                if !stopped { factsLoaded.formUnion(covered) }
            }
            guard self.folder == folder else { return }
            let keep = current?.url
            for j in allPhotos.indices {
                guard let (info, score) = facts[allPhotos[j].url] else { continue }
                if let score { allPhotos[j].sharpness = score }
                guard let info else { continue }
                // An empty string is "read, and it does not say", which is what
                // keeps the next pass from reading this header again.
                allPhotos[j].camera = info.camera ?? ""
                allPhotos[j].lens = info.lens
                allPhotos[j].iso = info.iso
                if let d = info.dateTaken { allPhotos[j].dateTaken = d }
            }
            rebuild()
            if let keep { cursor = photos.firstIndex { $0.url == keep } }
            // Anything asked for while this pass was running goes now, in a
            // pass of its own rather than a second banner beside it.
            if factsPass == pass, !stopped { loadFolderFactsIfNeeded() }
        }
    }

    /// What the folder has to know right now, from the sort, the two grouping
    /// modes and the search field.
    private var wantedFacts: FolderFacts {
        var want: FolderFacts = []
        if sort == .dateTaken || stackBursts || groupByScene { want.insert(.dates) }
        if sort == .sharpness { want.insert(.sharpness) }
        if !PhotoQuery(searchText.trimmingCharacters(in: .whitespaces)).isNameOnly { want.insert(.camera) }
        return want
    }

    /// The banner says what the pass is for. A pass doing both has no honest
    /// short name for it, so it names the folder instead.
    static func factsLabel(_ facts: FolderFacts) -> String {
        if facts == .dates { return "Reading dates" }
        if facts == .sharpness { return "Measuring sharpness" }
        if facts.isDisjoint(with: .sharpness) { return "Reading camera details" }
        return "Reading the folder"
    }

    /// Files per hop off the main actor while reading dates, and the number of
    /// files below which the read is not worth reporting.
    private static let dateChunk = 64
    private static let progressFloor = 200
    /// Smaller than the date chunk: each of these is a decode and a convolution
    /// rather than a header read, and a smaller hop keeps the bar moving.
    private static let sharpnessChunk = 16

    // MARK: cursor and selection

    /// Steps sideways in the folder row, and off its ends into nothing.
    func moveInFolderRow(by delta: Int) {
        guard let f = folderCursor, !folderRow.isEmpty else { return }
        folderCursor = min(max(f + delta, 0), folderRow.count - 1)
    }

    /// Up out of the first row of photos lands in the folder row, under the
    /// column you left, so the cursor keeps its place on screen.
    func enterFolderRow(fromColumn column: Int) -> Bool {
        guard !folderRow.isEmpty else { return false }
        folderCursor = min(max(column, 0), folderRow.count - 1)
        return true
    }

    /// Down out of the folder row lands on the photo under it.
    func leaveFolderRow() {
        guard let f = folderCursor else { return }
        folderCursor = nil
        guard !photos.isEmpty else { return }
        cursor = min(f, photos.count - 1)
    }

    var currentFolderEntry: FolderEntry? {
        guard let f = folderCursor, folderRow.indices.contains(f) else { return nil }
        return folderRow[f]
    }

    func move(by delta: Int, extendingSelection: Bool = false) {
        guard !photos.isEmpty else { return }
        // From nowhere, the first key lands rather than steps: it says where
        // the cursor is about to be, and the next one moves from there. Any
        // direction, because "back one from nothing" has no answer that is
        // not a guess (D-141).
        guard let cursor else {
            self.cursor = 0
            if extendingSelection { selectionAnchor = 0 }
            return
        }
        let target = min(max(cursor + delta, 0), photos.count - 1)
        if extendingSelection {
            let anchor = selectionAnchor ?? cursor
            selectionAnchor = anchor
            let range = min(anchor, target)...max(anchor, target)
            selected = Set(photos[range].map(\.url))
        }
        self.cursor = target
    }

    func moveToFirst() { if !photos.isEmpty { cursor = 0 } }
    func moveToLast() { if !photos.isEmpty { cursor = photos.count - 1 } }

    /// After a decision, step on. A decision made through a control on some
    /// other photo leaves the cursor alone: clicking keep on a cell across the
    /// grid is about that cell, not about where you are.
    /// Lightroom's trick: with Caps Lock down the flag keys move you on, and
    /// with it up they hold. A mode you can see on your own keyboard, unlike a
    /// toggle you can forget (D-97).
    /// Injectable for the same reason the pasteboard is (D-54): otherwise a
    /// test's result depends on whether the person running it happens to have
    /// Caps Lock down.
    @ObservationIgnored
    nonisolated(unsafe) static var capsLockIsDown: () -> Bool = { NSEvent.modifierFlags.contains(.capsLock) }

    var capsLockAdvances: Bool { Self.capsLockIsDown() }

    func advanceIfEnabled() {
        guard autoAdvance || capsLockAdvances, let cursor, cursor < photos.count - 1 else { return }
        if let actionScope, let current, !actionScope.contains(where: { $0.url == current.url }) { return }
        self.cursor = cursor + 1
        // The decision moved you, so the way back from it stays up. It names
        // the photograph instead, because it is no longer the one on screen
        // (D-283).
        undoLeftBehind = false
    }

    /// A plain click: this photograph and nothing else.
    ///
    /// The grid used to move only the cursor here, so clicking one cell inside
    /// a run of selected ones left the run chosen: the blue stayed on every
    /// cell, and the next command acted on all of them rather than on the one
    /// that had just been clicked (D-377). Finder's first rule, and the
    /// selection the shift and command clicks beside it build on.
    func selectOnly(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        cursor = index
        selected = [photos[index].url]
        selectionAnchor = index
    }

    func toggleSelectCurrent() {
        guard let current else { return }
        if selected.contains(current.url) { selected.remove(current.url) } else { selected.insert(current.url) }
        selectionAnchor = cursor
    }

    func selectAll() { selected = Set(photos.map(\.url)) }
    func clearSelection() { selected = []; selectionAnchor = nil }

    /// A click on the canvas: nothing chosen, and the keyboard nowhere. The
    /// tile and the pill are two marks for two facts (D-119), and clicking
    /// past every photograph is the one gesture that means neither — clearing
    /// only the pill left the first photo wearing a tile on a screen where
    /// nothing had been touched (D-141).
    func clearCursorAndSelection() {
        clearSelection()
        cursor = nil
        folderCursor = nil
    }

    // MARK: mutation

    /// Patches one photo in place (flag, favorite, rename) without rescanning.
    func update(_ url: URL, _ change: (inout PhotoRef) -> Void) {
        if let i = allPhotos.firstIndex(where: { $0.url == url }) { change(&allPhotos[i]) }
        let keep = current?.url
        rebuild()
        if let keep, let i = photos.firstIndex(where: { $0.url == keep }) { cursor = i }
    }

    /// Drops photos by URL. The cursor stays put so the next photo slides in (auto-advance).
    func remove(_ urls: Set<URL>) {
        let keepIndex = cursor
        allPhotos.removeAll { urls.contains($0.url) }
        selected.subtract(urls)
        rebuild()
        // A selection trashed with the keyboard nowhere leaves it nowhere.
        // `?? 0` here used to plant a cursor on the first photo as a side
        // effect of deleting something else (D-141).
        cursor = photos.isEmpty ? nil : keepIndex.map { min($0, photos.count - 1) }
        if let compareAnchor, urls.contains(compareAnchor) {
            self.compareAnchor = nil
            showingCompare = false
            sideBySide = false
        }
        if photos.isEmpty { previewOpen = false }
    }

    /// Reinserts a photo (after an undo) and puts the cursor on it.
    func insert(_ ref: PhotoRef) {
        allPhotos.append(ref)
        rebuild()
        cursor = photos.firstIndex(of: ref)
    }

    /// What a cursor move throws away, and what it keeps. The zoom stays:
    /// holding 100% while arrowing through a burst is how you find the frame
    /// that is actually in focus, and it is the one thing every other culler
    /// does that Sift did not (D-79).
    private func resetViewState() {
        faces = []
        faceCursor = 0
        facesKey = nil
        focusRequest = nil
        cropping = false
        cropRect = nil
        reverting = false
        // The panel stays; what it was set to does not (D-161). What the new
        // photograph itself carries takes its place (D-165).
        loadAdjustRecord()
        showingCompare = false
    }

    /// Which photograph the faces on hand belong to, so a second ask about the
    /// same frame does not run Vision again.
    @ObservationIgnored private var facesKey: String?

    /// True while a pass is running, so the thing that asked can say so.
    var findingFaces = false

    /// Finds the faces in `ref`, unless they are the ones already on hand.
    ///
    /// The store owns this because two callers want it and they must not
    /// disagree: the info panel finds faces while it is open, and `⇧Z` asks
    /// for them whether or not it ever has been. Detection used to live inside
    /// the panel's `task`, so the face key said "No faces in this one" about a
    /// photograph full of them, which is a control lying rather than failing
    /// (D-151).
    ///
    /// The full frame is preferred over the thumbnail when the cache has one,
    /// which in the preview window it usually does: a face small in the frame
    /// is a handful of pixels at 320 and a findable face at full size.
    func loadFaces(for ref: PhotoRef) async {
        let key = ref.contentID
        guard facesKey != key else { return }
        findingFaces = true
        defer { findingFaces = false }
        let url = ref.url
        let cached = ImageCache.fulls[key]
            ?? ImageCache.thumbnails["\(key)|\(Tokens.Layout.thumbnailPixels)"]
            ?? ImageCache.thumbnails[key]
        let decoded: DecodedImage? = if let cached { cached }
            else { await ImageLoader.shared.decode(url, maxPixels: Tokens.Layout.thumbnailPixels) }
        guard let decoded else { return }
        let found = await Task.detached { FaceReader.faces(in: decoded.cgImage) }.value
        // The cursor may have moved while Vision was running, and answering
        // about the photograph that was on screen when the key went down is
        // worse than answering about none.
        guard current?.contentID == key else { return }
        faces = found
        faceCursor = 0
        facesKey = key
    }

    /// `⇧Z`: around the faces one at a time, then back to the whole frame.
    /// The keyboard's half of clicking a close-up.
    func zoomToNextFace() {
        guard !faces.isEmpty else { return }
        if faceCursor >= faces.count {
            faceCursor = 0
            resetZoom()
            return
        }
        focusRequest = faces[faceCursor].framed
        faceCursor += 1
    }

    /// Fit and 1:1 as one act, so the double-click, the readout in the corner
    /// and `z` cannot drift apart (D-154). `scale` is what 1:1 means for
    /// whatever is on screen: the single frame has its own, and a pair is
    /// drawn smaller, so the number that fills one is not the number that
    /// fills the other.
    func toggleActualSize(oneToOne scale: CGFloat? = nil) {
        if zoom == nil {
            zoom = scale ?? oneToOneScale
            zoomIsActual = true
        } else {
            resetZoom()
        }
    }

    /// Back to fit, and back to the whole frame. What Esc and the fit control
    /// mean, as opposed to what an arrow key means.
    func resetZoom() {
        zoom = nil
        zoomIsActual = false
        visibleRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Focus mode is a borrowed window, not a preference: leaving it puts the
    /// filmstrip and the info panel back the way they were found.
    /// Leaves any mode or overlay whose feature has just been switched off.
    /// Called by `AppModel` when the set changes, and only then: this is not
    /// a thing to check on every render (D-123).
    func standDown(_ features: FeatureSet) {
        if !features.isOn(.compare) {
            compareAnchor = nil
            showingCompare = false
            sideBySide = false
        }
        if !features.isOn(.survey) { surveying = false }
        if !features.isOn(.bare), bareWindow != nil { leaveFocusMode() }
        // Abandoned rather than finished: `endTournament` keeps the champion,
        // and a feature being switched off is not the reader saying this
        // frame won.
        if !features.isOn(.tournament) { tournament = false; champion = nil }
        if !features.isOn(.highlights) { showClipping = false }
        if !features.isOn(.focusPeaking) { showFocusPeaking = false }
        if !features.isOn(.faces) { faces = [] }
        if !features.isOn(.crop) { cropping = false; cropRect = nil }
        if !features.isOn(.adjust) { adjusting = false; adjustments = .neutral; adjustBaseline = .neutral }
        if !features.isOn(.slideshow) { slideshow = false }
    }

    /// Only the named window's chrome goes away. The preview's panels and the
    /// gallery's sidebar are different furniture, and taking both would mean
    /// `⇧F` in one window rearranging the other one behind it (D-150).
    func enterFocusMode(in window: WindowFocus) {
        guard bareWindow == nil else { return }
        preFocus = (info: showInfo, filmstrip: showFilmstrip, sidebar: showSidebar)
        switch window {
        case .preview:
            showInfo = false
            showFilmstrip = false
        case .gallery:
            showSidebar = false
        }
        bareWindow = window
    }

    func leaveFocusMode() {
        guard bareWindow != nil else { return }
        bareWindow = nil
        if let was = preFocus {
            showInfo = was.info
            showFilmstrip = was.filmstrip
            showSidebar = was.sidebar
        }
        preFocus = nil
    }

    private func clampCursor() {
        if photos.isEmpty { if cursor != nil { cursor = nil }; return }
        if let c = cursor, !photos.indices.contains(c) {
            cursor = min(max(c, 0), photos.count - 1)
        }
    }
}
