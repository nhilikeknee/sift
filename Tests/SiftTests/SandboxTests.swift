import Testing
import Foundation
@testable import Sift

/// What Sift is allowed to read, and what takes it back (D-324).
///
/// The app was unsandboxed until 2026-09-18 and read whatever the account
/// read, so every control here acted on what it had written down rather than
/// on what it could reach. "I removed folder access and it still opens the
/// folder" was reported three times, and was correct every time. These are
/// the rules that make the report impossible rather than explained.
///
/// The suite runs outside the sandbox, where there is no fence at all, so the
/// ones about reach stand inside it with `pretendingSandboxed`. What they
/// exercise is the path arithmetic — which grant covers which folder — and
/// that is where every branch is. Whether macOS honors a bookmark is macOS's
/// to keep, and was proved against a real sandboxed bundle before any of this
/// was written.
/// Serialized, and `pretendingSandboxed` is why. The fence is a static and
/// the grants are one preferences domain, so two of these running at once
/// would each be reading the other's folders — and the failure looks like a
/// rule being wrong rather than a suite being parallel.
@Suite(.serialized) @MainActor struct SandboxTests {
    init() {
        Preferences.useTestDefaults()
        Preferences.forgetHistory()
        Preferences.dropBookmarks(Preferences.bookmarks.keys.map { $0 })
        Preferences.forget(["pinnedFolders"])
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    // MARK: what a grant covers

    @Test("a grant on a card reaches the shoots inside it")
    func aGrantCoversWhatIsUnderIt() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            #expect(FolderAccess.isReachable(url("/cards/Harbor")))
            #expect(FolderAccess.isReachable(url("/cards/Harbor/Day 1")))
            #expect(FolderAccess.isReachable(url("/cards/Harbor/Day 1/raw")))
        }
    }

    /// The one thing about this that will surprise people, so it is written
    /// down as intended rather than discovered as a bug: handing over a shoot
    /// does not hand over the card it sits in, and `⌘↑` out of it is refused.
    @Test("a grant does not reach above itself")
    func aGrantDoesNotReachUpward() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor/Day 1"))
            #expect(FolderAccess.isReachable(url("/cards/Harbor/Day 1")))
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
            #expect(!FolderAccess.isReachable(url("/cards")))
        }
    }

    /// A sibling whose name starts with the granted one's is not inside it.
    /// Prefix matching on strings says `/cards/Harbor2` is under
    /// `/cards/Harbor`, which would hand over a folder nobody chose.
    @Test("a folder whose name merely starts the same is not covered")
    func aPrefixIsNotAnAncestor() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            #expect(!FolderAccess.isReachable(url("/cards/Harbor2")))
            #expect(!FolderAccess.isReachable(url("/cards/HarborWeekend/Day 1")))
        }
    }

    @Test("nothing is reachable before anything is handed over")
    func theFenceStartsClosed() {
        FolderAccess.pretendingSandboxed {
            #expect(FolderAccess.granted.isEmpty)
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
        }
    }

    // MARK: taking it back

    @Test("revoking a folder takes back everything under it")
    func revokingClosesTheWholeGrant() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.revoke(url("/cards/Harbor"))
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
            #expect(!FolderAccess.isReachable(url("/cards/Harbor/Day 1")))
            #expect(FolderAccess.granted.isEmpty)
        }
    }

    /// Revoking one grant leaves the others, because they are two grants and
    /// only one was named. The reverse of the rule above about reaching down.
    ///
    /// Two folders that are not inside each other. The nested case is the test
    /// below, and it does not end the same way.
    @Test("revoking one grant leaves the others")
    func revokingIsNotRevokingEverything() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.remember(url("/shoots/Headland"))
            FolderAccess.revoke(url("/shoots/Headland"))
            #expect(FolderAccess.isReachable(url("/cards/Harbor/Day 1")))
            #expect(!FolderAccess.isReachable(url("/shoots/Headland")))
        }
    }

    /// Removing a row does **not** always make that folder unreadable, and the
    /// README says so now (S-33). A grant reaches everything under it, so a
    /// shoot inside a card you also handed over is still covered by the card
    /// after its own grant has gone: `nearestGrant` simply falls back to the
    /// next longest prefix.
    ///
    /// The test above carries the docstring this one needed for a while. Its
    /// two paths are siblings, so it never stood on this ground, and the
    /// README's sentence was absolute for as long as nothing asked.
    ///
    /// Two nested rows is an ordinary state: `remember` is called from the
    /// Finder open, the open panel, the move destination panel and the drop,
    /// so opening a card and then picking a shoot inside it with `⌘O` gets
    /// there.
    @Test("removing a row inside a granted card leaves the card holding it")
    func revokingInsideACardLeavesTheCardsGrant() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.remember(url("/cards/Harbor/Day 1"))
            FolderAccess.revoke(url("/cards/Harbor/Day 1"))
            #expect(FolderAccess.isReachable(url("/cards/Harbor/Day 1")),
                    "the card's grant still reaches it, which is what the README now says")
            #expect(FolderAccess.granted.count == 1, "and the row itself has gone")

            // The card, and only the card, takes it away.
            FolderAccess.revoke(url("/cards/Harbor"))
            #expect(!FolderAccess.isReachable(url("/cards/Harbor/Day 1")))
        }
    }

    /// The rule the whole app is built on: a mutation carries its inverse.
    @Test("a revoked grant can be put back")
    func revokeCarriesItsInverse() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            let was = FolderAccess.revoke(url("/cards/Harbor"))
            #expect(was != nil)
            FolderAccess.restore(was!, for: url("/cards/Harbor"))
            #expect(FolderAccess.isReachable(url("/cards/Harbor/Day 1")))
        }
    }

    // MARK: the controls in Settings

    /// The report, three times: press Forget Recent Folders, the folder is
    /// still readable. It was, and the button never claimed otherwise. Now
    /// the two are one act, and this is the test that says so.
    @Test("Forget Recent Folders revokes what it forgets")
    func forgettingIsRevoking() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            Preferences.noteRecent(url("/cards/Harbor"))
            Preferences.forgetHistory()
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
            #expect(Preferences.recentFolders.isEmpty)
        }
    }

    /// A pin was chosen and a recent was merely recorded, so the pin keeps
    /// its grant as well as its place on the list. That rule used to decide
    /// only what stayed listed, because a list was all there was.
    @Test("Forget Recent Folders keeps a pinned folder readable")
    func aPinSurvivesTheWholeTrailGoing() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.remember(url("/shoots/Headland"))
            Preferences.pin(url("/shoots/Headland"))
            Preferences.forgetHistory()
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
            #expect(FolderAccess.isReachable(url("/shoots/Headland")))
        }
    }

    /// Per-row Forget already returned a token that undid it. The grant had
    /// to join the token rather than sit outside it, or the one mutation in
    /// the app whose inverse was partial would be the one about permission.
    @Test("forgetting one path revokes it, and the undo hands it back")
    func oneRowForgetsAndRestoresTheGrant() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            Preferences.noteRecent(url("/cards/Harbor"))
            let token = Preferences.forget(path: url("/cards/Harbor"))
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
            Preferences.restore(token)
            #expect(FolderAccess.isReachable(url("/cards/Harbor")))
            #expect(Preferences.recentFolders.contains(url("/cards/Harbor")))
        }
    }

    // MARK: the sidebar's roots

    /// One root per grant, and nothing above one (D-327).
    ///
    /// This replaces three tests about a computed root. The tree used to
    /// start at the open folder's parent, which under the sandbox meant a
    /// root it could not list; the fix was a fourth rule, and then a pinned
    /// folder from another disk could still be in the sidebar with no root
    /// holding it. A root is a grant now, so both go away: "show me the
    /// siblings" is "you handed over the card", and nothing can be in the
    /// sidebar that Sift cannot read.
    @Test("the sidebar's roots are exactly the folders Sift can read")
    func theRootsAreTheGrants() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.remember(url("/shoots/Headland"))
            #expect(FolderAccess.granted.map(\.path) == ["/cards/Harbor", "/shoots/Headland"])
        }
    }

    /// A pin cannot outlive the grant under it, or Pinned would hold a row
    /// that Folders does not — the invariant, broken by the one press most
    /// likely to be aimed at it.
    @Test("removing a folder unpins it")
    func removingUnpins() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/shoots/Headland"))
            Preferences.pin(url("/shoots/Headland"))
            #expect(Preferences.isPinned(url("/shoots/Headland")))
            FolderAccess.revoke(url("/shoots/Headland"))
            #expect(!Preferences.isPinned(url("/shoots/Headland")))
        }
    }

    @Test("Remove All leaves nothing pinned")
    func removeAllUnpinsEverything() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.remember(url("/shoots/Headland"))
            Preferences.pin(url("/cards/Harbor"))
            Preferences.pin(url("/shoots/Headland"))
            FolderAccess.revokeAll(keeping: [])
            #expect(Preferences.pinnedFolders.isEmpty)
        }
    }

    /// The invariant, stated as the thing a test can check: every pinned
    /// folder is one Sift can read, so every Pinned row has a root below it.
    @Test("nothing can be pinned that Sift cannot read")
    func pinnedIsASubsetOfTheRoots() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            Preferences.pin(url("/cards/Harbor"))
            FolderAccess.remember(url("/shoots/Headland"))
            FolderAccess.revoke(url("/shoots/Headland"))
            let roots = Set(FolderAccess.granted.map(\.path))
            #expect(Preferences.pinnedFolders.allSatisfy { roots.contains($0.path) })
            #expect(FolderAccess.canPin(url("/cards/Harbor")))
            #expect(!FolderAccess.canPin(url("/shoots/Headland")))
        }
    }

    // MARK: the breadcrumb and the sidebar agree

    /// Reported twice. The path bar named the parent while the sidebar did
    /// not, about the same folder, a few inches apart. The first attempt drew
    /// that crumb quietly and changed its tooltip, which fixed nothing the
    /// reader could see: what they were pointing at was whether the folder is
    /// named at all, not how brightly. So the path stops at the grant.
    ///
    /// By path, not by URL: `deletingLastPathComponent` hands back a
    /// directory URL with a trailing slash, and two URLs for one folder do
    /// not compare equal — the same trap `sidebarRoot` names.
    @Test("the path bar stops at the folder Sift was handed")
    func theCrumbsStopAtTheGrant() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor/Day 1"))
            let names = Breadcrumb.pathSegments(for: url("/cards/Harbor/Day 1")).map(\.url.path)
            #expect(names == ["/cards/Harbor/Day 1"])
        }
    }

    /// The header and the sidebar agree on what is above the open folder,
    /// which is the whole point: one control cannot offer a folder the other
    /// says is not there.
    @Test("the header and the sidebar name the same folders")
    func theTwoControlsAgree() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor/Day 1"))
            let crumbs = Set(Breadcrumb.pathSegments(for: url("/cards/Harbor/Day 1")).map(\.url.path))
            #expect(crumbs.allSatisfy { FolderAccess.isReachable(url($0)) })
            // The sidebar's root for this folder is in the crumbs too, so
            // the header and the tree name the same folders.
            #expect(FolderAccess.granted.allSatisfy { root in
                !FolderScanner.contains(root, url("/cards/Harbor/Day 1")) || crumbs.contains(root.path)
            })
        }
    }

    /// Hand over the card and the shoot's crumbs go back up to it, so the
    /// trim is the grant's shape rather than a flat "one crumb only".
    @Test("a wider grant gives the path bar more crumbs")
    func theTrimFollowsTheGrant() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            let names = Breadcrumb.pathSegments(for: url("/cards/Harbor/Day 1")).map(\.url.path)
            #expect(names == ["/cards/Harbor", "/cards/Harbor/Day 1"])
        }
    }

    /// The rule that undid the first fix: a path trimmed to one crumb gets
    /// its parent back so there is somewhere above to click (D-111), and that
    /// line ran after the grant trim and put the forbidden parent straight
    /// back on screen.
    @Test("the lone-crumb rule does not restore a parent outside the grant")
    func theParentRestoreRespectsTheGrant() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor/Day 1"))
            let names = Breadcrumb.pathSegments(for: url("/cards/Harbor/Day 1")).map(\.url.path)
            #expect(!names.contains("/cards/Harbor"))
        }
    }

    // MARK: Revoke All

    @Test("Revoke All takes every grant, pins included")
    func revokeAllTakesThePinsToo() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            FolderAccess.remember(url("/shoots/Headland"))
            Preferences.pin(url("/shoots/Headland"))
            let dropped = FolderAccess.revokeAll(keeping: [])
            #expect(dropped.count == 2)
            #expect(FolderAccess.granted.isEmpty)
            #expect(!FolderAccess.isReachable(url("/shoots/Headland")))
            // The pin goes too. It stayed until 2026-09-18, on the reading
            // that a pin is a place on a list and only the reach was lost;
            // that left Pinned holding a row with no root under it in the
            // sidebar, which is the one thing the Folders section is now
            // built to make impossible (D-327).
            #expect(!Preferences.isPinned(url("/shoots/Headland")))
        }
    }

    /// The difference between the two whole-list buttons, stated as a test so
    /// neither drifts into being the other: Forget keeps the pins readable,
    /// Revoke All does not.
    @Test("Revoke All and Forget Recent Folders differ on the pins")
    func theTwoWholeListButtonsAreNotTheSame() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/shoots/Headland"))
            Preferences.pin(url("/shoots/Headland"))
            Preferences.forgetHistory()
            #expect(FolderAccess.isReachable(url("/shoots/Headland")))
            FolderAccess.revokeAll(keeping: [])
            #expect(!FolderAccess.isReachable(url("/shoots/Headland")))
        }
    }

    // MARK: one list, not two

    /// A folder that is both granted and remembered appears once, under the
    /// group that says Sift can read it. Two rows for one folder is what the
    /// two sections were, and the merge is pointless if the list keeps them.
    @Test("a folder that is granted and remembered is one row, not two")
    func aFolderAppearsOnce() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            Preferences.noteRecent(url("/cards/Harbor"))
            let trail = Preferences.folderTrail
            #expect(trail.granted.map(\.path) == ["/cards/Harbor"])
            #expect(trail.remembered.isEmpty)
        }
    }

    /// And the state a reader could not see before: remembered, and not
    /// readable. This is the row that used to be in one section while its
    /// twin sat in the other.
    @Test("a revoked folder stays on the list, in the group that says why")
    func aRevokedFolderMovesGroupRatherThanVanishing() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            Preferences.noteRecent(url("/cards/Harbor"))
            FolderAccess.revoke(url("/cards/Harbor"))
            let trail = Preferences.folderTrail
            #expect(trail.granted.isEmpty)
            #expect(trail.remembered.map(\.path) == ["/cards/Harbor"])
        }
    }

    /// One control, one act. **Remove** takes the record and the grant, so
    /// the folder leaves the list rather than moving down it.
    @Test("Remove takes the record and the grant together")
    func removeTakesBoth() {
        FolderAccess.pretendingSandboxed {
            FolderAccess.remember(url("/cards/Harbor"))
            Preferences.noteRecent(url("/cards/Harbor"))
            FolderAccess.forget(path: url("/cards/Harbor"))
            let trail = Preferences.folderTrail
            #expect(trail.granted.isEmpty)
            #expect(trail.remembered.isEmpty)
            #expect(!FolderAccess.isReachable(url("/cards/Harbor")))
        }
    }

    /// The editor is an application, not a folder, and spent the life of the
    /// old list filed under "Last targets" beside three folders.
    @Test("the remembered editor is not counted as a folder")
    func theEditorIsNotAFolder() {
        Preferences.lastEditor = url("/Applications/Preview.app")
        let trail = Preferences.folderTrail
        #expect(trail.editor?.path == "/Applications/Preview.app")
        #expect(!trail.granted.contains { $0.path.hasSuffix(".app") })
        #expect(!trail.remembered.contains { $0.path.hasSuffix(".app") })
        Preferences.lastEditor = nil
    }

    // MARK: the window keeps its own controls

    /// A window with no folder still has a title bar, and therefore still
    /// has close, minimize and zoom.
    ///
    /// The toolbar was hidden whenever there was no folder, which read as
    /// tidy and was not: the window uses the unified toolbar style, where
    /// the toolbar *is* the title bar, so hiding it took the traffic lights
    /// with it. The empty state and the refusal screen both had no way to
    /// close the window but ⌘W — a capability reachable only by a keystroke,
    /// which is the rule this project states outright, broken by a line
    /// about something else. Only `bare` hides it now, which is focus mode
    /// and means it on purpose (D-150, D-326).
    @Test func theWindowKeepsItsTitleBarWithNoFolderOpen() throws {
        let view = try Repo.text("Sift/Views/RootView.swift")
        #expect(view.contains(".toolbar(bare ? .hidden : .visible, for: .windowToolbar)"),
                "the gallery hides its toolbar for something other than bare mode, which takes the traffic lights with it (D-326)")
    }

    // MARK: who owns a started scope

    /// Nothing outside `FolderAccess` starts or stops one.
    ///
    /// This is a source check because the failure it guards has no unit test
    /// in it: outside the sandbox every read succeeds, so a scope started on
    /// the wrong folder is invisible here and shows up only as a tree that
    /// cannot list its own root. It did. The first shape started a scope for
    /// the *nearest* grant covering the folder being opened and let the store
    /// hold that token, so opening a shoot inside a card you had also been
    /// given left the card's bookmark in place — reachable by every test —
    /// and its scope never started. Every grant is held open now, for as long
    /// as it exists, and the rule that keeps it that way is this one.
    @Test func onlyFolderAccessStartsAScope() throws {
        for file in ["Sift/Store/LibraryStore.swift", "Sift/Views/FolderSidebar.swift",
                     "Sift/Views/Breadcrumb.swift", "Sift/Input/CommandRouter.swift",
                     "Sift/SiftApp.swift"] {
            #expect(!(try Repo.text(file)).contains("startAccessingSecurityScopedResource"),
                    "\(file) starts a scope of its own; FolderAccess owns them (D-324)")
        }
    }

    // MARK: the store

    /// A folder the app cannot read is a state with a way forward, not an
    /// empty grid: the two looked identical and only one of them is fixed by
    /// pressing something.
    @Test("opening a folder with no grant refuses rather than showing nothing")
    func aRefusalIsAState() {
        FolderAccess.pretendingSandboxed {
            let store = LibraryStore()
            store.open(url("/cards/Harbor"))
            #expect(store.refused == url("/cards/Harbor"))
            #expect(store.folder == nil)
        }
    }

    /// Revoking while the folder is open has to close the door now, not at
    /// the next launch. A started scope outlives its bookmark, so dropping
    /// the bookmark alone would leave the folder readable for the rest of the
    /// sitting — which is exactly the failure the sandbox was adopted to end,
    /// one layer further down.
    /// A real folder on disk, because the store only holds one it managed to
    /// scan: a made-up path fails the scan and never becomes the open folder,
    /// so the revoke would have nothing to close and the test would pass by
    /// missing the thing it is about.
    @Test("revoking the open folder closes it rather than waiting for a relaunch")
    func revokingTheOpenFolderTakesEffectNow() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sift-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = FolderScanner.canonical(dir)

        FolderAccess.pretendingSandboxed {
            let store = LibraryStore()
            FolderAccess.remember(folder)
            store.open(folder)
            #expect(store.refused == nil)
            #expect(store.folder == folder)

            FolderAccess.revoke(folder)
            store.recheckAccess()
            #expect(store.folder == nil)
            #expect(store.refused == nil, "a folder you just revoked is not a folder you asked for")
        }
    }

    /// The other half of the same rule. A folder named by a person — a typed
    /// path, a recent, a crumb — is owed the reason and the way through.
    @Test("a folder somebody named draws the refusal, with its way through")
    func namingAFolderYouCannotReadExplainsItself() {
        FolderAccess.pretendingSandboxed {
            let store = LibraryStore()
            store.open(url("/cards/Harbor"))
            #expect(store.refused == url("/cards/Harbor"))
        }
    }

    /// And a folder the *app* chose is not. Resuming into a grant that has
    /// gone puts up the ordinary empty state rather than a wall about a path
    /// the reader never typed and may not recognize.
    @Test("a folder the app resumed into falls back to the empty state")
    func resumingIntoARevokedFolderSaysNothing() {
        FolderAccess.pretendingSandboxed {
            let store = LibraryStore()
            store.open(url("/cards/Harbor"), asked: false)
            #expect(store.refused == nil)
            #expect(store.folder == nil)
        }
    }

    /// Outside the sandbox there is no fence, and this type must not invent
    /// one: the suite and any build whose entitlements went missing both land
    /// here, and a broker that refused would break the first and hide the
    /// second. `bundle.sh` reads the sandbox back off the signed bundle, so
    /// the second cannot ship.
    @Test("unsandboxed, every folder is reachable and nothing is refused")
    func thereIsNoFenceWithoutTheSandbox() {
        #expect(!FolderAccess.isSandboxed)
        #expect(FolderAccess.isReachable(url("/anywhere/at/all")))
        #expect(FolderAccess.reach(url("/anywhere/at/all")) != nil)
    }
}
