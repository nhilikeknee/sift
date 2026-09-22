import SwiftUI

/// Settings' Keyboard section: every command, the key it is on, and a way to
/// put it on a different one (D-175).
///
/// A filter over the whole list rather than a short list of the ones somebody
/// might want: which keys a person wants to move is not something this app can
/// know, and a list that guesses is a list that is wrong for everybody it
/// guessed against. Typing "trash" is faster than scrolling to Files anyway.
///
/// It reads the same table the shortcuts overlay does and narrows it the same
/// way, because both go through `KeyMap.matches` (D-7).
@MainActor
struct KeyboardSettings: View {
    private let bindings = KeyBindings.shared
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    private var needle: String { query.trimmingCharacters(in: .whitespaces) }
    private var map: KeyMap { bindings.map }

    /// A switched-off feature has no row here, for the reason it has no line in
    /// the shortcuts overlay: a key you can reassign and then cannot press is
    /// worse than a list that is short (D-123).
    private var groups: [(String, [Command])] {
        let features = AppModel.shared.features
        return Command.groups
            .map { g in (g, Command.allCases.filter {
                $0.group == g && features.allows($0) && map.matches($0, query: needle)
            }) }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        let groups = groups
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            Text("Keyboard")
                .textStyle(.heading)
            Text("Click a key to put that command on a different one, then press the key you want. A key another command is using moves to the new one, as long as that command has another key left. Esc, ⌘Q and ⌘W stay where they are.")
                .textStyle(.readout)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Filter by command, group or key", text: $query)
                .textFieldStyle(.plain)
                .textStyle(.label)
                .padding(.horizontal, Tokens.Space.s12)
                .frame(width: Tokens.Layout.settingsControl,
                       height: Tokens.Layout.searchFieldHeight, alignment: .leading)
                .background(Tokens.Surface.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                .focused($filterFocused)
                .padding(.top, Tokens.Space.s4)

            if groups.isEmpty {
                Text("No command matches \"\(needle)\".")
                    .textStyle(.quiet)
                    .padding(.top, Tokens.Space.s8)
            }

            ForEach(groups, id: \.0) { group, commands in
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    Text(group)
                        .textStyle(.strong)
                        // More space above a heading than below it, or it
                        // attaches to the group before it.
                        .padding(.top, Tokens.Space.s16)
                    ForEach(commands, id: \.self) { row($0) }
                }
            }

            // Absent until there is something to undo: a reset with nothing to
            // reset is a control that says the app has been changed when it
            // has not.
            if bindings.anyOverride {
                Button("Put Every Key Back") { bindings.resetAll() }
                    .textStyle(.label)
                    .padding(.top, Tokens.Space.s16)
            }
        }
    }

    private func row(_ command: Command) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            HStack(spacing: Tokens.Space.s8) {
                Text(command.label)
                    .textStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tokens.Space.s8)
                // Only on a command that was moved, so the row says whether it
                // is where it shipped without a word for it.
                if bindings.isOverridden(command) { revert(command) }
                chip(command)
            }
            if let refused = bindings.refused, refused.command == command {
                Text(refused.reason.message)
                    .textStyle(.quiet, color: Tokens.State.reject)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The readout is the control: the keys you look at are the button you
    /// press to change them. A second "Change…" button beside them would be
    /// two controls for one fact.
    ///
    /// `keyCapWidth`, not `keyColumn`: the column is the text, and the chip is
    /// the text plus its padding. Measured against the column, the one row
    /// whose keys fill it grew a chip 8pt wider than the rest of a
    /// right-aligned stack (D-315).
    private func chip(_ command: Command) -> some View {
        let recording = bindings.recording == command
        return Button {
            if recording { bindings.cancelRecording() } else { bindings.beginRecording(command) }
        } label: {
            Text(recording ? "Press a key" : map.keys(for: command).map(\.display).joined(separator: "  "))
                .textStyle(recording ? .quiet : .data)
                .lineLimit(1)
                .padding(.horizontal, Tokens.Space.s8)
                .frame(minWidth: Tokens.Layout.keyCapWidth, minHeight: Tokens.Layout.glyphButton)
                .background(Tokens.Surface.keyCap, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                // The ring the rest of the app draws around whatever the
                // keyboard is on (DESIGN, focus), which is exactly what this
                // row is while it waits. At rest it is the hairline instead:
                // the fill alone sits on a row the system draws, and in dark
                // it came to 1.01:1 against it (D-312).
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .strokeBorder(recording ? Tokens.Border.focus : Tokens.Border.hairline,
                                      lineWidth: recording ? Tokens.Border.ringWidth
                                                           : Tokens.Border.hoverWidth)
                }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(recording ? "Press the key you want, or Esc to leave it alone"
                        : "Change the key for \(command.label)")
        .accessibilityLabel(recording ? "Press the key for \(command.label)"
                                      : "\(command.label), currently \(map.keys(for: command).map(\.display).joined(separator: ", "))")
    }

    /// The rotate glyph, which is the reset mark on this platform and is
    /// already drawn (D-162). It appears with the state it belongs to.
    ///
    /// Through `GlyphButton` rather than a `Button` of its own (D-185). The
    /// hand-rolled one had no `contentShape`, so its hit target was the
    /// stroked arc itself: a 2pt line bent into a circle, which is a control
    /// you press by tracing. It was also `text.tertiary` at rest with no
    /// hover, so the one thing that would have shown the target was missing
    /// too. The shared button carries the rectangle, the hover ink and the
    /// fill, and the box goes to `glyphActionButton` because the glyph inside
    /// it is at the action scale: 20 in 28 leaves four points of margin.
    private func revert(_ command: Command) -> some View {
        // The action scale, not the chrome one: at 14 the arc and its head
        // ran together into a smudge beside a chip of clean letterforms.
        GlyphButton(shape: Glyph.Revert(),
                    size: Tokens.Layout.glyphActionButton,
                    glyphSize: Tokens.Layout.glyphAction,
                    label: "Reset the key for \(command.label)",
                    hint: "Put \(command.label) back on the key it shipped with") {
            bindings.reset(command)
        }
    }
}
