import Testing
import Foundation
@testable import Sift

/// Words the app does not say (D-204), and the spellings it does not use
/// (D-231).
///
/// "Cull" is the one the trade uses and most people have never met; the ones
/// who have know it from livestock. It was the app's own word for its own
/// subject, which is exactly how a piece of jargon gets into a button label
/// without anybody choosing it — the documents are full of it, the commit
/// messages are full of it, and the shortcuts overlay had a column headed
/// "Cull" for three weeks.
///
/// The documents keep it. This is about what a reader sees, so it reads string
/// literals only: a comment, a type name and a test name are all fine.
@Suite struct WordTests {
    /// Every double-quoted run in a file, with the comments and the code left
    /// out. Crude on purpose — a false positive here is a line to look at, and
    /// there is no cost to looking.
    private func literals(in text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//"),
                  !line.trimmingCharacters(in: .whitespaces).hasPrefix("///") else { continue }
            var inside = false, current = "", escaped = false
            for c in line {
                if escaped { escaped = false; if inside { current.append(c) }; continue }
                if c == "\\" { escaped = true; continue }
                if c == "\"" {
                    if inside { out.append(current); current = "" }
                    inside.toggle()
                    continue
                }
                if inside { current.append(c) }
            }
        }
        return out
    }

    private func swiftFiles() throws -> [(name: String, text: String)] {
        let root = Repo.at("Sift")
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try found.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test func nothingTheAppSaysUsesTheWordCull() throws {
        var offenders: [String] = []
        for file in try swiftFiles() {
            for literal in literals(in: file.text) where literal.lowercased().contains("cull") {
                offenders.append("\(file.name): \"\(literal)\"")
            }
        }
        #expect(offenders.isEmpty, """
            the app says "cull" to somebody: \(offenders.joined(separator: " | "))
            It is the trade's word, not the reader's. Decide, keep, reject, sort through.
            """)
    }

    /// "Header" is the second one, and it went stale rather than being jargon.
    ///
    /// The app drew its own header for most of its life and the shortcuts
    /// overlay told the reader so: "every command has a control on screen: the
    /// bar in the header". D-208 replaced it with a real `NSToolbar` and the
    /// sentence stayed, pointing at a thing that is not on screen any more.
    /// The generated half of that overlay cannot go stale — it is built from
    /// `Command.allCases` — and the prose around it has nothing holding it, so
    /// this is what holds it (D-216).
    ///
    /// The type names are not affected: this reads string literals only, and
    /// `HeaderChips` and `HeaderIcon` are what the code calls them.
    @Test func nothingTheAppSaysCallsTheToolbarAHeader() throws {
        var offenders: [String] = []
        for file in try swiftFiles() {
            for literal in literals(in: file.text) where literal.lowercased().contains("header") {
                offenders.append("\(file.name): \"\(literal)\"")
            }
        }
        #expect(offenders.isEmpty, """
            the app says "header" to somebody: \(offenders.joined(separator: " | "))
            There is no header any more — it is the toolbar (D-208).
            """)
    }

    // MARK: American English (D-231)

    /// Every British spelling this repository has ever had to take back out,
    /// as a stem and the American form that replaces it.
    ///
    /// Not a dictionary and not trying to be. A word earns a line here by
    /// having been written into this app once, which is why `colour` is the
    /// first of them: the adjust panel shipped a group named `Colour`.
    static let british: [(brit: String, amer: String)] = [
        ("colour", "color"), ("behaviour", "behavior"), ("neighbour", "neighbor"),
        ("favourite", "favorite"), ("grey", "gray"), ("centre", "center"),
        ("labelled", "labeled"), ("modelling", "modeling"), ("travelling", "traveling"),
        ("initialise", "initialize"), ("organise", "organize"), ("recognise", "recognize"),
        ("normalise", "normalize"), ("customise", "customize"), ("summarise", "summarize"),
        ("minimise", "minimize"), ("maximise", "maximize"), ("prioritise", "prioritize"),
        ("utilise", "utilize"), ("analyse", "analyze"), ("apologise", "apologize"),
        ("licence", "license"), ("defence", "defense"), ("offence", "offense"),
        ("catalogue", "catalog"), ("dialogue", "dialog"), ("programme", "program"),
        ("towards", "toward"), ("whilst", "while"), ("amongst", "among"),
        ("metre", "meter"), ("litre", "liter"), ("storey", "story"),
        ("mould", "mold"), ("draught", "draft"), ("sceptic", "skeptic"),
    ]

    /// American English, in the strings *and* in the comments (D-231).
    ///
    /// The other two tests in this suite read string literals only, on the
    /// stated ground that they are about what a reader sees. This one is not:
    /// the comments in this repository are prose somebody reads every day, and
    /// a spelling that drifts in one of them is a spelling that gets copied
    /// into the next label. `Colour` reached a panel heading by being written
    /// in the comment above it first.
    ///
    /// The stems match with a word boundary at the front, so `-ise` verbs catch
    /// their own `-ised`, `-ising` and `-isation` without each needing a line.
    ///
    /// **`cancelled` is deliberately not on the list.** Swift spells it
    /// `Task.isCancelled` and the app has enum cases named to match, so a ban
    /// would be a ban with more exceptions than uses. It is the one place this
    /// rule gives way to the platform, and it gives way on purpose rather than
    /// by being forgotten.
    @Test func nothingInTheAppIsSpelledTheBritishWay() throws {
        var offenders: [String] = []
        for file in try allSwiftFiles() where file.name != "WordTests.swift" {
            for (number, raw) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Lowercased once and checked with a plain `contains` before
                // any regex runs. Thirty-six patterns against every line of the
                // repository took eight seconds; this takes none of it, and a
                // suite people wait for is a suite people stop running.
                let line = String(raw)
                let lowered = line.lowercased()
                for (brit, amer) in Self.british
                where lowered.contains(brit) && Self.startsAWord(brit, in: line, lowered: lowered) {
                    offenders.append("\(file.name):\(number + 1) \"\(brit)\" — write \"\(amer)\"")
                }
            }
        }
        #expect(offenders.isEmpty, """
            British spelling in the source: \(offenders.joined(separator: " | "))
            This project is written in American English, labels and comments alike (D-231).
            """)
    }

    /// Where a stem counts as starting a word. Two ways in: the character
    /// before it is not a letter or a digit, or the stem itself is capitalised
    /// where it sits, which is the camel-cased half of a name — `adjustColour`
    /// has to be caught, and `parameter` must not be.
    ///
    /// The lowercased copy is passed in rather than made here, because the
    /// caller has already made it to do the cheap `contains` that decides
    /// whether this runs at all.
    static func startsAWord(_ stem: String, in line: String, lowered: String) -> Bool {
        var from = lowered.startIndex
        while let found = lowered.range(of: stem, range: from..<lowered.endIndex) {
            if found.lowerBound == lowered.startIndex { return true }
            let before = lowered[lowered.index(before: found.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            if line[found.lowerBound].isUppercase { return true }
            from = lowered.index(after: found.lowerBound)
        }
        return false
    }

    /// The matcher's own cases, because a spelling check that silently matches
    /// nothing passes forever. Both halves: what it has to catch, and the
    /// substring it must not fire on.
    @Test func theSpellingMatcherCatchesWordsAndNotSubstrings() {
        func hit(_ stem: String, _ line: String) -> Bool {
            WordTests.startsAWord(stem, in: line, lowered: line.lowercased())
        }
        #expect(hit("colour", "case colour = \"Colour\""))
        #expect(hit("colour", "Colour, everywhere at once"))
        #expect(hit("colour", "let adjustColour = 1"), "a camel-cased name is a word start")
        #expect(hit("grey", "came out mid-grey over a bright frame"))
        #expect(hit("metre", "a metre of it"))
        #expect(!hit("metre", "the parameter it takes"), "parameter is not a British metre")
        #expect(!hit("colour", "discolouration"), "not a word start, and not a word this app writes")
        // And the list is live: every stem has to differ from what replaces it.
        #expect(WordTests.british.allSatisfy { $0.brit != $0.amer })
        #expect(!WordTests.british.isEmpty)
    }

    /// Both trees, because the rule is about how this repository is written and
    /// not only about what ships. `swiftFiles()` is the app alone, which is
    /// what the two literal-reading tests above want.
    private func allSwiftFiles() throws -> [(name: String, text: String)] {
        return try ["Sift", "Tests"].flatMap { folder -> [(name: String, text: String)] in
            let dir = Repo.at(folder)
            let found = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            return try found.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        }
    }

    /// The group the word used to head, so the rename is a fact rather than a
    /// coincidence of nobody having typed it lately.
    @Test func theDecideGroupIsNamedForWhatItDoes() {
        #expect(Command.groups.contains("Decide"))
        #expect(!Command.groups.contains("Cull"))
        #expect(Command.flagKeep.group == "Decide")
        #expect(Command.toggleFavorite.group == "Decide")
    }

    /// Every file `git` tracks that a person would read, which is the set that
    /// goes public and nothing else. The walk asks `git` rather than the
    /// filesystem on purpose: the author's own documents sit beside these,
    /// they are ignored, and they are full of the words below.
    private func trackedTextFiles() throws -> [(name: String, text: String)] {
        let root = Repo.root
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", root.path, "ls-files", "-z"]
        let pipe = Pipe()
        git.standardOutput = pipe
        git.standardError = FileHandle.nullDevice
        try git.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        let listed = String(decoding: out, as: UTF8.self)
            .split(separator: "\0").map(String.init)
        let readable: Set<String> = [
            "swift", "md", "yml", "yaml", "sh", "plist", "json", "txt", "svg", "resolved",
        ]
        return listed
            .filter { readable.contains(($0 as NSString).pathExtension) }
            .compactMap { path in
                let url = root.appendingPathComponent(path)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return (path, text)
            }
    }

    /// The tools that wrote this are not part of what it says.
    ///
    /// A trailer on a commit and one sentence in a test comment were the two
    /// that got through, and neither was noticed until somebody read the whole
    /// repository an hour before it went public. Both were written months
    /// apart by the ordinary act of explaining where a rule lived. This is the
    /// same argument as the spelling test above: a preference nobody can grep
    /// is a preference that holds until the day it doesn't.
    ///
    /// Commit messages are the other half and this cannot see them. They are
    /// the client's setting to make, once, for every repository at the same
    /// time.
    @Test func nothingPublicNamesTheToolsThatWroteIt() throws {
        let named = ["claude", "anthropic", "co-authored", "copilot", "chatgpt", "openai"]
        var offenders: [String] = []
        for file in try trackedTextFiles() where !file.name.hasSuffix("WordTests.swift") {
            for (number, raw) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let lowered = String(raw).lowercased()
                for word in named where lowered.contains(word) {
                    offenders.append("\(file.name):\(number + 1) \"\(word)\"")
                }
            }
        }
        #expect(offenders.isEmpty, """
            The repository names a tool that wrote it: \(offenders.joined(separator: " | "))
            This one is public. Say what the code does, not what typed it (D-305).
            """)
    }

    /// The walk finds the repository at all, so a `git` that failed silently
    /// reads as a pass rather than as nothing to check.
    @Test func theTrackedWalkSeesTheRepository() throws {
        let files = try trackedTextFiles()
        #expect(files.count > 50, "expected the tracked tree, found \(files.count) files")
        #expect(files.contains { $0.name == "README.md" })
    }
}
