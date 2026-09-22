import SwiftUI

/// Full-screen single photo. No chrome; state shows on keypress (DESIGN exception 2).
@MainActor
struct SingleView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var pinchStart: CGFloat?
    /// What the current crop drag is doing to the rect: drawing a new one,
    /// moving it, or pulling one of its edges (D-159). Set when the drag
    /// starts, from where it started, and cleared when it ends.
    @State private var cropGrip: CropGrip?
    @State private var pixelSize: CGSize?
    /// The size the current half of a side-by-side pair was painted at (D-155).
    @State private var pairDrawn: CGSize?
    /// Last known pointer position in view coordinates; zoom centers here.
    @State private var pointer: CGPoint?
    @State private var clipMask: DecodedImage?
    @State private var focusMask: DecodedImage?

    private var shown: PhotoRef? {
        store.showingCompare ? (store.compareRef ?? store.current) : store.current
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ground.ignoresSafeArea()
                if store.surveying, store.surveyRefs.count > 1 {
                    survey(store.surveyRefs, in: geo.size)
                } else if store.sideBySide, let a = store.compareRef, let b = store.current, a.url != b.url {
                    pair(a: a, b: b, in: geo.size)
                } else if let ref = shown {
                    let inset = Tokens.Space.s16
                    let avail = CGSize(width: geo.size.width - inset * 2, height: geo.size.height - inset * 2)
                    let fit = fitSize(for: pixelSize, in: avail)
                    let scale = resolvedScale(fit: fit)
                    let size = CGSize(width: fit.width * scale, height: fit.height * scale)

                    photo(ref)
                        .frame(width: size.width, height: size.height)
                        .offset(scale > 1 ? clampedPan(size: size, avail: avail) : .zero)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay {
                            if store.showClipping, let clipMask {
                                mask(clipMask, size: size, avail: avail, scale: scale)
                            }
                        }
                        .overlay {
                            if store.showFocusPeaking, let focusMask {
                                mask(focusMask, size: size, avail: avail, scale: scale)
                            }
                        }
                        .overlay { if store.cropping { cropOverlay(imageFrame: imageFrame(size: size, in: geo.size)) } }
                        .onContinuousHover { phase in
                            if case .active(let p) = phase { pointer = p }
                        }
                        .onChange(of: store.zoom) { old, new in
                            // Every step in, not only the first: the pixel under
                            // the pointer stays under the pointer, which is what
                            // every other viewer does (D-80).
                            guard let new, new > (old ?? 1), let p = pointer else { return }
                            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let was = old ?? 1
                            // Where the pointer sits in the image, then the pan
                            // that puts that same place back under it.
                            let inImage = CGPoint(x: (p.x - c.x - pan.width) / was, y: (p.y - c.y - pan.height) / was)
                            pan = CGSize(width: p.x - c.x - inImage.x * new, height: p.y - c.y - inImage.y * new)
                            pan = clampedPan(size: CGSize(width: fit.width * new, height: fit.height * new), avail: avail)
                            panStart = pan
                            remember(size: CGSize(width: fit.width * new, height: fit.height * new))
                        }
                        .task(id: "\(ref.contentID)|\(store.showClipping)") {
                            guard store.showClipping else { clipMask = nil; return }
                            let url = ref.url
                            clipMask = await Task.detached {
                                guard let img = await ImageLoader.shared.decode(url, maxPixels: Tokens.Layout.clippingPixels) else { return nil }
                                return PixelStats.clippingMask(of: img.cgImage, color: Tokens.State.rejectRGB).map(DecodedImage.init)
                            }.value
                        }
                        .task(id: "\(ref.contentID)|peak|\(store.showFocusPeaking)") {
                            guard store.showFocusPeaking else { focusMask = nil; return }
                            let url = ref.url
                            focusMask = await Task.detached {
                                guard let img = await ImageLoader.shared.decode(url, maxPixels: Tokens.Layout.peakingPixels) else { return nil }
                                return PixelStats.focusMask(of: img.cgImage, color: Tokens.State.keepRGB).map(DecodedImage.init)
                            }.value
                        }
                        // Somebody asked to look at one part of the photo: a
                        // face crop clicked, or ⇧Z (D-99). Zoom enough to fill
                        // the window with it, then put it in the middle.
                        .onChange(of: store.focusRequest) { _, target in
                            guard let target, target.width > 0, target.height > 0 else { return }
                            let wanted = min(1 / target.width, 1 / target.height)
                            store.zoom = max(1.01, min(wanted, store.oneToOneScale))
                            store.zoomIsActual = false
                            let scale = max(1, store.zoom ?? 1)
                            let size = CGSize(width: fit.width * scale, height: fit.height * scale)
                            // The center of the target, in the scaled photo,
                            // measured from the photo's own middle.
                            let wantedPan = clampedPan(
                                size: size,
                                avail: avail,
                                from: CGSize(width: -(target.midX - 0.5) * size.width,
                                             height: -(target.midY - 0.5) * size.height))
                            // Travelled rather than cut. The photograph does
                            // not teleport under a hand, and the distance the
                            // view covers is what says where it went (D-274).
                            withAnimation(Tokens.Motion.travel) { pan = wantedPan }
                            panStart = wantedPan
                            store.lookingAt = LibraryStore.look(fromPan: wantedPan, in: size)
                            store.focusRequest = nil
                        }
                        // What the histogram is a histogram of (D-76).
                        .onChange(of: visible(size: size, avail: avail, scale: scale), initial: true) { _, r in
                            store.visibleRect = r
                        }
                        .gesture(dragGesture(size: size, avail: avail, imageFrame: imageFrame(size: size, in: geo.size)))
                        .simultaneousGesture(magnifyGesture(fit: fit))
                        .onTapGesture(count: 2) { store.toggleActualSize() }
                        .task(id: ref.contentID) {
                            pixelSize = await Task.detached { ImageLoader.pixelSize(of: ref.url).map { CGSize(width: $0.width, height: $0.height) } }.value
                        }
                        // The next photograph, on the place this one was
                        // showing. This used to be `pan = .zero` in the task
                        // above, which quietly undid the rule written twenty
                        // lines below it: the zoom survived a cursor move and
                        // the position did not, so a burst walked at 20%
                        // snapped back to the middle of every frame (D-273).
                        .onChange(of: ref.contentID) { _, _ in restoreLook(fit: fit, avail: avail) }
                        // And again once this photograph's own size is known,
                        // because the fit above was still the last one's.
                        .onChange(of: fit) { _, f in restoreLook(fit: f, avail: avail) }
                        .onChange(of: fit, initial: true) { _, f in
                            if let px = pixelSize, f.width > 0 { store.oneToOneScale = max(1, px.width / f.width) }
                        }
                        // A ratio is chosen in the bar and lands on the box up
                        // here, which is where the photograph's own shape is
                        // known (D-238).
                        .onChange(of: store.cropRatio) { _, _ in reshapeCrop() }
                        .onChange(of: store.cropRatioTurned) { _, _ in reshapeCrop() }

                    VStack {
                        HStack {
                            // Which of the two you are looking at, and nothing
                            // about how to see the other one: the flip is a
                            // control in the bar now, so a tag naming its key
                            // would be the second definition of one command
                            // (D-268).
                            if store.showingCompare { Tag("A  ·  \(ref.name)") }
                            else if store.compareAnchor != nil, store.compareAnchor != ref.url { Tag("B  ·  \(ref.name)") }
                            if store.cropping { Tag(cropLabel) }
                            // What is on screen is not what is on disk, which
                            // is the one thing a picture cannot say about
                            // itself (D-240).
                            if store.reverting { Tag("The original") }
                            // Adjust has no tag here. The panel is on screen for
                            // exactly as long as the mode is running and already
                            // says every number, so a second copy of it over the
                            // photograph is six words in the corner of the frame
                            // being judged. Crop's tag stays because crop has no
                            // panel.
                            if store.showClipping { Tag("Blown highlights") }
                            if store.showFocusPeaking { Tag("In focus") }
                            if store.tournament { Tag("Tournament: keep promotes, Esc ends it") }
                            Spacer()
                            // Ordered by how long each one stays, with the
                            // steadiest against the corner. A cluster pinned to
                            // the right grows leftward, so an item that arrives
                            // at the right-hand end shoves everything already
                            // there sideways: zooming used to move the heart
                            // and the flag out from under the pointer that was
                            // about to press them. The heart is offered on
                            // every photograph, the flag is set once and stays,
                            // the label is rarer, and the zoom comes and goes
                            // while looking at one frame (D-222).
                            //
                            // The readout is the control (D-154), and it is
                            // only there when there is something to read: at
                            // fit the word "Fit" was a button on every
                            // photograph saying what the photograph already
                            // showed (D-163). The photograph is what starts a
                            // zoom, by double-click and by pinch.
                            if scale > 1 || store.zoom != nil {
                                ZoomTag(text: zoomLabel(scale: scale, fit: fit),
                                        hint: "Back to fit (z)") { store.toggleActualSize() }
                            }
                            if let label = ref.label {
                                LabelDot(label: label)
                            }
                            if let flag = ref.flag {
                                FlagMark(flag: flag, size: Tokens.Layout.flagBadgeMax)
                            }
                            // The heart is on the photograph for as long as the
                            // photograph is, set or not. It used to come and go
                            // with the bar, which put the one mark this window
                            // is for behind a pointer move: you looked at a
                            // frame, decided it was worth showing someone, and
                            // had to wake the chrome to say so. The grid's rule
                            // is the opposite for the opposite reason — an empty
                            // heart on every cell is a wall of empty hearts, and
                            // there is one photograph here (D-224).
                            //
                            // Focus mode is the exception, because taking the
                            // chrome away is the whole of what it does.
                            FavoriteMarkButton(ref: ref, subject: ref.name,
                                               size: Tokens.Layout.favoriteMarkMax,
                                               revealed: !store.isBare(.preview)) {
                                router.perform(.toggleFavorite, on: ref)
                            }
                        }
                        Spacer()
                    }
                    .padding(Tokens.Space.s16)
                }
            }
        }
        // The pan stays with the zoom across a cursor move (D-79): holding one
        // corner of the frame while arrowing through a burst is the whole point
        // of keeping the zoom at all.
        .onChange(of: store.cursor) { _, _ in
            if store.zoom == nil { pan = .zero }
        }
        .onChange(of: store.zoom) { _, z in if z == nil { pan = .zero; panStart = .zero } }
    }

    /// The photograph itself, in whichever of the four ways this mode wants
    /// it drawn.
    ///
    /// Keyed on the opening rather than on the photograph. No key at all is
    /// what lets one frame dissolve into the next across a cursor move
    /// (D-63), and it is also what put the last photograph on screen for a
    /// moment when the window was closed and opened on a different one: the
    /// view is reused, and the frame it holds is the one from last time. The
    /// opening changes when the window comes back and never when the cursor
    /// moves, so the crossfade survives and the stale frame does not (D-375).
    private func photo(_ ref: PhotoRef, onDrawnSize: ((CGSize) -> Void)? = nil) -> some View {
        photoBody(ref, onDrawnSize: onDrawnSize).id(store.previewOpening)
    }

    @ViewBuilder
    private func photoBody(_ ref: PhotoRef, onDrawnSize: ((CGSize) -> Void)? = nil) -> some View {
        if ref.isAnimated {
            AnimatedImageView(url: ref.url)
        } else if store.reverting {
            // The question the bar is asking, drawn where the answer is
            // decided (D-240).
            RevertPreview(ref: ref, onDrawnSize: onDrawnSize)
        } else if store.adjusting {
            // The sliders are what is on screen while the panel is open, so the
            // photograph comes from the recipe rather than from the cache
            // (D-161).
            AdjustedPhoto(ref: ref, adjustments: store.adjustments, onDrawnSize: onDrawnSize)
        } else {
            PhotoImage(ref: ref, full: true, onDrawnSize: onDrawnSize)
        }
    }

    /// Focus mode takes the ground dark in both themes: nothing else is on
    /// screen, so the surround is doing the whole job (D-62).
    private var ground: Color { store.isBare(.preview) ? Tokens.Surface.judging : Tokens.Surface.sunken }

    // MARK: side by side

    /// A and the cursor's photo at equal height, sharing one zoom and one pan,
    /// so the same detail is under the eye in both (D-70). Clicking the other
    /// frame makes it the one the next keystroke decides about, which is how a
    /// pair gets down to one.
    @ViewBuilder
    private func pair(a: PhotoRef, b: PhotoRef, in container: CGSize) -> some View {
        let gap = Tokens.Space.s16
        let width = max(1, (container.width - gap * 3) / 2)
        let height = max(1, container.height - gap * 2 - Self.pairCaption)
        HStack(spacing: gap) {
            pairFrame(a, label: store.tournament ? "Best so far" : "A",
                      width: width, height: height, isCurrent: b.url == a.url)
            pairFrame(b, label: store.tournament ? "Challenger" : "B",
                      width: width, height: height, isCurrent: true)
        }
        .padding(gap)
        .gesture(pairDrag(width: width, height: height))
        .simultaneousGesture(magnifyGesture(fit: CGSize(width: width, height: height)))
        // A pair scales the fitted frame rather than going through the pixel
        // path a single photograph does, so it had no percentage at all while
        // the frame beside it had one (D-155). It reads off the size the
        // photograph was actually painted at, which is the only number that
        // cannot drift from what is on screen.
        .overlay(alignment: .topTrailing) {
            Group {
                if let label = pairZoomLabel() {
                    ZoomTag(text: label, hint: "Back to fit (z)") { store.toggleActualSize() }
                }
            }
            .padding(gap)
        }
        .task(id: b.contentID) {
            // The single-frame path is not on screen in a pair, so the pixel
            // size it would have read has to be read here.
            pixelSize = await Task.detached {
                ImageLoader.pixelSize(of: b.url).map { CGSize(width: $0.width, height: $0.height) }
            }.value
        }
    }

    /// What the pair is magnified to, or nil at fit. The drawn size is measured
    /// rather than computed: `.fit` decides the painted rect, and a pair frame
    /// letterboxes both photographs.
    private func pairZoomLabel() -> String? {
        guard store.zoom != nil, let px = pixelSize, let drawn = pairDrawn, drawn.width > 0 else { return nil }
        let scale = max(1, store.zoom ?? 1)
        return String(format: "%.0f%%", drawn.width * scale / px.width * 100)
    }

    @ViewBuilder
    private func pairFrame(_ ref: PhotoRef, label: String, width: CGFloat, height: CGFloat, isCurrent: Bool) -> some View {
        let scale = max(1, store.zoom ?? 1)
        VStack(spacing: Tokens.Space.s8) {
            photo(ref, onDrawnSize: isCurrent ? { pairDrawn = $0 } : nil)
                .frame(width: width, height: height)
                .scaleEffect(scale)
                .offset(pairPan(width: width, height: height, scale: scale))
                .frame(width: width, height: height)
                .clipped()
                .overlay {
                    // The frame the next keystroke is about wears the cursor
                    // ring, the same one the grid draws. Nothing else marks it.
                    if isCurrent {
                        Rectangle().strokeBorder(Tokens.Border.focus, lineWidth: Tokens.Border.ringWidth)
                    }
                }
            HStack(spacing: Tokens.Space.s8) {
                if !label.isEmpty {
                    Text(label)
                        .textStyle(.strong)
                }
                Text(ref.name)
                    .textStyle(.label, color: isCurrent ? Tokens.Text.primary : Tokens.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let flag = ref.flag {
                    FlagMark(flag: flag)
                }
                if ref.favorite { FavoriteMark(size: Tokens.Layout.favoriteMarkSmall) }
            }
            .frame(height: Self.pairCaption)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isCurrent { makeCurrent(ref) } }
        .help(isCurrent ? ref.name : "\(ref.name) — click to decide about this one")
    }

    /// Clicking the other frame swaps the two: the one you clicked becomes the
    /// photo the cursor is on, and the one you were on becomes A. The pair on
    /// screen does not change, only which half the keys are aimed at.
    private func makeCurrent(_ ref: PhotoRef) {
        guard let was = store.current, let i = store.photos.firstIndex(where: { $0.url == ref.url }) else { return }
        store.compareAnchor = was.url
        store.cursor = i
        store.sideBySide = true
    }

    private func pairPan(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGSize {
        let maxX = max(0, width * (scale - 1) / 2), maxY = max(0, height * (scale - 1) / 2)
        return CGSize(width: min(max(pan.width, -maxX), maxX), height: min(max(pan.height, -maxY), maxY))
    }

    private func pairDrag(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard store.zoom != nil else { return }
                pan = CGSize(width: panStart.width + v.translation.width, height: panStart.height + v.translation.height)
            }
            .onEnded { _ in
                let scale = max(1, store.zoom ?? 1)
                panStart = pairPan(width: width, height: height, scale: scale)
                pan = panStart
                remember(size: CGSize(width: width * scale, height: height * scale))
            }
    }

    /// The row of words under each frame. Fixed, so the two photos are the same
    /// height whatever their filenames are.
    private static let pairCaption: CGFloat = 24

    /// A mask over the photo, at the photo's own size and offset.
    private func mask(_ image: DecodedImage, size: CGSize, avail: CGSize, scale: CGFloat) -> some View {
        Image(decorative: image.cgImage, scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: size.width, height: size.height)
            .offset(scale > 1 ? clampedPan(size: size, avail: avail) : .zero)
            .allowsHitTesting(false)
    }

    /// The part of the photo on screen, normalized, origin top left. The whole
    /// frame at fit; the window into it once zoomed.
    private func visible(size: CGSize, avail: CGSize, scale: CGFloat) -> CGRect {
        guard scale > 1, size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let off = clampedPan(size: size, avail: avail)
        let w = min(1, avail.width / size.width), h = min(1, avail.height / size.height)
        // The pan moves the photo, so the window moves the other way.
        let x = (size.width - avail.width) / 2 - off.width
        let y = (size.height - avail.height) / 2 - off.height
        return CGRect(x: max(0, min(1 - w, x / size.width)),
                      y: max(0, min(1 - h, y / size.height)),
                      width: w, height: h)
    }

    // MARK: survey

    /// Lightroom's survey: everything under consideration at once, on one
    /// screen, at whatever size fits (D-82). Picking the best of a six-frame
    /// run is the job; doing it two at a time is doing it five times.
    @ViewBuilder
    private func survey(_ refs: [PhotoRef], in container: CGSize) -> some View {
        let gap = Tokens.Space.s16
        let columns = surveyColumns(refs.count, in: container)
        let rows = Int(ceil(Double(refs.count) / Double(columns)))
        let width = max(1, (container.width - gap * CGFloat(columns + 1)) / CGFloat(columns))
        let height = max(1, (container.height - gap * CGFloat(rows + 1)) / CGFloat(rows) - Self.pairCaption)
        VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(Array(refs.enumerated()).filter { $0.offset / columns == row }, id: \.element.id) { _, ref in
                        pairFrame(ref, label: "", width: width, height: height,
                                  isCurrent: ref.url == store.current?.url)
                    }
                }
            }
        }
        .padding(gap)
    }

    /// Two across for two or four, three for anything more. Whichever keeps the
    /// frames closest to the shape of the window they are in.
    private func surveyColumns(_ count: Int, in container: CGSize) -> Int {
        if count <= 2 { return count }
        if count <= 4 { return 2 }
        return 3
    }

    // MARK: geometry

    private func fitSize(for px: CGSize?, in avail: CGSize) -> CGSize {
        guard let px, px.width > 0, px.height > 0 else { return avail }
        let s = min(avail.width / px.width, avail.height / px.height, 1)
        return CGSize(width: px.width * s, height: px.height * s)
    }

    /// `zoom == nil` fits; otherwise a multiplier over the fit size.
    private func resolvedScale(fit: CGSize) -> CGFloat {
        max(1, store.zoom ?? 1)
    }

    private func zoomLabel(scale: CGFloat, fit: CGSize) -> String {
        guard let px = pixelSize, px.width > 0 else { return "" }
        return String(format: "%.0f%%", fit.width * scale / px.width * 100)
    }

    /// Write down where the window is now looking, once a pan has settled.
    /// Every place that moves the photograph ends here, so the intent cannot
    /// disagree with what is on screen (D-273).
    private func remember(size: CGSize) {
        guard store.zoom != nil, size.width > 0, size.height > 0 else { return }
        store.lookingAt = LibraryStore.look(fromPan: pan, in: size)
    }

    /// And put it back, in this photograph's points. A frame of another shape
    /// needs a different offset to show the same place, which is why the intent
    /// is normalized and the pan is not.
    private func restoreLook(fit: CGSize, avail: CGSize) {
        guard store.zoom != nil else { pan = .zero; panStart = .zero; return }
        let scale = resolvedScale(fit: fit)
        let size = CGSize(width: fit.width * scale, height: fit.height * scale)
        guard size.width > 0, size.height > 0 else { return }
        pan = LibraryStore.pan(lookingAt: store.lookingAt, in: size)
        pan = clampedPan(size: size, avail: avail)
        panStart = pan
    }

    private func clampedPan(size: CGSize, avail: CGSize) -> CGSize {
        clampedPan(size: size, avail: avail, from: pan)
    }

    /// The same clamp over an offset that is not `pan` yet, which is what an
    /// animated move needs: the end of the travel has to be worked out before
    /// anything is assigned, or the assignment is the first frame of it.
    private func clampedPan(size: CGSize, avail: CGSize, from offset: CGSize) -> CGSize {
        let maxX = max(0, (size.width - avail.width) / 2), maxY = max(0, (size.height - avail.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    private func imageFrame(size: CGSize, in container: CGSize) -> CGRect {
        let off = store.zoom != nil ? clampedPan(size: size, avail: container) : .zero
        return CGRect(x: (container.width - size.width) / 2 + off.width,
                      y: (container.height - size.height) / 2 + off.height,
                      width: size.width, height: size.height)
    }

    // MARK: gestures

    private func dragGesture(size: CGSize, avail: CGSize, imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if store.cropping {
                    // A crop used to be one drag and nothing else: every
                    // adjustment meant drawing the whole rectangle again, and
                    // nudging one edge in by ten pixels meant re-judging the
                    // other three (D-159).
                    let grip = cropGrip ?? CropGrip(at: v.startLocation, in: drawnCrop(in: imageFrame))
                    cropGrip = grip
                    let moved = grip.apply(translation: v.translation,
                                           to: v.startLocation,
                                           at: v.location,
                                           within: imageFrame,
                                           aspect: cropAspect(in: imageFrame))
                    store.cropRect = normalize(moved, in: imageFrame)
                } else if store.zoom != nil {
                    pan = CGSize(width: panStart.width + v.translation.width, height: panStart.height + v.translation.height)
                }
            }
            .onEnded { _ in
                cropGrip = nil
                panStart = clampedPan(size: size, avail: avail)
                pan = panStart
                remember(size: size)
            }
    }

    /// What the crop is about to save, in the pixels of the file it comes from,
    /// because a copy one generation down is worth knowing the size of before
    /// it is written (D-159).
    ///
    /// The size and nothing else. It used to carry the keys as well, and the
    /// crop bar says those on its own buttons now: a tag that repeats the
    /// controls under it is a wall in front of the work (D-238).
    private var cropLabel: String {
        guard let r = store.cropRect, r.width > 0, r.height > 0 else { return "Drag a box" }
        guard let px = pixelSize else { return "Drag the edges" }
        let w = Int((r.width * px.width).rounded()), h = Int((r.height * px.height).rounded())
        return "\(w) × \(h)"
    }

    /// The photograph's own shape, from the file rather than from the layout.
    /// The frame is the same shape once it has been drawn, and a ratio chosen
    /// before that — at launch, or in the frame after a cursor move — would be
    /// worked out against whatever size the view was mid-layout: a 16:9 box
    /// came out 1.94:1 that way, which is a bug that only shows up in the
    /// readout (D-238).
    private var photoAspect: CGFloat? {
        guard let px = pixelSize, px.width > 0, px.height > 0 else { return nil }
        return px.width / px.height
    }

    /// The shape the box is held to while it is dragged, in the points the
    /// drag is in. A box that is 16:9 in pixels is 16:9 on screen, because the
    /// photograph is drawn to one scale in both directions.
    private func cropAspect(in frame: CGRect) -> CGFloat? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return store.cropRatio.aspect(photo: photoAspect ?? frame.width / frame.height,
                                      turned: store.cropRatioTurned)
    }

    /// The box a newly chosen ratio leaves on screen: the one already there
    /// taken in about its own middle, or the biggest one of that shape when
    /// there is nothing to take in. A shape chosen and nothing happening is a
    /// control that looks broken (D-238).
    ///
    /// Worked out in the normalized square the rectangle is kept in rather than
    /// in points, so it does not need a laid-out frame to be right. What the
    /// ratio means there is the ratio divided by the photograph's own shape.
    private func reshapeCrop() {
        guard store.cropping, let photo = photoAspect,
              let aspect = store.cropRatio.aspect(photo: photo, turned: store.cropRatioTurned)
        else { return }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let current = store.cropRect
        let base = (current?.width ?? 0) > 0.01 && (current?.height ?? 0) > 0.01 ? current! : unit
        store.cropRect = CropGrip.shaped(base.size, aspect: aspect / photo, driven: .smaller,
                                         unit: CGPoint(x: 0.5, y: 0.5),
                                         pin: CGPoint(x: base.midX, y: base.midY),
                                         within: unit, least: 0.02) ?? current
    }

    private func magnifyGesture(fit: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let base = pinchStart ?? resolvedScale(fit: fit)
                pinchStart = base
                let s = base * v.magnification
                store.zoom = s <= 1.02 ? nil : s
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// The crop as it is drawn, worked back from the one place it is kept.
    ///
    /// The rectangle used to live twice: normalized in the store for the file
    /// operation, and in points in a `@State` here for the overlay. Two copies
    /// of one fact, and the second was the reason a crop could never be set
    /// from anywhere but a drag — which is why the grips could not be
    /// photographed until they were (D-159).
    private func drawnCrop(in frame: CGRect) -> CGRect? {
        guard let r = store.cropRect, r.width > 0, r.height > 0 else { return nil }
        return CGRect(x: frame.minX + r.minX * frame.width,
                      y: frame.minY + r.minY * frame.height,
                      width: r.width * frame.width, height: r.height * frame.height)
    }

    private func normalize(_ r: CGRect, in frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGRect(x: (r.minX - frame.minX) / frame.width, y: (r.minY - frame.minY) / frame.height,
                      width: r.width / frame.width, height: r.height / frame.height)
    }

    @ViewBuilder
    private func cropOverlay(imageFrame: CGRect) -> some View {
        Canvas { ctx, _ in
            // design-system:allow — the crop scrim is painted on the photograph,
            // and a photograph has no theme. Black in both, like the heart's
            // keyline (DESIGN, colors).
            ctx.fill(Path(imageFrame), with: .color(Tokens.Surface.scrim))
            if let r = drawnCrop(in: imageFrame) {
                ctx.blendMode = .destinationOut
                // design-system:allow — the same scrim, at full strength.
                ctx.fill(Path(r), with: .color(.black))
                ctx.blendMode = .normal
                ctx.stroke(Path(r), with: .color(Tokens.Border.selected), lineWidth: Tokens.Border.ringWidth)
                // Eight grips, each one a mark drawn over a photograph, so
                // each carries its own keyline: a white square alone
                // disappears into a bride's dress (D-159, DESIGN colors).
                for point in CropGrip.grips(of: r) {
                    let box = CGRect(x: point.x - CropGrip.grip / 2, y: point.y - CropGrip.grip / 2,
                                     width: CropGrip.grip, height: CropGrip.grip)
                    // design-system:allow — the grip's own keyline, black in
                    // both themes for the same reason the heart's is.
                    ctx.stroke(Path(box), with: .color(.black), lineWidth: Tokens.Border.ringWidth * 2)
                    ctx.fill(Path(box), with: .color(Tokens.State.favoriteKeyline))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The zoom readout, which is also the zoom control (D-154). One mark for one
/// fact: the number you look at to see where the zoom is, is the thing you
/// press to change it.
///
/// It carries its own contrast rather than a chrome tone, because it is drawn
/// over a photograph and nothing here controls what is behind it — the same
/// reason the heart and the cull pill have a keyline (D-58, D-120).
private struct ZoomTag: View {
    let text: String
    let hint: String
    let act: () -> Void
    @State private var hovering = false

    /// The scrim is the edge. A control drawn on a photograph already sits on
    /// `bg.overPhoto`, and a keyline around that is two edges for one control,
    /// which is the rule `ControlFill` states and this view was breaking: it
    /// wore a near-white hairline at rest, the color the heart uses for a mark
    /// with no ground under it at all. The ink carries the pointer instead, the
    /// way every other control in the app does (D-222).
    var body: some View {
        Button(action: act) {
            Text(text)
                .textStyle(.label, color: hovering ? Tokens.Text.onPhoto : Tokens.Text.onPhotoQuiet)
                .padding(.horizontal, Tokens.Space.s8)
                .padding(.vertical, Tokens.Space.s4)
                .background(Tokens.Surface.overPhoto, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .linkCursor()
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .help(hint)
        // "Zoom" is what the control is; the magnification is where it has
        // got to, and only a value change is passed on (D-343).
        .accessibilityLabel("Zoom")
        .accessibilityValue(text)
    }
}

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .textStyle(.label)
            .padding(.horizontal, Tokens.Space.s8)
            .padding(.vertical, Tokens.Space.s4)
            .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}

/// What a crop drag is doing to the rectangle: drawing a new one, moving it, or
/// pulling one or two of its edges (D-159).
///
/// A struct with the geometry in it rather than four branches inside the
/// gesture, because the gesture cannot be driven from a test and this can. The
/// rules it has to keep: an edge dragged past its opposite flips rather than
/// inverting the rect, nothing leaves the photograph, and a crop never becomes
/// too small to see or to save.
struct CropGrip: Equatable {
    var left = false
    var right = false
    var top = false
    var bottom = false
    /// The whole rectangle, dragged from inside it.
    var moving = false
    /// Nil when this drag is drawing a new rectangle.
    var start: CGRect?

    /// How near an edge the pointer has to be to take hold of it, and the side
    /// of the square drawn there. Comfortably bigger than the mark, because a
    /// 10pt target is a target nobody hits.
    static let reach: CGFloat = 16
    static let grip: CGFloat = 8
    /// No crop smaller than this, in points on screen. A one-pixel crop is a
    /// mistake every time.
    static let least: CGFloat = 24

    /// The eight points a grip is drawn at: four corners, four edge middles.
    static func grips(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    /// What a press at `point` takes hold of. Outside an existing rectangle it
    /// draws a new one, which is what the crop has always done and still does.
    init(at point: CGPoint, in rect: CGRect?) {
        guard let rect else { return }
        let near = Self.reach
        let onLeft = abs(point.x - rect.minX) <= near
        let onRight = abs(point.x - rect.maxX) <= near
        let onTop = abs(point.y - rect.minY) <= near
        let onBottom = abs(point.y - rect.maxY) <= near
        let inRows = point.y >= rect.minY - near && point.y <= rect.maxY + near
        let inColumns = point.x >= rect.minX - near && point.x <= rect.maxX + near
        if (onLeft || onRight) && inRows || (onTop || onBottom) && inColumns {
            left = onLeft && inRows
            right = onRight && inRows && !left
            top = onTop && inColumns
            bottom = onBottom && inColumns && !top
            start = rect
            return
        }
        if rect.contains(point) {
            moving = true
            start = rect
        }
    }

    var isNew: Bool { start == nil }

    /// The rectangle this drag has arrived at. `from` and `to` are where the
    /// press started and where the pointer is now, which is what a new
    /// rectangle is drawn between; `translation` is what moves an existing one.
    ///
    /// `aspect` is the shape the box is held to, width over height, or nil for
    /// a free crop. It is imposed after the drag has been worked out rather
    /// than inside each branch: every branch already knows which point is not
    /// moving, and that point is the whole of what a ratio needs (D-238).
    func apply(translation: CGSize, to from: CGPoint, at to: CGPoint,
               within bounds: CGRect, aspect: CGFloat? = nil) -> CGRect {
        guard let start else {
            let drawn = CGRect(origin: from, size: .zero)
                .union(CGRect(origin: to, size: .zero))
            guard let aspect else { return drawn.intersection(bounds) }
            // The press is the corner that stays; the pointer is the one being
            // dragged. Which corner that makes depends on which way the drag
            // went, so the pin is the press and the unit point is the corner
            // of the drawn rectangle it landed on.
            let unit = CGPoint(x: to.x >= from.x ? 0 : 1, y: to.y >= from.y ? 0 : 1)
            return Self.shaped(drawn.size, aspect: aspect, driven: .larger,
                               unit: unit, pin: from, within: bounds) ?? drawn.intersection(bounds)
        }
        if moving {
            let x = min(max(start.minX + translation.width, bounds.minX), bounds.maxX - start.width)
            let y = min(max(start.minY + translation.height, bounds.minY), bounds.maxY - start.height)
            return CGRect(x: x, y: y, width: start.width, height: start.height).intersection(bounds)
        }
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if left { minX = start.minX + translation.width }
        if right { maxX = start.maxX + translation.width }
        if top { minY = start.minY + translation.height }
        if bottom { maxY = start.maxY + translation.height }
        // An edge dragged past its opposite swaps the two rather than making a
        // rectangle with a negative side, which is what the pointer looks like
        // it is doing and what every other crop tool does.
        let rect = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: abs(maxX - minX), height: abs(maxY - minY))
            .intersection(bounds)
        guard let aspect else {
            guard rect.width >= Self.least, rect.height >= Self.least else { return start }
            return rect
        }
        // A corner drag is driven by both edges it holds; a single edge drives
        // its own axis and the other one opens out from the middle, so the box
        // grows where the hand is pulling and stays where it was everywhere
        // else.
        let horizontal = left || right, vertical = top || bottom
        let driven: Driven = horizontal && vertical ? .larger : (horizontal ? .width : .height)
        let unit = CGPoint(x: left ? 1 : (right ? 0 : 0.5), y: top ? 1 : (bottom ? 0 : 0.5))
        let pin = CGPoint(x: unit.x * rect.width + rect.minX, y: unit.y * rect.height + rect.minY)
        return Self.shaped(rect.size, aspect: aspect, driven: driven,
                           unit: unit, pin: pin, within: bounds) ?? start
    }

    /// Which side of the drag decides the size once a ratio is on it.
    enum Driven { case width, height, larger, smaller }

    /// `size` forced to `aspect`, placed so its own `unit` point sits at `pin`,
    /// and shrunk about that pin until it is inside `bounds`. Nil when what
    /// comes back would be too small to see or to save.
    ///
    /// `unit` is where the pin sits in the rectangle: `(0, 0)` its top left,
    /// `(1, 0.5)` the middle of its right edge, `(0.5, 0.5)` its center. One
    /// function for drawing, for pulling an edge and for snapping a box that is
    /// already there, because all three are the same question — what stays put
    /// (D-238).
    static func shaped(_ size: CGSize, aspect: CGFloat, driven: Driven,
                       unit: CGPoint, pin: CGPoint, within bounds: CGRect,
                       least: CGFloat = CropGrip.least) -> CGRect? {
        guard aspect > 0 else { return nil }
        var w: CGFloat
        switch driven {
        case .width: w = size.width
        case .height: w = size.height * aspect
        case .larger: w = max(size.width, size.height * aspect)
        case .smaller: w = min(size.width, size.height * aspect)
        }
        var h = w / aspect
        // How big the box can be before the pin's own share of it leaves the
        // photograph on one side or the other.
        var roomW = CGFloat.infinity, roomH = CGFloat.infinity
        if unit.x > 0 { roomW = min(roomW, (pin.x - bounds.minX) / unit.x) }
        if unit.x < 1 { roomW = min(roomW, (bounds.maxX - pin.x) / (1 - unit.x)) }
        if unit.y > 0 { roomH = min(roomH, (pin.y - bounds.minY) / unit.y) }
        if unit.y < 1 { roomH = min(roomH, (bounds.maxY - pin.y) / (1 - unit.y)) }
        let fit = min(1, roomW / w, roomH / h)
        guard fit > 0 else { return nil }
        w *= fit; h *= fit
        guard w >= least, h >= least else { return nil }
        return CGRect(x: pin.x - unit.x * w, y: pin.y - unit.y * h, width: w, height: h)
    }

}
