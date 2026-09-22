import Testing
import AppKit
import SwiftUI
@testable import Sift

/// Light, dark, and the desktop's choice (D-112).
///
/// Serialized: two tests here write `Preferences.appearance`, and the suites
/// share one scratch domain, so in parallel each reads the other's value (tech
/// debt 25). Anything that writes a preference states this.
@Suite(.serialized) struct AppearanceTests {
    init() { Preferences.useTestDefaults() }

    @Test func matchingTheSystemHandsTheChoiceBackToAppKit() {
        #expect(Appearance.system.nsAppearance == nil)
        #expect(Appearance.light.nsAppearance?.name == .aqua)
        #expect(Appearance.dark.nsAppearance?.name == .darkAqua)
    }

    @Test func theSettingSurvivesALaunch() {
        let before = Preferences.appearance
        defer { Preferences.appearance = before }
        Preferences.appearance = .light
        #expect(Preferences.appearance == .light)
    }

    @Test func anUnsetPreferenceMatchesTheSystem() {
        let before = Preferences.appearance
        defer { Preferences.appearance = before }
        Preferences.appearance = .system
        #expect(Preferences.appearance == .system, "the default is the desktop's choice, not a guess at one")
    }
}

/// Every color token answers in both palettes, and the ones that deliberately
/// do not follow the theme stay put (D-112).
@Suite @MainActor struct ColorTokenTests {
    private func rgb(_ color: Color, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            out = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        return out
    }

    /// Reads back the color that would actually be painted, in both palettes,
    /// rather than the branch the token file says it takes.
    private func differs(_ color: Color) -> Bool {
        let light = rgb(color, dark: false)
        let dark = rgb(color, dark: true)
        let dr: CGFloat = abs(light.r - dark.r)
        let dg: CGFloat = abs(light.g - dark.g)
        let db: CGFloat = abs(light.b - dark.b)
        return dr + dg + db > 0.01
    }

    @Test func theSurfacesAndTextChangeWithTheTheme() {
        #expect(differs(Tokens.Surface.canvas))
        #expect(differs(Tokens.Surface.chrome))
        #expect(differs(Tokens.Surface.raised))
        #expect(differs(Tokens.Surface.sunken))
        #expect(differs(Tokens.Text.primary))
        #expect(differs(Tokens.Text.secondary))
        #expect(differs(Tokens.Border.selected))
    }

    @Test func theCanvasIsLightInLightAndDarkInDark() {
        #expect(rgb(Tokens.Surface.canvas, dark: false).r > 0.8, "the light canvas is near white")
        #expect(rgb(Tokens.Surface.canvas, dark: true).r < 0.2, "the dark canvas is near black")
        #expect(rgb(Tokens.Text.primary, dark: false).r < 0.2)
        #expect(rgb(Tokens.Text.primary, dark: true).r > 0.8)
    }

    @Test func theJudgingSurfaceStaysDarkInBoth() {
        // D-62: the one moment the app takes everything else away is not the
        // moment to follow the system into a light gray.
        #expect(rgb(Tokens.Surface.judging, dark: false).r < 0.15)
        #expect(rgb(Tokens.Surface.judging, dark: true).r < 0.15)
    }

    @Test func theHeartsKeylineStaysNearWhiteInBoth() {
        // D-58: it is painted over photographs, and a photograph has no theme.
        #expect(rgb(Tokens.State.favoriteKeyline, dark: false).r > 0.9)
        #expect(rgb(Tokens.State.favoriteKeyline, dark: true).r > 0.9)
    }

    @Test func everyColorLabelHasItsOwnPairOfHues() {
        for label in ColorLabel.allCases {
            #expect(differs(Tokens.State.label(label)), "\(label) is one color in both themes")
        }
    }
}

/// The readability floors, in both palettes. Numbers rather than judgment:
/// the design document asks for 4.5:1 on text and 3:1 on marks, and a theme nobody had
/// looked at is exactly where a pair drifts under (D-112).
/// `.serialized` because this suite flips `Tokens.increaseContrast`, a
/// process-global, and puts it back with a `defer`. Nothing raced before it
/// said so: the flip and the restore sit inside a synchronous `@MainActor`
/// function, which has no suspension point, so no other main-actor test can
/// run between them. That is the *absence* of an `await` doing the work —
/// a property nobody stated and the next edit could remove without noticing.
/// `SandboxTests` is serialized for the same class of reason (S-29).
@Suite(.serialized) @MainActor struct ContrastTests {
    private func components(_ color: Color, dark: Bool, highContrast: Bool = false) -> (CGFloat, CGFloat, CGFloat) {
        // The appearance cannot carry this: `NSAppearance(named:
        // .accessibilityHighContrastDarkAqua)` reports itself as plain
        // `darkAqua`, so asking for the high-contrast appearance and reading
        // the color back measured the ordinary value and passed nothing. The
        // seam is what the app actually reads (D-340).
        let previous = Tokens.increaseContrast
        defer { Tokens.increaseContrast = previous }
        Tokens.increaseContrast = { highContrast }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            out = (c.redComponent, c.greenComponent, c.blueComponent)
        }
        return out
    }

    /// The same, and the alpha it was throwing away (D-341).
    private func opacity(_ color: Color, dark: Bool, highContrast: Bool = false) -> CGFloat {
        let previous = Tokens.increaseContrast
        defer { Tokens.increaseContrast = previous }
        Tokens.increaseContrast = { highContrast }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var a: CGFloat = 1
        appearance.performAsCurrentDrawingAppearance {
            a = NSColor(color).usingColorSpace(.sRGB)!.alphaComponent
        }
        return a
    }

    /// The cursor ring in the filmstrip is two tones so that a photograph
    /// cannot swallow both (D-178). The rule is not "they differ", it is that
    /// they sit on opposite sides of mid-gray: whatever a frame's edge happens
    /// to be, it is far from one of them.
    ///
    /// Asserted against black and white rather than against each other,
    /// because two colors can be far apart and still both be light.
    ///
    /// **The upper bound was 10 and is now mid-gray, rewritten rather than
    /// loosened (D-341).** The keyline is 65% opaque and `ratio` was reading
    /// its channels with the alpha thrown away, so the number under test was
    /// `#F0F0F0` against black — 18.4:1, a color nobody ever sees. Composited,
    /// the light tone measures 7.6:1, and 10 was never a claim about anything.
    /// The rule this test exists for is the one in the sentence above: the two
    /// tones sit on *opposite sides of mid-gray*. So that is the threshold now,
    /// and it is derived rather than tuned — `#777777` is 4.7:1 against black.
    /// The light tone clears it with room; the point is that the number means
    /// something.
    @Test func theCursorRingsTwoTonesCannotBothBeLostOnOnePhotograph() {
        // Mid-gray against black. Anything lighter than this is on the light
        // side of the divide, anything darker is on the dark side.
        let midGray = 4.7
        for dark in [false, true] {
            let ring = ratio(Tokens.Border.selected, .black, dark: dark)
            let keyline = ratio(Tokens.Border.cursorKeyline, .black, dark: dark)
            // One of the pair is near black and the other near white, so one
            // ratio against black is small and the other large.
            #expect(min(ring, keyline) < 3, "both tones are light in \(dark ? "dark" : "light")")
            #expect(max(ring, keyline) > midGray, "both tones are dark in \(dark ? "dark" : "light")")
            // And the ring itself has to read against the strip it sits on.
            #expect(ratio(Tokens.Border.selected, Tokens.Surface.chrome, dark: dark) >= 3,
                    "the ring is lost on the strip's own chrome in \(dark ? "dark" : "light")")
        }
    }

    /// The key chip has to be visible on a row this app does not draw.
    ///
    /// Settings' Keyboard tab is a grouped `Form`, so the ground under each
    /// chip is AppKit's and no token describes it. The chip used
    /// `Surface.canvas`, which is tuned against the photo grid: `#303030` on a
    /// dark Form row is 1.01:1, a box that is not faint but absent. What a
    /// screenshot showed was the Form's own row edge (D-312).
    ///
    /// The two grounds are sampled from a real window rather than guessed, the
    /// way `bg.cursor`'s step was (D-117). They are constants here because the
    /// system owns them: if a macOS release retunes a grouped Form, this test
    /// is where that is noticed, and the right response is to sample again
    /// rather than to lower the floor.
    ///
    /// The floors are what the platform does, not WCAG: 1.4.11 asks 3:1 of a
    /// boundary that carries meaning, and neither Apple's own controls nor any
    /// keycap in this class reaches that with a fill. The information is in
    /// the letters, which clear 4.5 on the chip, and the chip carries a
    /// hairline besides. What is held here is that the box is *there*.
    @Test func theKeyChipIsVisibleOnTheFormItSitsOn() {
        // Sampled from Settings' Keyboard tab, both palettes, 2026-09-18.
        let formRow: [(dark: Bool, ground: Color, floor: Double)] = [
            (true, Color(red: 49 / 255, green: 46 / 255, blue: 45 / 255), 1.4),
            (false, Color(red: 235 / 255, green: 233 / 255, blue: 232 / 255), 1.15),
        ]
        for (dark, ground, floor) in formRow {
            let measured = ratio(Tokens.Surface.keyCap, ground, dark: dark)
            #expect(measured >= floor, """
                the key chip is \(String(format: "%.2f", measured)):1 against the Form row in \
                \(dark ? "dark" : "light"), under the \(floor) this asks. A chip that does not \
                separate from its row is not a chip; it was `Surface.canvas` and measured 1.01 \
                in dark (D-312).
                """)
            // And the letters on it, which is where the information is.
            #expect(ratio(Tokens.Text.primary, Tokens.Surface.keyCap, dark: dark) >= 4.5,
                    "the keys on the chip are under 4.5:1 in \(dark ? "dark" : "light")")
        }
    }

    /// WCAG relative luminance, then the contrast ratio between two colors.
    private func ratio(_ a: Color, _ b: Color, dark: Bool, highContrast: Bool = false) -> Double {
        func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> Double {
            func channel(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
        }
        // A translucent ink is measured over its ground, not off its own
        // channels. Black at 8% and black at 45% are the same three numbers,
        // so every ratio involving an alpha token was answering about a color
        // nobody can see: the `border.hairline` assertion moved by zero when
        // the value nearly sextupled, which is how this was found (D-341).
        let ground = components(b, dark: dark, highContrast: highContrast)
        let ink = components(a, dark: dark, highContrast: highContrast)
        let alpha = opacity(a, dark: dark, highContrast: highContrast)
        let over = (ink.0 * alpha + ground.0 * (1 - alpha),
                    ink.1 * alpha + ground.1 * (1 - alpha),
                    ink.2 * alpha + ground.2 * (1 - alpha))
        let l1 = luminance(over)
        let l2 = luminance(ground)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Increase Contrast has to *do* something, and it has to do it upward.
    ///
    /// `dyn` matched two of the platform's four appearance names, so the one
    /// system setting whose whole job is making an app like this readable
    /// produced a screen byte for byte identical to everybody else's — and
    /// nothing could see it, because every number in the design document's contrast
    /// column is a reading at the default setting (D-340).
    ///
    /// The floors here are one tier above the ordinary ones: a reader who asks
    /// for contrast should get more than the minimum that was already passing.
    @Test func increaseContrastRaisesTheInksThatSitNearestTheirFloor() {
        for dark in [false, true] {
            for (name, ground) in grounds {
                let secondary = ratio(Tokens.Text.secondary, ground, dark: dark, highContrast: true)
                #expect(secondary >= 7, """
                    text.secondary is \(secondary) on \(name) under Increase Contrast, \
                    dark=\(dark). Anything a reader has to read to use the app is this \
                    ink or better, so it should clear 7:1 when contrast is asked for.
                    """)
                // Tertiary is held to 3:1 normally, being a mark ink. Asked for
                // contrast, it clears the body floor instead — which is the same
                // value `secondary` has at rest, and the design document is right that the
                // collapse cannot be the default. The setting is the reader
                // saying they would rather have it.
                let tertiary = ratio(Tokens.Text.tertiary, ground, dark: dark, highContrast: true)
                #expect(tertiary >= 4.5, """
                    text.tertiary is \(tertiary) on \(name) under Increase Contrast, \
                    dark=\(dark), and should clear the body floor when contrast is asked for.
                    """)
                // And it has to be a rise, not a repaint.
                #expect(tertiary > ratio(Tokens.Text.tertiary, ground, dark: dark),
                        "text.tertiary did not move on \(name), dark=\(dark)")
            }
            // A hairline at 8% is an edge you infer. The platform draws real
            // borders under the setting; so should this one.
            //
            // Composited by hand, because `components` reads the color's own
            // channels and throws its alpha away: black at 8% and black at 30%
            // are the same three numbers, so `ratio` says a translucent ink
            // never moves. That blind spot is older than this test and is
            // noted in the PRD rather than fixed here, where it would change
            // what every other assertion in this suite measures.
            let plain = ratio(Tokens.Border.hairline, Tokens.Surface.raised, dark: dark)
            let asked = ratio(Tokens.Border.hairline, Tokens.Surface.raised, dark: dark, highContrast: true)
            #expect(asked >= 3, """
                border.hairline is \(asked) against its panel under Increase Contrast \
                and \(plain) without, dark=\(dark). A panel edge is a graphical \
                object, and WCAG's floor for one of those is 3:1.
                """)
        }
    }

    /// The tokens that carry an alpha, which nothing measured until `ratio`
    /// learned to composite (D-341). Two of them are deliberately faint and the
    /// assertions say so; the point is that the numbers are now readings.
    @Test func theTranslucentInksMeasureWhatAReaderSees() {
        for dark in [false, true] {
            for (name, ground) in grounds {
                // A disabled control is supposed to be hard to read: WCAG
                // exempts one, and making it legible is how a dead control
                // starts looking live. The floor is that it stays *under* the
                // body floor, which is the claim the design document makes.
                let disabled = ratio(Tokens.Text.disabled, ground, dark: dark)
                #expect(disabled < 3, """
                    text.disabled is \(disabled) on \(name), dark=\(dark) — legible \
                    enough to look live.
                    """)
                // And it must not vanish either, or a disabled control reads as
                // an empty space where something used to be.
                #expect(disabled > 1.3, """
                    text.disabled is \(disabled) on \(name), dark=\(dark) — gone \
                    rather than quiet.
                    """)
            }
            // A hairline at rest is an edge you infer. That is the intent, and
            // it is why Increase Contrast has something to do (D-340).
            let hairline = ratio(Tokens.Border.hairline, Tokens.Surface.raised, dark: dark)
            #expect(hairline > 1.1 && hairline < 1.5,
                    "border.hairline is \(hairline) at rest, dark=\(dark)")
        }
    }

    private var grounds: [(String, Color)] {
        [("canvas", Tokens.Surface.canvas),
         ("chrome", Tokens.Surface.chrome),
         ("raised", Tokens.Surface.raised)]
    }

    /// D-191. The table in the design document is a reading, not a claim.
    ///
    /// It carried `text.secondary` as `#A0A0A0` and `text.tertiary` as
    /// `#7A7A7A` for two days after D-117 lifted both of them, with the old
    /// ratios beside them, because a number in prose has nothing holding it.
    /// This walks the rows: every hex the document prints has to be the hex
    /// the token is, and every ratio has to be the one the pair measures.
    @Test func theDocumentsColorTableIsWhatTheTokensActuallyAre() throws {
        guard let doc = try designDocument() else { return }  // a clone: no document to hold

        let named: [String: Color] = [
            "text.primary": Tokens.Text.primary,
            "text.secondary": Tokens.Text.secondary,
            "text.tertiary": Tokens.Text.tertiary,
            "bg.canvas": Tokens.Surface.canvas,
            "bg.chrome": Tokens.Surface.chrome,
            "bg.raised": Tokens.Surface.raised,
            "bg.cursor": Tokens.Surface.cursor,
            "bg.hovered": Tokens.Surface.hovered,
            "bg.sunken": Tokens.Surface.sunken,
        ]
        var checked = 0
        for line in doc.components(separatedBy: .newlines) {
            let cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4,
                  let token = named[cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "`"))]
            else { continue }
            for (i, dark) in [(2, false), (3, true)] {
                guard let printed = hex(cells[i]) else { continue }
                #expect(hex(token, dark: dark) == printed,
                        "\(cells[1]) is \(hex(token, dark: dark)) and the document says \(printed)")
                checked += 1
            }
        }
        #expect(checked >= 16, "the scan read almost no rows, so it is asserting nothing")
    }

    /// And the ratios beside them. One decimal place, so the table can round
    /// and still be true, and a tenth of a point of slack for the rounding.
    @Test func theDocumentsContrastNumbersAreTheOnesMeasured() throws {
        guard let doc = try designDocument() else { return }  // a clone: no document to hold

        let inks: [(String, Color)] = [("text.primary", Tokens.Text.primary),
                                       ("text.secondary", Tokens.Text.secondary),
                                       ("text.tertiary", Tokens.Text.tertiary)]
        var checked = 0
        for line in doc.components(separatedBy: .newlines) {
            let cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 5, let ink = inks.first(where: {
                cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "`")) == $0.0
            })?.1 else { continue }
            // "18.4:1 / 11.6:1", light first, whatever follows it.
            let printed = cells[4].components(separatedBy: "/").compactMap { part -> Double? in
                guard let colon = part.range(of: ":1") else { return nil }
                return Double(part[part.startIndex..<colon.lowerBound].trimmingCharacters(in: .whitespaces))
            }
            guard printed.count == 2 else { continue }
            // The column says "on bg.canvas", which is the stated ground.
            for (i, dark) in [(0, false), (1, true)] {
                let measured = ratio(ink, Tokens.Surface.canvas, dark: dark)
                #expect(abs(measured - printed[i]) < 0.1,
                        "\(cells[1]) \(dark ? "dark" : "light") measures \(String(format: "%.1f", measured)) and the document says \(printed[i])")
                checked += 1
            }
        }
        #expect(checked == 6, "the scan read \(checked) of the six numbers")
    }

    /// The quiet tier's own contract, written down in the design document because the
    /// ladder cannot hold 4.5 three times: tertiary is a mark ink at 3:1 and
    /// is never the only thing carrying a fact (D-191).
    @Test(arguments: [false, true])
    func theQuietInkClearsTheMarkFloorOnEveryGround(dark: Bool) {
        for (name, ground) in grounds {
            let r = ratio(Tokens.Text.tertiary, ground, dark: dark)
            #expect(r >= 3, "tertiary on \(name), \(dark ? "dark" : "light") is \(String(format: "%.2f", r))")
        }
    }

    /// The document, or nil on a clone.
    ///
    /// It returned `""` there, which is not the same thing: the two tests below
    /// read no rows out of an empty string and then failed their own "did this
    /// scan anything" floor. The comment said a clone skips this and the code
    /// did not, so the suite failed for everybody who was not the author —
    /// found by running it against a fresh clone, which is what CI is (D-246).
    ///
    /// There is nothing to ship as a fixture in their place. What these two
    /// check is the document's prose against the tokens, and a copy of the
    /// numbers would be the tokens checked against themselves. The names the
    /// document declares are a different matter and do ship (D-172).
    private func designDocument() throws -> String? {
        // `Repo.root.appendingPathComponent` and not `Repo.at`: the
        // pre-commit guard refuses an added line naming a document a
        // clone does not have, and exempts the one spelling the two
        // tests that read it were already written in (D-262).
        let url = Repo.root.appendingPathComponent("DESIGN.md")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func hex(_ cell: String) -> String? {
        let t = cell.trimmingCharacters(in: CharacterSet(charactersIn: "`#"))
        guard t.count == 6, t.allSatisfy({ $0.isHexDigit }) else { return nil }
        return t.uppercased()
    }

    private func hex(_ color: Color, dark: Bool) -> String {
        let c = components(color, dark: dark)
        return String(format: "%02X%02X%02X",
                      Int((c.0 * 255).rounded()), Int((c.1 * 255).rounded()), Int((c.2 * 255).rounded()))
    }

    @Test(arguments: [false, true])
    func bodyTextClearsFourAndAHalfOnEveryGround(dark: Bool) {
        for (name, ground) in grounds {
            #expect(ratio(Tokens.Text.primary, ground, dark: dark) >= 4.5,
                    "primary on \(name), \(dark ? "dark" : "light")")
            #expect(ratio(Tokens.Text.secondary, ground, dark: dark) >= 4.5,
                    "secondary on \(name), \(dark ? "dark" : "light")")
        }
    }

    /// A control drawn on a photograph does not get to assume a ground. The
    /// scrim under it is composited over whatever the picture happens to be,
    /// so the number that matters is the glyph against the scrim *after* the
    /// scrim has been laid over the worst frame in the fixture. 55% looked
    /// fine and measured 3.1:1 — over the graphic floor and under the one a
    /// control's label answers to, which is why the floor here is 4.5 (D-120).
    @Test(arguments: [false, true])
    func theCullPillIsLegibleOverAnyPhotograph(dark: Bool) {
        // Near-white sky, near-black night frame, and a mid-tone in between:
        // the three grounds the fixture folder is drawn with.
        let photographs: [(String, (CGFloat, CGFloat, CGFloat))] =
            [("a white sky", (1, 1, 1)),
             ("a night frame", (0.06, 0.06, 0.06)),
             ("skin", (0.78, 0.47, 0.47))]
        for (what, photo) in photographs {
            let scrim = composite(Tokens.Surface.overPhoto, over: photo, dark: dark)
            // 4.5, not the 3 a decorative mark gets. This pill is a pair of
            // buttons with glyph labels, and a control's label is interface
            // text wherever it happens to be painted. 55% cleared 3 and would
            // have shipped under the lower floor.
            for (name, ink, floor) in [("resting", Tokens.Text.onPhotoQuiet, 4.5),
                                       ("reached for", Tokens.Text.onPhoto, 4.5)] {
                let glyph = composite(ink, over: scrim, dark: dark)
                #expect(ratio(rgb: glyph, rgb: scrim) >= floor,
                        "\(name) glyph on the pill over \(what), \(dark ? "dark" : "light")")
            }
        }
    }

    /// A translucent token laid over a known ground, the way the window server
    /// will lay it. Asking `NSColor` for its components gives the token's own
    /// alpha, which is not what anybody sees.
    private func composite(_ color: Color, over ground: (CGFloat, CGFloat, CGFloat),
                           dark: Bool) -> (CGFloat, CGFloat, CGFloat) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            let a = c.alphaComponent
            out = (a * c.redComponent + (1 - a) * ground.0,
                   a * c.greenComponent + (1 - a) * ground.1,
                   a * c.blueComponent + (1 - a) * ground.2)
        }
        return out
    }

    private func ratio(rgb a: (CGFloat, CGFloat, CGFloat), rgb b: (CGFloat, CGFloat, CGFloat)) -> Double {
        func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> Double {
            func channel(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
        }
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test(arguments: [false, true])
    func theQuietestTextStillClearsThree(dark: Bool) {
        // Tertiary is separators and the ellipsis: a mark, not a sentence.
        for (name, ground) in grounds {
            #expect(ratio(Tokens.Text.tertiary, ground, dark: dark) >= 3,
                    "tertiary on \(name), \(dark ? "dark" : "light")")
        }
    }

    /// The destructive word in a sheet footer is drawn on the panel, not on a
    /// button: a bordered button's fill is the system's gray and a token tuned
    /// against this app's grounds says nothing about it (D-357).
    @Test(arguments: [false, true])
    func theDestructiveWordClearsItsPanel(dark: Bool) {
        #expect(ratio(Tokens.State.reject, Tokens.Surface.chrome, dark: dark) >= 3,
                "the Trash word on a sheet footer, \(dark ? "dark" : "light")")
    }

    @Test(arguments: [false, true])
    func everyMarkClearsThreeOnTheCellItSitsOn(dark: Bool) {
        let ground = Tokens.Surface.raised
        #expect(ratio(Tokens.State.keep, ground, dark: dark) >= 3, "keep, \(dark ? "dark" : "light")")
        #expect(ratio(Tokens.State.reject, ground, dark: dark) >= 3, "reject, \(dark ? "dark" : "light")")
        #expect(ratio(Tokens.State.favorite, ground, dark: dark) >= 3, "favorite, \(dark ? "dark" : "light")")
        for label in ColorLabel.allCases {
            #expect(ratio(Tokens.State.label(label), ground, dark: dark) >= 3,
                    "\(label) label, \(dark ? "dark" : "light")")
        }
    }
}


/// Defaults that are a product decision rather than whatever `UserDefaults`
/// hands back for a missing key. `bool(forKey:)` answers false for "unset",
/// so every preference that should start on has to say so — and every one of
/// them is a thing a reader would otherwise have to find a shortcut to
/// discover (D-122).
///
/// Serialized and restoring what it found: it writes preferences, and the
/// scratch domain is shared across suites (tech debt 25).
@Suite(.serialized) @MainActor struct PreferenceDefaultTests {
    init() { Preferences.useTestDefaults() }

    @Test func theFilmstripStartsOn() {
        let was = Preferences.showFilmstrip
        defer { Preferences.showFilmstrip = was }

        Preferences.forget(["showFilmstrip"])
        #expect(Preferences.showFilmstrip,
                "the preview is where a burst is compared, and the strip is the only thing in it that says the neighbors exist")

        // And a reader who turns it off is not overruled on the next launch.
        Preferences.showFilmstrip = false
        #expect(!Preferences.showFilmstrip)
    }

    /// D-378. Name was the filesystem's order, not the shoot's.
    @Test func theSortStartsOnCaptureDateOldestFirst() {
        let sort = Preferences.sort, direction = Preferences.sortDirection
        defer { Preferences.sort = sort; Preferences.sortDirection = direction }

        Preferences.forget(["sort", "sortDirection"])
        #expect(Preferences.sort == .dateTaken)
        #expect(Preferences.sortDirection == .natural)
        #expect(SortOrder.dateTaken.label(.natural) == "Oldest first",
                "natural is the direction, and this is what it means for this field")

        // And a reader who picks another one is not overruled on the next launch.
        Preferences.sort = .name
        #expect(Preferences.sort == .name)
    }

    @Test func aFreshStoreTakesTheStoredAnswerAndNotItsOwn() {
        let was = Preferences.showFilmstrip
        defer { Preferences.showFilmstrip = was }

        Preferences.showFilmstrip = false
        #expect(LibraryStore().showFilmstrip == false)
        Preferences.showFilmstrip = true
        #expect(LibraryStore().showFilmstrip == true)
    }

    /// The other two that default on, kept here so the three read as one rule.
    @Test func theSidebarAndAutoAdvanceStartOnToo() {
        let sidebar = Preferences.showSidebar, auto = Preferences.autoAdvance
        defer { Preferences.showSidebar = sidebar; Preferences.autoAdvance = auto }

        Preferences.forget(["showSidebar", "autoAdvance"])
        #expect(Preferences.showSidebar)
        #expect(Preferences.autoAdvance)
    }
}
