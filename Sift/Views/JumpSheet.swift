import SwiftUI

/// `⌘K`. Type a few letters of a folder and land in it. The candidates are the
/// folders already in reach — pinned, recent, the siblings of this one and the
/// folders inside it — so it answers without walking the disk (D-37).
struct JumpSheet: View {
    let candidates: [JumpCandidate]
    let go: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var matches: [JumpCandidate] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Array(candidates.prefix(8)) }
        return candidates
            .compactMap { c in FuzzyMatch.score(needle, in: c.folder.lastPathComponent).map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map(\.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
            TextField("Jump to a folder", text: $query)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .focused($focused)
                .onSubmit(open)
                .onChange(of: query) { _, _ in selection = 0 }
            if matches.isEmpty {
                Text("No folder by that name")
                    .textStyle(.readout)
            }
            ForEach(Array(matches.enumerated()), id: \.element.id) { i, match in
                Button { go(match.folder); dismiss() } label: {
                    HStack(spacing: Tokens.Space.s8) {
                        Glyph.draw(Glyph.Folder())
                        Text(match.folder.lastPathComponent)
                            .textStyle(.label)
                        Spacer(minLength: Tokens.Space.s16)
                        Text(match.source)
                            .textStyle(.quiet)
                    }
                    .padding(.vertical, Tokens.Space.s8)
                    .padding(.horizontal, Tokens.Space.s8)
                    .background(i == selection ? Tokens.Surface.raised : .clear,
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(match.folder.path)
            }
        }
        .padding(Tokens.Space.s16)
        .frame(width: Tokens.Layout.jumpSheet, alignment: .leading)
        .background(Tokens.Surface.chrome)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
        .onMoveCommand { direction in
            switch direction {
            case .down: selection = min(selection + 1, max(0, matches.count - 1))
            case .up: selection = max(selection - 1, 0)
            default: break
            }
        }
    }

    private func open() {
        guard matches.indices.contains(selection) else { return }
        go(matches[selection].folder)
        dismiss()
    }
}

/// A folder the jump sheet knows about, and why it knows about it.
struct JumpCandidate: Identifiable, Hashable, Sendable {
    let folder: URL
    let source: String
    var id: URL { folder }
}
