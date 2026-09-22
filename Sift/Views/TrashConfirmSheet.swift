import SwiftUI

/// The one question this app asks before it does something (D-193).
///
/// The guardrail is matched to the cost of being wrong, which for almost every
/// trash is nothing: the file is in the system Trash, `⌘Z` brings it straight
/// back, and the offer outlives the toast. A favorite is the exception. It is a
/// mark somebody set deliberately, one photograph at a time, and the undo that
/// covers a trash lives in memory: quit after trashing a loved frame and the
/// way back is Finder rather than this app.
///
/// So it names what it is about to do and how many of them were loved, rather
/// than asking "are you sure" — a dialog that says nothing specific is a dialog
/// that gets clicked through.
struct TrashConfirmSheet: View {
    let confirm: TrashConfirm
    let trash: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text(confirm.question)
                .textStyle(.title)
            Text(confirm.because)
                .textStyle(.body, color: Tokens.Text.secondary)
            // The names, when there are few enough to read. A list of four
            // hundred is not information, and the count above already said it.
            if confirm.favorites.count > 1, confirm.favorites.count <= Self.namesShown {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    ForEach(confirm.favorites, id: \.url) { ref in
                        HStack(spacing: Tokens.Space.s8) {
                            FavoriteMark(size: Tokens.Layout.favoriteMarkSmall)
                            Text(ref.name)
                                .textStyle(.data)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            Text(confirm.reassurance)
                .textStyle(.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Tokens.Space.s8) {
                Spacer()
                // Cancel leads and carries Return, which is the platform's rule
                // for a destructive question: the safe answer is the one a
                // reflex reaches. Esc gets here too, through the sheet itself.
                Button("Cancel", action: cancel)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                // `role: .destructive`, so the platform colors it rather than
                // this app deciding what a dangerous button looks like. The
                // prominent one is still Cancel: Apple's rule for a
                // destructive question is that the default is the safe answer
                // (D-213).
                Button("Move to Trash", role: .destructive, action: trash)
            }
            // The pointing hand, like every other control in the app. This row
            // keeps its own layout rather than using `SheetFooter` — a
            // confirmation is two answers to one question, not a rank of
            // actions (D-355) — so it has to say this for itself (D-359).
            .pointerStyle(.link)
            .padding(.top, Tokens.Space.s8)
        }
        .padding(Tokens.Space.s24)
        .frame(width: Tokens.Layout.listSheet)
    }

    /// Past this the list stops being readable and the count is the answer.
    private static let namesShown = 8
}
