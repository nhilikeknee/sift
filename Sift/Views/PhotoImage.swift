import SwiftUI

/// Loads through the caches. Shows the thumbnail first if the full frame isn't ready (D-6).
struct PhotoImage: View {
    let ref: PhotoRef
    let full: Bool
    /// The edge the thumbnail is drawn at, so a grid at 300 decodes for 300
    /// rather than stretching the 320px decode the default cell asks for.
    var cell: CGFloat = Tokens.Layout.gridCell
    /// Fill the space rather than fit inside it, cropping what does not go.
    /// Only the folder tile asks for this: its square is a cover rather than a
    /// frame somebody is judging, and a fitted cover leaves ground above and
    /// below that reads as another sheet of the stack (D-350). A photograph
    /// being decided about is never cropped by the view showing it.
    var fills = false
    /// The size the picture was actually painted at, which is not the frame it
    /// was given: the fit letterboxes everything that is not square. Anything
    /// drawn *on* a photograph needs this, or it lands in the empty band above
    /// the picture rather than in the picture's corner (D-120).
    var onDrawnSize: ((CGSize) -> Void)?

    @State private var image: DecodedImage?
    /// What is on screen, as a key. A `DecodedImage` is a value with no
    /// identity SwiftUI can diff, so the crossfade needs something to key the
    /// insert and the removal on (D-63).
    @State private var shown = ""

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    // Measured on the fitted image rather than computed from
                    // the decode's pixel dimensions: `.fit` is what decides
                    // the painted rect, so asking it is the only answer that
                    // cannot drift from what is on screen.
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { onDrawnSize?($0) }
                    .id(shown)
                    .transition(.opacity)
            } else {
                Tokens.Surface.raised
            }
        }
        // Only the full frame dissolves. A grid scrolling past two hundred
        // thumbnails would be two hundred animations for nothing to see.
        .animation(full ? Tokens.Motion.crossfade : nil, value: shown)
        .task(id: "\(ref.contentID)|\(full ? 0 : pixels)") { await load() }
    }

    private var pixels: Int { Tokens.Layout.thumbnailPixels(for: cell) }

    private func load() async {
        let url = ref.url
        // Full frames stay keyed on content alone, which is what the prefetcher
        // writes. A thumbnail also carries the edge it was decoded at: one file
        // can be in the cache at two sizes while the grid is being resized, and
        // the smaller must not answer for the larger.
        let fullKey = ref.contentID
        let thumbKey = "\(ref.contentID)|\(pixels)"
        if full, let cached = ImageCache.fulls[fullKey] { show(cached, key: fullKey); return }
        if let thumb = ImageCache.thumbnails[thumbKey] {
            // The thumbnail stands in under the full frame's key, so the swap
            // to the full decode of the same photo is not a second crossfade.
            show(thumb, key: full ? fullKey : thumbKey)
            if !full { return }
        }
        if full {
            if let decoded = await ImageLoader.shared.decode(url, maxPixels: nil) {
                ImageCache.fulls[fullKey] = decoded
                if !Task.isCancelled { show(decoded, key: fullKey) }
            } else if !Task.isCancelled {
                // The view is kept across a cursor move so one frame can
                // dissolve into the next, which means a file that will not
                // decode has to clear the one before it. Otherwise the old
                // photo sits there wearing the new one's name.
                clear(key: fullKey)
            }
        } else {
            if let decoded = await ImageLoader.shared.decode(url, maxPixels: pixels) {
                ImageCache.thumbnails[thumbKey] = decoded
                if !Task.isCancelled { show(decoded, key: thumbKey) }
            } else if !Task.isCancelled {
                clear(key: thumbKey)
            }
        }
    }

    private func show(_ decoded: DecodedImage, key: String) {
        image = decoded
        shown = key
    }

    private func clear(key: String) {
        image = nil
        shown = key
    }
}

/// The photograph with the sliders applied, while the adjust panel is open
/// (D-161).
///
/// A separate view from `PhotoImage` rather than a parameter on it, because the
/// two cache different things: `PhotoImage` keeps one decode per photograph and
/// `ImageCache` is keyed on content alone, while this keeps a small base decode
/// and a render keyed on the recipe that made it. Putting a recipe-dependent
/// result into a content-keyed cache is how a photograph ends up wearing
/// somebody else's exposure.
///
/// The base is decoded once per photograph at `adjustPreviewPixels`, so a drag
/// along a slider is four filters over two megapixels rather than over forty.
/// What Return writes is rendered against the whole file.
struct AdjustedPhoto: View {
    let ref: PhotoRef
    let adjustments: Adjustments
    var onDrawnSize: ((CGSize) -> Void)?

    /// The unadjusted base, and which photograph it is of.
    @State private var base: DecodedImage?
    @State private var baseKey = ""
    /// The last render that finished. Kept on screen while the next one runs,
    /// so a drag moves the photograph rather than blinking it.
    @State private var shown: DecodedImage?

    var body: some View {
        ZStack {
            if let image = shown ?? base {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { onDrawnSize?($0) }
            } else {
                // Nothing rendered yet: the ordinary path, which has the
                // thumbnail and the full decode already cached.
                PhotoImage(ref: ref, full: true, onDrawnSize: onDrawnSize)
            }
        }
        .task(id: "\(ref.contentID)|\(adjustments.key)") { await refresh() }
    }

    private func refresh() async {
        if baseKey != ref.contentID {
            // The kept original when this photograph has been overwritten
            // before, so the sliders develop the same pixels the write will
            // and a second edit is not one edit on top of another (D-165).
            base = await ImageLoader.shared.decode(AdjustRecord.base(for: ref.url),
                                                   maxPixels: Tokens.Layout.adjustPreviewPixels)
            baseKey = ref.contentID
            shown = nil
        }
        guard let base else { return }
        guard !adjustments.isNeutral else { shown = base; return }
        // A beat before rendering, so a drag along a slider renders once where
        // it stopped rather than forty times on the way. `.task(id:)` cancels
        // the previous one, which is what makes the beat a debounce.
        try? await Task.sleep(for: Tokens.Motion.adjustSettle)
        guard !Task.isCancelled else { return }
        let recipe = adjustments
        let rendered = await Task.detached { recipe.render(base.cgImage).map(DecodedImage.init) }.value
        guard !Task.isCancelled, let rendered else { return }
        shown = rendered
    }
}
