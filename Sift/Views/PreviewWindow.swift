import SwiftUI

/// The preview window: one photo, the filmstrip, and the info panel. Separate
/// from the gallery so both can be on screen at once (D-28).
struct PreviewWindow: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    /// The bar is there while the pointer is *moving* over the photograph, for
    /// `barIdle` after it stops, and gone when it leaves, so the photograph is
    /// bare whenever nobody is reaching for anything (DESIGN exception 2).
    ///
    /// Presence was the rule until 2026-09-17 and it was the wrong one: a hand
    /// resting on the trackpad is not reaching for a control, so anybody
    /// arrowing through a folder with the pointer parked over the picture
    /// never got a clean look at a frame (D-199).
    @State private var pointerAwake = false
    /// Bumped by every pointer move, which is what restarts the countdown.
    @State private var pointerMoves = 0
    /// The last place the pointer was, so a hover event caused by the bar
    /// appearing or going under the pointer does not read as a move.
    @State private var lastPoint: CGPoint?
    /// The pointer is on the bar itself, which is reaching for a control even
    /// when it has stopped: a row of buttons that vanishes while somebody is
    /// deciding which one to press is worse than one that never went away.
    @State private var barHovered = false
    /// And it comes back for a moment after any keystroke, because the pointer
    /// rule alone made the controls invisible to someone working entirely from
    /// the keyboard — which is most of the time, in this app (D-64).
    @State private var keyboardReveal = false
    /// The window this scene is in, reported by the view rather than looked up
    /// by title (D-102). Both the slideshow and the display move ask it.
    @State private var box = WindowBox()

    /// Cropping is a drag over the bottom of the photo, and the bar is what you
    /// would drag across.
    /// `SIFT_BAR=1` pins it up for one launch. The bar is deliberately absent
    /// unless somebody is reaching for it (DESIGN exception 2), which makes it
    /// the one screen a script cannot photograph: no pointer to put in the
    /// window, and the keystroke reveal has faded long before the capture.
    /// Read once, like every other `SIFT_` (D-112, D-123).
    private static let pinnedForScreenshot =
        Launch.isOn(ProcessInfo.processInfo.environment["SIFT_BAR"])

    private var barVisible: Bool {
        // The bar stays up for as long as the keyboard is on one of its
        // controls: a ring that fades while it is being walked is a ring
        // nobody can follow (D-157).
        (pointerAwake || barHovered || keyboardReveal || store.barCursor != nil
            || Self.pinnedForScreenshot) && !store.cropping && !store.reverting
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let ref = store.current {
                    ZStack(alignment: .bottom) {
                        SingleView()
                            .contextMenu { PhotoMenu(ref: ref, store: store, router: router) }
                        if barVisible {
                            PreviewBar(ref: ref)
                                .transition(.opacity)
                                .onHover { barHovered = $0 }
                        }
                        // The crop bar takes the preview bar's place for as
                        // long as the mode runs, rather than sitting beside it:
                        // the twelve controls up there are about the
                        // photograph, and while a box is on it the question is
                        // the box (D-238). It does not come and go with the
                        // pointer either — the mode is what it belongs to.
                        if store.cropping {
                            CropBar()
                        }
                        // The same slot again: three modes, one place a mode's
                        // own controls go (D-240).
                        if store.reverting {
                            RevertBar()
                        }
                        // The band that reports sits in the bottom left corner
                        // whatever else is up. The bars are centered, so there
                        // is nothing to clear (D-282).
                        StatusOverlay(window: .preview)
                    }
                    if store.showFilmstrip { Filmstrip() }
                } else {
                    ZStack {
                        Tokens.Surface.sunken
                        Text("No photo")
                            .textStyle(.body, color: Tokens.Text.secondary)
                        StatusOverlay(window: .preview)
                    }
                }
            }
            if store.showInfo { InfoPanel().frame(width: Tokens.Layout.infoPanel) }
            if store.adjusting { AdjustPanel().frame(width: Tokens.Layout.adjustPanel) }
        }
        // The panels arrive without animating. Opening one inserts 320pt into
        // this row, so every animated frame of it re-fits the photograph at a
        // new width — the photograph slides left and scales at the same time,
        // which is the one thing the motion rules say not to do: animate
        // transform and opacity, never a reflow of the neighbors (D-210).
        //
        // There is nothing here to replace it with. A slide would have to be
        // the panel moving over a photograph that has already taken its new
        // size, and an adjust panel that covers the photograph it adjusts is
        // worse than one that simply appears. Readers with Reduce Motion on
        // have had this behavior all along, because `Motion.panel` was nil
        // for them, and it is the better one.
        .animation(nil, value: store.showInfo)
        .animation(nil, value: store.adjusting)
        .animation(Tokens.Motion.fast, value: barVisible)
        // Movement, not presence. `.onContinuousHover` reports a point on every
        // pointer event inside the window and `.ended` when it leaves; the
        // point is compared because the bar arriving under a still pointer
        // generates events of its own, and those are not somebody reaching.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                guard point != lastPoint else { return }
                lastPoint = point
                pointerAwake = true
                pointerMoves &+= 1
            case .ended:
                lastPoint = nil
                pointerAwake = false
                barHovered = false
            }
        }
        // Restarted by every move, so the countdown is always measured from the
        // last one rather than from the first.
        .task(id: pointerMoves) {
            guard pointerAwake else { return }
            try? await Task.sleep(for: Tokens.Motion.barIdle)
            guard !Task.isCancelled else { return }
            pointerAwake = false
        }
        // A cull ends by showing someone (D-90). Full screen, one photo, and
        // the arrows still work if you would rather drive.
        .task(id: store.slideshow) {
            guard store.slideshow else { return }
            while !Task.isCancelled, store.slideshow {
                try? await Task.sleep(for: .seconds(store.slideSeconds))
                guard !Task.isCancelled, store.slideshow else { return }
                if store.isAtLastPhoto { store.moveToFirst() } else { store.move(by: 1) }
            }
        }
        .onChange(of: store.slideshow) { _, on in
            guard let window = box.window else { return }
            let isFull = window.styleMask.contains(.fullScreen)
            if on != isFull { window.toggleFullScreen(nil) }
        }
        // Any command performed while this window has the keyboard bumps the
        // pulse; the bar shows itself and then goes back to being absent.
        .task(id: store.barPulse) {
            guard store.barPulse > 0 else { return }
            keyboardReveal = true
            try? await Task.sleep(for: Tokens.Motion.barDwell)
            guard !Task.isCancelled else { return }
            keyboardReveal = false
        }
        .frame(minWidth: Tokens.Layout.previewMinWidth, minHeight: Tokens.Layout.previewMinHeight)
        .background(WindowFocusReporter(focus: .preview) { store.focus = $0 })
        .background(WindowReader {
            box.window = $0
            // There is one preview window, so it never tabs: without this it
            // joins a gallery's group when the system setting says to prefer
            // tabs, and the photograph ends up as a tab of the grid it came
            // from (D-370).
            $0?.tabbingMode = .disallowed
        })
        .navigationTitle(store.current?.name ?? "Preview")
        .sheet(item: Binding(get: { store.trashConfirm?.window == .preview ? store.trashConfirm : nil },
                             set: { if $0 == nil { store.trashConfirm = nil } })) { confirm in
            TrashConfirmSheet(confirm: confirm,
                              trash: { router.performTrash(confirm.refs) },
                              cancel: { store.trashConfirm = nil })
        }
        .sheet(isPresented: paletteHere) {
            CommandPalette(focus: .preview) { router.perform($0) }
        }
        .onAppear {
            store.previewOpen = true
            // Before anything else: the photograph's view is keyed on this,
            // and it has to change before the stale frame is drawn (D-375).
            store.notePreviewOpened()
            // Only a view can reach its own window, so the router borrows this
            // the way it borrows the two window openers (D-91). The window
            // comes from the box the scene fills, not from a title search
            // (D-102): this window is titled with the photo's filename.
            router.movePreviewToOtherScreen = { [weak store, box] in
                guard let store else { return }
                guard let window = box.window else { return }
                let screens = NSScreen.screens
                guard screens.count > 1 else {
                    store.showToast("There is only one display", undoable: false)
                    return
                }
                let here = window.screen ?? screens[0]
                let next = screens.first { $0 != here } ?? screens[0]
                // Filling the other screen is what "put it over there" means
                // when the other screen is the one somebody else is looking at.
                window.setFrame(next.visibleFrame, display: true, animate: true)
            }
        }
        .onDisappear {
            store.previewOpen = false
            store.focus = .gallery
            store.leaveFocusMode()
            store.slideshow = false
            pointerAwake = false
            barHovered = false
            lastPoint = nil
            keyboardReveal = false
        }
    }

    /// The palette is one sheet over one store shown by two scenes, so each
    /// scene presents only the one it was asked for (D-67).
    private var paletteHere: Binding<Bool> {
        Binding(get: { store.palette == .preview }, set: { if !$0 { store.palette = nil } })
    }
}

