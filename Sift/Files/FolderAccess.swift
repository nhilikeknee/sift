import Foundation

/// The one place a path becomes a folder this app is allowed to read.
///
/// Sift was unsandboxed until 2026-09-18 and read whatever the account read,
/// which made every privacy control in the app a control over what it had
/// *written down* rather than over what it could reach. Three reports said the
/// same thing — remove folder access, the folder is still there — and each
/// answer was a better sentence explaining why that was expected. The sandbox
/// is what makes the sentence unnecessary (D-324, PRD open question 2).
///
/// Three doors hand a folder over, and all three are Launch Services or
/// AppKit telling the sandbox to extend this process: the open panel, a drop
/// on the window, and opening from the Finder. A path typed into the jump
/// sheet is not a door, and neither is a path this app wrote down last week.
/// So each folder that comes through a door is bookmarked here, and a
/// bookmark is the whole of the permission: drop it and the folder is
/// unreadable at the next launch, stop its scope and it is unreadable now.
///
/// **The grant and the scope are two different things**, which is the part
/// that is easy to get wrong. Resolving a bookmark grants nothing;
/// `startAccessingSecurityScopedResource` is what opens the door, and it was
/// proved against a real sandboxed bundle rather than assumed: with the
/// bookmark resolved and the scope not started, the read is still refused.
@MainActor
enum FolderAccess {
    /// A started scope, and the thing that ends it.
    ///
    /// Access is process-wide once started, so a background decode never has
    /// to ask: the store holds the token for as long as the folder is open
    /// and lets go when it opens another. The token exists because a start
    /// without a stop is a leak the sandbox never complains about — the
    /// folder simply stays readable for the rest of the launch, which is the
    /// bug this whole decision is about, reintroduced one function lower.
    final class Scope {
        let root: URL
        private var open: Bool

        fileprivate init(root: URL, open: Bool) {
            self.root = root
            self.open = open
        }

        /// Idempotent, and `nonisolated` so `deinit` can reach it. Stopping a
        /// scope is thread-safe in the way starting one is.
        nonisolated func end() {
            guard open else { return }
            open = false
            root.stopAccessingSecurityScopedResource()
        }

        deinit { end() }
    }

    // MARK: what the app holds

    /// Every folder handed over, nearest-first is not meaningful here so this
    /// is sorted by path: it is a list somebody reads in Settings, and a list
    /// that reorders itself between two looks is a list nobody trusts.
    static var granted: [URL] {
        Preferences.bookmarks.keys.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Whether this process is actually inside the sandbox.
    ///
    /// Not a style question: the test suite is an ordinary SwiftPM binary with
    /// no entitlements, so `.withSecurityScope` cannot be made there and every
    /// read succeeds anyway. Unsandboxed, this whole type becomes a recorder
    /// of which folders were handed over, which is what the tests check, and
    /// the scope calls are the no-ops the platform already makes them.
    static var isSandboxed = ProcessInfo.processInfo
        .environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Lets a test stand inside the fence, and puts it back afterwards.
    ///
    /// Everything worth testing here — which grant covers a folder, what a
    /// revoke takes away, whether a card's grant reaches the shoots inside it
    /// — is behind the sandbox check, and the suite is an ordinary binary
    /// outside it. Without this seam the rules would be exercised only by
    /// launching the app, which is the arrangement that leaves half the work
    /// verified by reasoning (D-324). The real bookmark calls still cannot
    /// run here; the path arithmetic they sit on is what this reaches, and
    /// that is the part with the branches in it.
    static func pretendingSandboxed<T>(_ body: () throws -> T) rethrows -> T {
        let was = isSandboxed
        isSandboxed = true
        defer { isSandboxed = was }
        return try body()
    }

    // MARK: the doors

    /// Records that somebody with the right to hand this folder over did.
    ///
    /// Called from the three doors and nowhere else. Returns whether a
    /// bookmark was actually written, because the caller that cannot get one
    /// has a folder it can read now and not after the quit, and a reader who
    /// is about to lose their folder should be told before it happens rather
    /// than after.
    @discardableResult
    static func remember(_ url: URL) -> Bool {
        let folder = FolderScanner.canonical(url)
        guard isSandboxed else {
            // The recording half still happens, so Settings lists what was
            // opened and the tests have something to assert on. The value is
            // empty because there is no scope to record: outside the sandbox
            // the key is the fact and the bytes would be a forgery.
            Preferences.setBookmark(Data(), for: folder.path)
            return true
        }
        // The grant is recorded either way, and the return value is the
        // difference: with bytes the folder survives the quit, without them
        // it is reachable for this launch only. Two facts, and collapsing
        // them into one would either lose a folder the reader just handed
        // over or promise a grant that is not written down.
        let data = (try? folder.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)) ?? Data()
        Preferences.setBookmark(data, for: folder.path)
        start(folder.path)
        return !data.isEmpty
    }

    // MARK: the doors, held open

    /// One started scope per grant, for as long as the grant exists.
    ///
    /// The first shape of this started a scope for the *nearest* grant
    /// covering the folder being opened, and the store held that one token.
    /// It was wrong in a way that only showed on screen: open a shoot inside
    /// a card you had also been given, and the scope started on the shoot,
    /// so the card's bookmark existed — `isReachable` said yes, the path bar
    /// drew the crumb, the sidebar rooted there — and every actual read of
    /// the card was refused, because nothing had started *its* scope. A tree
    /// rooted at a folder it could not list, again.
    ///
    /// Holding them all is simpler and it is also the honest model: a grant
    /// is a folder Sift can read, not a folder Sift could read if the right
    /// one happened to be open. Sift holds a handful of these, not hundreds.
    private static var held: [String: Scope] = [:]

    /// Starts every stored grant. Called once, at launch, before the first
    /// folder is opened.
    static func openGranted() {
        for path in Preferences.bookmarks.keys { start(path) }
    }

    /// Idempotent: a grant already open is left alone rather than started
    /// twice, because two starts need two stops and the second never comes.
    private static func start(_ path: String) {
        guard isSandboxed, held[path] == nil,
              let data = Preferences.bookmarks[path], !data.isEmpty
        else { return }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale),
              resolved.startAccessingSecurityScopedResource()
        else { return }
        // A stale bookmark still resolved and still granted, so the door is
        // open; it is the stored copy that has gone off, and it is rewritten
        // now rather than at the next launch, which is the launch that would
        // have failed.
        if stale, let fresh = try? resolved.bookmarkData(options: .withSecurityScope,
                                                         includingResourceValuesForKeys: nil,
                                                         relativeTo: nil) {
            Preferences.setBookmark(fresh, for: path)
        }
        held[path] = Scope(root: resolved, open: true)
    }

    private static func stop(_ path: String) {
        held.removeValue(forKey: path)?.end()
    }

    // MARK: reaching one

    /// Opens the door to `url`, or to the nearest folder above it that was
    /// handed over. Nil when nothing above it was.
    ///
    /// The ancestor walk is the difference between a sandbox somebody keeps
    /// and one they turn off: hand over a card once and every shoot inside it
    /// opens, because a grant on a directory covers what is under it. It also
    /// means walking *up* past the folder you handed over is refused, which is
    /// correct and is the one thing about this that will surprise people. The
    /// refusal has a way forward rather than an empty grid.
    /// Whether the app may open `url`. The doors are already held open by
    /// `openGranted` and `remember`, so this asks rather than acts.
    ///
    /// It keeps the `Scope?` shape because the caller's contract has not
    /// changed — nil is still "refused" — and because an ancestor's scope
    /// being the one that matters is exactly the detail that made the first
    /// shape wrong. Nothing outside this type starts or stops one now.
    static func reach(_ url: URL) -> Scope? {
        let folder = FolderScanner.canonical(url)
        // Outside the sandbox there is no fence, so there is nothing here to
        // open and refusing would be this type inventing a restriction the
        // process does not have. That is the test suite's world and it is
        // also a build whose entitlements went missing — which is why
        // `bundle.sh` reads the sandbox back off the signed bundle and fails
        // the build rather than leaving this line to notice.
        guard isSandboxed else { return Scope(root: folder, open: false) }
        guard let (root, _) = nearestGrant(covering: folder) else { return nil }
        return Scope(root: root, open: false)
    }

    /// Whether `url` is covered, without opening anything. For a menu that has
    /// to draw a row before anybody presses it.
    static func isReachable(_ url: URL) -> Bool {
        guard isSandboxed else { return true }
        return nearestGrant(covering: FolderScanner.canonical(url)) != nil
    }

    /// Longest matching prefix, so a card and a shoot inside it can both be
    /// held and the shoot's own grant is the one used.
    private static func nearestGrant(covering folder: URL) -> (URL, Data)? {
        Preferences.bookmarks
            .filter { path, _ in
                let root = URL(fileURLWithPath: path)
                return root.path == folder.path || FolderScanner.contains(root, folder)
            }
            .max { $0.key.count < $1.key.count }
            .map { (URL(fileURLWithPath: $0.key), $0.value) }
    }

    // MARK: taking it back

    /// Drops the bookmark. The folder is unreadable at the next launch, and
    /// unreadable now for anything that has not already started a scope on it
    /// — which is why the caller ends the scope too. Returns what was dropped,
    /// because the rule is that a mutation carries its inverse even when
    /// today's screen throws the token away.
    @discardableResult
    static func revoke(_ url: URL) -> Data? {
        let folder = FolderScanner.canonical(url)
        stop(folder.path)
        // The pin goes too. A pin is a row in the sidebar's Pinned section
        // and that section is a subset of the folders Sift can read, so a
        // pin whose grant has gone is a row with no root under it — the
        // invariant broken the moment somebody presses Remove All (D-327).
        // It also matches what Remove says: everything Sift holds about this
        // folder, and a pin is something Sift holds.
        Preferences.unpin(folder)
        return Preferences.dropBookmark(for: folder.path)
    }

    /// Puts one back. Nothing in the app calls this yet; `revoke` would be a
    /// one-way door without it, and the day a Revoke grows an undo the way
    /// back is here and tested rather than being that change's problem.
    static func restore(_ data: Data, for url: URL) {
        let path = FolderScanner.canonical(url).path
        Preferences.setBookmark(data, for: path)
        start(path)
    }

    /// Forgetting one path, with the door closed rather than only the record
    /// erased.
    ///
    /// `Preferences.forget(path:)` takes the bookmark out and cannot close
    /// the scope, because closing one is this type's job and a stored
    /// preference has no business holding a permission open. Paired here so
    /// the two cannot come apart: a drop with no stop leaves the folder
    /// readable for the rest of the launch, which is the bug this whole
    /// decision exists to end.
    @discardableResult
    static func forget(path url: URL) -> Preferences.ForgottenPath {
        let folder = FolderScanner.canonical(url)
        stop(folder.path)
        Preferences.unpin(folder)
        return Preferences.forget(path: folder)
    }

    /// The whole trail, keeping the pins readable. Same pairing.
    @discardableResult
    static func forgetHistory() -> [String: Data] {
        let kept = Set(Preferences.pinnedFolders.map(\.path))
        let going = Preferences.bookmarks.keys.filter { !kept.contains($0) }
        for path in going { stop(path) }
        return Preferences.forgetHistory()
    }

    /// Whether this folder may be pinned: only a folder Sift can read, which
    /// is what keeps Pinned a subset of Folders (D-327).
    static func canPin(_ url: URL) -> Bool { isReachable(url) }

    /// Every grant except the ones named. Forget Recent Folders keeps the
    /// pins, because a pin was chosen and a recent was merely recorded, and
    /// that rule now decides what stays readable rather than only what stays
    /// listed.
    @discardableResult
    static func revokeAll(keeping kept: [URL]) -> [String: Data] {
        let keep = Set(kept.map { FolderScanner.canonical($0).path })
        let going = Preferences.bookmarks.keys.filter { !keep.contains($0) }
        for path in going {
            stop(path)
            Preferences.unpin(URL(fileURLWithPath: path))
        }
        return Preferences.dropBookmarks(going)
    }
}
