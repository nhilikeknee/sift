import CoreGraphics
import Foundation

/// UserDefaults-backed. The only persistence that isn't the filesystem itself.
enum Preferences {
    /// Every preference reads and writes through here. The test suite points it
    /// at a scratch domain, for the reason the pasteboard is injectable (D-54):
    /// a test that flips a toggle must not change what another test sees, and
    /// it must not change what the person running the tests sees either (D-86).
    /// Lazy on purpose: this has to be decided before anything reads a
    /// preference, and the first read happens while `AppModel.shared`'s
    /// stored properties are being initialized — earlier than any `init` body
    /// could reach. A `static var` with an initializer runs once, on first
    /// access, which is exactly then (D-123).
    nonisolated(unsafe) private static var backing: UserDefaults = {
        guard Launch.isOn(ProcessInfo.processInfo.environment["SIFT_SCRATCH_PREFS"]),
              let scratch = UserDefaults(suiteName: screenshotDomain)
        else { return .standard }
        scratch.removePersistentDomain(forName: screenshotDomain)
        return scratch
    }()

    /// Where a launch that is only being photographed keeps its preferences,
    /// so the sheet cannot change what the app is like afterwards. It could:
    /// `SIFT_SHOW=filmstrip` goes through the router, the router writes the
    /// store, and the store writes the preference, so a sheet run left the
    /// filmstrip in whatever state its last launch ended in and the next real
    /// launch inherited it.
    private static let screenshotDomain = "sift.screenshots"
    nonisolated(unsafe) private static var isTestDomain = false
    private static var d: UserDefaults { backing }

    /// Idempotent, and safe to call from every suite's init.
    static func useTestDefaults() { useScratchDomain(named: "sift.tests") }

    private static func useScratchDomain(named name: String) {
        listLock.withLock {
            guard !isTestDomain else { return }
            guard let scratch = UserDefaults(suiteName: name) else { return }
            scratch.removePersistentDomain(forName: name)
            backing = scratch
            isTestDomain = true
        }
    }
    /// The two list-valued preferences are read-modify-write. The app touches
    /// them from the main actor, but `noteRecent` and `setResume` are ordinary
    /// statics that anything can call, and two interleaved calls lose an entry.
    private static let listLock = NSLock()

    static var autoAdvance: Bool {
        get { d.object(forKey: "autoAdvance") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoAdvance") }
    }
    static var includeSubfolders: Bool {
        get { d.bool(forKey: "includeSubfolders") }
        set { d.set(newValue, forKey: "includeSubfolders") }
    }
    static var lastFolder: URL? {
        get { d.string(forKey: "lastFolder").map { URL(fileURLWithPath: $0) } }
        set { d.set(newValue?.path, forKey: "lastFolder") }
    }
    static var lastMoveFolder: URL? {
        get { d.string(forKey: "lastMoveFolder").map { URL(fileURLWithPath: $0) } }
        set { d.set(newValue?.path, forKey: "lastMoveFolder") }
    }
    /// The application the keepers were last handed to. Remembered so the
    /// second hand-off is a keystroke rather than a menu (D-88).
    static var lastEditor: URL? {
        get { d.string(forKey: "lastEditor").map { URL(fileURLWithPath: $0) } }
        set { d.set(newValue?.path, forKey: "lastEditor") }
    }
    /// Where the last card was copied to. Offered first next time, because a
    /// year of shoots usually lands under one roof.
    static var lastIngestFolder: URL? {
        get { d.string(forKey: "lastIngestFolder").map { URL(fileURLWithPath: $0) } }
        set { d.set(newValue?.path, forKey: "lastIngestFolder") }
    }
    /// Write an `.xmp` beside every photo whose flag or favorite changes, so
    /// Lightroom and Bridge can read them (D-94). Off by default: it writes
    /// files into the shoot.
    static var writeSidecars: Bool {
        get { d.bool(forKey: "writeSidecars") }
        set { d.set(newValue, forKey: "writeSidecars") }
    }
    /// On unless somebody turned it off. The preview window is where a burst
    /// gets compared, and the strip is the only thing in it that says the
    /// neighbors exist: off by default it was a feature that needed `f` to be
    /// discovered before it could be used (D-122). `showSidebar` and
    /// `autoAdvance` default the same way and for the same reason.
    static var showFilmstrip: Bool {
        get { d.object(forKey: "showFilmstrip") as? Bool ?? true }
        set { d.set(newValue, forKey: "showFilmstrip") }
    }
    /// Whether compare's three controls are drawn in the preview bar. **Off by
    /// default**, at the owner's call, because seven controls over a photograph
    /// for a feature most sittings never open is a worse default than a bar of
    /// six (D-270).
    ///
    /// This is the one preference in the app that hides a control rather than
    /// removing a capability: `a`, `\` and `|` keep working with it off, and so
    /// do the View menu's three items, so compare is not keyboard-only — but it
    /// is not *on screen* either, which is the rule about a shortcut never
    /// being the only way in, deliberately spent. The `compare` Feature switch
    /// is the other one and means something different: off there is gone, keys
    /// and all (D-123).
    static var compareControlsInBar: Bool {
        get { d.object(forKey: "compareControlsInBar") as? Bool ?? false }
        set { d.set(newValue, forKey: "compareControlsInBar") }
    }
    /// Thumbnail edge. Snapped to the nearest step on read, so a value left
    /// behind by an older build lands on a stop the control can reach.
    static var gridCell: CGFloat {
        get {
            if let forced = forcedGridCell { return forced }
            let saved = d.object(forKey: "gridCell") as? Double
            guard let saved else { return Tokens.Layout.gridCell }
            return snapped(saved)
        }
        set { d.set(Double(newValue), forKey: "gridCell") }
    }

    /// `SIFT_GRID=96` forces a step for one launch without writing it, the way
    /// `SIFT_APPEARANCE` forces a palette (D-118). The contact sheet shoots the
    /// smallest and largest steps with it: a name under a 96pt thumbnail is the
    /// crowded case, and nobody had looked at one (D-120).
    ///
    /// Read once, not on every get. The getter runs on every draw, so a value
    /// that cannot be read would say so thousands of times; and `SIFT_GRID=big`
    /// used to fall through to the saved preference in silence, which is a
    /// sheet shot at a size nobody asked for (D-265). A `static let` is lazy
    /// and runs the one time, which is what the launch-once contract means
    /// everywhere else.
    private static let forcedGridCell: CGFloat? = {
        guard let value = Launch.measurement(ProcessInfo.processInfo.environment["SIFT_GRID"],
                                             named: "SIFT_GRID")
        else { return nil }
        return snapped(value)
    }()

    /// The nearest step, so a value left behind by an older build or handed in
    /// from outside lands on a stop the size control can reach.
    private static func snapped(_ value: Double) -> CGFloat {
        Tokens.Layout.gridCellSteps.min { abs($0 - value) < abs($1 - value) } ?? Tokens.Layout.gridCell
    }

    // MARK: recent folders (last 10, most recent first)

    static var recentFolders: [URL] {
        (d.stringArray(forKey: "recentFolders") ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func noteRecent(_ folder: URL) {
        listLock.withLock {
            var list = recentFolders.filter { $0.path != folder.path }
            list.insert(folder, at: 0)
            d.set(list.prefix(10).map(\.path), forKey: "recentFolders")
        }
    }

    // MARK: folder grants

    /// Path to the security-scoped bookmark that reaches it (D-324).
    ///
    /// This is the only preference that is a permission rather than a
    /// setting: deleting an entry here takes a folder away from the app,
    /// where deleting any other entry only takes away something it
    /// remembered. That is why `forget(path:)` carries the bookmark out in
    /// its token — a Forget that could not be undone in full would be the one
    /// mutation in the app whose inverse is partial.
    ///
    /// Unsandboxed — the test suite, and any build whose entitlements went
    /// missing — the value is empty and the dictionary is a record of which
    /// folders were handed over. The keys are what the app reasons about; the
    /// bytes are what macOS reasons about.
    static var bookmarks: [String: Data] {
        d.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
    }

    static func setBookmark(_ data: Data, for path: String) {
        listLock.withLock {
            var all = d.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
            all[path] = data
            d.set(all, forKey: "folderBookmarks")
        }
    }

    @discardableResult
    static func dropBookmark(for path: String) -> Data? {
        listLock.withLock {
            var all = d.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
            let gone = all.removeValue(forKey: path)
            d.set(all, forKey: "folderBookmarks")
            return gone
        }
    }

    /// Several at once, handing back what went, so one press has one inverse
    /// rather than a list of them.
    @discardableResult
    static func dropBookmarks(_ paths: some Sequence<String>) -> [String: Data] {
        listLock.withLock {
            var all = d.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
            var gone: [String: Data] = [:]
            for path in paths { if let was = all.removeValue(forKey: path) { gone[path] = was } }
            d.set(all, forKey: "folderBookmarks")
            return gone
        }
    }

    // MARK: session backup directories

    /// Where each running session put its undo backups (D-299).
    ///
    /// The cleanup on quit runs in `applicationWillTerminate`, which a crash, a
    /// force-quit or a logout never reaches, so a launch has to be able to find
    /// what the last session left. It cannot find it by looking:
    /// `.itemReplacementDirectory` hands out a directory inside `TemporaryItems`,
    /// and that folder refuses to be listed — by this app as much as by anyone,
    /// `NSPOSIXErrorDomain Code=1` on `contentsOfDirectory`, even for the
    /// process that owns a directory inside it. So the path is written down
    /// here instead, which is also the only persistence in the app that is not
    /// the filesystem.
    ///
    /// A list rather than one path, because Sift can be running twice
    /// (`open -n`) and the second launch must not take the first one's backups,
    /// which are its undo stack.
    static var sessionBackupPaths: [String] {
        d.stringArray(forKey: "sessionBackups") ?? []
    }

    /// Adds a path and hands back every other one, so the caller does one
    /// read-modify-write rather than a read and then a write with a gap in it.
    static func registerSessionBackups(_ path: String) -> [String] {
        listLock.withLock {
            let others = (d.stringArray(forKey: "sessionBackups") ?? []).filter { $0 != path }
            d.set(others + [path], forKey: "sessionBackups")
            return others
        }
    }

    /// Takes paths off the list: the ones a sweep removed, and this session's
    /// own on the way out.
    static func forgetSessionBackups(_ paths: [String]) {
        listLock.withLock {
            let gone = Set(paths)
            d.set((d.stringArray(forKey: "sessionBackups") ?? []).filter { !gone.contains($0) },
                  forKey: "sessionBackups")
        }
    }

    // MARK: pinned folders (the two or three you cull into)

    static var pinnedFolders: [URL] {
        (d.stringArray(forKey: "pinnedFolders") ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func togglePin(_ folder: URL) -> Bool {
        listLock.withLock {
            var list = pinnedFolders.map(\.path)
            let path = folder.path
            let wasPinned = list.contains(path)
            if wasPinned { list.removeAll { $0 == path } } else { list.append(path) }
            d.set(list, forKey: "pinnedFolders")
            return !wasPinned
        }
    }

    /// Adds a pin. Returns false when it was already there, so the caller can
    /// say "already pinned" instead of silently unpinning it, which is what
    /// `togglePin` would do to a folder chosen from a panel.
    @discardableResult
    static func pin(_ folder: URL) -> Bool {
        listLock.withLock {
            var list = pinnedFolders.map(\.path)
            let path = folder.path
            guard !list.contains(path) else { return false }
            list.append(path)
            d.set(list, forKey: "pinnedFolders")
            return true
        }
    }

    /// Takes a pin off, and says whether there was one. The inverse of
    /// `pin`, and needed on its own because a grant going away takes the pin
    /// with it (D-327) without anybody pressing Unpin.
    @discardableResult
    static func unpin(_ folder: URL) -> Bool {
        listLock.withLock {
            var list = pinnedFolders.map(\.path)
            let path = folder.path
            guard list.contains(path) else { return false }
            list.removeAll { $0 == path }
            d.set(list, forKey: "pinnedFolders")
            return true
        }
    }

    static func isPinned(_ folder: URL) -> Bool { pinnedFolders.contains { $0.path == folder.path } }

    /// How wide the reader dragged the sidebar. Clamped on the way out rather
    /// than only on the way in: a value written by an older build, or edited by
    /// hand, must not be able to wedge the window at a width nothing can
    /// recover from (D-229).
    static var sidebarWidth: CGFloat {
        get {
            guard let stored = d.object(forKey: "sidebarWidth") as? Double else { return Tokens.Layout.sidebar }
            return min(max(CGFloat(stored), Tokens.Layout.sidebarMin), Tokens.Layout.sidebarMax)
        }
        set { d.set(Double(min(max(newValue, Tokens.Layout.sidebarMin), Tokens.Layout.sidebarMax)), forKey: "sidebarWidth") }
    }

    static var showSidebar: Bool {
        get { d.object(forKey: "showSidebar") as? Bool ?? true }
        set { d.set(newValue, forKey: "showSidebar") }
    }

    // MARK: per-folder resume (last 200 folders, most recent first)

    private static let resumeKey = "resume"

    static func resumeFile(for folder: URL) -> URL? {
        let entries = d.array(forKey: resumeKey) as? [[String: String]] ?? []
        return entries.first { $0["folder"] == folder.path }?["file"].map { URL(fileURLWithPath: $0) }
    }

    static func setResume(_ file: URL?, for folder: URL) {
        listLock.withLock {
            var entries = (d.array(forKey: resumeKey) as? [[String: String]] ?? []).filter { $0["folder"] != folder.path }
            if let file { entries.insert(["folder": folder.path, "file": file.path], at: 0) }
            d.set(Array(entries.prefix(200)), forKey: resumeKey)
        }
    }

    // MARK: the reader's own keys

    /// Command name to the keystrokes it was moved onto, both in their stored
    /// spellings (D-175). `KeyBindings` owns the meaning; this is the shelf.
    static var keyOverrides: [String: [String]] {
        get { d.dictionary(forKey: "keyOverrides") as? [String: [String]] ?? [:] }
        set {
            if newValue.isEmpty { d.removeObject(forKey: "keyOverrides") }
            else { d.set(newValue, forKey: "keyOverrides") }
        }
    }

    // MARK: first-time hints

    /// A hint is shown once, ever, and then never again (D-66). The record is
    /// one boolean per hint id rather than a list, so a hint added later starts
    /// unseen without migrating anything.
    static func hintSeen(_ id: String) -> Bool { d.bool(forKey: "hint.\(id)") }

    /// Returns true the first time it is called for an id, false afterwards.
    static func claimHint(_ id: String) -> Bool {
        listLock.withLock {
            guard !d.bool(forKey: "hint.\(id)") else { return false }
            d.set(true, forKey: "hint.\(id)")
            return true
        }
    }

    /// Every hint the app can show, so the control that brings them back can
    /// name them all. A hint whose id is not here would be spent forever, which
    /// is why the list lives beside `claimHint` rather than in the view
    /// (D-153).
    static let hintIDs = [
        "adjust", "focusPeaking", "reviewRejects", "sideBySide",
        "slideshow", "survey", "tournament", "undo",
    ]

    /// For Settings' "Show the first-time hints again", and for a test that
    /// needs a clean slate.
    static func forgetHints(_ ids: [String] = hintIDs) {
        forget(ids.map { "hint.\($0)" })
    }

    /// The other direction, for a launch that is only being filmed:
    /// `SIFT_HINTS=off` spends every hint before the first frame.
    ///
    /// A recording runs on a throwaway preferences domain (D-123), which wipes
    /// itself at launch, so every clip is somebody's first sitting and every
    /// hint fires. The side-by-side one landed across both photographs at the
    /// exact moment the clip existed to show them (D-271). It is real and it is
    /// useful once; it is not what the second beat of a demo should be.
    static func spendHints() {
        for id in hintIDs { d.set(true, forKey: "hint.\(id)") }
    }

    /// Whether any hint has been spent, so the control can say whether there
    /// is anything to bring back.
    static var anyHintSeen: Bool { hintIDs.contains(where: hintSeen) }

    /// Every key that records somewhere you have been, so the control that
    /// clears them can name them all and a later one cannot be forgotten here
    /// by accident. `pinnedFolders` is deliberately not among them: a pin is
    /// something you chose, and a control called "forget where I have been"
    /// that also threw away the two folders you cull into would be taking
    /// something nobody asked it to take (D-173).
    ///
    /// The last four are AppKit's, not this app's. An `NSOpenPanel` writes
    /// where it was last pointed into the same domain, and
    /// `NSOSPLastRootDirectory` is a bookmark with the path sitting in it as
    /// readable bytes: opening one folder through the panel left
    /// `/Users/someone/Documents/2025-06-18 Birthday` in
    /// preferences, where a control that said it cleared every trail did not
    /// touch it. Clearing a key the framework owns is allowed, it reads the
    /// same domain back, and a button that clears all but one trail is worse
    /// than one that admits it clears none (D-234).
    static let historyKeys = [
        "recentFolders", "lastFolder", "lastMoveFolder", "lastIngestFolder",
        "lastEditor", resumeKey,
        "NSOSPLastRootDirectory", "NSNavLastRootDirectory",
        "NSNavLastCurrentDirectory", "NSNavRecentPlaces",
    ]

    /// Whether there is any trail to clear, so the control can say so rather
    /// than claiming to have done something.
    static var anyHistory: Bool { historyKeys.contains { d.object(forKey: $0) != nil } }

    /// Everything Sift holds about folders, as one list rather than two
    /// (D-325).
    ///
    /// Access and History were separate sections answering separate
    /// questions — what Sift can read, and where you have been — and the
    /// reader asked what the difference was, which is the question a screen
    /// should not raise. They were mostly the same folders, a few inches
    /// apart, each with its own red word, and the two words did different
    /// amounts: Forget took the record and the grant, Revoke took only the
    /// grant. A reader had to work that out from the labels.
    ///
    /// One row per folder now, in two groups, because the one thing a reader
    /// wants at a glance is whether Sift can still read it. A folder that is
    /// both granted and remembered appears once, under `granted`: that is
    /// the stronger fact, and its control takes both away.
    ///
    /// The other two are not folders and keep their own place. `panel` is
    /// macOS's, written by its open panel into whatever domain it runs in,
    /// and it comes back on the next ⌘O. `editor` is an application.
    struct FolderTrail: Sendable {
        var granted: [URL] = []
        var remembered: [URL] = []
        var panel: [URL] = []
        var editor: URL?

        var folderCount: Int { granted.count + remembered.count }
        var count: Int { folderCount + panel.count + (editor == nil ? 0 : 1) }
        var isEmpty: Bool { count == 0 }
    }

    static var folderTrail: FolderTrail {
        var t = FolderTrail()
        let granted = Set(bookmarks.keys)

        // Every folder Sift has written down anywhere, deduplicated. A
        // resume entry is a folder and the frame you had reached in it; the
        // frame is your position rather than another place you have been, so
        // the folder appears once and the position rides with it.
        var remembered: [String] = recentFolders.map(\.path)
        remembered += (d.array(forKey: resumeKey) as? [[String: String]] ?? [])
            .compactMap { $0["folder"] }
        remembered += ["lastFolder", "lastMoveFolder", "lastIngestFolder"]
            .compactMap { d.string(forKey: $0) }

        var seen = Set<String>()
        for path in remembered where seen.insert(path).inserted && !granted.contains(path) {
            t.remembered.append(URL(fileURLWithPath: path))
        }
        t.granted = granted.sorted().map { URL(fileURLWithPath: $0) }

        for key in ["NSOSPLastRootDirectory", "NSNavLastRootDirectory", "NSNavLastCurrentDirectory"] {
            if let path = d.string(forKey: key) { t.panel.append(URL(fileURLWithPath: path)) }
        }
        t.panel += (d.stringArray(forKey: "NSNavRecentPlaces") ?? []).map { URL(fileURLWithPath: $0) }
        t.editor = lastEditor
        return t
    }

    /// For Settings' "Forget Recent Folders". Every folder the reader has
    /// opened leaves `~/Library/Preferences` with it: the last ten, the last
    /// move, ingest and editor targets, and the two hundred per-folder resume
    /// positions (D-173).
    ///
    /// The resume positions do not come back, which is the trade-off: it is
    /// a privacy control, and one that asked twice before doing what it says
    /// would be a privacy control nobody uses.
    ///
    /// Two paths in this domain stay, and neither is an oversight. The folders
    /// the reader pinned are a choice they made and the control says so.
    /// `sessionBackups` is the list D-299 reads on the next launch to sweep
    /// the backup directories a crash left behind, and those hold full-size
    /// copies of photographs: forgetting where they are would leave them in
    /// the temporary area with nothing remaining that knows to take them away.
    /// A privacy control that strands photographs is worse than one that
    /// leaves an unguessable temporary path behind (S-27).
    ///
    /// Since the sandbox it clears the grants too, all but the pinned ones,
    /// so the press takes away what Sift can read and not only what it wrote
    /// down (D-324). Those were the same sentence in the reader's head all
    /// along, and for a year they were two different acts: the report that
    /// this button does nothing arrived three times and was correct about
    /// what it saw every time. Returns what went, so a caller that wants to
    /// offer the way back has it.
    @discardableResult
    static func forgetHistory() -> [String: Data] {
        let kept = Set(pinnedFolders.map(\.path))
        let dropped = dropBookmarks(bookmarks.keys.filter { !kept.contains($0) })
        forget(historyKeys)
        return dropped
    }

    /// One path out of the trail, and the way to put it back.
    ///
    /// The whole-list button is a single act with a stated cost: everything
    /// goes and the resume positions do not come back. One row is a different
    /// act. Somebody dropping a single folder is keeping the rest on purpose,
    /// so getting the wrong row is a real mistake and there has to be a way
    /// out of it — which is why this returns its own inverse rather than
    /// leaving the undo to whatever screen calls it.
    ///
    /// Everything the path is stored under goes at once. It can sit in the
    /// recents, in a resume position and in two of the targets, and a reader
    /// who asked Sift to forget a folder meant the folder, not the row their
    /// pointer happened to be over.
    ///
    /// The open panel's own keys are not touched. AppKit rewrites them from
    /// its own domain whenever a panel opens, so a row removed there would be
    /// back the next time the reader pressed ⌘O, and a control that undoes
    /// itself is worse than no control (D-234, D-321).
    struct ForgottenPath: Sendable, Equatable {
        let url: URL
        fileprivate var recentAt: Int?
        fileprivate var resumeAt: Int?
        fileprivate var resume: [String: String]?
        fileprivate var targets: [String] = []
        /// The grant itself, so restoring puts the folder back within reach
        /// and not merely back in a list (D-324).
        fileprivate var bookmark: Data?

        /// Nothing was stored under this path, so nothing was removed and
        /// there is nothing to offer an undo for.
        var isEmpty: Bool {
            recentAt == nil && resumeAt == nil && targets.isEmpty && bookmark == nil
        }
    }

    /// Discardable, and the return value still exists. Settings drops the
    /// token because the reader asked for a plain control there (D-321), and
    /// the inverse stays in the signature because the rule is that a mutation
    /// carries the thing that undoes it: the day something else forgets a
    /// path — a context menu, a script, an ingest that cleans up after itself
    /// — the way back is already here and already tested, rather than being
    /// the tenth feature's problem.
    @discardableResult
    static func forget(path url: URL) -> ForgottenPath {
        listLock.withLock {
            var out = ForgottenPath(url: url)
            let path = url.path

            var recents = d.stringArray(forKey: "recentFolders") ?? []
            if let i = recents.firstIndex(of: path) {
                out.recentAt = i
                recents.remove(at: i)
                d.set(recents, forKey: "recentFolders")
            }

            var entries = d.array(forKey: resumeKey) as? [[String: String]] ?? []
            if let i = entries.firstIndex(where: { $0["folder"] == path }) {
                out.resumeAt = i
                out.resume = entries[i]
                entries.remove(at: i)
                d.set(entries, forKey: resumeKey)
            }

            for key in ["lastFolder", "lastMoveFolder", "lastIngestFolder", "lastEditor"]
            where d.string(forKey: key) == path {
                out.targets.append(key)
                d.removeObject(forKey: key)
            }

            // The grant goes with the path. This is the line the whole
            // sandbox retrofit was for: before it, Forget cleared what Sift
            // had written down and left what Sift could read untouched, which
            // is the report that arrived three times (D-324). Inline rather
            // than through `dropBookmark`, which takes the lock this already
            // holds.
            var grants = d.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
            if let was = grants.removeValue(forKey: path) {
                out.bookmark = was
                d.set(grants, forKey: "folderBookmarks")
            }
            return out
        }
    }

    /// The inverse, put back where it was rather than at the front: a restored
    /// recent that jumped to the top of ⌘1 would have the undo rearranging the
    /// menu it was meant to leave alone.
    static func restore(_ forgotten: ForgottenPath) {
        listLock.withLock {
            let path = forgotten.url.path
            if let i = forgotten.recentAt {
                var recents = d.stringArray(forKey: "recentFolders") ?? []
                recents.removeAll { $0 == path }
                recents.insert(path, at: min(i, recents.count))
                d.set(Array(recents.prefix(10)), forKey: "recentFolders")
            }
            if let i = forgotten.resumeAt, let entry = forgotten.resume {
                var entries = d.array(forKey: resumeKey) as? [[String: String]] ?? []
                entries.removeAll { $0["folder"] == path }
                entries.insert(entry, at: min(i, entries.count))
                d.set(Array(entries.prefix(200)), forKey: resumeKey)
            }
            for key in forgotten.targets { d.set(path, forKey: key) }
            if let bookmark = forgotten.bookmark {
                var grants = d.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
                grants[path] = bookmark
                d.set(grants, forKey: "folderBookmarks")
            }
        }
    }

    /// Clears stored preferences so the next read gets its default back. The
    /// help overlay's "show the hints again" is the app's use of it; a test
    /// that asserts what a default *is* needs it too, because a suite that has
    /// already written the key would otherwise be reading its own answer
    /// (D-122).
    static func forget(_ keys: [String]) {
        listLock.withLock { for key in keys { d.removeObject(forKey: key) } }
    }

    /// Capture date, oldest first, until somebody chooses otherwise.
    ///
    /// It was name, which is the filesystem's order and not the shoot's. A
    /// card writes `DSC_0001` after `DSC_9999` and a second body writes its
    /// own run of numbers beside the first, so name order is the shoot only
    /// by luck. Oldest first is the order the frames were made in, which is
    /// what a person culling a shoot is walking through (D-378).
    ///
    /// Absent, not written: a domain that already holds a sort keeps it, and
    /// the rows this preference feeds are unchanged.
    static var sort: SortOrder {
        get { d.string(forKey: "sort").flatMap(SortOrder.init) ?? .dateTaken }
        set { d.set(newValue.rawValue, forKey: "sort") }
    }

    /// Which way round the sort runs. Absent means `natural`, which is what
    /// every order did before there was a choice, so an existing preferences
    /// domain keeps the order it had (D-349).
    static var sortDirection: SortDirection {
        get { d.string(forKey: "sortDirection").flatMap(SortDirection.init) ?? .natural }
        set { d.set(newValue.rawValue, forKey: "sortDirection") }
    }

    /// Which features are switched off. Stored as the exceptions rather than
    /// as the whole set, so a feature added in a later build starts on for
    /// everybody without migrating anything (D-123).
    static var featuresOff: Set<Feature> {
        get {
            // Absent means nobody has touched a switch, which is not the same
            // as "all of them are on": four start off (D-124, D-236). Once anybody
            // writes, the stored array is the whole answer.
            guard let stored = d.object(forKey: "featuresOff") as? [String] else {
                return Feature.offByDefault
            }
            return Set(stored.compactMap(Feature.init))
        }
        set { d.set(newValue.map(\.rawValue).sorted(), forKey: "featuresOff") }
    }

    /// Light, dark, or whatever the desktop is doing. Defaults to the desktop,
    /// so a Mac that goes dark at dusk takes Sift with it (D-112).
    static var appearance: Appearance {
        get { d.string(forKey: "appearance").flatMap(Appearance.init) ?? .system }
        set { d.set(newValue.rawValue, forKey: "appearance") }
    }
}
