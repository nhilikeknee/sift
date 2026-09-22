import SwiftUI

/// `⇧X`. Everything in the folder flagged reject, in one place, before the one
/// thing in the app a click cannot bring back. Take any of them back, then
/// trash the rest in a single batch with a single undo (D-69).
///
/// The rejects come from the whole folder, not from what a filter happens to be
/// showing: a review that quietly leaves some out is worse than no review.
struct RejectReview: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router
    /// The Trash takes its red as the pointer arrives (D-356).
    @State private var trashHovering = false
    @Environment(\.dismiss) private var dismiss

    private var refs: [PhotoRef] { store.rejected }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text(headline)
                .textStyle(.title)
            Text("Click a photo to take it back. What is left goes together, under one undo.")
                .textStyle(.readout)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Tokens.Layout.gridCell), spacing: Tokens.Space.s12)],
                          spacing: Tokens.Space.s12) {
                    ForEach(refs) { ref in
                        RejectCell(ref: ref) { router.takeBack(ref) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SheetFooter {
                // Apart from the rest, at the far edge, because it is the one
                // thing here a click cannot bring back (D-355). It used to sit
                // last in the row, where the default button goes.
                Button(role: .destructive) { router.trashRejects() } label: {
                    ActionLabel(title: trashTitle,
                                shape: Glyph.Trash(),
                                tint: trashHovering ? Tokens.State.reject : nil)
                }
                // A box while nobody is pointing at it, and no box once
                // somebody is. The red has to sit on a ground this app sets
                // and measures, and a bordered button's is the system's:
                // `state.reject` on it came to about 1.7:1 where text is held
                // to 4.5 (D-356). So the fill is ours, `bg.control`, drawn
                // only at rest, and the red only ever lands on the panel's own
                // `bg.chrome`, which the suite holds to the graphic floor.
                //
                // D-357 argued for no box in either state, on the grounds that
                // hover adds emphasis everywhere else and a control that sheds
                // its box reads as one going away. Overruled by the owner,
                // twice: the red and a gray fill under it fight, and losing
                // the fill is what lets the word be the whole signal (D-359).
                .buttonStyle(.plain)
                .padding(.horizontal, Tokens.Space.s12)
                .padding(.vertical, Tokens.Space.s8)
                .background(trashHovering ? .clear : Tokens.Surface.control,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .linkCursor()
                // Red as the pointer arrives, not at rest. The rule for a word
                // in a column of paths is the other way round, and for the
                // same reason it is the other way round here: that word is
                // read before it is pointed at, and this button already sits
                // apart at the far edge (D-321, D-356).
                //
                // The tint, not an ink of our own inside the label. Coloring
                // the label put `state.reject` on the button's own hover fill,
                // a mid-gray this app does not set and cannot measure against:
                // about 1.7:1, where text is held to 4.5. A tinted button is
                // the platform coloring both sides of that pair, which is the
                // same argument `bg.keyCap` makes about a ground the system
                // supplies.
                .tint(trashHovering ? Tokens.State.reject : nil)
                .onHover { trashHovering = $0 }
                .animation(Tokens.Motion.fast, value: trashHovering)
                .disabled(refs.isEmpty)
                .help("Move all \(refs.count) to the Trash, undoable with ⌘Z")
            } actions: {
                WordButton(title: "Keep reviewing", hint: "Close this and leave the rejects alone (Esc)") {
                    dismiss()
                }
                // The safe one is the prominent one. Moving them aside keeps
                // the files on the disk, in order, in a folder you can walk
                // into; the Trash is the one a cleaner app can empty behind
                // your back (D-81). It does not claim Return: keys are the key
                // map's, and a `keyboardShortcut` here would be a second place
                // this app decides what a key does.
                Button { router.moveRejectsAside() } label: {
                    ActionLabel(title: asideTitle, shape: Glyph.MoveToFolder())
                }
                .buttonStyle(.borderedProminent)
                .disabled(refs.isEmpty)
                .help("Move all \(refs.count) into a \(CommandRouter.rejectFolderName) folder beside the photos")
            }
        }
        .padding(Tokens.Space.s24)
        .frame(width: Tokens.Layout.reviewSheet, height: Tokens.Layout.reviewSheetHeight)
        .background(Tokens.Surface.chrome)
        .onExitCommand { dismiss() }
        // Taking the last one back leaves nothing to review, and a sheet with
        // nothing in it is a sheet nobody asked to keep looking at.
        .onChange(of: refs.isEmpty) { _, empty in if empty { dismiss() } }
    }

    private var headline: String {
        refs.count == 1 ? "One rejected photo" : "\(refs.count) rejected photos"
    }

    private var trashTitle: String {
        refs.count == 1 ? "Trash it" : "Trash all \(refs.count)"
    }

    private var asideTitle: String {
        "Move to \(CommandRouter.rejectFolderName)"
    }
}

/// A reject, and the one thing to do about it here. The whole cell is the
/// control: there is one verb on this screen, so it does not need a button.
private struct RejectCell: View {
    let ref: PhotoRef
    let takeBack: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: takeBack) {
            PhotoImage(ref: ref, full: false, cell: Tokens.Layout.gridCell)
                .frame(width: Tokens.Layout.gridCell, height: Tokens.Layout.gridCell)
                .background(Tokens.Surface.raised)
                .overlay {
                    if hovering {
                        ZStack {
                            // design-system:allow — a scrim over the photograph
                            // so the count on top of it stays legible against
                            // any frame. Not chrome, so not themed.
                            Rectangle().fill(Tokens.Surface.scrim)
                            Text("Take it back")
                                .textStyle(.strong, color: Tokens.State.favoriteKeyline)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Tokens.State.reject)
                        .frame(width: Tokens.Space.s12, height: Tokens.Space.s12)
                        .padding(Tokens.Space.s8)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .linkCursor()
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .help("\(ref.name) — click to clear the reject flag")
        .accessibilityLabel("Take \(ref.name) back")
    }
}
