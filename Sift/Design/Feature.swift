import Foundation

/// A part of the app that can be switched off in Settings.
///
/// Only the ones that are not the job. Keep, reject, trash, undo, the arrows,
/// zoom, the info panel and the filmstrip have no switch: an app that can be
/// configured into not being a photo culler is a preference nobody wants and
/// a state nobody can support. What is here is the specialist half — the ways
/// of comparing two frames, the two overlays that paint on the picture, and
/// the three that are about showing rather than deciding.
///
/// Off means gone, not hidden. No button in the preview bar, no key in the
/// map, no line in the shortcuts overlay, no row in the command palette, no
/// item in the menus. Half-off is worse than either: a key that silently does
/// nothing is a bug report, and a grayed row is the feature still taking up
/// the space it was turned off for (D-123).
enum Feature: String, CaseIterable, Sendable, Hashable {
    case compare, survey, tournament, bare, highlights, focusPeaking, faces, crop, adjust, slideshow, summary

    /// Off until somebody turns it on.
    ///
    /// Four of the eight, and the test is what a cull needs rather than what
    /// is clever. Comparing two frames is the job, so `compare` stays.
    /// Judging an exposure is judging the photograph, so `highlights` stays.
    /// `faces` stays because it draws nothing at all unless there is a face
    /// in the frame, so it costs the bar nothing on the photographs it does
    /// not apply to.
    ///
    /// The four that are off are modes you enter *instead of* deciding: each
    /// one asks "which of these frames is the better one", and each was a word
    /// sitting on every photograph for the fraction of a cull that ever uses
    /// it. Settings is where they are found, which is why every row there
    /// carries a sentence and its keys (D-124).
    ///
    /// **`crop` and `adjust` are the two that are modes and are still on**,
    /// because they are not that kind of mode. They are what you do to a frame
    /// you are keeping, which puts them with rotate — and rotate is not a
    /// switch at all. Crop was off until D-236 on the reading that a mode is a
    /// mode; the reading that replaced it is that straightening a horizon and
    /// taking a pole out of the corner are the same kind of work as turning a
    /// photograph the right way up, and hiding one of the three behind a
    /// preference nobody opens is what made it look missing. Adjust had the
    /// same argument from the start: the question it answers — is this frame a
    /// keeper, or is it only too dark to tell — is asked during a cull rather
    /// than instead of one, and a slider nobody can find is a frame thrown
    /// away for being underexposed (D-161).
    static let offByDefault: Set<Feature> = [.survey, .tournament, .focusPeaking, .slideshow]

    /// The same set as a run of words, for the one sentence in the shortcuts
    /// overlay that has to name them (D-236). It lives here rather than in the
    /// view because it *is* the set: typed out over there it went on naming
    /// crop for as long as it took somebody to notice.
    ///
    /// In `allCases` order, so the sentence does not reshuffle itself between
    /// launches the way a `Set`'s own order would.
    static var offByDefaultSentence: String {
        let names = allCases.filter { offByDefault.contains($0) }.map { $0.label.lowercased() }
        guard let last = names.last else { return "none" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Not finished, so not on offer. An unreleased feature is off for
    /// everybody, has no row in Settings, and cannot be switched on from
    /// inside the app: it is the app's own half-built work, not a preference.
    ///
    /// This is a stronger statement than `offByDefault`, which says "most
    /// people will not want this" and leaves the choice on the table. There is
    /// no choice here, so there is no switch to leave grayed out, which is
    /// D-123's rule applied to the one case it did not cover. Releasing it is
    /// taking it out of this set; the code, its tests and its screen stay where
    /// they are meanwhile, and `SIFT_SHOW` still reaches it so work can carry
    /// on (D-129).
    static let unreleased: Set<Feature> = [.summary]

    /// Features with no button in the preview bar even while they are on.
    /// The bar is drawn over a photograph, and a mode you enter with a key
    /// and leave with Esc does not need a word sitting there the rest of the
    /// time. They keep their menu item, which is the on-screen way in (D-126).
    static let notInThePreviewBar: Set<Feature> = [.bare]

    /// What the switch says.
    var label: String {
        switch self {
        case .compare: "Compare"
        case .survey: "Survey"
        case .tournament: "Tournament"
        case .bare: "Bare"
        case .highlights: "Blown highlights"
        case .focusPeaking: "Focus peaking"
        case .faces: "Faces"
        case .crop: "Crop"
        case .adjust: "Adjust"
        case .slideshow: "Slideshow"
        case .summary: "Summary"
        }
    }

    /// What it is for, in the words somebody deciding would use. A switch with
    /// only a name on it makes the reader open the feature to find out whether
    /// they want it, which is the opposite of what a settings screen is for.
    var explanation: String {
        switch self {
        case .compare: "Mark one frame as A, then flip to it or put it side by side with another."
        case .survey: "Up to six frames at once, at whatever size fits."
        case .tournament: "Hold the best so far and show it the next one, until one is left."
        case .bare: "Take everything off the preview window except the photograph, on a black ground."
        case .highlights: "Paint the pixels that have blown out."
        case .focusPeaking: "Paint the edges the lens actually resolved."
        case .faces: "Find faces in the frame and zoom to each in turn."
        case .crop: "Drag a box, in any shape or held to a ratio; Return writes a cropped copy beside the original and ⇧Return writes the crop into it."
        case .adjust: "Ten sliders beside the photograph; Return writes an adjusted copy beside the original and ⇧Return writes the adjustment into it."
        case .slideshow: "Full screen, one frame every few seconds."
        case .summary: "What this sitting did, and where the folder stands."
        }
    }
}

/// Which features are on. A value rather than a read of `UserDefaults`, so a
/// test hands one in instead of writing preferences and a view observes it
/// instead of polling (D-86, D-123).
struct FeatureSet: Sendable, Equatable {
    /// Stored as the exceptions, so a feature added later starts on without
    /// migrating anybody's stored set.
    private(set) var off: Set<Feature>

    init(off: Set<Feature> = []) { self.off = off }

    static let everything = FeatureSet()

    /// `SIFT_FEATURES_OFF=compare,crop` for one launch, without writing the
    /// preference — the same trick `SIFT_APPEARANCE` uses, and for the same
    /// reason: the contact sheet has to photograph a thinned preview bar
    /// without leaving the reader's app thinned (D-118, D-123).
    static var atLaunch: FeatureSet {
        guard let list = ProcessInfo.processInfo.environment["SIFT_FEATURES_OFF"], !list.isEmpty else {
            return FeatureSet(off: Preferences.featuresOff)
        }
        var off: Set<Feature> = []
        for name in Launch.list(list) {
            guard let feature = Feature(rawValue: name) else {
                Launch.refuse("SIFT_FEATURES_OFF", "no feature called \(name)")
                continue
            }
            off.insert(feature)
        }
        return FeatureSet(off: off)
    }

    /// Unreleased beats everything, including a stored preference and
    /// `FeatureSet.everything`. A half-built feature that a hand-edited plist
    /// or a test helper can switch on is a feature that ships by accident.
    func isOn(_ feature: Feature) -> Bool {
        !Feature.unreleased.contains(feature) && !off.contains(feature)
    }

    mutating func set(_ feature: Feature, on: Bool) {
        if on { off.remove(feature) } else { off.insert(feature) }
    }

    /// Whether a command is reachable at all. A command with no feature behind
    /// it is always reachable; that is most of them. One with more than one is
    /// reachable while any of them is on, because a command two features share
    /// is gone only when both are (D-239).
    func allows(_ command: Command) -> Bool {
        command.features.isEmpty || command.features.contains { isOn($0) }
    }
}
