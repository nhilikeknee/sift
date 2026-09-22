import SwiftUI

/// File facts and EXIF for the current photo. Toggled with `i`.
@MainActor
struct InfoPanel: View {
    @Environment(LibraryStore.self) private var store
    @State private var exif: ExifInfo?
    @State private var histogram: Histogram?
    @State private var sharpness: Double?
    /// The decoded thumbnail the tones are read from, kept so a zoom can
    /// recompute the histogram without going back to the file (D-76).
    @State private var source: DecodedImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s24) {
                if let ref = store.current {
                    VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                        Text(ref.name)
                            .textStyle(.heading)
                            .lineLimit(3)
                        // None of these five is a measurement. A byte count
                        // carries its unit, a date is a sentence, and a flag
                        // is a word: set in monospace the dates wrapped onto
                        // a second line they did not need (D-121).
                        row("Size", ref.fileSize.formatted(.byteCount(style: .file)), measured: false)
                        row("Modified", ref.modified.formatted(date: .abbreviated, time: .shortened), measured: false)
                        row("Created", ref.created.formatted(date: .abbreviated, time: .shortened), measured: false)
                        row("Flag", ref.flag?.rawValue ?? "None", measured: false)
                        row("Favorite", ref.favorite ? "Yes" : "No", measured: false)
                    }
                    if let histogram {
                        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                                Text("Tones")
                                    .textStyle(.heading)
                                Spacer()
                                // Says what it is about, because a histogram of
                                // the whole frame and one of a face are two very
                                // different answers on the same axes.
                                if zoomed {
                                    Text("on screen")
                                        .textStyle(.quiet)
                                }
                            }
                            HistogramView(histogram: histogram)
                                .frame(height: Tokens.Layout.histogramHeight)
                            row("White", histogram.white.formatted(.percent.precision(.fractionLength(1))))
                            row("Black", histogram.black.formatted(.percent.precision(.fractionLength(1))))
                            if let sharpness {
                                row("Sharpness", String(format: "%.1f", sharpness))
                            }
                        }
                    }
                    if !store.faces.isEmpty {
                        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                                Text(store.faces.count == 1 ? "Face" : "Faces")
                                    .textStyle(.heading)
                                Spacer()
                                Text("⇧Z")
                                    .textStyle(.data, color: Tokens.Text.tertiary)
                            }
                            // Pre-zoomed, the way Narrative's close-ups panel
                            // does it, so checking an expression needs no
                            // panning (D-99).
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: Tokens.Layout.faceCrop),
                                                         spacing: Tokens.Space.s8)],
                                      spacing: Tokens.Space.s8) {
                                ForEach(store.faces) { face in
                                    FaceCrop(ref: ref, face: face, image: source) {
                                        store.focusRequest = face.framed
                                    }
                                }
                            }
                            if store.faces.contains(where: { $0.eyesClosed == true }) {
                                Text("Eyes look closed. Worth a look at 1:1.")
                                    .textStyle(.label, color: Tokens.State.reject)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let exif, !exif.facts.isEmpty {
                        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                            Text("Camera")
                                .textStyle(.heading)
                            ForEach(exif.facts, id: \.key) { fact in
                                row(fact.key, fact.value, measured: fact.measured)
                            }
                        }
                    }
                    Text(ref.url.deletingLastPathComponent().path)
                        .textStyle(.data, color: Tokens.Text.tertiary)
                        .textSelection(.enabled)
                } else {
                    Text("No photo").textStyle(.readout)
                }
            }
            .padding(Tokens.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Surface.chrome)
        .task(id: store.current?.contentID) {
            exif = nil
            histogram = nil
            sharpness = nil
            source = nil
            guard let ref = store.current else { return }
            let url = ref.url
            let key = ref.contentID
            async let e = Task.detached { EXIFReader.read(url) }.value
            async let img = Task.detached { () -> DecodedImage? in
                if let cached = ImageCache.thumbnails[key] { return cached }
                return await ImageLoader.shared.decode(url, maxPixels: Tokens.Layout.thumbnailPixels)
            }.value
            exif = await e
            guard let decoded = await img else { return }
            source = decoded
            let rect = store.visibleRect
            let stats = await Task.detached { () -> (Histogram?, Double?) in
                (PixelStats.histogram(of: decoded.cgImage, in: rect), PixelStats.sharpness(of: decoded.cgImage))
            }.value
            histogram = stats.0
            sharpness = stats.1
            // Last, and on its own: it is the slowest of the three and the only
            // one that can be wrong.
            let found = await Task.detached { FaceReader.faces(in: decoded.cgImage) }.value
            guard store.current?.contentID == key else { return }
            store.faces = found
            store.faceCursor = 0
        }
        // Zooming in is asking about what is on screen, so the tones follow.
        .task(id: store.visibleRect) {
            guard let decoded = source else { return }
            let rect = store.visibleRect
            histogram = await Task.detached { PixelStats.histogram(of: decoded.cgImage, in: rect) }.value
        }
    }

    private var zoomed: Bool { store.visibleRect.width < 0.999 || store.visibleRect.height < 0.999 }

    /// A key and a value. `measured` picks the value's role: `.data` for the
    /// numbers a reader scans down a column of — exposures, percentages, a
    /// pixel size, coordinates — and `.label` for everything that is a name or
    /// a sentence. Monospace is for data, never for prose (DESIGN), and this
    /// panel was setting a camera name and two dates in it.
    private func row(_ key: String, _ value: String, measured: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
            Text(key)
                .textStyle(.quiet)
                .frame(width: Tokens.Layout.labelColumn, alignment: .leading)
            Text(value)
                .textStyle(measured ? .data : .label)
                .textSelection(.enabled)
        }
        // Fifteen rows, one key and one value apiece, and the panel rewrites
        // every one of them on each arrow key. Two loose pieces of text is two
        // stops for the reader's cursor and neither one says what the other
        // is; one element with a name and a value is a row (D-343).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(key)
        .accessibilityValue(value)
    }
}


/// One face, cropped out of the thumbnail the panel already decoded. Clicking
/// it points the photo at that face.
private struct FaceCrop: View {
    let ref: PhotoRef
    let face: Face
    let image: DecodedImage?
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Group {
                if let cropped {
                    Image(decorative: cropped, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Tokens.Surface.canvas
                }
            }
            .frame(width: Tokens.Layout.faceCrop, height: Tokens.Layout.faceCrop)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .strokeBorder(ring, lineWidth: face.eyesClosed == true ? Tokens.Border.ringWidth : Tokens.Border.hoverWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(face.eyesClosed == true ? "Eyes look closed. Click to see it up close" : "Click to see this face up close")
        .accessibilityLabel("Face")
        .accessibilityValue(face.eyesClosed == true ? "eyes look closed" : "")
    }

    /// The one thing the ring says is "look at this one", which is exactly what
    /// the reject color means everywhere else in the app.
    private var ring: Color {
        if face.eyesClosed == true { return Tokens.State.reject }
        return hovering ? Tokens.Border.selected : Tokens.Border.hairline
    }

    private var cropped: CGImage? {
        guard let image else { return nil }
        let w = CGFloat(image.cgImage.width), h = CGFloat(image.cgImage.height)
        let r = CGRect(x: face.framed.minX * w, y: face.framed.minY * h,
                       width: face.framed.width * w, height: face.framed.height * h).integral
        guard r.width >= 1, r.height >= 1 else { return nil }
        return image.cgImage.cropping(to: r)
    }
}

/// 64 bars in `text.secondary`. Height is log-scaled so a flat photo still reads.
struct HistogramView: View {
    let histogram: Histogram

    var body: some View {
        Canvas { ctx, size in
            let n = histogram.bins.count
            let w = size.width / CGFloat(n)
            let peak = log(Double(histogram.peak) + 1)
            for (i, v) in histogram.bins.enumerated() {
                let h = peak > 0 ? CGFloat(log(Double(v) + 1) / peak) * size.height : 0
                let r = CGRect(x: CGFloat(i) * w, y: size.height - h, width: max(w - 1, 1), height: h)
                ctx.fill(Path(r), with: .color(Tokens.Text.secondary))
            }
        }
        .background(Tokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .accessibilityLabel("Histogram")
    }
}
