import SwiftUI

/// `⌘⇧K`. The jump sheet finds folders; this finds verbs. Every command in
/// `KeyMap.standard` by name, fuzzy, each row carrying the keys that also run
/// it — so looking a command up here is how you stop needing to look it up
/// (D-68).
@MainActor
struct CommandPalette: View {
    /// Which window opened it. The command runs against the same store either
    /// way, but the sheet has to be presented by one scene only.
    let focus: WindowFocus
    let run: (Command) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    // The live table, not the shipped one: a reassigned key has to show up
    // here too, or the overlay is a second list of the bindings (D-7, D-175).
    private let bindings = KeyBindings.shared
    private var map: KeyMap { bindings.map }

    /// Everything but the way in here. A palette that offers to open itself is
    /// a row that can never be the answer.
    private var all: [Command] {
        let features = AppModel.shared.features
        return Command.allCases.filter { $0 != .commandPalette && features.allows($0) }
    }

    private var matches: [Command] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Array(all.prefix(Self.rows)) }
        return all
            .compactMap { c in score(needle, for: c).map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.rows)
            .map(\.0)
    }

    /// The label carries the search; the group and the keys are there as a
    /// fallback, so "files" finds the file commands and "⌘Z" finds undo.
    private func score(_ needle: String, for command: Command) -> Int? {
        if let s = FuzzyMatch.score(needle, in: command.label) { return s }
        if command.group.localizedCaseInsensitiveContains(needle) { return 1 }
        if map.keys(for: command).contains(where: { $0.display.localizedCaseInsensitiveContains(needle) }) { return 1 }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
            TextField("Run a command", text: $query)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .focused($focused)
                .onSubmit(pick)
                .onChange(of: query) { _, _ in selection = 0 }
            if matches.isEmpty {
                Text("No command by that name")
                    .textStyle(.readout)
            }
            ForEach(Array(matches.enumerated()), id: \.element) { i, command in
                Button { go(command) } label: {
                    row(command, highlighted: i == selection)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(command.label)
            }
        }
        .padding(Tokens.Space.s16)
        .frame(width: Tokens.Layout.palette, alignment: .leading)
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

    private func row(_ command: Command, highlighted: Bool) -> some View {
        HStack(spacing: Tokens.Space.s8) {
            Text(command.label)
                .textStyle(.label)
                .lineLimit(1)
            Spacer(minLength: Tokens.Space.s16)
            Text(command.group)
                .textStyle(.quiet)
            Text(map.keys(for: command).prefix(2).map(\.display).joined(separator: "  "))
                .textStyle(.data, color: Tokens.Text.secondary)
                .frame(width: Tokens.Layout.keyColumn, alignment: .trailing)
        }
        .padding(Tokens.Space.s8)
        .background(highlighted ? Tokens.Surface.raised : .clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .contentShape(Rectangle())
    }

    private func pick() {
        guard matches.indices.contains(selection) else { return }
        go(matches[selection])
    }

    /// The sheet goes before the command runs: several of them open a sheet or
    /// a panel of their own, and two sheets on one window is one that never
    /// appears.
    private func go(_ command: Command) {
        dismiss()
        run(command)
    }

    /// Eight rows, the same as the jump sheet. A list you scroll is a list you
    /// read, and this one is meant to be typed at.
    private static let rows = 8
}
