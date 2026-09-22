import SwiftUI

/// The kept original, on screen, with the one question about it (D-240).
///
/// Revert used to write the moment it was pressed. The layers under it were
/// real — `⌘Z` in the toast, the corner undo after that — but the thing that
/// says whether somebody wants an edit back is the photograph, not a sentence
/// naming the file. So the mark you press shows you the original first, and the
/// write waits for this bar.
///
/// One row, because there are two answers. `Cancel` as a plain word and the
/// save boxed, which is the weighting the crop bar and the adjust panel already
/// use for the same pair.
@MainActor
struct RevertBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some View {
        FloatingBar(label: "Revert controls") {
            HStack(spacing: Tokens.Space.s12) {
                WordButton(title: "Cancel", hint: "Leave the photograph as it is (Esc)",
                           focused: store.modeBarCursor == .cancel) {
                    router.pressModeBar(.cancel)
                }
                BoxedButton(title: "Save changes",
                            hint: "Put \(name) back the way it was and take the edit off (Return). ⌘Z undoes it",
                            enabled: true,
                            focused: store.modeBarCursor == .saveOver) {
                    router.pressModeBar(.saveOver)
                }
            }
        }
    }

    private var name: String { store.current?.name ?? "this photo" }
}

/// The photograph as it arrived, drawn from the copy kept beside it.
///
/// Decoded rather than pulled from `ImageCache`, which is keyed on the content
/// under the photograph's own name (D-45): the original is a different file
/// wearing a hidden one, and putting it into that cache would hand the edited
/// frame's key to the unedited pixels.
struct RevertPreview: View {
    let ref: PhotoRef
    var onDrawnSize: ((CGSize) -> Void)?

    @State private var original: DecodedImage?

    var body: some View {
        ZStack {
            if let original {
                Image(decorative: original.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { onDrawnSize?($0) }
            } else {
                // Until it is decoded, the photograph that is actually on disk.
                // The alternative is an empty ground where a picture is about
                // to be, which reads as the revert having already happened.
                PhotoImage(ref: ref, full: true, onDrawnSize: onDrawnSize)
            }
        }
        .task(id: ref.contentID) {
            guard let kept = AdjustRecord.original(for: ref.url) else { original = nil; return }
            original = await ImageLoader.shared.decode(kept, maxPixels: Tokens.Layout.adjustPreviewPixels)
        }
    }
}
