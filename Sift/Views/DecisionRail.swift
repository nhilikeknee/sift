import SwiftUI

/// One segment per photo in folder order, colored by what you decided about it,
/// with a mark where the cursor is. "14 of 340" says where you are; this says
/// how much of the folder is still waiting (D-65).
///
/// It appears only once something has been decided. An all-neutral band under
/// the header is a rule between the header and the grid, which is the one thing
/// the header is not allowed to grow.
struct DecisionRail: View {
    @Environment(LibraryStore.self) private var store

    /// The order the rail draws in is the order the grid shows, so a segment is
    /// in the place its photo is.
    private var flags: [Flag?] { store.photos.map(\.flag) }

    var body: some View {
        if shows {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let flags = flags
                    guard !flags.isEmpty, size.width > 0 else { return }
                    let w = size.width / CGFloat(flags.count)
                    for (i, flag) in flags.enumerated() {
                        let rect = CGRect(x: CGFloat(i) * w, y: 0, width: ceil(w), height: size.height)
                        ctx.fill(Path(rect), with: .color(color(flag)))
                    }
                    if let c = store.cursor, flags.indices.contains(c) {
                        // Wide enough to find in a folder of a thousand, where
                        // one photo's own segment is under a pixel.
                        let x = (CGFloat(c) + 0.5) * w - Self.tick / 2
                        ctx.fill(Path(CGRect(x: x, y: 0, width: Self.tick, height: size.height)),
                                 with: .color(Tokens.Border.selected))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { p in
                    let count = store.photos.count
                    guard count > 0, geo.size.width > 0 else { return }
                    store.folderCursor = nil
                    store.cursor = min(count - 1, max(0, Int(p.x / geo.size.width * CGFloat(count))))
                }
            }
            .frame(height: Tokens.Layout.railHeight)
            .help(summary)
            .accessibilityLabel("How much of this folder you have decided about")
            .accessibilityValue(summary)
        }
    }

    private var shows: Bool {
        let counts = store.folderCounts
        return !store.photos.isEmpty && (counts.keep + counts.reject) > 0
    }

    private func color(_ flag: Flag?) -> Color {
        switch flag {
        case .keep: Tokens.State.keep
        case .reject: Tokens.State.reject
        case nil: Tokens.State.untouched
        }
    }

    private var summary: String {
        let c = store.folderCounts
        return "\(c.keep) kept, \(c.reject) rejected, \(c.unflagged) still to decide. Click to jump."
    }

    /// The cursor mark's width. Two points reads at every folder size without
    /// covering the segment it is pointing at.
    private static let tick: CGFloat = 2
}
