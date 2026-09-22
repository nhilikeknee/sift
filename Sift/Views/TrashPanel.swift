import SwiftUI

/// Everything sent to the Trash this sitting, with a way back for each one.
struct TrashPanel: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("Trashed this sitting")
                .textStyle(.title)
            if store.trashLog.isEmpty {
                Text("Nothing yet.")
                    .textStyle(.body, color: Tokens.Text.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                        ForEach(store.trashLog) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s12) {
                                Text(entry.name)
                                    .textStyle(.label, color: entry.restored ? Tokens.Text.tertiary : Tokens.Text.primary)
                                    .lineLimit(1)
                                Text(entry.size.formatted(.byteCount(style: .file)))
                                    .textStyle(.data, color: Tokens.Text.tertiary)
                                Spacer()
                                if entry.restored {
                                    Text("Restored")
                                        .textStyle(.quiet)
                                } else {
                                    Button("Restore") { router.restoreFromTrash(entry) }
                                        .buttonStyle(.plain)
                                        .pointerStyle(.link)
                                        .textStyle(.strong)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: Tokens.Layout.listSheetHeight)
            }
            HStack {
                let pending = store.trashLog.filter { !$0.restored }
                if pending.count > 1 {
                    Button("Restore All") { for e in pending { router.restoreFromTrash(e) } }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .textStyle(.readout)
                }
                Spacer()
                // One button, so it is the default one: a sheet with nothing to
                // decide is dismissed by Return. Escape reaches it through the
                // sheet itself (D-213).
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.s24)
        .frame(width: Tokens.Layout.listSheet)
    }
}
