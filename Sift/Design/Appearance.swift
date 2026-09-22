import AppKit

/// Which of the two palettes in `Tokens` the app draws with. Three states and
/// not two: `system` is the default because a Mac that goes dark at dusk should
/// take Sift with it, and the other two exist for the times the surround the
/// photographs are being judged against matters more than the rest of the
/// desktop does (D-112).
enum Appearance: String, CaseIterable, Sendable {
    case system, light, dark

    /// What the control says it will do, in the words the menu shows.
    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil hands the choice back to AppKit, which is what `system` means.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// The setting this launch starts in. `SIFT_APPEARANCE=light` overrides the
    /// stored preference for one run without writing it, which is what the
    /// contact sheet needs: it shoots every screen twice, and a script that set
    /// the real preference would leave the reader's app in whichever palette it
    /// happened to finish on. Read once, like `SIFT_SHOW` and
    /// `SIFT_WINDOW_REPORT`, and inert on every launch that is not a screenshot
    /// (D-112, D-118).
    ///
    /// The override is not written back because nothing assigns to
    /// `AppModel.appearance` during launch; the first assignment is a reader
    /// picking from the menu, and at that point they mean it.
    static var atLaunch: Appearance {
        guard let name = ProcessInfo.processInfo.environment["SIFT_APPEARANCE"] else {
            return Preferences.appearance
        }
        guard let forced = Appearance(rawValue: name) else {
            Launch.refuse("SIFT_APPEARANCE", "no appearance called \(name)")
            return Preferences.appearance
        }
        return forced
    }
}
