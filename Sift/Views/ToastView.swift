import SwiftUI

/// Reports something that is not on screen and cannot be taken back: a copy, a
/// refusal, the end of a folder. Flags and the favorite get no toast either —
/// their state is drawn on the cell.
///
/// It used to carry an Undo button too, and an undoable operation used to raise
/// one of these as well as leaving the pill in the corner: two shapes, one of
/// them a plain word and the other an icon, for the same fact. The way back is
/// its own pill now and this one never offers it (D-283).
struct ToastView: View {
    let toast: ToastState
    let dismiss: () -> Void
    /// No default: a toast that offers a folder and cannot open it is worse
    /// than one that never offered.
    let accept: (FolderOffer) -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s16) {
            Text(toast.message)
                .textStyle(.label)
                // The one hue that means "this is bad" is the one the reject
                // flag already uses, so an error needs no new color (D-48).
                .foregroundStyle(toast.isError ? Tokens.State.reject : Tokens.Text.primary)
            if let offer = toast.offer {
                Button(action: { accept(offer) }) {
                    HStack(spacing: Tokens.Space.s4) {
                        Text(offer.label)
                        Glyph.draw(Glyph.Chevron())
                    }
                    // Without it the chevron's hit target is the stroked arc
                    // and the offer is pressable on its word only (D-185).
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .linkCursor()
                .textStyle(.strong)
                .help(offer.ingests ? "Copy the photos off \(offer.folder.lastPathComponent)" : "Open \(offer.folder.path) (⌘⇧→)")
            }
            if toast.isError {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(.plain)
                    .linkCursor()
                    .textStyle(.strong)
                    .help("Dismiss")
            }
        }
        .padding(.horizontal, Tokens.Space.s16)
        .padding(.vertical, Tokens.Space.s12)
        .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .shadow(color: Tokens.Elevation.overlay.color,
                radius: Tokens.Elevation.overlay.radius,
                y: Tokens.Elevation.overlay.y)
        .padding(.bottom, Tokens.Space.s32)
        .task(id: toast.id) {
            // An error gets longer, because reading it is the whole point and
            // there is no second copy of it anywhere.
            try? await Task.sleep(for: .seconds(toast.isError ? 12 : 6))
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
    }
}
