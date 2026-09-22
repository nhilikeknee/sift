import Testing
import Foundation
@testable import Sift

/// What a screen reader is told, held by the build (D-338).
///
/// Source checks, and for the reason `SandboxTests.onlyFolderAccessStartsAScope`
/// is one: SwiftUI will not hand a test the traits it computed, and the only
/// library that would read them back is a dependency this project does not
/// take. So these read the source. What they cannot see is whether the result
/// makes sense out loud, which needs somebody with VoiceOver on.
@Suite struct AccessibilityTests {
    private static func views() -> [(name: String, lines: [String])] {
        let dir = Repo.root.appendingPathComponent("Sift")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return files.sorted { $0.path < $1.path }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent,
                    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        }
    }

    /// A heading is a heading to VoiceOver, not just a size and a weight.
    ///
    /// Eleven of them had no trait, so the rotor and the heading jump found
    /// nothing — in a list of 89 bindings, that jump is how somebody gets
    /// around. The fix went into `textStyle` rather than into eleven call
    /// sites, so this checks the one place instead of counting the eleven.
    @Test func theHeadingRoleCarriesTheHeadingTrait() throws {
        let text = try Repo.text("Sift/Design/TextRole.swift")
        #expect(text.contains(".isHeader"), """
            `.textStyle(.heading)` no longer adds `.isHeader`, so every heading in \
            the app is a size and a weight with nothing a screen reader can find.
            """)
        // And it is the role that decides, not the caller: a `color:` argument
        // must not be able to turn a heading into something else.
        #expect(text.contains("role == .heading"),
                "the header trait is no longer tied to the role")
    }

    /// `.isSelected` means membership in a set. A control that is *on* is a
    /// toggle with a value, and saying "selected" for a showing filmstrip is
    /// the wrong word in the one place the reader cannot see the screen.
    @Test func nothingUsesSelectedToMeanSwitchedOn() {
        /// The real selections, each named with the set it is membership in,
        /// and each matched on its own line rather than on its file.
        ///
        /// Per line because `GalleryToolbar.swift` also holds three toggles
        /// that this rule is the whole reason are `.isToggle`: exempting the
        /// file to let two menu rows through would stop the test watching
        /// them, which is loosening a rule to get to green rather than
        /// changing it.
        let selections: [(file: String, mark: String)] = [
            // A photograph in the selected set.
            ("GridView.swift", "isSelected ? [.isSelected] : []"),
            // The sort menu's checked field: one of six. A menu row that is on
            // is membership and not a switch, which is why `NSMenuItem` has
            // `.on` and why VoiceOver says *selected* for it (A-8).
            ("GalleryToolbar.swift", "order == store.sort ?"),
            // And which of that field's two ends.
            ("GalleryToolbar.swift", "direction == store.sortDirection ?"),
        ]
        var wrong: [String] = []
        for (file, lines) in Self.views() {
            let allowed = selections.filter { $0.file == file }.map(\.mark)
            for (i, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.contains("accessibilityAddTraits"), line.contains(".isSelected") else { continue }
                guard !allowed.contains(where: line.contains) else { continue }
                wrong.append("\(file):\(i + 1) \(line)")
            }
        }
        let clean = wrong.isEmpty
        #expect(clean, """
            `.isSelected` is membership in a set. For a control that is on, use \
            `.isToggle` with an `accessibilityValue`, or add the file to `selections` \
            with the set it means:
            \(wrong.joined(separator: "\n"))
            """)
    }

    /// A label is what a control is; a value is where it has got to. Only the
    /// second is watched for changes, so a readout that counts inside its label
    /// counts where nothing is listening — the progress banner reached sixty in
    /// silence, and the zoom readout kept saying the old magnification until
    /// the reader left it and came back (D-343).
    ///
    /// The check is mechanical, because the distinction is not: a label that
    /// interpolates or branches is holding something, and the question is
    /// whether that something is the thing's name or the thing's state.
    /// Sixteen were state. The ones left are named below with the name each
    /// one interpolates, which is what puts the question to the seventeenth.
    @Test func aValueDoesNotLiveInALabel() {
        /// Identities, not states. Each names what the control *is*: the file
        /// it acts on, the folder it opens, the binding it is recording, the
        /// two names a disclosure has.
        ///
        /// Matched on what the line says rather than on where it sits. The
        /// first draft listed `file:line` and an unrelated edit twenty lines
        /// above one of them failed this test, which is a guard crying about
        /// its own bookkeeping.
        let identities: Set<String> = [
            "\"Remove \\(Self.shown(url))\"",                 // the row's own folder
            "\"Take \\(ref.name) back\"",                     // which photograph
            "\"Reset \\(knob.label.lowercased())\"",          // which slider
            "expanded ? \"Collapse\" : \"Expand\"",             // a disclosure's two names
            "open ? \"Collapse burst\" : \"Expand burst\"",     // the same two
            "\"Subfolders of \\(folder.lastPathComponent)\"",  // the menu's folder
            "recording ? \"Press the key for \\(command.label)\"", // which binding
        ]
        var moving: [String] = []
        for (file, lines) in Self.views() {
            for (i, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                // Both ways a label is set: the modifier, and the argument
                // `PopMenuButton` takes because a menu button builds its own.
                let sets = line.hasPrefix(".accessibilityLabel(")
                    || (line.hasPrefix("accessibilityLabel:") && !line.contains(": String"))
                guard sets else { continue }
                guard line.contains("\\(") || line.contains(" ? ") else { continue }
                // What was handed to the label, with the call around it
                // taken off: the modifier's parentheses, or the argument's
                // label and whatever follows it on the line.
                var argument = line
                if let marker = argument.range(of: line.hasPrefix(".") ? "accessibilityLabel(" : "accessibilityLabel:") {
                    argument = String(argument[marker.upperBound...])
                }
                while let last = argument.last, last != "\"" { argument.removeLast() }
                argument = argument.trimmingCharacters(in: .whitespaces)
                if !identities.contains(argument) {
                    moving.append("\(file):\(i + 1) \(line)")
                }
            }
        }
        let still = moving.isEmpty
        #expect(still, """
            A label that interpolates or branches is carrying something, and if that \
            something moves it moves silently: a label change is not announced. Put \
            the moving part in `.accessibilityValue`, or add the site to `identities` \
            with the name it interpolates:
            \(moving.joined(separator: "\n"))
            """)
    }

    /// A toggle that says it is a toggle and never says which way it is set
    /// reads as a switch with no position.
    @Test func everyToggleTraitComesWithAValue() {
        var bare: [String] = []
        for (file, lines) in Self.views() {
            for (i, raw) in lines.enumerated() where raw.contains(".isToggle") {
                let after = lines[(i + 1)...].prefix(2).joined(separator: " ")
                if !after.contains("accessibilityValue") {
                    bare.append("\(file):\(i + 1)")
                }
            }
        }
        let paired = bare.isEmpty
        #expect(paired, """
            `.isToggle` says the control is a switch; the value says which way it is \
            set. These have the trait and no value: \(bare.joined(separator: ", "))
            """)
    }
}
