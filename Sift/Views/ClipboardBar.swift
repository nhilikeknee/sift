import SwiftUI

/// What `⌘C` put on the clipboard, and the two things you can do with it
/// (D-135). Above the grid, and only while there is something loaded: a bar
/// that is always there is chrome, and a bar that arrives with the state it
/// belongs to is the state saying so.
///
/// This is also paste's way in that is not a keystroke (D-42). `⌘V` is the
/// accelerator; the button is the thing that tells somebody the command is
/// there at all.
struct ClipboardBar: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    var body: some View {
        HStack(spacing: Tokens.Space.s12) {
            Text(subject)
                .textStyle(.readout)
            Spacer(minLength: Tokens.Space.s12)
            WordButton(title: pasteTitle, hint: "Copy the clipboard into this folder (⌘V)") {
                router.perform(.pasteHere)
            }
            WordButton(title: "Clear", hint: "Empty the clipboard (⇧⌘V)") {
                router.perform(.clearClipboard)
            }
        }
        .padding(.horizontal, Tokens.Space.s16)
        .padding(.vertical, Tokens.Space.s8)
        .background(Tokens.Surface.raised)
    }

    private var subject: String {
        let n = store.clipboard.count
        let name = store.clipboard.first?.lastPathComponent ?? ""
        return n == 1 ? "\(name) on the clipboard" : "\(n) photos on the clipboard"
    }

    /// Names the folder, because the whole point of this clipboard is that it
    /// outlives the folder it was filled in and a paste lands wherever you
    /// happen to be looking.
    private var pasteTitle: String {
        guard let folder = store.folder else { return "Paste" }
        return "Paste into \(folder.lastPathComponent)"
    }
}
