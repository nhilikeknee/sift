import Testing
import Foundation
@testable import Sift

/// A switched-off feature leaves nothing behind (D-123). Four places have to
/// agree, and the whole value of the switch is that they do: a key that
/// silently does nothing is a bug report, and a row still listed in the
/// shortcuts overlay is the feature taking the room it was turned off for.
@Suite struct FeatureTests {
    init() { FileOps.useTestBackups() }

    private let map = KeyMap.standard

    /// Rewritten for D-129. It used to read "every feature", and the rule it
    /// was holding is still the rule: a switch nobody has touched leaves the
    /// feature on. What changed is that there is now a second way to say
    /// otherwise, and it is not a preference. An unreleased feature is off
    /// under `FeatureSet.everything` too, which is the point of it.
    @Test func everyReleasedFeatureIsOnUntilSomebodySaysOtherwise() {
        for feature in Feature.allCases where !Feature.unreleased.contains(feature) {
            #expect(FeatureSet.everything.isOn(feature))
        }
    }

    /// Off for everybody, by every route into the set. A stored preference
    /// saying it is on is a plist somebody edited or a preference left behind
    /// by a build where it was released; neither is permission to ship it.
    @Test func anUnreleasedFeatureCannotBeSwitchedOn() {
        for feature in Feature.unreleased {
            #expect(!FeatureSet.everything.isOn(feature))
            #expect(!FeatureSet(off: []).isOn(feature))
            var set = FeatureSet(off: [feature])
            set.set(feature, on: true)
            #expect(!set.isOn(feature), "\(feature) came back on")
        }
    }

    /// The whole reason the set exists: nothing reaches it. `SIFT_SHOW` still
    /// does, deliberately, because that path is the development one and is not
    /// available to a reader (D-129).
    @Test func anUnreleasedFeaturesCommandsAreOutOfReach() {
        for feature in Feature.unreleased {
            let governed = Command.allCases.filter { $0.features == [feature] }
            #expect(!governed.isEmpty, "\(feature) governs no command, so shelving it does nothing")
            for command in governed {
                #expect(!FeatureSet.everything.allows(command))
                for key in map.keys(for: command) {
                    for focus in [WindowFocus.gallery, .preview] {
                        #expect(map.command(for: key, focus: focus) != command,
                                "\(key.display) still reaches \(command)")
                    }
                }
            }
        }
    }

    @Test func aCommandWithNoFeatureIsAlwaysAllowed() {
        let nothingOn = FeatureSet(off: Set(Feature.allCases))
        for command in Command.allCases where command.features.isEmpty {
            #expect(nothingOn.allows(command), "\(command) is the app, not a feature of it")
        }
    }

    /// The five that are the job. If one of these ever grows a feature, the
    /// app can be configured into not being a photo culler.
    @Test func theCullItselfHasNoSwitch() {
        for command in [Command.flagKeep, .flagReject, .trash, .undo, .next, .previous] {
            #expect(command.features.isEmpty, "\(command) must not be switchable")
        }
    }

    /// Rewritten for D-239, deliberately: it read `$0.feature == feature` and
    /// there is no longer one feature per command. ⇧Return and ⇧R belong to
    /// crop *and* adjust, and switching one of the two off must leave them
    /// reachable — which is what `aCommandTwoFeaturesShareSurvivesOneOfThem`
    /// below holds them to. This one is about the commands a switch governs
    /// alone, which is every other one.
    @Test func switchingOneOffTakesItsKeysWithIt() {
        for feature in Feature.allCases {
            let off = FeatureSet(off: [feature])
            let governed = Command.allCases.filter { $0.features == [feature] }
            #expect(!governed.isEmpty, "\(feature) governs no command, so its switch does nothing")

            for command in governed {
                for key in map.keys(for: command) {
                    for focus in [WindowFocus.gallery, .preview] {
                        #expect(map.command(for: key, focus: focus, features: off) != command,
                                "\(key.display) still reaches \(command) with \(feature) off")
                    }
                }
                #expect(!off.allows(command))
            }
        }
    }

    @Test func switchingOneOffLeavesEveryOtherKeyAlone() {
        let off = FeatureSet(off: [.crop])
        for command in Command.allCases where !command.features.contains(.crop) {
            for key in map.keys(for: command) {
                for focus in [WindowFocus.gallery, .preview] {
                    // Whatever this key did before, it still does.
                    #expect(map.command(for: key, focus: focus, features: off)
                            == map.command(for: key, focus: focus),
                            "turning crop off changed what \(key.display) means")
                }
            }
        }
    }

    /// The overlay and the palette both filter on `allows`, so this is the
    /// shape of what they will show.
    @Test func theShortcutsOverlayHasNoLineForSomethingSwitchedOff() {
        let off = FeatureSet(off: [.tournament, .slideshow])
        let listed = Command.allCases.filter { off.allows($0) }
        #expect(!listed.contains(.tournament))
        #expect(!listed.contains(.slideshow))
        #expect(listed.contains(.survey), "one switch is not all of them")
        #expect(listed.contains(.flagKeep))
    }

    @Test func everyFeatureSaysWhatItIsFor() {
        for feature in Feature.allCases {
            #expect(!feature.label.isEmpty)
            #expect(feature.explanation.count > 20,
                    "\(feature) has a name and no sentence; a switch with only a name makes the reader turn it on to find out")
            #expect(feature.explanation.hasSuffix("."), "\(feature)'s explanation is a sentence")
        }
    }

    @Test func theSetRoundTripsThroughItsStoredForm() {
        var set = FeatureSet()
        set.set(.crop, on: false)
        set.set(.faces, on: false)
        set.set(.crop, on: true)
        #expect(set.off == [.faces])
        #expect(set.isOn(.crop))
        // Stored as the exceptions, so a feature added later starts on.
        #expect(FeatureSet(off: set.off).isOn(.survey))
    }
}

/// Switching a feature off while it is running has to put it away, or the
/// highlights stay painted on the photograph with no control left to clear
/// them (D-5, D-123).
@Suite @MainActor struct FeatureStandDownTests {
    private func storeInEveryMode() -> LibraryStore {
        let store = LibraryStore()
        store.showClipping = true
        store.showFocusPeaking = true
        store.surveying = true
        store.sideBySide = true
        store.showingCompare = true
        store.compareAnchor = URL(fileURLWithPath: "/tmp/a.jpg")
        store.tournament = true
        store.champion = URL(fileURLWithPath: "/tmp/b.jpg")
        store.cropping = true
        store.slideshow = true
        store.faces = []
        return store
    }

    @Test func turningEverythingOffLeavesNoModeRunning() {
        let store = storeInEveryMode()
        store.standDown(FeatureSet(off: Set(Feature.allCases)))

        #expect(!store.showClipping)
        #expect(!store.showFocusPeaking)
        #expect(!store.surveying)
        #expect(!store.sideBySide)
        #expect(!store.showingCompare)
        #expect(store.compareAnchor == nil)
        #expect(!store.tournament)
        #expect(store.champion == nil, "a switch is not the reader saying this frame won")
        #expect(!store.cropping)
        #expect(!store.slideshow)
    }

    @Test func turningOneOffLeavesTheOthersRunning() {
        let store = storeInEveryMode()
        store.standDown(FeatureSet(off: [.highlights]))

        #expect(!store.showClipping)
        #expect(store.surveying, "survey was not the switch that moved")
        #expect(store.cropping)
        #expect(store.tournament)
    }

    @Test func withEverythingOnNothingIsPutAway() {
        let store = storeInEveryMode()
        store.standDown(.everything)

        #expect(store.showClipping)
        #expect(store.surveying)
        #expect(store.cropping)
        #expect(store.slideshow)
    }
}

/// What a new reader sees. The switches shipped all-on and the bar was
/// unchanged until somebody went and found Settings, which is not a default,
/// it is homework (D-124).
@Suite struct FeatureDefaultTests {
    /// Rewritten for D-236, deliberately: this read `fiveFeaturesStartOff` and
    /// named `crop` among them. Crop is a thing you do to a frame you are
    /// keeping, which puts it with rotate and adjust rather than with the four
    /// that ask which frame is better, and a basic edit behind a preference
    /// nobody opens reads as a missing feature.
    @Test func fourFeaturesStartOff() {
        let fresh = FeatureSet(off: Feature.offByDefault)
        #expect(Feature.offByDefault.count == 4)
        for feature in [Feature.survey, .tournament, .focusPeaking, .slideshow] {
            #expect(!fresh.isOn(feature), "\(feature) should start off")
        }
    }

    /// Everything a new reader gets, and the argument for each is in
    /// `Feature.offByDefault`'s comment. This is where it changes.
    @Test func theOnesACullUsesStayOn() {
        let fresh = FeatureSet(off: Feature.offByDefault)
        #expect(fresh.isOn(.compare), "comparing two frames is the job")
        #expect(fresh.isOn(.highlights), "judging an exposure is judging the photograph")
        #expect(fresh.isOn(.faces), "it draws nothing unless there is a face, so it costs the bar nothing")
        #expect(fresh.isOn(.bare), "taking the chrome away is what the preview window is for")
        #expect(fresh.isOn(.crop), "a crop is what you do to a frame you are keeping, like a rotate (D-236)")
        #expect(fresh.isOn(.adjust), "the same argument, and the one it was first made for (D-161)")
    }

    /// The sentence the shortcuts overlay shows is the set, not a copy of it
    /// (D-236). It used to be typed out and named crop after crop came on.
    @Test func theOverlaySentenceNamesExactlyWhatStartsOff() {
        let sentence = Feature.offByDefaultSentence
        for feature in Feature.allCases {
            let named = sentence.localizedCaseInsensitiveContains(feature.label)
            #expect(named == Feature.offByDefault.contains(feature),
                    "the overlay \(named ? "names" : "does not name") \(feature.label), which is wrong")
        }
        // Readable English, not a debug dump of a Set.
        #expect(sentence.contains(" and "))
        #expect(!sentence.contains("["))
    }

    /// The three edits a kept frame gets are reachable together or the set is
    /// arbitrary. Rotate is not a `Feature` at all — it is always there — so
    /// the other two starting off was the odd one out rather than the rule.
    @Test func everyEditAKeptFrameGetsIsOnOutOfTheBox() {
        let fresh = FeatureSet(off: Feature.offByDefault)
        for command in [Command.crop, .adjust, .rotateCW, .rotateCCW] {
            #expect(command.features.allSatisfy { fresh.isOn($0) },
                    "\(command) is behind a switch that starts off")
            #expect(!KeyMap.standard.keys(for: command).isEmpty, "\(command) has no key")
        }
    }

    /// A feature with no bar button still needs a way in that is not a key
    /// (D-42). Bare's is its View menu item, and this is the reminder that
    /// anything added to the set owes the same.
    @Test func aFeatureKeptOutOfTheBarStillHasAKey() {
        for feature in Feature.notInThePreviewBar {
            let governed = Command.allCases.filter { $0.features.contains(feature) }
            #expect(governed.allSatisfy { !KeyMap.standard.keys(for: $0).isEmpty },
                    "\(feature) has no bar button and no key either")
        }
        #expect(Feature.notInThePreviewBar.isSubset(of: Set(Feature.allCases)))
    }

    /// ⇧Return saves a crop or an adjustment into the photograph and ⇧R takes
    /// either one off again, so each belongs to both features and neither
    /// switch alone can take it away. It was `adjustInPlace`, governed by
    /// adjust, which meant a reader who switched the sliders off lost the key
    /// that saves a crop over the original — a crop feature turned off by the
    /// adjust switch (D-239).
    @Test func aCommandTwoFeaturesShareSurvivesOneOfThem() {
        let shared: [Command] = [.saveOverOriginal, .revertToOriginal]
        for command in shared {
            #expect(command.features == [.crop, .adjust], "\(command) is not the shared pair any more")
            #expect(FeatureSet(off: [.adjust]).allows(command), "the adjust switch took \(command)")
            #expect(FeatureSet(off: [.crop]).allows(command), "the crop switch took \(command)")
            #expect(!FeatureSet(off: [.crop, .adjust]).allows(command),
                    "\(command) is still on offer with nothing to save into the photo")
            for key in KeyMap.standard.keys(for: command) {
                #expect(KeyMap.standard.command(for: key, focus: .preview,
                                                features: FeatureSet(off: [.adjust])) == command,
                        "\(key.display) stopped reaching \(command) with adjust off")
                #expect(KeyMap.standard.command(for: key, focus: .preview,
                                                features: FeatureSet(off: [.crop, .adjust])) != command,
                        "\(key.display) still reaches \(command) with both off")
            }
        }
    }

    @Test func theDefaultIsNotTheSameAsEverythingOn() {
        #expect(FeatureSet(off: Feature.offByDefault) != .everything,
                "if these ever match, the switches ship doing nothing again")
    }
}

/// Serialized and restoring what it found: writes a preference, and the
/// scratch domain is shared across suites (tech debt 25).
@Suite(.serialized) @MainActor struct FeaturePreferenceTests {
    init() { Preferences.useTestDefaults() }

    @Test func anUntouchedInstallGetsTheDefaultAndATouchedOneGetsItsOwn() {
        let was = Preferences.featuresOff
        defer { Preferences.featuresOff = was }

        Preferences.forget(["featuresOff"])
        #expect(Preferences.featuresOff == Feature.offByDefault,
                "absent means nobody has touched a switch, not that all of them are on")

        // Turning everything on is a real answer and has to survive a launch.
        Preferences.featuresOff = []
        #expect(Preferences.featuresOff.isEmpty,
                "a reader who switched them all on does not get the default back")
    }
}
