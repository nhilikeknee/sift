import SwiftUI

/// `⌘⇧I`. Copy, rename and open in one pass, which is the reason Photo Mechanic
/// exists (D-89). Sift knew when a card mounted and offered to open it; opening
/// a card is the one thing you should not do, because culling off a card is
/// culling over a USB bus and a card you can eject.
///
/// Copy only. Nothing here moves or deletes anything on the card: a card is the
/// only copy of a shoot until this finishes.
@MainActor
struct IngestSheet: View {
    @Environment(CommandRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// Where the photos are now.
    let source: URL

    @State private var destination: URL?
    @State private var pattern = ""
    @State private var subfolder = ""
    @State private var found: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("Copy off \(source.lastPathComponent)")
                .textStyle(.title)

            field("From", source.path)
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                label("To")
                if let destination {
                    Text(destination.path)
                        .textStyle(.data)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("Pick a folder")
                        .textStyle(.readout)
                }
                Spacer()
                WordButton(title: destination == nil ? "Choose…" : "Change…",
                           hint: "Where the copies go") {
                    destination = router.chooseFolder(prompt: "Copy here", message: "Copy the photos into…")
                }
            }

            entry("Into", text: $subfolder, placeholder: "A new folder inside it, optional")
            entry("Rename", text: $pattern, placeholder: "{name} — or {nnn}, {date}, {ext}")

            Text(summary)
                .textStyle(.readout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Space.s16) {
                Spacer()
                WordButton(title: "Cancel", hint: "Copy nothing (Esc)") { dismiss() }
                Button {
                    guard let destination else { return }
                    dismiss()
                    router.ingest(from: source, into: destination, subfolder: subfolder, pattern: pattern)
                } label: {
                    Text(found == 0 ? "Nothing to copy" : "Copy")
                        .textStyle(.strong)
                        .padding(.horizontal, Tokens.Space.s12)
                        .padding(.vertical, Tokens.Space.s8)
                        .background(Tokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(Tokens.Text.primary)
                .disabled(destination == nil || found == 0 || refusal != nil)
                .help("Copy every photo on the card into the folder above")
            }
        }
        .padding(Tokens.Space.s24)
        .frame(width: Tokens.Layout.ingestSheet, alignment: .leading)
        .background(Tokens.Surface.chrome)
        .onExitCommand { dismiss() }
        .task(id: source) {
            found = await Task.detached { FolderScanner.count(source, recursive: true) }.value
            // The last folder somebody culled into is the likeliest place for
            // this card to land, so it is offered rather than asked for.
            if destination == nil { destination = Preferences.lastIngestFolder ?? Preferences.lastMoveFolder }
        }
    }

    /// Where the copies would go, or why they cannot go there. The same call
    /// the ingest itself makes, so the line under the fields cannot say one
    /// thing and the copy do another (D-303, D-304).
    private var landing: Result<URL, FileOps.Failure>? {
        guard let destination else { return nil }
        do { return .success(try FileOps.ingestPlan(destination: destination,
                                                    subfolder: subfolder, pattern: pattern)) }
        catch { return .failure(error) }
    }

    /// A name that is a path stops the copy here, with the reason on screen,
    /// rather than being refused after the sheet has closed. An ingest has no
    /// inverse, so the moment to say so is before the button (D-303).
    private var refusal: String? {
        guard case .failure(let error) = landing else { return nil }
        return error.message
    }

    private var summary: String {
        guard let found else { return "Counting…" }
        if found == 0 { return "No photos under \(source.lastPathComponent)." }
        if let refusal { return refusal }
        let what = found == 1 ? "1 photo" : "\(found) photos"
        // No destination is the only way past the refusal without a landing
        // folder, and it is not a refusal: the sheet opens with the field
        // empty and offers to fill it.
        guard let destination, case .success(let dest) = landing else {
            return "\(what) to copy. Nothing is removed from the card."
        }
        let where_ = dest == destination
            ? destination.lastPathComponent
            : "\(destination.lastPathComponent)/\(dest.lastPathComponent)"
        return "\(what) into \(where_). Nothing is removed from the card."
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .textStyle(.quiet)
            .frame(width: Tokens.Layout.labelColumn, alignment: .leading)
    }

    private func field(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
            label(key)
            Text(value)
                .textStyle(.data)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
    }

    private func entry(_ key: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
            label(key)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textStyle(.data)
                .padding(.horizontal, Tokens.Space.s8)
                .padding(.vertical, Tokens.Space.s4)
                .background(Tokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        }
    }
}
