import Testing
import Foundation
@testable import Sift

/// The design system, held by the build rather than by review (D-114).
///
/// The design document has been the contract since the first commit and the drift still
/// happened: `Tokens.Font.ui` ended up at 65 call sites in three colors, six
/// pixel literals sat in views, and one 14pt size was doing four different
/// jobs. A document nothing checks is a document that describes the app it
/// used to be. These read the source.
@Suite struct DesignSystemTests {
    private static let root = Repo.root

    private static func swiftFiles(under folder: String) -> [(name: String, text: String)] {
        let dir = root.appendingPathComponent(folder)
        let found = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return found.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) }
        }
    }

    /// A line is exempt when it carries the marker, or when the comment above
    /// it does — which is where the reason fits.
    private static let marker = "design-system:allow"

    private static func offendingLines(_ text: String, matching: (String) -> Bool) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.enumerated().filter { i, line in
            guard matching(line) else { return false }
            if line.contains(marker) { return false }
            // Walk back over the comment block immediately above.
            var j = i - 1
            while j >= 0 {
                let above = lines[j].trimmingCharacters(in: .whitespaces)
                guard above.hasPrefix("//") else { break }
                if above.contains(marker) { return false }
                j -= 1
            }
            return true
        }.map(\.element)
    }

    @Test func noViewSetsAFontDirectly() {
        // A size is not a style. `.textStyle(.role)` pairs the size, the weight
        // and the resting color, which is the only thing that keeps four kinds
        // of 14pt text telling themselves apart.
        for file in Self.swiftFiles(under: "Sift") where file.name != "TextRole.swift" {
            let bad = Self.offendingLines(file.text) { $0.contains(".font(") }
            #expect(bad.isEmpty, "\(file.name) sets a font: \(bad.joined(separator: " | "))")
        }
    }

    @Test func noViewNamesAColorOutsideTheTokens() {
        for file in Self.swiftFiles(under: "Sift/Views") {
            let bad = Self.offendingLines(file.text) { line in
                guard line.contains("Color(") || line.contains("NSColor(")
                        || Self.mentions(".white", in: line) || Self.mentions(".black", in: line)
                else { return false }
                return !line.contains("Tokens.")
            }
            #expect(bad.isEmpty, "\(file.name) names a color: \(bad.joined(separator: " | "))")
        }
    }

    /// `.white` the color, and not `.whitespaces` or `histogram.white`. The
    /// next character must not continue an identifier, and the one before the
    /// dot must not be part of one — a color literal follows a space, a bracket
    /// or a colon, never a property it is being read from.
    private static func mentions(_ needle: String, in line: String) -> Bool {
        var from = line.startIndex
        while let found = line.range(of: needle, range: from..<line.endIndex) {
            from = found.upperBound
            if found.upperBound < line.endIndex {
                let next = line[found.upperBound]
                if next.isLetter || next.isNumber || next == "_" { continue }
            }
            if found.lowerBound > line.startIndex {
                let previous = line[line.index(before: found.lowerBound)]
                if previous.isLetter || previous.isNumber || previous == "_" { continue }
            }
            return true
        }
        return false
    }

    /// Every margin, padding, gap and fixed size comes off the scale.
    /// D-192. The suite watched for a font, a color and a measurement in a
    /// view, and not for an opacity — so `text.tertiary.opacity(0.4)` sat in
    /// two files as the disabled ink with nothing in the design document saying what
    /// disabled looks like, and nothing to stop a third view picking 0.35.
    ///
    /// A *state* opacity is fine and is most of what a view writes: `hovering
    /// ? 1 : 0` is a view saying whether something is there. What is not fine
    /// is a value in between, which is a color decision.
    @Test func noViewInventsAnOpacityBetweenOnAndOff() {
        var bad: [String] = []
        for file in Self.swiftFiles(under: "Sift/Views") {
            for (i, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init).enumerated() {
                var rest = Substring(line)
                while let mark = rest.range(of: ".opacity(") {
                    let argument = rest[mark.upperBound...].prefix { $0.isNumber || $0 == "." }
                    rest = rest[mark.upperBound...]
                    guard let value = Double(argument), value > 0, value < 1 else { continue }
                    bad.append("\(file.name):\(i + 1) draws at \(value)")
                }
            }
        }
        #expect(bad.isEmpty, "an opacity that is neither on nor off, and is not a token: \(bad.joined(separator: " | "))")
    }

    /// A `View` with any view-building member other than `body` is `@MainActor`.
    ///
    /// This was D-194's answer to the breadcrumb crash and it was the wrong
    /// one: the isolation it adds is already inferred from `View` itself, so
    /// the annotation changed nothing and the app went on crashing (D-195).
    /// It stays because saying the isolation out loud is still worth doing —
    /// it is what makes `nonisolated` a deliberate word rather than a default.
    /// The rule that actually holds the crash shut is
    /// `noViewBuildingClosureOutlivesTheBodyThatMadeIt`, below.
    ///
    /// The scan used to stop reading a type at its first nested declaration,
    /// which is why it passed while `Breadcrumb` — whose `Segment` struct sits
    /// above `row(_:keep:)` — was not annotated at all. A nested type no
    /// longer closes the one around it.
    @Test func everyViewThatBuildsContentOutsideBodyIsOnTheMainActor() {
        var bad: [String] = []
        for file in Self.swiftFiles(under: "Sift/Views") {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var owner: String?
            var isolated = false
            // A declaration at the same indentation as the one that opened the
            // type closes it. Reading any nested declaration as the end is what
            // hid `Breadcrumb` from this scan for a whole session: its `Segment`
            // struct sits between the type and the member that crashed.
            var ownerIndent = 0
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let indent = line.prefix { $0 == " " }.count
                if let name = Self.viewStructName(trimmed) {
                    owner = name
                    ownerIndent = indent
                    isolated = trimmed.contains("@MainActor")
                        || (i > 0 && lines[i - 1].contains("@MainActor"))
                    continue
                }
                if owner != nil, indent <= ownerIndent,
                   ["extension ", "struct ", "enum ", "final class ", "class "]
                    .contains(where: { trimmed.hasPrefix($0) || trimmed.hasPrefix("private " + $0)
                                       || trimmed.hasPrefix("@MainActor ") }) {
                    owner = nil
                }
                guard let type = owner, !isolated, trimmed.contains("some View"),
                      let member = Self.viewBuildingMemberName(trimmed), member != "body"
                else { continue }
                bad.append("\(file.name):\(i + 1) \(type).\(member)")
            }
        }
        #expect(bad.isEmpty, "a view is assembled off `body` on a type that is not @MainActor: \(bad.joined(separator: " | "))")
    }

    /// `struct Foo: View` / `struct Foo: Equatable, View`, and not a `ViewModifier`.
    static func viewStructName(_ line: String) -> String? {
        for prefix in ["struct ", "private struct ", "fileprivate struct ", "public struct "]
        where line.hasPrefix(prefix) {
            let rest = line.dropFirst(prefix.count)
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            let conformances = rest[rest.index(after: colon)...]
            guard conformances.contains("View"), !conformances.contains("ViewModifier") else { return nil }
            return String(rest[rest.startIndex..<colon])
                .prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                .description
        }
        return nil
    }

    /// `func label(…) -> some View` or `var panel: some View`.
    static func viewBuildingMemberName(_ line: String) -> String? {
        var rest = Substring(line)
        for prefix in ["private ", "fileprivate ", "public ", "@ViewBuilder "] where rest.hasPrefix(prefix) {
            rest = rest.dropFirst(prefix.count)
        }
        for keyword in ["func ", "var "] where rest.hasPrefix(keyword) {
            return String(rest.dropFirst(keyword.count).prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        }
        return nil
    }

    /// D-195. The crash D-194 named and did not fix.
    ///
    /// SwiftUI renders from `com.apple.SwiftUI.DisplayLink` as well as from the
    /// main thread — `NSHostingView.startAsyncRendering` — and a `ForEach`
    /// hands it a content closure to call whenever it rebuilds the list. The
    /// closure is main-actor isolated, because `View` is, so the executor check
    /// in its prologue trips and the process is gone. Five crash reports, one
    /// stack, every one of them inside the closure in `Breadcrumb.row`.
    ///
    /// A `ViewThatFits` is what turns the exposure into a crash: it rebuilds
    /// every candidate's list during measurement, so a `ForEach` under one is
    /// re-materialized on whatever thread the render is on, over and over.
    /// Those are the ones that have to be written out as slots instead.
    ///
    /// *Trade-off accepted:* slots need a ceiling, and a list that outgrows it
    /// loses its tail silently. Each one is pinned by a test that counts
    /// (`theChipRowHasASlotForEveryChip`, `theCrumbRowHasASlotForEveryCrumb`).
    @Test func noViewBuildingClosureOutlivesTheBodyThatMadeIt() {
        var bad: [String] = []
        var laddered: Set<String> = []
        for file in Self.swiftFiles(under: "Sift/Views") where file.text.contains("ViewThatFits(") {
            laddered.insert(file.name)
        }
        // A file that grew a ladder and was never added to the list below would
        // be checked by nothing, so the list is checked against the files.
        let unlisted = laddered.subtracting(Self.underALadder)
        #expect(unlisted.isEmpty, """
            a `ViewThatFits` appeared in a file the D-195 scan does not read. Add it \
            to `underALadder` and take the `ForEach`es out of it: \
            \(unlisted.sorted().joined(separator: " | "))
            """)

        for file in Self.swiftFiles(under: "Sift/Views") where Self.underALadder.contains(file.name) {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var inContextMenu: Int?
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let indent = line.prefix { $0 == " " }.count
                if let open = inContextMenu, indent <= open, !trimmed.isEmpty { inContextMenu = nil }
                // A context menu's content is built by AppKit when the menu
                // opens, in its own hosting context. The ladder never measures
                // it, so its list is never rebuilt during a layout pass.
                if trimmed.contains(".contextMenu") { inContextMenu = indent }
                guard inContextMenu == nil, trimmed.contains("ForEach("),
                      !trimmed.hasPrefix("//") else { continue }
                bad.append("\(file.name):\(i + 1)")
            }
        }
        #expect(bad.isEmpty, """
            a `ForEach` sits in a view a `ViewThatFits` measures, so SwiftUI will \
            rebuild its content during layout — and layout runs on the display \
            link as well as the main thread, where a main-actor closure kills the \
            process (D-195). Write the row out as slots: \(bad.joined(separator: " | "))
            """)
    }

    /// The files whose views a `ViewThatFits` measures: the preview bar, which
    /// still has a ladder, and the breadcrumb, which keeps its own — the path
    /// gives up crumbs rather than running off the edge of its toolbar item.
    ///
    /// `Chips.swift` came off this list with the header (D-208). The chips are
    /// a band under the toolbar now and nothing measures them, but the row is
    /// still written out as slots: a `ForEach` that was safe here once is a
    /// trap for whoever puts the chips back under something that measures.
    static let underALadder: Set<String> = ["Breadcrumb.swift", "PreviewBar.swift", "Chips.swift"]

    @Test func noViewMeasuresInBarePixels() {
        let measuring = [".padding(", ".frame(", ".offset(", "spacing:", "cornerRadius:", "lineWidth:"]
        for file in Self.swiftFiles(under: "Sift/Views") {
            let bad = Self.offendingLines(file.text) { line in
                guard measuring.contains(where: line.contains) else { return false }
                guard !line.contains("Tokens.") else { return false }
                // 0, 1 and 2 are a hairline, a fraction or a count, not a
                // measurement off the scale. Anything larger is a literal.
                return Self.numbers(in: line).contains { $0 > 2 }
            }
            #expect(bad.isEmpty, "\(file.name) measures in pixels: \(bad.joined(separator: " | "))")
        }
    }

    /// Whole numbers appearing in a line, ignoring anything inside a comment.
    private static func numbers(in line: String) -> [Int] {
        let code = line.components(separatedBy: "//").first ?? line
        return code.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    // MARK: - The design document, and the part of it that ships

    /// The design document is local-only (D-168), so these two tests used
    /// to fail on any clone rather than skip: the contract the suite exists to
    /// hold was unenforceable for everyone except the author, which is the
    /// state a contract is least useful in.
    ///
    /// What the tests actually need is not the document, it is the set of names
    /// the document declares — every identifier inside an inline-code span.
    /// That set is 258 words with no prose in it, so it ships as a fixture and
    /// the reasoning stays private. On this machine the fixture is checked
    /// against the document on every run, so it cannot go stale silently; on a
    /// clone the fixture is the contract.
    private static let namesFixture = "Tests/SiftTests/Fixtures/design-names.txt"

    /// Identifiers inside inline-code spans, sorted and deduplicated. Splitting
    /// a line on the backtick puts the spans at the odd indices, which also
    /// drops fenced blocks: a bare ``` fence has no text between its ticks.
    private static func names(inDesignDocument text: String) -> [String] {
        var found: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            for (i, span) in line.split(separator: "`", omittingEmptySubsequences: false).enumerated()
            where i % 2 == 1 {
                var word = ""
                for character in span {
                    if character.isLetter || character.isNumber || character == "_" {
                        word.append(character)
                    } else {
                        if !word.isEmpty { found.insert(word) }
                        word = ""
                    }
                }
                if !word.isEmpty { found.insert(word) }
            }
        }
        return found.sorted()
    }

    /// The names the document declares, from the document when it is here and
    /// from the fixture when it is not.
    private static func declaredNames() throws -> Set<String> {
        let fixture = root.appendingPathComponent(namesFixture)
        let lines = try String(contentsOf: fixture, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        return Set(lines)
    }

    private static var designDocument: String? {
        try? String(contentsOf: root.appendingPathComponent("DESIGN.md"), encoding: .utf8)
    }

    /// The fixture is generated, so the only thing that makes it trustworthy is
    /// failing when it no longer matches what generated it. Refresh it with
    /// `make design-names` after editing the design document.
    @Test func theNameFixtureMatchesTheDesignDocument() throws {
        guard let design = Self.designDocument else { return }   // a clone: the fixture is the contract
        let current = Self.names(inDesignDocument: design)
        let fixture = Self.root.appendingPathComponent(Self.namesFixture)

        if ProcessInfo.processInfo.environment["SIFT_REFRESH_DESIGN_NAMES"] != nil {
            try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try (current.joined(separator: "\n") + "\n").write(to: fixture, atomically: true, encoding: .utf8)
            return
        }

        let stored = try Self.declaredNames()
        let added = current.filter { !stored.contains($0) }
        let gone = stored.subtracting(current).sorted()
        #expect(added.isEmpty && gone.isEmpty, """
            \(Self.namesFixture) is stale — run `make design-names`.
            in the design document but not the fixture: \(added.joined(separator: ", "))
            in the fixture but not the design document: \(gone.joined(separator: ", "))
            """)
    }

    /// Both halves of the contract, checked against each other: a token nobody
    /// wrote down is a value that can drift without anyone noticing.
    @Test func everyTokenIsInTheDesignDocument() throws {
        let declared = try Self.declaredNames()
        let tokens = try String(contentsOf: Self.root.appendingPathComponent("Sift/Design/Tokens.swift"),
                                encoding: .utf8)
        var missing: [String] = []
        for raw in tokens.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("static let ") || line.hasPrefix("static func ")
                    || line.hasPrefix("static var ") else { continue }
            let rest = line.drop(while: { $0 != " " }).dropFirst()      // let / func / var
            let after = rest.drop(while: { $0 != " " }).dropFirst()     // the name
            let name = String(after.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            guard !name.isEmpty else { continue }
            // The document names a token by its own name or by its design name
            // ("bg.canvas" for `Surface.canvas`), and both are identifiers in
            // the same span, so the component is the check. It used to be a
            // substring of the whole file, which let `Motion.reduce` pass on
            // the word "reduced" in a sentence about something else.
            if !declared.contains(name) { missing.append(name) }
        }
        #expect(missing.isEmpty, "not in \(Self.namesFixture): \(missing.joined(separator: ", "))")
    }

    @Test func everyTextRoleIsInTheDesignDocument() throws {
        let declared = try Self.declaredNames()
        // The missing ones, not the set: `#expect` expands what it is given,
        // and `declared.contains(x)` printed all 279 names on a one-role miss.
        let missing = TextRole.allCases.map(\.rawValue).filter { !declared.contains($0) }
        #expect(missing.isEmpty, "not in \(Self.namesFixture): \(missing.joined(separator: ", "))")
    }

    /// Every button says it is one before it is pressed (D-137). The rule was
    /// written as a decision and nothing held it, so twenty-one plain buttons
    /// were still handing the arrow cursor a session later — a control that
    /// looks like a label until you click it is a control most people never
    /// click. `.buttonStyle(.plain)` strips AppKit's own affordance, so it is
    /// exactly the line that has to pay the cursor back (D-140).
    @Test func everyPlainButtonTakesThePointingHand() {
        for file in Self.swiftFiles(under: "Sift/Views") {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (i, line) in lines.enumerated() where line.contains(".buttonStyle(.plain)") {
                if line.contains(Self.marker) { continue }
                // The modifier chain around it, not the whole file: a
                // `.pointerStyle` on some other button in the same view is not
                // this button's affordance.
                let near = lines[max(0, i - 14)..<min(lines.count, i + 14)].joined(separator: "\n")
                #expect(near.contains(".pointerStyle("),
                        "\(file.name):\(i + 1) is a plain button with no pointing hand")
            }
        }
    }

    /// 14 is the floor, and `caption` is the one break in it (D-139). The rule
    /// is not "no small text"; it is that going under the floor is a decision
    /// somebody made once, for text that is recognized rather than read, and
    /// that adding a second one is not something a font token can do quietly.
    @Test func captionIsTheOnlyTextUnderTheReadabilityFloor() throws {
        let tokens = try String(contentsOf: Self.root.appendingPathComponent("Sift/Design/Tokens.swift"),
                                encoding: .utf8)
        guard let fonts = tokens.range(of: "enum Font {"),
              let end = tokens.range(of: "\n    }", range: fonts.upperBound..<tokens.endIndex)
        else { Issue.record("no Font block in Tokens.swift"); return }
        var small: [String] = []
        for raw in tokens[fonts.upperBound..<end.lowerBound].split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("static let "), let mark = line.range(of: "size: ") else { continue }
            let size = Int(line[mark.upperBound...].prefix { $0.isNumber }) ?? 0
            guard size > 0, size < 14 else { continue }
            small.append(String(line.dropFirst("static let ".count).prefix { $0.isLetter }))
        }
        #expect(small == ["caption"], "under the 14pt floor: \(small.joined(separator: ", "))")
    }

    @Test func everySpacingTokenIsOnTheFourPixelScale() {
        for value in [Tokens.Space.s4, Tokens.Space.s8, Tokens.Space.s12, Tokens.Space.s16,
                      Tokens.Space.s24, Tokens.Space.s32, Tokens.Space.s48, Tokens.Space.s64] {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0, "\(value) is off the scale")
        }
    }

    // MARK: - The three scales (D-177)

    /// Every measurement token is a multiple of 4, except the handful that are
    /// line weights and mark geometry rather than measurements. The exceptions
    /// are listed by name: a new one is a decision, not a number that slipped
    /// past a modulo.
    @Test func everyLayoutTokenIsOnTheFourPixelScaleOrIsANamedException() throws {
        let exceptions: Set<String> = [
            "glyph", "glyphTile",
            "favoriteMarkRatio", "favoriteMarkSmall",
            // A ratio between two copies of one mark, not a measurement: the
            // rim around the empty heart is 7% of it, so the keyline scales
            // with the mark instead of being a flat number at every size
            // (D-200). The two stroke widths it replaces were on this list.
            "favoriteKeylineScale",
        ]
        var off: [String] = []
        // Only `Layout`: a border's line width and a line-height multiplier are
        // their own kinds of number and were never on this scale.
        for line in try Self.layoutSection().split(separator: "\n").map(String.init) {
            guard let name = Self.tokenName(in: line), let value = Self.tokenValue(in: line) else { continue }
            guard !exceptions.contains(name) else { continue }
            // Pixel counts for a decode are not a layout measurement.
            guard !name.hasSuffix("Pixels") else { continue }
            if value.truncatingRemainder(dividingBy: 4) != 0 { off.append("\(name) = \(value)") }
        }
        #expect(off.isEmpty, "off the 4pt scale and not a named exception: \(off.joined(separator: ", "))")
    }

    /// A glyph is drawn at one of three sizes. A fourth arrives one call site
    /// at a time, and the one that did arrive was a *box* token passed as a
    /// size, which is how a folder ended up 8pt larger than every icon beside
    /// it with nothing saying so.
    @Test func everyGlyphIsDrawnAtOneOfTheThreeSteps() throws {
        let allowed = Set(["glyph", "glyphAction", "glyphTile", "glyphSize", "size"])
        var bad: [String] = []
        for file in Self.swiftFiles(under: "Sift/Views") + Self.swiftFiles(under: "Sift/Design") {
            for (i, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init).enumerated() where line.contains("Glyph.draw(") {
                guard let mark = line.range(of: "size: ") else { continue }
                let argument = String(line[mark.upperBound...]).prefix { $0.isLetter || $0 == "." }
                let leaf = argument.split(separator: ".").last.map(String.init) ?? ""
                if !allowed.contains(leaf) { bad.append("\(file.name):\(i + 1) draws at \(argument)") }
            }
        }
        #expect(bad.isEmpty, "\(bad.joined(separator: " | "))")
        #expect(Tokens.Layout.glyphSteps.count == 3, "the scale is three steps")
        #expect(Set(Tokens.Layout.glyphSteps).count == 3, "and three different ones")
    }

    /// Nothing outside `Glyph` decides whether a shape is stroked or filled:
    /// solidity is the shape's own, and `on` is the control's state. The two
    /// used to be one `filled:` flag, which is how a solid MoveToFolder read
    /// as a pressed button.
    @Test func nothingOutsideGlyphChoosesStrokeOrFill() {
        for file in Self.swiftFiles(under: "Sift/Views") {
            let bad = Self.offendingLines(file.text) {
                $0.contains("Glyph.stroked(") || $0.contains("Glyph.filled(")
            }
            #expect(bad.isEmpty, "\(file.name) draws a glyph around `Glyph.draw`: \(bad.joined(separator: " | "))")
        }
    }

    /// A sheet is one of three widths. It was five, for one idea.
    @Test func everySheetIsOneOfTheThreeWidths() {
        let steps = Set(Tokens.Layout.sheetSteps)
        let sheets: [(String, CGFloat)] = [
            ("peekPanel", Tokens.Layout.peekPanel), ("pathField", Tokens.Layout.pathField),
            ("jumpSheet", Tokens.Layout.jumpSheet), ("listSheet", Tokens.Layout.listSheet),
            ("settingsWidth", Tokens.Layout.settingsWidth), ("palette", Tokens.Layout.palette),
            ("ingestSheet", Tokens.Layout.ingestSheet), ("reviewSheet", Tokens.Layout.reviewSheet),
        ]
        let off = sheets.filter { !steps.contains($0.1) }.map { "\($0.0) = \($0.1)" }
        #expect(off.isEmpty, "off the sheet scale: \(off.joined(separator: ", "))")
        #expect(Tokens.Layout.palette > Tokens.Layout.jumpSheet,
                "the palette carries a command, its group and its keys, so it stays the wider one")
    }

    /// The body of `enum Layout`, which is where a measurement lives.
    private static func layoutSection() throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("Sift/Design/Tokens.swift"),
                              encoding: .utf8)
        guard let start = text.range(of: "enum Layout {") else { return "" }
        return String(text[start.upperBound...])
    }

    private static func tokenName(in line: String) -> String? {
        guard let mark = line.range(of: "static let ") else { return nil }
        let name = String(line[mark.upperBound...]).prefix { $0.isLetter || $0.isNumber }
        return name.isEmpty ? nil : String(name)
    }

    /// The number a token is declared as, and nothing else: a token defined in
    /// terms of another (`folderTile = gridCell`) is that one's problem.
    private static func tokenValue(in line: String) -> CGFloat? {
        guard let equals = line.range(of: ": CGFloat = ") else { return nil }
        let text = String(line[equals.upperBound...]).prefix { $0.isNumber || $0 == "." }
        return Double(text).map { CGFloat($0) }
    }
}
