import SwiftUI

/// A row of thumbnails along the bottom of single view. On by `f`, remembered.
///
/// It scrubs: press on any frame and drag along the strip, and the cursor
/// follows the pointer through the folder rather than stepping one frame per
/// click (D-51). The gesture is attached to the cells, so it claims the press
/// before the scroll view does; the wheel and two fingers still scroll.
@MainActor
struct Filmstrip: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    /// Where each cell sits in the strip, so a drag anywhere over the row knows
    /// which photo is under the pointer. Only the visible cells are in here —
    /// `LazyHStack` builds no others, and nothing off screen can be dragged to.
    @State private var frames: [Int: CGRect] = [:]
    @State private var hovering: Int?
    @State private var scrubbing = false

    // `nonisolated` because an `onGeometryChange` transform is a Sendable
    // closure, and Swift 6.1 will not let one read a main-actor static. An
    // immutable String is safe anywhere (D-387).
    nonisolated private static let space = "filmstrip"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Tokens.Space.s8) {
                    ForEach(Array(store.photos.enumerated()), id: \.element.id) { index, ref in
                        cell(index: index, ref: ref)
                    }
                }
                .padding(.horizontal, Tokens.Space.s16)
                .padding(.vertical, Tokens.Space.s8)
            }
            .coordinateSpace(name: Self.space)
            .background(Tokens.Surface.chrome)
            .onChange(of: store.cursor, initial: true) { _, cursor in
                // A scrub already has the photo under the pointer; scrolling to
                // center it would drag the strip out from under the hand.
                guard !scrubbing, let cursor, store.photos.indices.contains(cursor) else { return }
                proxy.scrollTo(store.photos[cursor].id, anchor: .center)
            }
        }
        .frame(height: Tokens.Layout.filmstripCell + Tokens.Space.s16)
    }

    /// The cursor's tile, the pointer's half-step, or nothing. A filmstrip
    /// frame is never "selected" — the strip follows the cursor and the
    /// gallery owns the selection — so it uses two of the grid's three states.
    private func background(index: Int) -> Color {
        if index == store.cursor { Tokens.Surface.cursor }
        else if hovering == index { Tokens.Surface.hovered }
        else { Tokens.Surface.raised }
    }

    @ViewBuilder
    private func cell(index: Int, ref: PhotoRef) -> some View {
        PhotoImage(ref: ref, full: false, cell: Tokens.Layout.filmstripCell)
            .frame(width: Tokens.Layout.filmstripCell, height: Tokens.Layout.filmstripCell)
            // The fill says where the pointer is, and at 64pt it cannot say
            // where the keyboard is: a thumbnail covers its own cell, so the
            // cursor tone survives only in whatever letterbox a photograph's
            // aspect ratio leaves, and a strip of dark frames leaves almost
            // none. D-120 took the ring off here to match the grid's grammar,
            // and the grammar does not survive the size: a fill reads on a
            // 160pt cell with room around the photograph and vanishes on a
            // 64pt one without (D-178).
            //
            // No name under these. A 64pt cell truncates a filename to about
            // six characters, and the strip would grow by a whole label row to
            // carry them; the photograph's name is already in the window title
            // and in the preview bar. The grid's name earns its row because
            // the grid is where a file is identified.
            .background(background(index: index), in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .overlay { cursorRing(index: index) }
            .overlay(alignment: .topLeading) {
                if let flag = ref.flag {
                    FlagMark(flag: flag)
                        .padding(Tokens.Space.s4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if ref.favorite {
                    FavoriteMark(size: Tokens.Layout.favoriteMarkSmall)
                        .padding(Tokens.Space.s4)
                }
            }
            .id(ref.id)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[index] = $0 }
            .onHover { hovering = $0 ? index : (hovering == index ? nil : hovering) }
            .linkCursor()
            .gesture(scrub())
            .contextMenu { PhotoMenu(ref: ref, store: store, router: router) }
            .help(ref.name)
            .accessibilityLabel(ref.name)
    }

    /// Two rings, one inside the other, because a mark drawn over somebody
    /// else's photograph has to carry its own contrast (D-178).
    ///
    /// The outer one is `border.selected`, which is what every other control
    /// in the app wears when the keyboard is on it, and it reads against the
    /// strip's chrome. The inner hairline is the tone it is not, and it reads
    /// against the photograph. A frame can swallow either on its own; it
    /// cannot swallow both at one edge.
    ///
    /// Drawn over the cell rather than around it: the strip's gaps are 8pt and
    /// a ring hung outside would close half of one. It costs the outermost 3pt
    /// of the thumbnail, which is a crop of a navigation aid rather than of
    /// anything being judged.
    @ViewBuilder
    private func cursorRing(index: Int) -> some View {
        if index == store.cursor {
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(Tokens.Border.cursorKeyline,
                              lineWidth: Tokens.Border.ringWidth + Tokens.Border.hoverWidth)
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .strokeBorder(Tokens.Border.selected, lineWidth: Tokens.Border.ringWidth)
        }
    }

    /// A press with no minimum distance, so a click is the shortest possible
    /// scrub and there is one code path for both.
    private func scrub() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                scrubbing = true
                guard let index = index(atX: value.location.x) else { return }
                if store.cursor != index { store.cursor = index }
            }
            .onEnded { _ in scrubbing = false }
    }

    /// The cell under a point, or the nearest one when the pointer is in a gap
    /// between two — a scrub that stalls over an 8px gap reads as a stutter.
    private func index(atX x: CGFloat) -> Int? {
        if let hit = frames.first(where: { $0.value.minX <= x && x <= $0.value.maxX }) { return hit.key }
        return frames.min { a, b in
            abs(a.value.midX - x) < abs(b.value.midX - x)
        }?.key
    }
}
