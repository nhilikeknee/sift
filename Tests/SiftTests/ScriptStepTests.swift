import Testing
import Foundation
import CoreGraphics
@testable import Sift

/// The `SIFT_SCRIPT` grammar, which is how every GIF in the README was filmed.
///
/// Nothing outside this app can send it a keystroke, so a recording is the app
/// replaying `Command` raw values through its own router (D-250). That made the
/// grammar unwatched in both directions: it ran only under a recorder, and the
/// recorder only ever saw whether a clip came out. A renamed command is
/// expected here — `KeyMap` says so, because an override for a command that is
/// gone should not survive — and it silently turned a filmed step into a
/// stopped run (D-254).
@Suite struct ScriptStepTests {
    private static let root = Repo.root

    @Test func aCommandNameIsThatCommand() {
        #expect(ScriptStep.parse("flagReject") == .run(.flagReject))
        #expect(ScriptStep.parse("reviewRejects") == .run(.reviewRejects))
    }

    @Test func aBareWaitRestsWhateverTheStepIs() {
        #expect(ScriptStep.parse("wait") == .rest(milliseconds: nil))
    }

    @Test func aNumberedWaitRestsThatLong() {
        #expect(ScriptStep.parse("wait:2500") == .rest(milliseconds: 2500))
        #expect(ScriptStep.parse("wait:0") == .rest(milliseconds: 0))
    }

    @Test func aCropBoxIsFourNumbers() {
        #expect(ScriptStep.parse("cropBox:0.06 0.05 0.88 0.9")
                == .cropBox(CGRect(x: 0.06, y: 0.05, width: 0.88, height: 0.9)))
    }

    /// The adjust panel's sliders are the one control a script cannot reach
    /// through a command, so the token is the only way this clip exists.
    @Test func aKnobIsANameAndANumber() {
        #expect(ScriptStep.parse("knob:exposure 35") == .knob(.exposure, 35))
        #expect(ScriptStep.parse("knob:shadows -12.5") == .knob(.shadows, -12.5))
        #expect(ScriptStep.parse("knob:vibrance 0") == .knob(.vibrance, 0))
    }

    @Test func aKnobThatIsMisspelledOrOutOfRangeIsRefused() {
        for bad in ["knob:exposur 35", "knob:exposure", "knob:exposure 35 20",
                    "knob:exposure lots", "knob:exposure 101", "knob:exposure -101", "knob:"] {
            guard case .refused = ScriptStep.parse(bad) else {
                Issue.record("\(bad) was taken for a knob")
                return
            }
        }
    }

    /// The peek is a modifier and a pointer, so it has no command and no way in
    /// from outside the app. Three forms, one prefix.
    @Test func aPeekIsAPhotographOrOnOrOff() {
        #expect(ScriptStep.parse("peek:6") == .peek(.hover(6)))
        #expect(ScriptStep.parse("peek:0") == .peek(.hover(0)))
        #expect(ScriptStep.parse("peek:on") == .peek(.option(true)))
        #expect(ScriptStep.parse("peek:off") == .peek(.option(false)))
    }

    @Test func aPeekThatIsNeitherANumberNorOnOrOffIsRefused() {
        for bad in ["peek:", "peek:-1", "peek:yes", "peek:6 on", "peek:ON"] {
            guard case .refused = ScriptStep.parse(bad) else {
                Issue.record("\(bad) was taken for a peek")
                return
            }
        }
    }

    /// The refusals, one each. A run stops on the first of these rather than
    /// skipping the step it was made for, so each one has to be reachable.
    @Test func aTokenThatIsNotACommandIsRefused() {
        guard case .refused = ScriptStep.parse("flagRejct") else {
            Issue.record("a misspelled command was taken for one")
            return
        }
        guard case .refused = ScriptStep.parse("") else {
            Issue.record("the empty token was taken for a command")
            return
        }
    }

    @Test func aCropBoxWithTheWrongCountIsRefused() {
        for bad in ["cropBox:0.1 0.1 0.5", "cropBox:", "cropBox:0.1 0.1 0.5 0.5 0.5"] {
            guard case .refused = ScriptStep.parse(bad) else {
                Issue.record("\(bad) was taken for a crop box")
                return
            }
        }
    }

    /// `lookAt:` aims the view where `zoomIn` can only magnify it. Same four
    /// numbers as a crop box and a different destination, which is why one
    /// reader serves both.
    @Test func aLookIsFourNumbers() {
        #expect(ScriptStep.parse("lookAt:0.3 0.08 0.4 0.3")
                == .lookAt(CGRect(x: 0.3, y: 0.08, width: 0.4, height: 0.3)))
    }

    @Test func aLookWithTheWrongCountIsRefused() {
        for bad in ["lookAt:0.1 0.1 0.5", "lookAt:", "lookAt:0.1 0.1 0.5 0.5 0.5"] {
            guard case .refused = ScriptStep.parse(bad) else {
                Issue.record("\(bad) was taken for a look")
                return
            }
        }
    }

    /// A wait that cannot be read is refused, not quietly given the default
    /// step: `wait:1s` used to rest for whatever the gap between commands
    /// happened to be, and the clip came out short with nothing said.
    @Test func aWaitThatIsNotANumberIsRefused() {
        for bad in ["wait:1s", "wait:", "wait:-40", "wait:1.5"] {
            guard case .refused = ScriptStep.parse(bad) else {
                Issue.record("\(bad) was taken for a rest")
                return
            }
        }
    }

    /// The two numbers that time a run. `wait:1s` is refused inside a script
    /// and these are the same rule one layer up: the recorder works out how
    /// many seconds to film from the step and the lead it hands the app, so a
    /// step the app quietly replaced with 650 is a clip cut against a length
    /// nothing ran to. Unset is the one case that means the default (D-264).
    @Test func aStepThatIsNotAWholeNumberIsRefusedRatherThanDefaulted() {
        #expect(Launch.milliseconds(nil, or: 650, named: "SIFT_SCRIPT_STEP") == 650)
        #expect(Launch.milliseconds("450", or: 650, named: "SIFT_SCRIPT_STEP") == 450)
        #expect(Launch.milliseconds("0", or: 650, named: "SIFT_SCRIPT_STEP") == 0)
        for bad in ["1s", "650ms", "1.5", "-40", "fast"] {
            #expect(Launch.milliseconds(bad, or: 650, named: "SIFT_SCRIPT_STEP") == nil,
                    "\(bad) was taken for a gap")
        }
    }

    /// A script is one run per process. `newWindow` is a `Command` like any
    /// other, and the window it opens arrives through the same `pending`
    /// handoff that starts a script, so the second window read the same
    /// `SIFT_SCRIPT` and ran it again — opening a third (D-264).
    @MainActor
    @Test func aLaunchVariableIsClaimedOnceNoMatterHowManyWindowsAsk() {
        Launch.releaseClaims()
        defer { Launch.releaseClaims() }
        #expect(Launch.claim("SIFT_SCRIPT"), "the first window runs the script")
        #expect(!Launch.claim("SIFT_SCRIPT"), "and the window it opens does not")
        #expect(Launch.claim("SIFT_SHOW"), "a different variable is its own latch")
    }

    /// Which photograph the marks get drawn on. A number past the end of the
    /// folder used to be dropped, leaving the cursor on the first frame and the
    /// launch photographing that: a screen asked for by name that came back as
    /// a picture of something else, which is the one thing D-227 exists to stop
    /// (D-265).
    @Test func aCursorPastTheEndOfTheFolderIsRefusedRatherThanDropped() {
        #expect(Launch.index("6", within: 8, named: "SIFT_CURSOR") == 6)
        #expect(Launch.index("0", within: 8, named: "SIFT_CURSOR") == 0)
        #expect(Launch.index("7", within: 8, named: "SIFT_CURSOR") == 7)

        // Asking for nothing is not a refusal, and says nothing.
        #expect(Launch.saying { _ = Launch.index(nil, within: 8, named: "SIFT_CURSOR") }.isEmpty)
        #expect(Launch.saying { _ = Launch.index("3", within: 8, named: "SIFT_CURSOR") }.isEmpty)

        // The refusal is the outcome: the value came back nil before this fix
        // too, and the launch went on to photograph the wrong cell in silence.
        // `contact-sheet.sh` fails a capture on the prefix, so the prefix is
        // what has to be there.
        for bad in ["8", "999", "-1", "last", "3.5"] {
            let said = Launch.saying { _ = Launch.index(bad, within: 8, named: "SIFT_CURSOR") }
            #expect(said.count == 1, "\(bad) was dropped without a word")
            #expect(said.first?.hasPrefix("SIFT-REFUSED SIFT_CURSOR: ") == true,
                    "\(bad) said \(said.first ?? "nothing"), which the sheet does not read")
        }

        // The empty folder every launch variable has to survive.
        #expect(Launch.saying { _ = Launch.index("0", within: 0, named: "SIFT_CURSOR") }.count == 1)
    }

    /// Blank is how a harness says "not on this screen", and it is not a
    /// refusal (D-266).
    ///
    /// The three tests above used to list `""` among the values that get
    /// refused, and that rule was wrong rather than merely narrow. One `open`
    /// carries every launch variable and `contact-sheet.sh` blanks the ones a
    /// given screen does not want, so `SIFT_CURSOR=` and `SIFT_GRID=` go out on
    /// nearly every capture. Refusing them refused thirty screens out of
    /// thirty-two, which is the whole sheet.
    @Test func ablankLaunchVariableMeansNobodyAskedRatherThanAskedWrongly() {
        for blank in ["", " ", "  \t "] {
            #expect(Launch.asked(blank) == nil)
            #expect(!Launch.isOn(blank), "a blank SIFT_BAR pinned the preview bar up on every screen")
            #expect(Launch.saying { _ = Launch.index(blank, within: 8, named: "SIFT_CURSOR") }.isEmpty,
                    "a blank cursor was refused, and the sheet fails a capture on a refusal")
            #expect(Launch.index(blank, within: 8, named: "SIFT_CURSOR") == nil)
            #expect(Launch.saying { _ = Launch.measurement(blank, named: "SIFT_GRID") }.isEmpty)
            #expect(Launch.measurement(blank, named: "SIFT_GRID") == nil)
            #expect(Launch.saying {
                _ = Launch.milliseconds(blank, or: 650, named: "SIFT_SCRIPT_STEP")
            }.isEmpty)
            #expect(Launch.milliseconds(blank, or: 650, named: "SIFT_SCRIPT_STEP") == 650)
        }
        #expect(Launch.asked(nil) == nil)
        #expect(!Launch.isOn(nil))
        #expect(Launch.isOn("1"))
        // Whitespace around a real value is the shell's, not the reader's.
        #expect(Launch.asked(" 96 ") == "96")
        #expect(Launch.measurement(" 96 ", named: "SIFT_GRID") == 96)
    }

    /// The thumbnail step. `SIFT_GRID=big` fell through to the saved preference
    /// without a word, so a sheet came out at whatever size the last sitting
    /// left behind and read as the size that was asked for (D-265).
    @Test func aThumbnailStepThatIsNotAPositiveNumberIsRefused() {
        #expect(Launch.measurement("96", named: "SIFT_GRID") == 96)
        #expect(Launch.measurement("128.5", named: "SIFT_GRID") == 128.5)
        #expect(Launch.saying { _ = Launch.measurement(nil, named: "SIFT_GRID") }.isEmpty)
        #expect(Launch.saying { _ = Launch.measurement("96", named: "SIFT_GRID") }.isEmpty)

        for bad in ["big", "0", "-96", "96pt"] {
            let said = Launch.saying { _ = Launch.measurement(bad, named: "SIFT_GRID") }
            #expect(Launch.measurement(bad, named: "SIFT_GRID") == nil,
                    "\(bad) was taken for a thumbnail step")
            #expect(said.first?.hasPrefix("SIFT-REFUSED SIFT_GRID: ") == true,
                    "\(bad) fell through to the saved preference without a word")
        }
    }

    /// A list with whitespace and a trailing comma in it, which is what a shell
    /// heredoc folded over three lines actually hands the app.
    @Test func theListDropsTheEmptiesAndTheWhitespace() {
        #expect(Launch.list(" next , flagKeep ,, wait:900,") == ["next", "flagKeep", "wait:900"])
        #expect(Launch.list(nil).isEmpty)
        #expect(Launch.list("").isEmpty)
    }

    /// The fixture from the wild: the scenes the committed GIFs were filmed
    /// from, read out of the recorder itself. Renaming a `Command` case is a
    /// supported move, and this is the one place that says which recordings it
    /// just broke — by name, before anyone spends eleven minutes finding out.
    ///
    /// The recorder is author-only and not in the repository, so on a clone
    /// there is nothing to read and this skips. It has to skip rather than
    /// throw: a test that fails for everybody except the author is the same
    /// D-246 that took the design document's two tests down, and the grammar
    /// above is checked on every machine either way.
    @Test func everyStepOfEveryCommittedSceneStillParses() throws {
        let recorder = Self.root.appendingPathComponent("scripts/record-demo.sh")
        guard let text = try? String(contentsOf: recorder, encoding: .utf8) else { return }
        // `SCRIPT="..."` and `SETUP="..."`, with the shell's line continuations
        // folded back out, which is how the two long scenes are written.
        let folded = text.replacingOccurrences(of: "\\\n", with: "")
        let pattern = try NSRegularExpression(pattern: #"^\s*(SCRIPT|SETUP)="([^"]*)""#,
                                              options: .anchorsMatchLines)
        let range = NSRange(folded.startIndex..., in: folded)
        let matches = pattern.matches(in: folded, range: range)
        #expect(matches.count >= 8, "every scene in the recorder should have been found")

        for match in matches {
            guard let body = Range(match.range(at: 2), in: folded) else { continue }
            for token in Launch.list(String(folded[body])) {
                if case .refused(let why) = ScriptStep.parse(token) {
                    Issue.record("the recorder films \(token): \(why)")
                }
            }
        }
    }
}

/// The prefetcher's one gap, which is what `cancelAll` was written for.
@MainActor
@Suite struct PrefetchHandoffTests {
    init() { Preferences.useTestDefaults() }

    private func folder(_ names: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prefetch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in names { try Data([0xFF, 0xD8, 0xFF]).write(to: url.appendingPathComponent(name)) }
        return url
    }

    /// Walking into a folder with nothing in it leaves nothing decoding behind
    /// it. `warm` cancels what is no longer wanted, so every other move was
    /// already covered; a folder with no photographs never reaches `warm`, and
    /// the last folder's full-size decodes went on holding a megabyte each
    /// until they finished (D-254).
    @Test func anEmptyFolderStopsTheLastFoldersDecodes() throws {
        let photos = try folder(["a.jpg", "b.jpg", "c.jpg"])
        let empty = try folder([])
        defer { for url in [photos, empty] { try? FileManager.default.removeItem(at: url) } }

        let store = LibraryStore()
        store.includeSubfolders = false
        let router = CommandRouter(store: store)

        router.open(photos)
        // A folder opens with the cursor nowhere (D-141), and it is the first
        // move that warms anything. The tasks cannot start before the next
        // suspension, so what is in flight here is exact rather than a race.
        router.perform(.first)
        #expect(router.prefetcher.pending > 0, "a move warms the cursor's neighbors")

        router.open(empty)
        #expect(router.prefetcher.pending == 0, "and walking off them takes the guesses with it")
    }
}
