import SwiftUI

/// `⇧⌘G`. A path typed, or pasted out of Finder or a terminal. The one way into
/// a folder that is nowhere on screen and not in the history.
struct GoToPathSheet: View {
    let go: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("Go to folder")
                .textStyle(.heading)
            TextField("/Volumes/CARD/DCIM", text: $path)
                .textFieldStyle(.plain)
                .textStyle(.data)
                .padding(Tokens.Space.s8)
                .background(Tokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .frame(width: Tokens.Layout.pathField)
                .focused($focused)
                .onSubmit(submit)
            SheetFooter {
                // The platform's buttons, not this app's text. A sheet is the
                // most convention-bound thing a Mac app draws: a bordered pair
                // at the bottom right, the action prominent and on Return, the
                // way out on Escape. They were two plain labels, so Return did
                // nothing unless the caret happened to be in the field and
                // Escape nothing at all (D-213).
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(path.isEmpty)
            }
        }
        .padding(Tokens.Space.s24)
        .background(Tokens.Surface.chrome)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
    }

    private func submit() {
        guard !path.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        go(path)
        dismiss()
    }
}
