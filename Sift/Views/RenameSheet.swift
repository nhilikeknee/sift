import AppKit
import SwiftUI

struct RenameSheet: View {
    let ref: PhotoRef
    let commit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("Rename").textStyle(.title)
            TextField("Name", text: $name)
                .textStyle(.label)
                .textFieldStyle(.roundedBorder)
                .focused($editing)
                .onSubmit(submit)
            // No mark on Rename. It is the only thing this sheet does and the
            // sheet is titled with it, so a pencil beside the word would be a
            // picture of the heading above it (D-355).
            SheetFooter {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.s24)
        .frame(width: Tokens.Layout.pathField)
        .onAppear { name = ref.name; editing = true }
        // Not `onAppear`: the field editor does not exist until SwiftUI has
        // made the field first responder, and it is AppKit that selects the
        // whole name when it does. This fires after that, and the hop puts
        // the narrowing after AppKit's own select-all rather than under it.
        .onChange(of: editing) { _, editing in
            guard editing else { return }
            Task { @MainActor in selectTheStem() }
        }
    }

    /// Opens with the name selected and the extension left out of it (D-379).
    ///
    /// Somebody renaming `frame-08.jpg` is renaming `frame-08`: typing over
    /// the whole thing takes `.jpg` with it, and a photograph whose extension
    /// no longer matches its bytes is a photograph the Finder opens in the
    /// wrong application. The extension is still there to be edited, one
    /// arrow key away. Finder, Xcode and every Save panel on the machine do
    /// this.
    ///
    /// Reaching for the field editor is the only way to say it: SwiftUI's
    /// `TextField` has no selection of its own on macOS 15.
    private func selectTheStem() {
        let range = FileOps.stemRange(of: ref.name)
        // Nothing before the dot, so there is nothing to offer: a name that is
        // all extension keeps AppKit's select-all rather than landing the
        // caret at the front of it.
        guard range.length > 0 else { return }
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        editor.setSelectedRange(range)
    }

    private func submit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != ref.name else { dismiss(); return }
        commit(n)
        dismiss()
    }
}

struct BatchRenameSheet: View {
    let refs: [PhotoRef]
    let commit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pattern = "{name}"

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("Rename \(refs.count) photos").textStyle(.title)
            TextField("Pattern", text: $pattern)
                .textStyle(.data)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            Text("{name} original, {n} {nn} {nnn} counter, {date} taken or created, {ext}. Extension is kept if omitted.")
                .textStyle(.readout)
            // The refusal stands where the preview would, rather than beside
            // it: a list of names the run will not write is not a preview of
            // anything, and two lines disagreeing about what is going to
            // happen is worse than either alone.
            if let refusal {
                Text(refusal)
                    .textStyle(.readout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    ForEach(Array(refs.prefix(4).enumerated()), id: \.element.id) { i, ref in
                        let renamed = FileOps.expand(pattern: pattern, ref: ref, index: i + 1)
                        // The arrow is the whole sentence on screen and nothing
                        // to a voice, which reads it as the name of a glyph or
                        // skips it. This row is the only place the sheet says
                        // what it is about to do to 120 files (A-12).
                        Text("\(ref.name)  →  \(renamed)")
                            .accessibilityLabel(ref.name)
                            .accessibilityValue("becomes \(renamed)")
                            .textStyle(.data)
                            .lineLimit(1)
                    }
                    if refs.count > 4 {
                        Text("and \(refs.count - 4) more").textStyle(.quiet)
                    }
                }
            }
            SheetFooter {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                // The count, because this one acts on more than the photograph
                // in front of you and the number is what somebody checks
                // before pressing it (D-355).
                Button("Rename \(refs.count)", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(refusal != nil)
            }
        }
        .padding(Tokens.Space.s24)
        .frame(width: Tokens.Layout.listSheet)
    }

    /// Why this pattern cannot be run, or nil. The same call the rename
    /// itself makes, so the line under the field cannot say one thing and the
    /// run do another (D-304, D-380).
    private var refusal: String? {
        do { _ = try FileOps.renamePlan(pattern: pattern, refs: refs); return nil }
        catch { return error.message }
    }

    private func submit() {
        guard !pattern.trimmingCharacters(in: .whitespaces).isEmpty, refusal == nil else { return }
        commit(pattern)
        dismiss()
    }
}
