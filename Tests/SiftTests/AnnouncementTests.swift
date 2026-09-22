import Testing
import Foundation
@testable import Sift

/// A-11. What the app says out loud, and what it deliberately does not.
///
/// Sift reports in pixels, so a reader listening to it hears nothing: the
/// refusal is a toast and the way back is a pill in a corner. Two things speak
/// now, and the other forty-four toast sites stay quiet on purpose. Both halves
/// are held here, because "announce everything" is one line away and would talk
/// over a cull that runs at three keystrokes a second.
@Suite @MainActor struct AnnouncementTests {
    /// Stands in front of the real post and keeps what the app tried to say.
    /// `NSAccessibility.post` has no readback of any kind, so this is as close
    /// to an outcome as the suite can get.
    private func spoken(during work: (LibraryStore) -> Void) -> [(String, Announcer.Insistence)] {
        var said: [(String, Announcer.Insistence)] = []
        let real = Announcer.say
        Announcer.say = { said.append(($0, $1)) }
        defer { Announcer.say = real }
        work(LibraryStore())
        return said
    }

    @Test func aRefusalIsSaidOutLoudAndGoesInFrontOfWhateverIsBeingRead() {
        let said = spoken { $0.showError("That name is already taken.") }
        #expect(said.map(\.0) == ["That name is already taken."])
        #expect(said.first?.1 == .interrupting)
    }

    /// The other half of the owner's decision. A toast that is not a refusal is
    /// a receipt, and a receipt read out on every keystroke is worse than
    /// silence for the person culling.
    @Test func anOrdinaryToastSaysNothing() {
        let said = spoken { $0.showToast("6 pictures copied", undoable: false) }
        #expect(said.isEmpty)
    }

    /// The pill's words, which `StatusOverlay` draws and announces. The rule
    /// lived in the view until A-11 and could not be read from here.
    @Test func theWayBackNamesTheActionAndStandsDownWhileSomethingElseIsUp() {
        let store = LibraryStore()
        #expect(store.undoOffer == nil, "nothing has happened yet")

        store.pushUndo(UndoableOp(label: "Reject", inverse: .all([])))
        #expect(store.undoOffer == "Undo reject")

        store.showError("Could not rotate that one.")
        #expect(store.undoOffer == nil, "the toast is the message while it is up")
    }

    /// The decision, held where it changes. Two sites speak; a third is a
    /// product change and not a refactor, so it fails here first.
    @Test func onlyTwoPlacesInTheAppSpeak() throws {
        var sites: [String] = []
        let root = Repo.at("Sift")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 20, "the scan found almost nothing, so it is asserting nothing")
        for file in files where file.lastPathComponent != "Announcer.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("Announcer.say") {
                _ = i
                sites.append(file.lastPathComponent)
            }
        }
        // By file rather than by line: a line number fails for every edit
        // above it, which is a control that cries wolf until somebody deletes
        // it.
        #expect(sites.sorted() == ["LibraryStore.swift", "StatusOverlay.swift"], """
            the app speaks somewhere new: \(sites.sorted())
            A-11 is two announcements on purpose, the refusal and the way back.
            A third is the owner's call rather than a refactor's: add the file
            here and say why that one earns an interruption.
            """)
    }
}
