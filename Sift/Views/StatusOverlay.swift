import SwiftUI

/// The toast and the progress banner, in whichever window the keyboard is
/// talking to. Trashing a photo from the preview used to put the confirmation,
/// and the only undo on offer, on the gallery window behind it (D-48).
@MainActor
struct StatusOverlay: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    /// Which window this copy of the overlay is drawn in.
    let window: WindowFocus

    var body: some View {
        if shows {
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                Spacer()
                // Above whatever is reporting, because the hint is about what
                // to do next and the toast is about what just happened.
                if let hint = store.hint {
                    HintView(hint: hint) { store.hint = nil }
                        .transition(.opacity)
                        // The toast brings its own 32 off the bottom edge. On
                        // its own the hint has to bring the same.
                        .padding(.bottom, store.toast == nil && store.progress == nil ? Tokens.Space.s32 : 0)
                }
                if let progress = store.progress {
                    ProgressBanner(progress: progress) { store.cancelProgress() }
                        .transition(.opacity)
                } else if let toast = store.toast {
                    ToastView(toast: toast,
                              dismiss: { store.toast = nil },
                              accept: { offer in
                                  store.toast = nil
                                  if offer.ingests { store.ingesting = offer.folder } else { router.open(offer.folder) }
                              })
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            // No clearance for the preview bar any more. It used to lift the
            // toast above the bar so neither covered the other, and it lifted
            // only the toast: the undo control is an overlay on the far side of
            // that padding, so the two sat at different heights and the one
            // replacing the other jumped. The bars are centered and this band
            // is in the left corner now, so they no longer share any width
            // worth clearing (D-282).
            //
            // The stack is as wide as its widest child, which with nothing
            // reporting is nothing at all, and an overlay hung off a zero-width
            // stack lands in the middle of the window rather than in the
            // corner (D-182).
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomLeading) { undoControl }
            // One inset, applied to the whole reporting band rather than by
            // each thing in it, and applied after the overlay so the toast and
            // the undo control that replaces it are the same distance from the
            // edge by construction rather than by two numbers agreeing (D-280).
            .padding(.leading, Tokens.Space.s16)
            .animation(Tokens.Motion.fast, value: store.toast)
            .animation(Tokens.Motion.fast, value: store.hint)
            // The way back arriving is the app's whole report of an undoable
            // act, and it arrives in a corner. Said out loud when it changes
            // rather than when this view appears: moving the keyboard to the
            // other window rebuilds the overlay, and the offer is the same one
            // (A-11).
            .onChange(of: store.undoOffer) { _, offer in
                if let offer { Announcer.say(offer, .ordinary) }
            }
        }
    }

    /// The way back, after the receipt has gone (D-182).
    ///
    /// A toast leaves after six seconds and carries its own Undo while it is
    /// up; this is what it decays into, and it stays until there is nothing
    /// left to undo. It used to be a chip in the header, which put the undo
    /// for a photograph at the opposite corner of the window from the
    /// photograph, competed for the width the header's ladder was negotiating,
    /// and read as one more piece of folder state rather than as an action.
    ///
    /// Never at the same time as the toast. Two Undo buttons in one band is two
    /// controls for one fact, and the reader has to work out whether they do
    /// the same thing. They now sit in the same corner as well, so the one
    /// replacing the other does not move (D-280).
    @ViewBuilder
    private var undoControl: some View {
        if let offer = store.undoOffer {
            Button { router.perform(.undo) } label: {
                HStack(spacing: Tokens.Space.s8) {
                    // The platform's undo mark, pointing back the way this
                    // one does (D-198).
                    Glyph.draw(Glyph.Revert(), size: Tokens.Layout.glyph)
                    Text(offer)
                        .textStyle(.label)
                        .lineLimit(1)
                }
                .padding(.horizontal, Tokens.Space.s12)
                .padding(.vertical, Tokens.Space.s8)
                .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .shadow(color: Tokens.Elevation.overlay.color,
                        radius: Tokens.Elevation.overlay.radius,
                        y: Tokens.Elevation.overlay.y)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .linkCursor()
            // The leading inset is the stack's, not this button's (D-280). The
            // 32 off the bottom is still here, because the toast brings its own
            // and these two are what have to agree.
            .padding(.bottom, Tokens.Space.s32)
            .transition(.opacity)
            // The same words the control draws, so the tooltip and the voice
            // and the pill cannot drift into three descriptions of one action.
            .help("\(offer) (⌘Z)")
        }
    }

    /// The window with the keyboard gets it. With the preview closed there is
    /// only one window to put it in, so the gallery takes everything.
    private var shows: Bool {
        store.previewOpen ? store.focus == window : window == .gallery
    }
}
