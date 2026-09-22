import AppKit

/// The raw value is the case name, which is what a stored key override is
/// filed under (D-175). Renaming a case therefore drops that command's
/// override back to its default, which is the right way round: a binding whose
/// command no longer exists should not survive.
enum Command: String, CaseIterable, Sendable {
    // Navigate
    case next, previous, up, down, first, last
    case extendNext, extendPrevious
    // View
    case enterSingle, confirm, cancel
    case zoomToggle, zoomIn, zoomOut, zoomToFace
    case setCompareAnchor, toggleCompare, compareSideBySide, survey, tournament
    case toggleFocusMode
    /// The keyboard's walk along the preview bar (D-157).
    case barNext, barPrevious
    // Declaration order is the order the shortcuts overlay and the command
    // palette list them in, so the panels come before the help that explains
    // them. `toggleHelp` sitting second put it between the info panel and the
    // filmstrip, which is how the filmstrip ended up below the fold of its own
    // group (D-122).
    case toggleInfo, toggleFilmstrip, toggleClipping, toggleFocusPeaking, toggleHelp
    // Cull
    case flagKeep, flagReject, unflag
    case labelRed, labelYellow, labelGreen, labelBlue, labelPurple, clearLabel
    case toggleFavorite
    /// The folder narrowed to what was loved, and back (D-176).
    case filterFavorites
    case toggleAutoAdvance
    // Files
    case trash, undo, reviewRejects
    case rotateCW, rotateCCW, crop, adjust, saveOverOriginal, revertToOriginal
    case moveToFolder, moveToLastFolder, copyToFolder, pasteHere, clearClipboard
    case openInEditor, ingest, slideshow, previewOnOtherScreen
    case rename, batchRename
    case revealInFinder, copy, copyImage, copyName, copyPath, openWith, toggleTrashPanel
    // Select
    case toggleSelect, selectAll
    // App
    case openFolder, openParent, openSubfolder, back, forward, nextFolder, previousFolder, goToPath, search, showSummary
    case toggleSidebar, togglePin, jumpToFolder, commandPalette, newWindow, newTab
    case thumbsLarger, thumbsSmaller

    /// Moving the cursor, as opposed to acting on what it is on. The preview
    /// bar stays away for these: a command's result is what the bar is there to
    /// show, and arriving at the next photograph is not a result (D-199).
    static let navigation: Set<Command> = [
        .next, .previous, .up, .down, .first, .last, .extendNext, .extendPrevious,
    ]

    var label: String {
        switch self {
        case .next: "Next photo"
        case .previous: "Previous photo"
        case .up: "Up one row"
        case .down: "Down one row"
        case .first: "First photo"
        case .last: "Last photo"
        case .extendNext: "Extend selection forward"
        case .extendPrevious: "Extend selection back"
        case .enterSingle: "Open the preview window"
        case .confirm: "Save the crop or the adjustment, or close the preview"
        case .cancel: "Close the preview, cancel crop or adjust, clear selection"
        case .zoomToggle: "Toggle fit / 1:1"
        case .zoomIn: "Zoom in"
        case .zoomOut: "Zoom out"
        case .zoomToFace: "Zoom to the next face"
        case .setCompareAnchor: "Set this photo as A for compare"
        case .toggleCompare: "Flip between A and this photo"
        case .compareSideBySide: "Show A and this photo side by side"
        case .survey: "Survey: the selection, all at once"
        case .tournament: "Tournament: hold the best so far and beat it"
        case .toggleFocusMode: "Focus mode: the photo and nothing else"
        case .barNext: "Next control in the bar over the photo"
        case .barPrevious: "Previous control in the bar over the photo"
        case .toggleInfo: "Show or hide info panel"
        case .toggleHelp: "Show or hide this help"
        case .toggleFilmstrip: "Show or hide the filmstrip"
        case .toggleClipping: "Show or hide blown highlights"
        case .toggleFocusPeaking: "Paint the edges that are in focus"
        case .flagKeep: "Flag keep"
        case .flagReject: "Flag reject"
        case .unflag: "Clear flag"
        case .labelRed: "Label red"
        case .labelYellow: "Label yellow"
        case .labelGreen: "Label green"
        case .labelBlue: "Label blue"
        case .labelPurple: "Label purple"
        case .clearLabel: "Clear the color label"
        case .toggleFavorite: "Favorite / unfavorite"
        case .filterFavorites: "Show only favorites"
        case .toggleAutoAdvance: "Toggle auto-advance after a decision"
        case .trash: "Move to Trash"
        case .undo: "Undo last file operation"
        case .reviewRejects: "Review the rejects before trashing them"
        case .rotateCW: "Rotate clockwise"
        case .rotateCCW: "Rotate counterclockwise"
        case .crop: "Crop (drag, then Return for a copy or ⇧Return to save over)"
        case .adjust: "Adjust: ten sliders, then Return. Writes a copy"
        case .saveOverOriginal: "Save the crop or the adjustment into the photo"
        case .revertToOriginal: "Show the original of a photo that was written into, to put it back"
        case .moveToFolder: "Move to folder…"
        case .moveToLastFolder: "Move to the last folder again"
        case .copyToFolder: "Copy to a folder, leaving the original"
        case .pasteHere: "Paste a copy of the clipboard into this folder"
        case .clearClipboard: "Empty the clipboard"
        case .openInEditor: "Open the selection in an editor"
        case .ingest: "Copy photos off a card"
        case .slideshow: "Slideshow, full screen"
        case .previewOnOtherScreen: "Move the preview to the other display"
        case .rename: "Rename"
        case .batchRename: "Batch rename selection"
        case .revealInFinder: "Reveal in Finder"
        case .copy: "Copy file"
        case .copyImage: "Copy the picture, to paste into anything"
        case .copyName: "Copy the filename"
        case .copyPath: "Copy the folder path"
        case .openWith: "Open in default app"
        case .toggleTrashPanel: "What went to the Trash this sitting"
        case .toggleSelect: "Select / deselect this photo"
        case .selectAll: "Select all"
        case .openFolder: "Open a folder"
        case .openParent: "Open the enclosing folder"
        case .openSubfolder: "Go down into a subfolder"
        case .back: "Back to the folder before this one"
        case .forward: "Forward again"
        case .nextFolder: "The next folder beside this one"
        case .previousFolder: "The folder before this one"
        case .goToPath: "Go to a folder by path"
        case .toggleSidebar: "Show or hide the folder sidebar"
        case .togglePin: "Pin this folder to the sidebar"
        case .jumpToFolder: "Jump to a folder by name"
        case .commandPalette: "Find a command by name"
        case .newWindow: "A second gallery on this folder"
        case .newTab: "This folder in a tab of this window"
        case .thumbsLarger: "Larger thumbnails"
        case .thumbsSmaller: "Smaller thumbnails"
        case .search: "Filter by filename"
        case .showSummary: "Summary of this sitting"
        }
    }

    var group: String {
        switch self {
        case .next, .previous, .up, .down, .first, .last, .extendNext, .extendPrevious: "Navigate"
        // Three groups where there was one. "View" held twenty-two commands
        // against Navigate's eight, so the overlay's two-column grid made its
        // first row twenty-two rows tall and everything from the info panel
        // down sat below the fold. `f` was in the list and still unfindable,
        // which is the same failure as a command with no control at all
        // (D-122).
        case .enterSingle, .confirm, .cancel, .zoomToggle, .zoomIn, .zoomOut, .zoomToFace,
             .toggleFocusMode, .slideshow, .previewOnOtherScreen,
             // The walk along the bar is about the preview window rather than
             // about a panel, and Panels is capped at eight so the filmstrip
             // stays above the fold of the overlay's grid (D-122).
             .barNext, .barPrevious: "View"
        case .setCompareAnchor, .toggleCompare, .compareSideBySide, .survey, .tournament: "Compare"
        case .toggleInfo, .toggleFilmstrip, .toggleClipping, .toggleFocusPeaking, .toggleHelp,
             .thumbsLarger, .thumbsSmaller: "Panels"
        case .filterFavorites,
             .flagKeep, .flagReject, .unflag, .toggleFavorite, .toggleAutoAdvance,
             .labelRed, .labelYellow, .labelGreen, .labelBlue, .labelPurple, .clearLabel: "Decide"
        // Files was eighteen and App fifteen, for the same reason View was
        // twenty-two: the group was "everything to do with the filesystem"
        // rather than a thing a reader would look under.
        case .trash, .undo, .reviewRejects, .moveToFolder, .moveToLastFolder, .copyToFolder,
             .pasteHere, .clearClipboard,
             .ingest, .toggleTrashPanel: "Files"
        case .rotateCW, .rotateCCW, .crop, .adjust, .saveOverOriginal, .revertToOriginal, .rename, .batchRename: "Edit"
        case .openInEditor, .revealInFinder, .copy, .copyImage, .copyName, .copyPath, .openWith: "Hand off"
        case .toggleSelect, .selectAll: "Select"
        case .openFolder, .openParent, .openSubfolder, .back, .forward,
             .nextFolder, .previousFolder, .goToPath, .jumpToFolder: "Folders"
        case .toggleSidebar, .togglePin, .commandPalette, .newWindow, .newTab, .search, .showSummary: "App"
        }
    }

    /// The order the help overlay lays them out in, two columns at a time.
    /// Paired so neither column of a row is much taller than the other: a row
    /// is as tall as its tallest group, and one long group pushes everything
    /// after it off the first screen.
    /// "Decide" was "Cull" until 2026-09-17. It is the word the trade uses and
    /// most people have never met it; the ones who have know it from livestock
    /// (D-204). Deciding about a photograph is what the group does.
    static let groups = ["Navigate", "View", "Compare", "Panels", "Decide", "Folders",
                         "Files", "Edit", "Hand off", "App", "Select"]

    /// The switches in Settings that govern this command. Most have none: keep,
    /// reject, trash, undo and the arrows are the app rather than a feature of
    /// it (D-123).
    ///
    /// A set rather than one feature, because two of them are shared. ⇧Return
    /// saves a crop or an adjustment into the photograph and ⇧R takes either
    /// one off again, so each is reachable while *either* feature is on and
    /// gone when both are off. It was one optional `Feature`, which made
    /// saving a crop over the original a command the adjust switch could turn
    /// off (D-239).
    var features: Set<Feature> {
        switch self {
        case .setCompareAnchor, .toggleCompare, .compareSideBySide: [.compare]
        case .survey: [.survey]
        case .toggleFocusMode: [.bare]
        case .tournament: [.tournament]
        case .toggleClipping: [.highlights]
        case .toggleFocusPeaking: [.focusPeaking]
        case .zoomToFace: [.faces]
        case .crop: [.crop]
        case .adjust: [.adjust]
        case .saveOverOriginal, .revertToOriginal: [.crop, .adjust]
        case .slideshow: [.slideshow]
        case .showSummary: [.summary]
        default: []
        }
    }

}

/// A keystroke, normalized. Special keys by keyCode, printable keys by character.
struct Key: Hashable, Sendable {
    enum Base: Hashable, Sendable {
        case char(Character)
        case code(UInt16)
    }
    let base: Base
    let command: Bool
    let shift: Bool
    let control: Bool

    static func char(_ c: Character, cmd: Bool = false, shift: Bool = false, ctrl: Bool = false) -> Key {
        Key(base: .char(c), command: cmd, shift: shift, control: ctrl)
    }
    static func code(_ k: UInt16, cmd: Bool = false, shift: Bool = false, ctrl: Bool = false) -> Key {
        Key(base: .code(k), command: cmd, shift: shift, control: ctrl)
    }

    static let left = code(123), right = code(124), down = code(125), up = code(126)
    static let returnKey = code(36), escape = code(53), space = code(49), delete = code(51)
    static let home = code(115), end = code(119)
    /// Tab, and the one key in the table that has to carry a modifier in its
    /// own name: ⇧Tab is how every Mac walks a row backwards (D-157).
    static let tabKey: UInt16 = 48
    static let tab = code(tabKey)
    static func tab(shift: Bool) -> Key { code(tabKey, shift: shift) }

    private static let specialCodes: Set<UInt16> = [123, 124, 125, 126, 36, 53, 49, 51, 115, 119, 48]

    init(base: Base, command: Bool, shift: Bool, control: Bool = false) {
        self.base = base; self.command = command; self.shift = shift; self.control = control
    }

    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Option rewrites the character (⌥z is Ω), so those events pass through untouched.
        if mods.contains(.option) { return nil }
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        let ctrl = mods.contains(.control)
        if Self.specialCodes.contains(event.keyCode) {
            self.init(base: .code(event.keyCode), command: cmd, shift: shift, control: ctrl)
        } else if let c = event.charactersIgnoringModifiers?.first {
            // Shifted punctuation ("?", "+") arrives as its own character; letters are lowercased.
            self.init(base: .char(Character(c.lowercased())), command: cmd, shift: shift && c.isLetter, control: ctrl)
        } else {
            return nil
        }
    }

    /// The stored form of a keystroke: three flags, then the base. The base is
    /// the rest of the string rather than another delimited field, because the
    /// character it holds can be `-`, `:` or `+` and every delimiter worth
    /// picking is a key somebody can press (D-175).
    var stored: String {
        let flags = "\(command ? "1" : "0")\(shift ? "1" : "0")\(control ? "1" : "0")"
        switch base {
        case .char(let c): return "\(flags):char:\(c)"
        case .code(let k): return "\(flags):code:\(k)"
        }
    }

    init?(stored: String) {
        guard stored.count > 8 else { return nil }
        let flags = Array(stored.prefix(3))
        guard flags.allSatisfy({ $0 == "0" || $0 == "1" }) else { return nil }
        let rest = String(stored.dropFirst(4))
        let base: Base
        if rest.hasPrefix("char:"), let c = rest.dropFirst(5).first, rest.dropFirst(5).count == 1 {
            base = .char(c)
        } else if rest.hasPrefix("code:"), let k = UInt16(rest.dropFirst(5)) {
            base = .code(k)
        } else {
            return nil
        }
        self.init(base: base, command: flags[0] == "1", shift: flags[1] == "1", control: flags[2] == "1")
    }

    /// Keys the app will not let you claim. Escape is every cancel in the app,
    /// including the one that backs out of recording a key; ⌘Q and ⌘W are the
    /// window and the app, and the local monitor sees a keystroke before the
    /// menu does, so binding one of them would take Quit away rather than
    /// share it (D-175).
    static let reserved: [Key: String] = [
        .escape: "Esc cancels everything in the app, including this.",
        .char("q", cmd: true): "⌘Q is Quit.",
        .char("w", cmd: true): "⌘W closes the window.",
    ]

    /// Display form for the help overlay.
    var display: String {
        var s = ""
        if control { s += "⌃" }
        if command { s += "⌘" }
        if shift { s += "⇧" }
        switch base {
        case .char(let c): s += c == " " ? "Space" : String(c).uppercased()
        case .code(let k):
            let name: String = switch k {
            case 123: "←"; case 124: "→"; case 125: "↓"; case 126: "↑"
            case 36: "Return"; case 53: "Esc"; case 49: "Space"; case 51: "Delete"
            case 115: "Home"; case 119: "End"; case 48: "Tab"
            default: "key \(k)"
            }
            s += name
        }
        return s
    }
}

/// The single table every keystroke goes through (D-7). The help overlay reads it too.
struct KeyMap: Sendable {
    struct Binding: Sendable {
        let keys: [Key]
        let command: Command
        /// Nil means either window.
        let focus: WindowFocus?
    }

    let bindings: [Binding]

    static let standard = KeyMap(bindings: [
        // Navigate
        .init(keys: [.right, .char("j")], command: .next, focus: nil),
        .init(keys: [.left, .char("k")], command: .previous, focus: nil),
        .init(keys: [.up], command: .up, focus: .gallery),
        .init(keys: [.down], command: .down, focus: .gallery),
        .init(keys: [.up], command: .previous, focus: .preview),
        .init(keys: [.down], command: .next, focus: .preview),
        .init(keys: [.home, .code(123, cmd: true)], command: .first, focus: nil),
        .init(keys: [.end, .code(124, cmd: true)], command: .last, focus: nil),
        .init(keys: [.code(124, shift: true)], command: .extendNext, focus: .gallery),
        .init(keys: [.code(123, shift: true)], command: .extendPrevious, focus: .gallery),
        // View
        // Space is Quick Look everywhere on this platform and zoom-to-100% in
        // Lightroom. It used to mean "next photo" here, which is the one thing
        // nobody expects of the most reflexive key on the keyboard (D-95).
        .init(keys: [.returnKey, .space], command: .enterSingle, focus: .gallery),
        .init(keys: [.returnKey], command: .confirm, focus: .preview),
        // Tab walks the bar and Return presses what it lands on (D-157). The
        // key was unbound and AppKit's own focus loop had nothing to move
        // between in this window, so nothing was lost by taking it.
        .init(keys: [.tab], command: .barNext, focus: .preview),
        .init(keys: [.tab(shift: true)], command: .barPrevious, focus: .preview),
        .init(keys: [.escape], command: .cancel, focus: nil),
        // Tap toggles 1:1; holding it peeks and releases back to fit (KeyMonitor handles the release).
        .init(keys: [.char("z"), .space], command: .zoomToggle, focus: .preview),
        .init(keys: [.char("z", shift: true)], command: .zoomToFace, focus: .preview),
        .init(keys: [.char("f")], command: .toggleFilmstrip, focus: .preview),
        .init(keys: [.char("h")], command: .toggleClipping, focus: .preview),
        // Next to the highlights key, because they are the same question asked
        // of two different things: what is blown, and what is sharp.
        .init(keys: [.char("g")], command: .toggleFocusPeaking, focus: .preview),
        .init(keys: [.char("="), .char("+")], command: .zoomIn, focus: .preview),
        .init(keys: [.char("-")], command: .zoomOut, focus: .preview),
        // `a` because the letter is drawn on screen: the grid badges the
        // anchored cell `A`, the tag over the photograph says `A · name`, and
        // side by side captions its two panes A and B. It was `b`, from the
        // phrase "A/B", which put the key and every label in the app one
        // letter apart — "press b to set this photo as A" (D-269).
        .init(keys: [.char("a")], command: .setCompareAnchor, focus: nil),
        .init(keys: [.char("\\")], command: .toggleCompare, focus: .preview),
        // Shift-backslash arrives as "|", because shift rewrites punctuation
        // before the event reaches us. Bound as what the keyboard actually
        // sends, so the help overlay shows the character on the keycap.
        .init(keys: [.char("|")], command: .compareSideBySide, focus: .preview),
        // Lightroom's survey is N; `n` renames here, so the other letter in
        // the word. Both live beside the compare keys. Tournament keeps `⇧B`
        // through D-269: it was chosen as the shifted twin of the anchor and
        // is now nobody's twin, but `⇧A` is adjust and every other letter in
        // "tournament" is taken, so a worse key would be the only change.
        .init(keys: [.char("v")], command: .survey, focus: nil),
        .init(keys: [.char("b", shift: true)], command: .tournament, focus: nil),
        .init(keys: [.char("f", shift: true)], command: .toggleFocusMode, focus: .preview),
        .init(keys: [.char("i")], command: .toggleInfo, focus: nil),
        .init(keys: [.char("?")], command: .toggleHelp, focus: nil),
        // Cull
        .init(keys: [.char("p")], command: .flagKeep, focus: nil),
        .init(keys: [.char("x")], command: .flagReject, focus: nil),
        .init(keys: [.char("u")], command: .unflag, focus: nil),
        // The key Photos uses for the same idea, and the one key a cull can
        // reach without leaving the flags under the other hand.
        .init(keys: [.char(".")], command: .toggleFavorite, focus: nil),
        // Shift and the same key, the way `⇧X` reviews what `x` rejected: the
        // shifted flag key is "show me the ones I put here" (D-176). Bound as
        // `>` because that is what the keyboard sends, the way `?` and `|` are.
        .init(keys: [.char(">")], command: .filterFavorites, focus: nil),
        // `o`, for carrying on to the next frame. It held `a` until D-269,
        // where the anchor needed the letter it is labeled with and this had
        // only the first letter of its own name: `o` is a step down in
        // mnemonic and the shortest reach of the free letters from `p` and
        // `x`, which is where the hand rests during a cull. Caps Lock is
        // still the way to do it without a toggle at all.
        .init(keys: [.char("o")], command: .toggleAutoAdvance, focus: nil),
        // The five Lightroom has, on the five keys Lightroom uses (D-96).
        .init(keys: [.char("1")], command: .labelRed, focus: nil),
        .init(keys: [.char("2")], command: .labelYellow, focus: nil),
        .init(keys: [.char("3")], command: .labelGreen, focus: nil),
        .init(keys: [.char("4")], command: .labelBlue, focus: nil),
        .init(keys: [.char("5")], command: .labelPurple, focus: nil),
        .init(keys: [.char("0")], command: .clearLabel, focus: nil),
        // Files
        .init(keys: [.delete, .char("d")], command: .trash, focus: nil),
        // ⌃Z is not a Mac convention, but it is muscle memory worth honoring.
        .init(keys: [.char("z", cmd: true), .char("z", ctrl: true)], command: .undo, focus: nil),
        .init(keys: [.char("]")], command: .rotateCW, focus: nil),
        .init(keys: [.char("[")], command: .rotateCCW, focus: nil),
        .init(keys: [.char("c")], command: .crop, focus: .preview),
        // `a` is auto-advance and every other letter in the word is taken, so
        // the shifted one. It sits with crop because they are the same kind of
        // thing: a mode over the photograph that ends in a copy.
        .init(keys: [.char("a", shift: true)], command: .adjust, focus: .preview),
        // Return saves a copy, so the shifted Return is the heavier half of the
        // same gesture: save over the original (D-163).
        .init(keys: [.code(36, shift: true)], command: .saveOverOriginal, focus: .preview),
        // ⇧R beside ⇧A, because reverting is the other end of adjusting rather
        // than a file command: it is the one undo in the app that still works
        // in a session the edit was not made in (D-165).
        .init(keys: [.char("r", shift: true)], command: .revertToOriginal, focus: .preview),
        .init(keys: [.char("m")], command: .moveToFolder, focus: nil),
        .init(keys: [.char("m", shift: true)], command: .moveToLastFolder, focus: nil),
        .init(keys: [.char("c", shift: true)], command: .copyToFolder, focus: nil),
        .init(keys: [.char("e")], command: .openInEditor, focus: nil),
        .init(keys: [.char("i", cmd: true, shift: true)], command: .ingest, focus: nil),
        .init(keys: [.char("y")], command: .slideshow, focus: nil),
        .init(keys: [.char("w", cmd: true, shift: true)], command: .previewOnOtherScreen, focus: nil),
        .init(keys: [.char("n")], command: .rename, focus: nil),
        .init(keys: [.char("n", shift: true)], command: .batchRename, focus: nil),
        .init(keys: [.char("r", cmd: true, shift: true)], command: .revealInFinder, focus: nil),
        .init(keys: [.char("c", cmd: true)], command: .copy, focus: nil),
        .init(keys: [.char("v", cmd: true)], command: .pasteHere, focus: nil),
        .init(keys: [.char("v", cmd: true, shift: true)], command: .clearClipboard, focus: nil),
        // `⌃⌘` rather than `⌥⌘`, which is the more usual home for a "copy as":
        // a `Key` carries command, shift and control and has never carried
        // option, and adding a fourth modifier to the stored form to place two
        // bindings is a bigger change than the bindings are worth.
        .init(keys: [.char("c", cmd: true, ctrl: true)], command: .copyImage, focus: nil),
        .init(keys: [.char("n", cmd: true, ctrl: true)], command: .copyName, focus: nil),
        .init(keys: [.char("c", cmd: true, shift: true)], command: .copyPath, focus: nil),
        .init(keys: [.code(125, cmd: true, shift: false)], command: .openWith, focus: .preview),
        .init(keys: [.char("o", cmd: true, shift: true)], command: .openWith, focus: nil),
        .init(keys: [.char("t")], command: .toggleTrashPanel, focus: nil),
        .init(keys: [.char("x", shift: true)], command: .reviewRejects, focus: nil),
        // Select
        .init(keys: [.char("s")], command: .toggleSelect, focus: nil),
        .init(keys: [.char("a", cmd: true)], command: .selectAll, focus: .gallery),
        // App
        .init(keys: [.char("o", cmd: true)], command: .openFolder, focus: nil),
        .init(keys: [.code(126, cmd: true)], command: .openParent, focus: nil),
        .init(keys: [.code(125, cmd: true)], command: .openSubfolder, focus: .gallery),
        .init(keys: [.char("[", cmd: true)], command: .back, focus: .gallery),
        .init(keys: [.char("]", cmd: true)], command: .forward, focus: .gallery),
        .init(keys: [.code(124, cmd: true, shift: true)], command: .nextFolder, focus: nil),
        .init(keys: [.code(123, cmd: true, shift: true)], command: .previousFolder, focus: nil),
        .init(keys: [.char("g", cmd: true, shift: true)], command: .goToPath, focus: nil),
        .init(keys: [.char("\\", cmd: true)], command: .toggleSidebar, focus: .gallery),
        .init(keys: [.char("d", cmd: true)], command: .togglePin, focus: nil),
        .init(keys: [.char("k", cmd: true)], command: .jumpToFolder, focus: nil),
        .init(keys: [.char("k", cmd: true, shift: true)], command: .commandPalette, focus: nil),
        .init(keys: [.char("n", cmd: true)], command: .newWindow, focus: nil),
        .init(keys: [.char("t", cmd: true)], command: .newTab, focus: .gallery),
        .init(keys: [.char("/")], command: .search, focus: .gallery),
        .init(keys: [.char("s", cmd: true, shift: true)], command: .showSummary, focus: nil),
        // The gallery's zoom is the cell size; the preview's is the photo. Same
        // pair of keys, told apart by which window is key.
        .init(keys: [.char("=", cmd: true), .char("+", cmd: true)], command: .thumbsLarger, focus: .gallery),
        .init(keys: [.char("-", cmd: true)], command: .thumbsSmaller, focus: .gallery),
    ])

    /// The defaults with a reader's own bindings laid over them (D-175). An
    /// override replaces every key a command had rather than adding to them,
    /// which is what "reassign" means and what makes the row in Settings
    /// readable: one command, the key it is on now, and a way back.
    ///
    /// The overridden bindings are put first. `bound` takes the first match,
    /// so a key moved onto a command wins over whatever default still names
    /// it, and the stale default is dropped below rather than left to shadow.
    func applying(_ overrides: [Command: [Key]]) -> KeyMap {
        guard !overrides.isEmpty else { return self }
        let moved = Set(overrides.values.flatMap { $0 })
        let rest = bindings.compactMap { b -> Binding? in
            guard overrides[b.command] == nil else { return nil }
            let kept = b.keys.filter { !moved.contains($0) }
            return kept.isEmpty ? nil : Binding(keys: kept, command: b.command, focus: b.focus)
        }
        // The focus a command was bound with is the focus it keeps: a
        // reassignment changes which key, never which window answers to it.
        let placed = overrides.compactMap { command, keys -> [Binding] in
            let focuses = bindings.filter { $0.command == command }.map(\.focus)
            return (focuses.isEmpty ? [nil] : focuses).map { Binding(keys: keys, command: command, focus: $0) }
        }.flatMap { $0 }
        return KeyMap(bindings: placed + rest)
    }

    /// Which command holds a key, ignoring whether its feature is switched on:
    /// a key that is taken is taken either way, and a conflict the reader
    /// cannot see because the feature is off is the worst kind (D-175).
    func holder(of key: Key) -> Command? {
        bindings.first { $0.keys.contains(key) }?.command
    }

    /// The command a keystroke means, or nil. `features` is what a switched
    /// off feature costs its keys: the binding is still in the table — the
    /// table is a constant and the shortcuts overlay reads the same one — but
    /// the key does not resolve to it. A key that silently does something the
    /// reader turned off is worse than a key that does nothing (D-123).
    func command(for key: Key, focus: WindowFocus, features: FeatureSet = .everything) -> Command? {
        guard let found = bound(key, focus: focus), features.allows(found) else { return nil }
        return found
    }

    private func bound(_ key: Key, focus: WindowFocus) -> Command? {
        bindings.first { b in (b.focus == nil || b.focus == focus) && b.keys.contains(key) }?.command
    }

    /// Whether a command answers to a typed query, by its name, its group or
    /// one of its keys. The shortcuts overlay and the Settings panel both
    /// narrow their list with this, and they narrow it the same way because
    /// there is one implementation rather than two that agree (D-175).
    func matches(_ command: Command, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if command.label.localizedCaseInsensitiveContains(query) { return true }
        if command.group.localizedCaseInsensitiveContains(query) { return true }
        return keys(for: command).contains { $0.display.localizedCaseInsensitiveContains(query) }
    }

    func keys(for command: Command) -> [Key] {
        var seen: Set<Key> = []
        return bindings.filter { $0.command == command }.flatMap(\.keys).filter { seen.insert($0).inserted }
    }
}
