import SwiftUI
import AppKit

/// Mirrors the design document exactly. Views reference these, never a literal.
enum Tokens {
    /// Whether the reader has asked for more contrast than the app draws by
    /// default. A closure rather than a read, for the reason D-329 gives: it
    /// is machine state, a test has to be able to stand in front of it, and
    /// the setting cannot be toggled from a test run. `ContrastTests` is the
    /// only thing that assigns it (D-340).
    nonisolated(unsafe) static var increaseContrast: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    enum Surface {
        /// The ground a photograph sits on. Retuned 2026-09-15 to the tones the
        /// platform's own file browser uses: the old dark canvas was `#0A0A0A`,
        /// which is near-black, and a folder of photographs on it read as a
        /// grid of light boxes in a void rather than as a window (D-117).
        static let canvas = dyn(light: 0xFFFFFF, dark: 0x303030)
        /// Behind the header and the sidebar, where the blur cannot be drawn:
        /// a window being dragged, a screenshot, reduced transparency.
        static let chrome = dyn(light: 0xF2F2F2, dark: 0x383838)
        /// A folder tile, a popover, a panel. One step off the canvas in the
        /// direction of the reader. Cells no longer use it: they have their
        /// own two steps below, because a cell has two different facts to say
        /// and this token was saying both of them identically (D-119).
        static let raised = dyn(light: 0xE8E8E8, dark: 0x3C3C3C)
        /// The cell the keyboard is on. The step is measured, not picked: a
        /// Finder window captured on this machine draws its selected icon tile
        /// at `#4B4947` on a `#312F2C` canvas, 26/255 above its own ground.
        /// These are 26 above `canvas`, for the same reason the grounds
        /// themselves were sampled rather than chosen (D-117, D-119).
        static let cursor = dyn(light: 0xE5E5E5, dark: 0x4A4A4A)
        /// A cell under the pointer. Half that step, because the pointer is
        /// an offer and the cursor is a place. The two used to be one fill,
        /// and it was the same fill selection used as well (D-119).
        static let hovered = dyn(light: 0xF1F1F1, dark: 0x3D3D3D)
        /// The key chip in Settings' Keyboard tab, which is also the button
        /// that reassigns it.
        ///
        /// Its own token because it is the one surface in the app drawn on a
        /// row the *system* supplies. Every other ground here is Sift's, so a
        /// token tuned against `canvas` says something true about where it
        /// sits; this one sits on a grouped `Form`, which samples `#312F2D`
        /// dark and `#EBE9E8` light, and no token tuned against the canvas
        /// knows that.
        ///
        /// It had `canvas`. In dark that is `#303030` on `#312F2D`, which is
        /// 1.01:1 — the box was not faint, it was not there, and what showed
        /// in a screenshot was the Form's own row edge. Light worked by
        /// accident: white happens to be lighter than the row under it.
        ///
        /// `#4A4A4A` is `cursor`'s dark step rather than a new number,
        /// measured the same way and for the same reason (D-117, D-119): 26
        /// off the ground, which is what this platform puts between a row and
        /// a control raised off it. 1.49:1 dark and 1.13:1 light against the
        /// Form. A chip also carries `Border.hairline`, because a fill alone
        /// has to be right against a ground this app does not set (D-312).
        static let keyCap = dyn(light: 0xFFFFFF, dark: 0x4A4A4A)
        /// The resting fill of a button this app draws itself (D-359).
        ///
        /// One button needs it. Second Pass's Trash cannot be a bordered
        /// button, because a bordered button's own hover gray is a ground
        /// `State.reject` cannot be measured against (D-357), and it still has
        /// to look like a button while nobody is pointing at it.
        static let control = dyn(light: 0xFFFFFF, dark: 0x4A4A4A)
        /// The folder tile's ground: a card lifted off the page, with
        /// `Elevation.tile` under it and no border at all (D-354).
        ///
        /// Lifted rather than sunken, which is the reversal of D-353. A well
        /// separates as well as a card does and puts the photographs it holds
        /// in a hole, and a shadow under a sunken ground is two claims about
        /// the same edge. Shares its values with `cursor` and `keyCap` and
        /// means what neither of them means, so the three move apart the day
        /// any one is retuned.
        static let folder = dyn(light: 0xFFFFFF, dark: 0x4A4A4A)
        /// A cell in the selection. The accent at a fraction of itself, so the
        /// backing and the name pill under it are one fact at two weights
        /// rather than two marks to reconcile. D-119 gave the tile to the
        /// cursor and the pill to the selection, and a select-all came out as
        /// a row of pills over nothing: the photographs themselves showed no
        /// sign of being chosen, which is the only part of the cell a sweep of
        /// the eye actually lands on (D-132).
        ///
        /// A fraction and not the accent itself, because this sits around a
        /// photograph and a full-strength accent ring would be the loudest
        /// thing in a grid of pictures.
        static let selected = State.selection.opacity(0.22)
        /// The selected cell the keyboard is also on. The same accent one step
        /// heavier, because a plain click now chooses as well as lands and the
        /// gray tile in the middle of a blue run read as a hole in it rather
        /// than as a place (D-377). Nearly twice `selected`, for the reason
        /// `cursor` is twice `hovered`: a place is worth twice what sits
        /// under it.
        static let selectedCursor = State.selection.opacity(0.40)
        static let sunken = dyn(light: 0xDCDCDC, dark: 0x262626)
        /// Dims the part of a photograph that is not being acted on: outside
        /// the crop rectangle, and behind the "take it back" cover in the
        /// reject review. Black in both themes, like the heart's keyline and
        /// `bg.overPhoto`, because what is underneath is a picture and a
        /// picture has no theme.
        ///
        /// One value, where there were two: 0.5 in the crop and 0.55 in the
        /// review, each written into its own view. The suite could not see
        /// either, because it watched for colors and measurements and not for
        /// opacities (D-192).
        static let scrim = dyn(light: 0x000000, dark: 0x000000, alpha: 0.55)
        /// Behind a chrome control under the pointer, and behind one that is
        /// on. Nothing at rest, so a header of six icons is six icons and not
        /// six buttons; a tint the moment the pointer is over one, which is
        /// how this platform's own toolbars say a glyph is a control (D-184).
        ///
        /// Black and white at a low alpha rather than a pair of flat tones,
        /// because these sit on the header's blur, the sidebar's, and a
        /// popover's, and a tone tuned to one of the three is wrong on the
        /// other two.
        static let controlHover = dyn(light: 0x000000, dark: 0xFFFFFF, alpha: 0.08)
        /// Twice the pointer's step, for the same reason `cursor` is twice
        /// `hovered`: the pointer is an offer and a state is a fact.
        static let controlOn = dyn(light: 0x000000, dark: 0xFFFFFF, alpha: 0.16)
        /// The ground under a control that is drawn *on* a photograph: the
        /// keep/reject pill in a cell's corner. Near-black in both themes and
        /// translucent, for the reason `state.favoriteKeyline` is near-white
        /// in both — a photograph has no theme, so a chrome tone here vanishes
        /// against half the pictures it lands on. It used to be `bg.raised`,
        /// which is `#E8E8E8` over a white sky and `#3C3C3C` over a night
        /// frame (D-58, D-120).
        /// 70%, which is the number the contrast test asked for rather than a
        /// number that looked right: at 55% the scrim over a near-white frame
        /// only reaches mid-gray, and the glyph on it came to 3.1:1 — the
        /// graphic floor exactly, and visibly thin in the shot. At 70% the
        /// worst ground in the fixture gives 6.0:1 resting.
        static let overPhoto = dyn(light: 0x000000, dark: 0x000000, alpha: 0.70)
        /// Focus mode's ground. Dark in both themes on purpose: a photograph is
        /// judged against a neutral dark surround, and the one moment the app
        /// takes everything else away is not the moment to follow the system
        /// into a light gray (D-62).
        static let judging = dyn(light: 0x141414, dark: 0x000000)
    }

    enum Text {
        static let primary = dyn(light: 0x141414, dark: 0xF0F0F0)
        /// Lifted with the grounds in D-117, for the reason below it.
        // 8.9:1 and 7.2:1 on the worst ground under Increase Contrast, against
        // 5.5 and 4.6 without it. Anything a reader has to read to use the app
        // is this ink or better, so this is the one that most repays the
        // setting (D-340).
        static let secondary = dyn(light: 0x5C5C5C, dark: 0xA8A8A8,
                                   lightHC: 0x3D3D3D, darkHC: 0xD0D0D0)
        /// Lifted with the grounds in D-117: a lighter canvas needs lighter
        /// quiet text to hold the same 3:1, and `#7A7A7A` no longer did.
        // Under Increase Contrast this *is* `secondary`'s ordinary value, and
        // three inks collapse into two. The design document argues that collapse
        // cannot be the default, and it is right; Increase Contrast is the
        // reader saying they would rather have the contrast than the third
        // tier. 5.5:1 and 4.6:1 on the worst ground, against 3.7 and 3.3 (D-340).
        static let tertiary = dyn(light: 0x767676, dark: 0x8C8C8C,
                                  lightHC: 0x5C5C5C, darkHC: 0xA8A8A8)
        /// On top of `state.selection`. White in both themes, because the
        /// accent underneath it is the reader's and can be any hue: this is the
        /// pairing AppKit itself uses for a selected label, and following it is
        /// what keeps a yellow accent legible (D-115).
        static let onSelection = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)
        /// On top of `bg.overPhoto`: a glyph in a control drawn on a
        /// photograph. Near-white in both themes, like `text.onSelection` and
        /// for a stronger version of the same reason — what is underneath is
        /// not a palette at all (D-120).
        static let onPhoto = dyn(light: 0xF0F0F0, dark: 0xF0F0F0)
        /// The resting state of that glyph: present, but not stamped on the
        /// picture until somebody reaches for it.
        static let onPhotoQuiet = dyn(light: 0xF0F0F0, dark: 0xF0F0F0, alpha: 0.85)
        /// A control at the end of its range: the back arrow with nowhere to
        /// go, a slider already at zero. It was `text.tertiary.opacity(0.4)`
        /// written out at two call sites, which is a design value living in a
        /// view — the thing `DesignSystemTests` exists to prevent, and the one
        /// shape it could not see, because it watched for colors and
        /// measurements and not for opacities (D-192).
        ///
        /// Deliberately under every contrast floor. A disabled control is the
        /// one mark that is supposed to be hard to read: WCAG exempts it, and
        /// making it legible is how a dead control starts looking live.
        static let disabled = dyn(light: 0x767676, dark: 0x8C8C8C, alpha: 0.4)
    }

    enum Border {
        // 8% is an edge you infer rather than see: 1.2:1 against its panel,
        // which is the point at rest and the wrong answer for somebody who
        // asked for contrast. 45% is the first step on the scale that clears
        // WCAG's 3:1 floor for a graphical object on the worst ground in both
        // themes — 3.2:1 light and 3.6:1 dark, measured over the composite
        // rather than off the ink, which is the part that took two tries
        // (D-340).
        static let hairline = dyn(light: 0x000000, dark: 0xFFFFFF,
                                  alpha: 0.08, alphaHC: 0.45)
        /// An edge meant to be seen rather than inferred (D-352).
        ///
        /// The folder tile's silhouette is the whole of what tells a folder
        /// from a photograph in a grid of photographs, and at 8% it was a
        /// tab nobody could find: two hex steps of fill and an edge at
        /// 1.2:1. 45% is where `hairline` already goes under Increase
        /// Contrast and for the same reason — the first step on the scale
        /// clearing the 3:1 floor for a graphical object on the worst ground
        /// in both themes. A second token rather than a louder hairline,
        /// because the hairline's whole argument is that it is quiet at rest.
        static let outline = dyn(light: 0x000000, dark: 0xFFFFFF,
                                 alpha: 0.45, alphaHC: 0.65)
        static let selected = dyn(light: 0x141414, dark: 0xF0F0F0)
        static let focus = selected
        /// The hairline inside the cursor ring, in the tone the ring is not
        /// (D-178).
        ///
        /// `selected` is near-black on a light desktop and near-white on a
        /// dark one, which is exactly right against the strip's own chrome and
        /// exactly wrong against a photograph of the same tone: a white ring
        /// on a bright sky is a ring nobody can see. A photograph can match
        /// one of the two; it cannot match both at the same edge.
        static let cursorKeyline = dyn(light: 0xF0F0F0, dark: 0x141414, alpha: 0.65)
        static let ringWidth: CGFloat = 2
        /// Hover sits one step under selection: same color, half the weight.
        static let hoverWidth: CGFloat = 1
    }

    enum State {
        static let keep = dyn(light: 0x1F7A3D, dark: 0x4FB06E)
        static let reject = dyn(light: 0xA32020, dark: 0xE06060)
        /// The heart. A rose, deliberately lighter and warmer than the reject
        /// brick, because the two appear on the same cell at the same time and
        /// a near-match would read as one color used carelessly (D-57).
        static let favorite = dyn(light: 0xD1344E, dark: 0xF2687E)
        /// The keyline drawn around the heart. Near-white in both themes, on
        /// purpose: it is painted over photographs, not over app chrome, and a
        /// photograph has no theme. It is what makes the mark survive a red
        /// sunset behind it (D-58).
        static let favoriteKeyline = dyn(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.92)
        /// A hairline outside the white one. The mark lands on the photograph
        /// or on the cell's letterbox band depending on the frame's shape, and
        /// in light mode that band is white: a near-white keyline on it is a
        /// mark nobody can see. Dark in both themes for the same reason the
        /// white one is light in both — what it has to survive is unknown
        /// content, not a palette (D-112).
        static let favoriteKeylineShadow = dyn(light: 0x000000, dark: 0x000000, alpha: 0.35)
        /// `state.reject` (light) as bytes, for the clipping mask painted pixel by pixel.
        static let rejectRGB: (r: UInt8, g: UInt8, b: UInt8) = (0xA3, 0x20, 0x20)
        /// `state.keep` (light) as bytes, for the focus mask. The same pair of
        /// hues the flags use: what is blown is painted in the reject color,
        /// what is sharp in the keep one, and neither needs a new hue.
        static let keepRGB: (r: UInt8, g: UInt8, b: UInt8) = (0x1F, 0x7A, 0x3D)
        /// The five color labels (D-96). These are the user's vocabulary, not
        /// the app's: Sift has no opinion about what blue means, which is why
        /// five hues can live here without breaking the three-hue rule. Picked
        /// to sit beside the Finder tag colors they are stored as, and darkened
        /// in light mode so each clears 3:1 against the cell.
        static func label(_ label: ColorLabel) -> Color {
            switch label {
            case .red: dyn(light: 0xC0392B, dark: 0xE8695B)
            case .yellow: dyn(light: 0x9A7B0A, dark: 0xE0C04A)
            case .green: dyn(light: 0x2E7D32, dark: 0x66BB6A)
            case .blue: dyn(light: 0x1565C0, dark: 0x64B5F6)
            case .purple: dyn(light: 0x6A1B9A, dark: 0xBA68C8)
            }
        }

        /// A photo nobody has decided about yet, in the cull rail. Quiet enough
        /// that a folder with three decisions in it reads as three marks on a
        /// neutral ground rather than as a striped bar.
        static let untouched = dyn(light: 0xD8D8D8, dark: 0x303030)

        /// Selection, and the one accent in the app that is not one of the
        /// three reserved hues. It is the accent the reader chose in System
        /// Settings, not a color anybody here picked, which is the only kind of
        /// accent this project allows — and it is what makes a selected cell
        /// read the way a selected file reads everywhere else on the machine
        /// (D-115).
        static let selection = Color(nsColor: .controlAccentColor)
    }

    enum Font {
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 16)
        static let ui = SwiftUI.Font.system(size: 14)
        /// The open folder in the breadcrumb, and any label that has to lead
        /// its neighbors without changing the height of the row it is in.
        static let uiStrong = SwiftUI.Font.system(size: 14, weight: .semibold)
        static let data = SwiftUI.Font.system(size: 14, design: .monospaced)
        /// The word under an action icon, and the only size under the 14pt
        /// floor. It is glanced at once and then the drawing carries the
        /// meaning; at 14 the word competed with the icon and the pair read as
        /// two controls. 11 is what AppKit sets a toolbar label at (D-139).
        static let caption = SwiftUI.Font.system(size: 10)
        static let lineSpacing: CGFloat = 0.5 // line height 1.5 = size + 0.5 * size
    }

    enum Radius {
        static let none: CGFloat = 0
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
    }

    enum Space {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s48: CGFloat = 48
        static let s64: CGFloat = 64
    }

    enum Elevation {
        static let raised = (color: SwiftUI.Color.black.opacity(0.10), radius: CGFloat(2), y: CGFloat(1))
        static let overlay = (color: SwiftUI.Color.black.opacity(0.20), radius: CGFloat(24), y: CGFloat(8))
        /// The folder tile: a card resting on the page rather than a panel
        /// floating over it. Heavier than `raised` and far tighter than
        /// `overlay`, and the whole of what separates the tile, since it
        /// carries no border (D-354).
        static let tile = (color: SwiftUI.Color.black.opacity(0.30), radius: CGFloat(6), y: CGFloat(2))
    }

    enum Motion {
        static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        static var fast: Animation? { reduce ? nil : .easeOut(duration: 0.12) }
        /// One frame dissolving into the next in single view. Short enough that
        /// a fast run through a folder still reads as instant, long enough to
        /// take the flash out of the swap (D-63).
        static var crossfade: Animation? { reduce ? nil : .easeOut(duration: 0.09) }
        /// The view moving to a part of the photograph somebody asked for: a
        /// face crop clicked, `⇧Z`, a scripted `lookAt:`. Two and a half times
        /// the next longest, because this is the one animation whose distance
        /// is the information: cut straight to the far end and the reader has
        /// to work out where they now are (D-274).
        static var travel: Animation? { reduce ? nil : .easeOut(duration: 0.30) }
        /// How long the preview bar stays up after a keystroke brings it back.
        /// Long enough to read a row of controls, short enough that it is gone
        /// before the next decision (D-64).
        static let barDwell: Duration = .milliseconds(1800)
        /// How long the bar stays up after the pointer stops moving. Longer
        /// than `barDwell`, because a pointer that has just stopped is often a
        /// hand on its way to a control, and shorter than a pause: the whole
        /// point is that a hand resting on the trackpad while somebody arrows
        /// through a folder is not reaching for anything (D-199).
        static let barIdle: Duration = .seconds(3)
        /// How long a first-time hint stays on screen.
        static let hintDwell: Duration = .seconds(8)
        /// How long the adjust preview waits after a slider stops before it
        /// renders. Short enough that letting go feels like the photograph
        /// changed, long enough that a drag across the track is one render
        /// rather than forty (D-161).
        static let adjustSettle: Duration = .milliseconds(80)
    }

    enum Layout {
        /// Grid cell edge, and the default the size control starts on.
        /// Thumbnails decode at 2x the cell for Retina.
        static let gridCell: CGFloat = 160
        /// What `⌘=` and `⌘-` step through. Five stops rather than a continuous
        /// slider: a cull happens at one of a few densities, and a stop you can
        /// land on twice is a stop you can get back to.
        static let gridCellSteps: [CGFloat] = [96, 128, 160, 220, 300]
        static let thumbnailPixels: Int = 320
        /// Decode size for a cell of a given edge. The default cell's 320 is
        /// the floor, so shrinking the grid never re-decodes the folder.
        static func thumbnailPixels(for cell: CGFloat) -> Int {
            max(thumbnailPixels, Int(cell * 2))
        }
        /// How many neighbors on each side the prefetcher keeps decoded.
        static let prefetchRadius = 3
        /// Info panel width. Wide enough for a lens name, narrow enough to leave the photo alone.
        static let infoPanel: CGFloat = 280
        /// The adjust panel, on the same edge of the same window as the info
        /// panel and therefore the same width: two panels that can be open at
        /// once and disagree about how wide a panel is would read as two
        /// windows stapled together. It is its own token because the reason is
        /// its own — a slider needs a run long enough to land on a value, and
        /// 280 less the padding is 248 of it (D-161).
        static let adjustPanel: CGFloat = 280
        /// Longest edge the adjust preview renders at. The sliders have to keep
        /// up with a drag, and four Core Image filters over a 45-megapixel
        /// frame do not; 2048 is a little over a Retina window's worth of
        /// pixels, so at fit it is the photograph and past fit it is soft. The
        /// copy Return writes is rendered against the whole file (D-161).
        static let adjustPreviewPixels: Int = 2048
        /// The peek panel's side, beside the thumbnail the pointer is on
        /// (D-131). Square, because the photograph inside is fitted and the
        /// folder has both orientations in it; sizing the panel to each frame
        /// would make it jump as the pointer sweeps a row. 420 is a little
        /// over twice the default cell and a little under half the narrowest
        /// window the gallery opens at, which is the range where it is clearly
        /// a look at one photograph and still leaves the grid around it.
        static let peekPanel: CGFloat = 420
        /// How wide a sentence in a centered empty state is allowed to run.
        /// The readability floor is about 75 characters, and a window is
        /// wider than that; the panel scale's first step is the nearest one
        /// (D-324).
        static let proseMax: CGFloat = 420
        static let helpMaxWidth: CGFloat = 820
        static let helpMaxHeight: CGFloat = 720

        /// One column of the help overlay's grid: `keyColumn` of keys and 200
        /// of label. The overlay draws two when it has room for two and one
        /// when it does not (D-333).
        static let helpColumn: CGFloat = 320
        /// Key column in the help overlay and label column in the info panel.
        static let keyColumn: CGFloat = 120
        /// The key chip in Settings, which is that column inside a box: 120 of
        /// text plus `space.s8` either side. It had been the column itself, so
        /// the one binding whose keys fill the column — "Return  Space", 112.5
        /// of the 120 — pushed its chip 8pt wider than every other chip in a
        /// right-aligned row, and one chip out of line reads as a mistake
        /// rather than as a long key (D-315).
        static let keyCapWidth: CGFloat = 136
        static let labelColumn: CGFloat = 72
        /// Where the close button's circle starts, and so where every top-level
        /// control lines up on the left.
        static let windowEdge: CGFloat = 8
        /// Filmstrip thumbnail edge, and the decode size behind it.
        static let filmstripCell: CGFloat = 64
        static let histogramHeight: CGFloat = 64
        /// A face in the info panel's close-ups. The filmstrip cell's edge, so
        /// the panel's blocks keep one rhythm.
        static let faceCrop: CGFloat = 64
        static let searchField: CGFloat = 260
        /// As tall as the icon-and-caption controls it sits beside: the 20pt
        /// glyph, the 4 under it and the caption's line. A field two thirds
        /// their height read as a leftover from a smaller header rather than
        /// one of the row's controls (D-174).
        static let searchFieldHeight: CGFloat = 36
        /// How wide the path is allowed to get. It is the one band the header
        /// never puts away (D-111), so it is capped instead: a folder called
        /// "2026-04-04 Fam in San Francisco" would otherwise take the room the
        /// actions need and push them into the overflow menu (D-113).
        static let breadcrumbMax: CGFloat = 320
        /// Path field in the go-to sheet. Long enough for /Volumes/… without
        /// the middle of a path scrolling out of sight.
        static let pathField: CGFloat = 420
        /// Folder sidebar. Wide enough for a shoot name and its count at one
        /// level of nesting, narrow enough to leave the grid four columns.
        static let sidebar: CGFloat = 220
        /// How far the sidebar can be dragged, and what a double-click on the
        /// divider puts it back to. 160 still fits a shoot name and its count;
        /// past 360 the grid drops a column on a 1280pt window, which is a
        /// bigger change than the drag was asking for (D-229).
        static let sidebarMin: CGFloat = 160
        static let sidebarMax: CGFloat = 360
        /// The divider between the sidebar and the grid. Two points of line and
        /// eight of grab: the pointer finds it before the eye has to.
        static let dividerGrab: CGFloat = 8
        /// Jump sheet. Wide enough for a folder name and where it came from.
        /// The settings window. Wide enough for a switch, a feature's name
        /// with its keys beside it, and a sentence under that without the
        /// sentence wrapping three times (D-123).
        static let settingsWidth: CGFloat = 520
        /// A segmented control in Settings: the appearance's three choices.
        /// Narrower than the pane, so it reads as one control among the rows
        /// rather than a band across the window.
        static let settingsControl: CGFloat = 260
        static let settingsHeight: CGFloat = 720
        static let jumpSheet: CGFloat = 520
        /// Command palette. Wider than the jump sheet, because every row
        /// carries a command, the group it belongs to, and its keys.
        static let palette: CGFloat = 640
        /// The ingest sheet. Wide enough for a full path on one line.
        static let ingestSheet: CGFloat = 640
        /// The two sheets that are a list of filenames: what was trashed this
        /// sitting, and a batch rename's preview. One width, because they are
        /// the same shape of thing (D-114).
        static let listSheet: CGFloat = 520
        /// How tall that list gets before it scrolls.
        static let listSheetHeight: CGFloat = 360
        /// Smallest the gallery window goes. Below this the grid drops to two
        /// columns and the sidebar has nothing left to sit beside.
        static let galleryMinWidth: CGFloat = 640
        static let galleryMinHeight: CGFloat = 480
        /// The reject review. Three columns of the default cell, plus gaps.
        static let reviewSheet: CGFloat = 640
        static let reviewSheetHeight: CGFloat = 520
        /// The widths a sheet or a floating panel may take. Three steps, and
        /// every one of them is a decision somebody made once rather than a
        /// number that happened to fit the content on the day (D-177). The
        /// jump sheet was 460 and the palette and the ingest sheet were 560,
        /// which is five widths for one idea; they moved outward, so nothing
        /// that fit before stopped fitting, and the palette is still wider
        /// than the jump sheet the way its own comment says it is.
        static let sheetSteps: [CGFloat] = [420, 520, 640]
        /// The cull rail under the header. One 4pt band on the spacing scale:
        /// thick enough to carry three colors, thin enough not to read as a
        /// rule between the header and the grid (D-65).
        static let railHeight: CGFloat = 4
        /// Icon edge, and the hit target drawn around it. Both scales went up
        /// one step: at 12 and 16, drawn in a 1.5pt line, the header's icons
        /// read as thin marks beside the words rather than as the controls the
        /// row is made of (D-140). 14 is the chrome scale, matching the 14pt
        /// text it sits beside rather than ducking under it, and 28 is the
        /// square around it.
        static let glyph: CGFloat = 14
        static let glyphButton: CGFloat = 28
        // There is no icon stroke token any more. The line was ours to pick
        // while the icons were paths we drew, and picking it wrong at one
        // scale is what D-140 and D-160 were both about. The icons are SF
        // Symbols now: the weight comes off the same axis as the text beside
        // them, at the point size the step names, and no call site and no
        // token gets a say (D-198).
        /// The second and last icon scale: the header's action bar, where the
        /// icon is the control and the word under it is the caption. Bigger
        /// than the chrome glyphs on purpose, so a toolbar reads as a toolbar
        /// and the path above it reads as punctuation (D-59).
        static let glyphAction: CGFloat = 20
        static let glyphActionButton: CGFloat = 36
        /// The keep / reject badge. It scales with what it is drawn on, the way
        /// the heart does and off the same ratio, and it is clamped at both
        /// ends: 12 is the companion size, beside a filename or in a 64pt
        /// filmstrip frame, and 20 is what it reaches on a large grid cell and
        /// on the photograph filling the preview window, where the heart beside
        /// it is 32 and a 12pt disc read as punctuation (D-225, D-228).
        ///
        /// A tighter clamp than the heart's 20-to-32. The heart is the only
        /// mark in its corner; the flag shares its corner with the color dot,
        /// and it is the decision rather than the filing, so it leads that pair
        /// without becoming the loudest thing on the picture.
        ///
        /// There is no token for the tick inside it: the tick and the disc are
        /// one symbol, so the set decides how much of the disc the mark covers
        /// (D-226).
        static let flagBadgeMin: CGFloat = 12
        static let flagBadgeMax: CGFloat = 20
        static func flagBadge(for cell: CGFloat) -> CGFloat {
            min(max(cell * favoriteMarkRatio, flagBadgeMin), flagBadgeMax)
        }
        /// The third and largest step: a mark that is the whole of what a tile
        /// says, rather than a control in a row of them. It is drawn in the
        /// action line, because a tile sits on the grid beside photographs and
        /// a third stroke weight would be a third family (D-177).
        static let glyphTile: CGFloat = 28
        /// The only sizes a glyph is drawn at. Three steps: chrome, action,
        /// tile. A size that is not one of them is a fourth icon family
        /// arriving one call site at a time, which is how a 28pt folder came
        /// to be drawn at the name of a *box* (D-177).
        static let glyphSteps: [CGFloat] = [glyph, glyphAction, glyphTile]
        /// Folder tile edge. The grid cell, so folders and photos sit on one
        /// rhythm whichever is on screen.
        static let folderTile: CGFloat = gridCell
        /// The name under a thumbnail, and the pill drawn around it. One line
        /// of 14pt text plus 2pt of breathing room above and below (D-115).
        static let cellLabelHeight: CGFloat = 20
        /// The name and the count under a folder tile, together: two lines of
        /// label, the gap, and one line of count. Taken whether or not the
        /// name needs its second line, so every tile in a row is the same
        /// height and the squares sit on one line. The slack lands under the
        /// count rather than between it and the name, which would put the
        /// count nearer the row below than the folder it counts (D-369).
        static let folderTextHeight: CGFloat = cellLabelHeight * 3 + Space.s4
        /// How far the photograph sits inside its cell. A constant 8 cost the
        /// same 16pt at every step, which is a sixth of the 96pt cell and
        /// nothing at 300 (D-120). A table rather than a ratio because the
        /// grid has exactly five sizes and every value here has to land on the
        /// 4px spacing scale; a ratio would produce 4.8 and 15.
        static func cellInset(for cell: CGFloat) -> CGFloat {
            switch cell {
            case ..<128: Space.s4
            case ..<220: Space.s8
            default: Space.s12
            }
        }
        /// Longest edge for the clipping mask. Enough to see where, not to count pixels.
        static let clippingPixels: Int = 2048
        /// Longest edge for the focus mask. The thing being looked for is fine
        /// detail, and an edge map of a downscaled photo is an edge map of the
        /// downscaling.
        static let peakingPixels: Int = 1600
        /// The heart on a thumbnail. It scales with the cell so it reads the
        /// same at every grid size, and it is clamped at both ends: below 20 it
        /// stops being findable at a glance, above 32 it starts competing with
        /// the photograph it is marking.
        static let favoriteMarkMin: CGFloat = 20
        static let favoriteMarkMax: CGFloat = 32
        static let favoriteMarkRatio: CGFloat = 0.15
        static func favoriteMark(for cell: CGFloat) -> CGFloat {
            min(max(cell * favoriteMarkRatio, favoriteMarkMin), favoriteMarkMax)
        }
        /// The same mark in the filmstrip, where the cell is 64 and the grid
        /// ratio would cover a third of the frame.
        static let favoriteMarkSmall: CGFloat = 14
        /// The empty mark is `heart` drawn twice, and the keyline is how much
        /// bigger the dark copy behind is: 7% of the mark, which is 0.73pt on
        /// each side at 20 and 1pt at 28. The old pair of strokes — 4.5 under
        /// 3 — showed 0.75 at every size, so this reads as it did at the size
        /// it was tuned for and scales where the old one did not.
        ///
        /// It is a scale and not a heavier weight, which was the first attempt
        /// and drew two separate rings: a heavier symbol is a *bigger* symbol
        /// as well as a thicker one, so the two hearts came apart and the mark
        /// read as a target. 7% is less than the stroke is wide, so the two
        /// bands overlap and what escapes is a rim (D-200).
        static let favoriteKeylineScale: CGFloat = 1.07
        /// Smallest the preview window goes. Set by the preview bar: below this
        /// its words wrap and the trash slides under the rotations.
        static let previewMinWidth: CGFloat = 720
        static let previewMinHeight: CGFloat = 360
    }
}

/// A token's value, per appearance. `…HC` is the value under **Increase
/// Contrast**; leaving it out means the token does not change, which is right
/// for most of them.
///
/// This matched two of the platform's four appearance names for a year, so
/// Increase Contrast — the one system setting whose whole job is making an app
/// like this readable — produced a screen byte for byte identical to
/// everybody else's. The measured contrast column was a reading at the default
/// setting only (D-340).
private func dyn(light: UInt32, dark: UInt32,
                 lightHC: UInt32? = nil, darkHC: UInt32? = nil,
                 alpha: CGFloat = 1, alphaHC: CGFloat? = nil) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        // The appearance cannot answer this. `NSAppearance(named:
        // .accessibilityHighContrastDarkAqua)` reports its own `name` as plain
        // `NSAppearanceNameDarkAqua`, and `bestMatch` says the same, so a
        // high-contrast appearance is indistinguishable from an ordinary one
        // — proved with a probe, after the first version of this shipped a
        // test that failed for exactly that reason. The workspace flag is the
        // only thing that knows, and it is the sibling of the one
        // `Motion.reduce` already reads.
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isHigh = Tokens.increaseContrast()
        let hex = isDark ? (isHigh ? (darkHC ?? dark) : dark)
                         : (isHigh ? (lightHC ?? light) : light)
        return NSColor(hex: hex, alpha: isHigh ? (alphaHC ?? alpha) : alpha)
    })
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
