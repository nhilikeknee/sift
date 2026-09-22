import Testing
import Foundation
@testable import Sift

@Suite struct KeyMapTests {
    init() { Preferences.useTestDefaults() }

    let map = KeyMap.standard

    @Test func returnDependsOnWhichWindowIsFocused() {
        #expect(map.command(for: .returnKey, focus: .gallery) == .enterSingle)
        #expect(map.command(for: .returnKey, focus: .preview) == .confirm)
    }

    @Test func arrowsStepPhotosInThePreviewAndRowsInTheGallery() {
        #expect(map.command(for: .up, focus: .gallery) == .up)
        #expect(map.command(for: .up, focus: .preview) == .previous)
        #expect(map.command(for: .down, focus: .preview) == .next)
    }

    @Test func unmodifiedLettersAreCommands() {
        #expect(map.command(for: .char("d"), focus: .preview) == .trash)
        #expect(map.command(for: .char("p"), focus: .preview) == .flagKeep)
        #expect(map.command(for: .char("p", cmd: true), focus: .preview) == nil, "⌘ makes a different key")
    }

    /// ⌘D is the bookmark chord everywhere else, and a pin is a bookmark. It
    /// deliberately does not reach `d`, which trashes.
    @Test func commandDPinsRatherThanTrashing() {
        #expect(map.command(for: .char("d", cmd: true), focus: .gallery) == .togglePin)
        #expect(map.command(for: .char("d"), focus: .gallery) == .trash)
    }

    @Test func everyCommandHasAKey() {
        for c in Command.allCases {
            #expect(!map.keys(for: c).isEmpty, "\(c) is unbound")
        }
    }
}

@Suite struct UndoBindingTests {
    init() { Preferences.useTestDefaults() }

    let map = KeyMap.standard

    @Test func bothUndoKeysWork() {
        #expect(map.command(for: .char("z", cmd: true), focus: .gallery) == .undo)
        #expect(map.command(for: .char("z", ctrl: true), focus: .gallery) == .undo)
    }

    @Test func plainZIsZoomNotUndo() {
        #expect(map.command(for: .char("z"), focus: .preview) == .zoomToggle)
        #expect(map.command(for: .char("z"), focus: .gallery) == nil)
    }

    @Test func modifiersAreDistinct() {
        #expect(Key.char("z", cmd: true) != Key.char("z", ctrl: true))
        #expect(Key.char("z", ctrl: true).display == "⌃Z")
    }
}

@Suite struct CopyBindingTests {
    init() { Preferences.useTestDefaults() }

    let map = KeyMap.standard

    @Test func copyFileAndCopyPathAreDistinct() {
        #expect(map.command(for: .char("c", cmd: true), focus: .gallery) == .copy)
        #expect(map.command(for: .char("c", cmd: true, shift: true), focus: .gallery) == .copyPath)
        #expect(map.command(for: .char("c", cmd: true, shift: true), focus: .preview) == .copyPath)
    }

    @Test func plainCIsStillCrop() {
        #expect(map.command(for: .char("c"), focus: .preview) == .crop)
    }
}

/// The shortcuts overlay is the app's own index of itself, and it is laid out
/// as a two-column grid of groups. A row is as tall as its tallest group, so
/// one long group pushes every group after it off the first screen: "View"
/// held twenty-two commands against "Navigate"'s eight, and the filmstrip —
/// bound, listed, and sixteen rows down — was unfindable in it (D-122).
@Suite struct HelpGroupTests {
    private var sizes: [String: Int] {
        Dictionary(grouping: Command.allCases, by: \.group).mapValues(\.count)
    }

    @Test func everyGroupIsNamedInTheOrderTheOverlayDrawsThem() {
        let used = Set(Command.allCases.map(\.group))
        #expect(used == Set(Command.groups),
                "a group with commands in it and no place in the order is a group the overlay drops")
    }

    @Test func noGroupIsLongEnoughToPushTheNextRowOffTheScreen() {
        // Twelve rows plus a heading is about what the overlay's height
        // budget holds before its first row starts scrolling.
        for (group, count) in sizes {
            #expect(count <= 12, "\(group) has \(count) commands; split it the way View was")
        }
    }

    @Test func theTwoGroupsSharingARowAreComparableInHeight() {
        // Laid out left-to-right, two per row.
        for pair in stride(from: 0, to: Command.groups.count, by: 2) {
            let left = sizes[Command.groups[pair]] ?? 0
            guard pair + 1 < Command.groups.count else { continue }
            let right = sizes[Command.groups[pair + 1]] ?? 0
            let tall = max(left, right), short = min(left, right)
            #expect(tall - short <= 8,
                    "\(Command.groups[pair]) (\(left)) and \(Command.groups[pair + 1]) (\(right)) leave a hole in the grid")
        }
    }

    @Test func theFilmstripIsNearTheTopOfAShortGroup() {
        let panels = Command.allCases.filter { $0.group == "Panels" }
        #expect(panels.contains(.toggleFilmstrip))
        #expect(panels.count <= 8, "the group the filmstrip is in is long again")
    }
}

/// The reader's own keys (D-175). Serialized, because they all drive one
/// singleton and a parallel suite would read another test's overrides.
@Suite(.serialized) @MainActor struct KeyBindingTests {
    init() {
        Preferences.useTestDefaults()
        KeyBindings.shared.resetAll()
    }

    /// The anchor is on the letter it is drawn with. The grid badges the cell
    /// `A`, the tag over the photograph says `A · name`, and side by side
    /// captions its two panes A and B — so `a` is the key, and a reader who
    /// guesses from the screen is right.
    ///
    /// It was `b` for two years, from the phrase "A/B", which made the help
    /// overlay read "B — Set this photo as A". Nothing failed, because a
    /// mnemonic is not a thing a suite usually holds; this is the line that
    /// makes moving it a decision rather than an edit (D-269).
    @Test func theCompareAnchorIsOnTheLetterItIsLabeledWith() {
        let map = KeyMap.standard
        #expect(map.command(for: .char("a"), focus: .preview) == .setCompareAnchor,
                "the photo the app labels A is not set with a")
        #expect(map.command(for: .char("a"), focus: .gallery) == .setCompareAnchor,
                "the anchor is set in one window and not the other")
        // And the letter it gave up went somewhere, rather than being dropped.
        #expect(map.command(for: .char("o"), focus: .gallery) == .toggleAutoAdvance,
                "auto-advance lost its key instead of moving")
    }

    private var bindings: KeyBindings { .shared }

    /// The whole point: press the new key, get the command. And the old key
    /// stops meaning it, which is the half a table that only ever adds would
    /// get wrong.
    @Test func aReassignedCommandAnswersToTheNewKeyAndNotTheOld() {
        #expect(bindings.map.command(for: .char("."), focus: .gallery) == .toggleFavorite)

        #expect(bindings.assign(.char("y", shift: true), to: .toggleFavorite) == nil)

        #expect(bindings.map.command(for: .char("y", shift: true), focus: .gallery) == .toggleFavorite)
        #expect(bindings.map.command(for: .char("."), focus: .gallery) == nil, "the old key still fires")
        #expect(bindings.map.keys(for: .toggleFavorite).map(\.display) == ["⇧Y"])
    }

    /// The trash ships on two keys. Taking one of them is allowed, because the
    /// command it comes from still has the other.
    @Test func aKeyCanBeTakenFromACommandThatHasAnother() {
        #expect(bindings.map.keys(for: .trash).count == 2)

        #expect(bindings.assign(.char("d"), to: .toggleFavorite) == nil)

        #expect(bindings.map.command(for: .char("d"), focus: .gallery) == .toggleFavorite)
        #expect(bindings.map.keys(for: .trash).map(\.display) == ["Delete"], "the trash keeps its other key")
        #expect(bindings.map.command(for: .delete, focus: .gallery) == .trash)
    }

    /// And taking a command's only key is refused, naming what holds it, since
    /// the alternative is a command with no keystroke at all.
    @Test func takingACommandsOnlyKeyIsRefusedByName() {
        let refusal = bindings.refusal(for: .char("p"), on: .toggleFavorite)
        #expect(refusal == .wouldStrand(.flagKeep))
        #expect(refusal?.message.contains("Flag keep") == true)

        #expect(bindings.assign(.char("p"), to: .toggleFavorite) == .wouldStrand(.flagKeep))
        #expect(bindings.map.command(for: .char("p"), focus: .gallery) == .flagKeep, "nothing moved")
        #expect(!bindings.isOverridden(.toggleFavorite))
    }

    @Test func theKeysTheAppNeedsCannotBeClaimed() {
        for key in [Key.escape, .char("q", cmd: true), .char("w", cmd: true)] {
            let refusal = bindings.assign(key, to: .toggleFavorite)
            #expect(refusal != nil, "\(key.display) was taken")
            if case .reserved = refusal {} else { Issue.record("\(key.display) is not refused as reserved") }
        }
        #expect(bindings.map.command(for: .escape, focus: .preview) == .cancel)
    }

    /// A reassignment changes which key, never which window answers to it: the
    /// gallery's Return and the preview's Return are two bindings and have to
    /// stay two.
    @Test func reassigningKeepsTheWindowTheCommandBelongsTo() {
        #expect(bindings.assign(.char("j", shift: true), to: .selectAll) == nil)
        #expect(bindings.map.command(for: .char("j", shift: true), focus: .gallery) == .selectAll)
        #expect(bindings.map.command(for: .char("j", shift: true), focus: .preview) == nil,
                "select all is the gallery's")
    }

    @Test func resetPutsOneCommandBackAndResetAllPutsBackEverything() {
        #expect(bindings.assign(.char("y", shift: true), to: .toggleFavorite) == nil)
        #expect(bindings.assign(.char("t", shift: true), to: .toggleSelect) == nil)
        #expect(bindings.isOverridden(.toggleFavorite))

        bindings.reset(.toggleFavorite)
        #expect(bindings.map.command(for: .char("."), focus: .gallery) == .toggleFavorite)
        #expect(!bindings.isOverridden(.toggleFavorite))
        #expect(bindings.isOverridden(.toggleSelect), "reset is one command, not all of them")

        bindings.resetAll()
        #expect(!bindings.anyOverride)
        #expect(bindings.map.command(for: .char("s"), focus: .gallery) == .toggleSelect)
    }

    /// No override may leave a command unreachable from the keyboard, however
    /// many of them are set. The rule the refusal enforces, checked on the
    /// resolved table rather than on the refusal.
    /// The README points at `?` for the shortcuts, and that pointer is the
    /// only thing in the file that says the help overlay exists.
    ///
    /// It used to name the count — *all 89 of them* — and this test held that
    /// number against `KeyMap.standard.bindings.count`, because it had been
    /// written by hand once and had no way of noticing two more bindings
    /// arriving. The count is gone from the README now, which closes the same
    /// hole one step earlier: a number that has to be kept true is worse than
    /// a sentence that cannot go stale. What is left to check is the pointer,
    /// because the overlay is a keystroke and a reader who is not told about
    /// it has no way in from this page.
    @Test func theReadmeSaysWhichKeyOpensTheShortcuts() throws {
        // The bool first, not `text.contains(…)` inside the macro: the macro
        // prints its operands, and the operand there is the whole README.
        let pointsAtTheKey = try Repo.text("README.md")
            .contains("Press `?` in the app for all keyboard shortcuts.")
        #expect(pointsAtTheKey,
                "the README stopped telling anybody how to see the shortcuts; run `grep 'Press .?.' README.md`")
    }

    @Test func noCommandIsLeftWithoutAKey() {
        #expect(bindings.assign(.char("d"), to: .toggleFavorite) == nil)
        #expect(bindings.assign(.char("y", shift: true), to: .toggleSelect) == nil)
        for c in Command.allCases {
            #expect(!bindings.map.keys(for: c).isEmpty, "\(c) was left unbound")
        }
    }

    /// What is written to disk has to come back as the same keystroke,
    /// including the characters that are also the obvious delimiters.
    @Test func everyKeyShapeSurvivesBeingWrittenDown() {
        let keys: [Key] = [.char("z"), .char("z", cmd: true, shift: true, ctrl: true),
                           .char("-"), .char(":"), .char("+"), .char("\\"), .char("|"), .char(" "),
                           .escape, .delete, .tab(shift: true), .code(124, cmd: true)]
        for key in keys {
            #expect(Key(stored: key.stored) == key, "\(key.display) did not survive \(key.stored)")
        }
        #expect(Key(stored: "") == nil)
        #expect(Key(stored: "abc:char:z") == nil)
        #expect(Key(stored: "000:char:zz") == nil)
    }

    /// The stored form is what a later launch reads, so the round trip is
    /// through `Preferences` rather than through the object that wrote it.
    @Test func anOverrideComesBackFromPreferences() {
        #expect(bindings.assign(.char("y", shift: true), to: .toggleFavorite) == nil)

        let stored = Preferences.keyOverrides
        #expect(stored["toggleFavorite"] == [Key.char("y", shift: true).stored])

        let reloaded = KeyMap.standard.applying(
            stored.reduce(into: [:]) { out, pair in
                guard let c = Command(rawValue: pair.key) else { return }
                out[c] = pair.value.compactMap(Key.init(stored:))
            })
        #expect(reloaded.command(for: .char("y", shift: true), focus: .gallery) == .toggleFavorite)
    }

    @Test func aStoredOverrideForACommandThatIsGoneIsIgnored() {
        Preferences.keyOverrides = ["noSuchCommand": ["000:char:q"], "toggleFavorite": ["nonsense"]]
        let overrides = Preferences.keyOverrides.reduce(into: [Command: [Key]]()) { out, pair in
            guard let c = Command(rawValue: pair.key) else { return }
            let keys = pair.value.compactMap(Key.init(stored:))
            if !keys.isEmpty { out[c] = keys }
        }
        #expect(overrides.isEmpty)
        #expect(KeyMap.standard.applying(overrides).command(for: .char("."), focus: .gallery) == .toggleFavorite)
    }
}
