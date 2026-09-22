import SwiftUI

/// What this sitting did, and where the folder stands. Any key closes it.
@MainActor
struct SummaryOverlay: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let s = store.session
        let f = store.folderCounts
        VStack(alignment: .leading, spacing: Tokens.Space.s24) {
            Text(store.folder?.lastPathComponent ?? "Summary")
                .textStyle(.title)
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                Text("This sitting")
                    .textStyle(.heading)
                row("Kept", "\(s.kept)")
                row("Rejected", "\(s.rejected)")
                row("Trashed", "\(s.trashed)")
                row("Freed", s.trashedBytes.formatted(.byteCount(style: .file)))
                row("Moved", "\(s.moved)")
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                Text("The folder")
                    .textStyle(.heading)
                row("Keep", "\(f.keep)")
                row("Reject", "\(f.reject)")
                row("Unflagged", "\(f.unflagged)")
                row("Photos", "\(store.allPhotos.count)")
            }
            Text("Any key closes this.")
                .textStyle(.quiet)
        }
        .padding(Tokens.Space.s32)
        .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .shadow(color: Tokens.Elevation.overlay.color, radius: Tokens.Elevation.overlay.radius, y: Tokens.Elevation.overlay.y)
        // "Any key closes this" is true of a keyboard and says nothing to a
        // screen reader, whose cursor would otherwise walk behind the panel
        // into the grid. Every other panel in the app is a `.sheet`, which
        // SwiftUI marks for us; these two are drawn by hand (D-339).
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
            Text(k).textStyle(.quiet)
                .frame(width: Tokens.Layout.labelColumn, alignment: .leading)
            Text(v).textStyle(.data)
        }
    }
}
