import Testing
import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Sift

/// The two claims SECURITY.md rests on, held by the suite instead of by a
/// reader (D-302).
///
/// Both were true before this file existed, and both had been verified by hand
/// in five security passes: there is no network code, and `SIFT_SCRIPT` does
/// not reach the download. Neither was verified by anything that runs.
/// `swift test` passed with a `URLSession` in `Sift/`, and it passed with the
/// `#if !DEBUG` deleted. `BundleTests.theBundleDoesNotRelaxTransportSecurity`
/// was the closest thing and it reads the `Info.plist`: an update checker over
/// ordinary HTTPS would never have touched it.
///
/// That was fine while one person wrote every line. `CONTRIBUTING.md` names
/// `make test` as the gate a pull request passes, and a repository that takes
/// pull requests is one where a rule kept in a document is a rule the tenth
/// contribution breaks quietly. So the rule moves to where the rule changes.
///
/// It found something on its first run. D-300 took the scripted *replay* out of
/// release builds and left `KeyMonitor`'s keystroke swallow reading the same
/// variable ungated, so a release build launched with `SIFT_SCRIPT` set to
/// anything came up with a live window and a dead keyboard. Five readings of
/// the same code missed it. That is the argument for this file in one line.
///
/// Both tests read the source rather than the binary. The binary is the better
/// evidence: the release build links no CFNetwork and carries none of the
/// pacing variables. But it costs a release build to produce and CI builds
/// debug, so what runs on every push reads the source instead. It can be wrong
/// in one direction only. `releaseLines` keeps anything it cannot parse, so the
/// failure mode is a false positive, which is a line to go and look at.
@Suite struct SecurityClaimTests {

    // MARK: what a release build compiles

    /// One line of source that survives into a release build.
    private struct Line {
        let number: Int
        let code: String
        /// Whether it sits inside an explicit `#if !DEBUG`, which is a line
        /// somebody wrote *for* the release build rather than one that merely
        /// ended up in it.
        let releaseOnly: Bool
    }

    /// The lines of a file a release build compiles, comments left out.
    ///
    /// A `#if DEBUG` region is dropped and a `#if !DEBUG` region is kept and
    /// marked. That distinction is the whole point: a gate that keeps code out
    /// of the download is stronger than a runtime check that leaves it there to
    /// be patched back in, and a test that could not see the difference would
    /// have nothing to say about it.
    ///
    /// Any other `#if`, whether `os`, `arch`, `canImport` or `swift`, keeps
    /// both branches. Strictly that is wrong, and here it is right: not knowing
    /// which branch ships means reporting both, and over-reporting costs
    /// somebody a look at a line.
    private func releaseLines(of text: String) -> [Line] {
        enum Region { case debugOnly, releaseOnly, either }
        var stack: [Region] = []
        var out: [Line] = []

        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let bare = line.trimmingCharacters(in: .whitespaces)

            if bare.hasPrefix("#if") {
                let condition = bare.dropFirst(3).trimmingCharacters(in: .whitespaces)
                stack.append(condition == "DEBUG" ? .debugOnly
                             : condition == "!DEBUG" ? .releaseOnly : .either)
                continue
            }
            if bare.hasPrefix("#elseif") {
                // The other half of something this does not evaluate. Keep it.
                if !stack.isEmpty { stack[stack.count - 1] = .either }
                continue
            }
            if bare.hasPrefix("#else") {
                if let top = stack.last {
                    stack[stack.count - 1] = top == .debugOnly ? .releaseOnly
                        : top == .releaseOnly ? .debugOnly : .either
                }
                continue
            }
            if bare.hasPrefix("#endif") {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }

            guard !stack.contains(.debugOnly) else { continue }
            guard !bare.hasPrefix("//") else { continue }
            out.append(Line(number: offset + 1, code: line,
                            releaseOnly: stack.contains(.releaseOnly)))
        }
        return out
    }

    /// The same, for a debug build. Only the positive control uses it: a test
    /// reporting nothing in the release view has said nothing at all until
    /// something reports the debug view differently.
    private func debugLines(of text: String) -> [Line] {
        // The two differ in one condition, and swapping it in the source is
        // cheaper and less wrong than a second evaluator that can drift from
        // the first.
        releaseLines(of: text
            .replacingOccurrences(of: "#if !DEBUG", with: "\u{1}")
            .replacingOccurrences(of: "#if DEBUG", with: "#if !DEBUG")
            .replacingOccurrences(of: "\u{1}", with: "#if DEBUG"))
    }

    /// A line with its string literals taken out, so a URL that is data cannot
    /// read as a URL that is a call. `XMPSidecar` holds three XML namespace
    /// identifiers and they are not network access.
    ///
    /// A line whose quotes do not pair, such as a raw string or an escape this
    /// does not model, comes back whole rather than half eaten. More text means
    /// more reported, which is the direction to be wrong in.
    private func withoutLiterals(_ line: String) -> String {
        var out = "", inside = false, escaped = false
        for c in line {
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "\"" { inside.toggle(); continue }
            if !inside { out.append(c) }
        }
        return inside ? line : out
    }

    private func appFiles() throws -> [(name: String, text: String)] {
        let root = Repo.at("Sift")
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try found.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    // MARK: the claims

    /// SECURITY.md: "It has no network code. There is no `URLSession` in the
    /// source, no analytics, no crash reporting and no update check."
    ///
    /// The whole trust model sits downstream of that sentence. Sift holds
    /// every folder the reader has handed it, a card or a whole Pictures
    /// directory at a time, so it can already read the photographs they care
    /// most about. What makes that acceptable is that it has nowhere to send
    /// one. A single `URLSession` turns the app from a thing with the reach
    /// the reader gave it into a thing with their photographs and a socket.
    ///
    /// Framework names and their entry points, not syscalls. Somebody
    /// determined to open a socket by hand through `libSystem` is not what this
    /// catches, and nothing reading source could. The link table is the check
    /// for that: `otool -L` on the release binary reports AppKit, CoreGraphics,
    /// CoreImage, Foundation, ImageIO, SwiftUI and Vision, with no CFNetwork,
    /// Network or Security among them.
    @Test func noCodeInTheAppReachesTheNetwork() throws {
        let banned = [
            "URLSession", "URLRequest", "URLCredential", "URLProtocol",
            "NSURLConnection", "NSURLRequest", "CFURLConnection",
            "NWConnection", "NWListener", "NWBrowser", "NWPathMonitor",
            "CFSocket", "CFReadStream", "CFWriteStream", "CFHTTPMessage",
            "SCNetworkReachability", "getaddrinfo", "gethostby", "socket(",
            "WKWebView", "import Network", "import WebKit", "import CFNetwork",
            "import CloudKit", "import StoreKit", "import MultipeerConnectivity",
        ]
        var offenders: [String] = []
        for file in try appFiles() {
            for line in releaseLines(of: file.text) {
                let code = withoutLiterals(line.code)
                for token in banned where code.contains(token) {
                    offenders.append("\(file.name):\(line.number) \(token)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            the app has network code: \(offenders.joined(separator: " | "))
            SECURITY.md says it has none, and the trust model is built on that:
            a culler holding the reader's folder grants is safe because it
            has nowhere to send a photograph. Either take this out, or rewrite
            SECURITY.md to say what the app now talks to and why.
            """)
    }

    /// D-300: `SIFT_SCRIPT` is a debug-build tool and does not reach the
    /// download.
    ///
    /// Every other `SIFT_*` variable shapes a window. This one presses keys,
    /// and `trash` is one of them. TCC grants attach to Sift rather than to
    /// whatever launched it, so a shipped build honoring the variable would let
    /// a process holding none of the reader's folder grants run `open --env
    /// SIFT_SCRIPT=trash,next,trash --args ~/Desktop` and have Sift do the
    /// reading and the trashing under Sift's own consent.
    ///
    /// Two halves, because the variable means two things:
    ///
    /// **The pacing variables have to be absent.** `SIFT_SCRIPT_STEP`,
    /// `_LEAD` and `_SETUP` exist only to run a script, so a release build that
    /// reads one is a release build that can be driven. Verified against the
    /// binary too: none of the three is a string in it.
    ///
    /// **`SIFT_SCRIPT` itself may be read only inside `#if !DEBUG`.** The app
    /// has to look at the variable to say it is ignoring it, and a launch that
    /// quietly does nothing is the failure D-264 spent a session on. What is
    /// refused is a read that merely happens to be harmless, which is what
    /// `KeyMonitor` had: the line has to be one somebody wrote for the release
    /// build, in a branch that says so.
    @Test func noCodeInAReleaseBuildIsDrivenByTheScriptingVariables() throws {
        let pacing = ["SIFT_SCRIPT_STEP", "SIFT_SCRIPT_LEAD", "SIFT_SCRIPT_SETUP"]

        var pacingReads: [String] = []
        var ungatedReads: [String] = []
        var seenInDebug = false

        for file in try appFiles() {
            for line in releaseLines(of: file.text) {
                for name in pacing where line.code.contains("\"\(name)\"") {
                    pacingReads.append("\(file.name):\(line.number) \(name)")
                }
                if line.code.contains("\"SIFT_SCRIPT\""), !line.releaseOnly {
                    ungatedReads.append("\(file.name):\(line.number)")
                }
            }
            // The positive control. Without it this passes whenever
            // `releaseLines` is broken enough to return nothing, which is how a
            // green check comes to mean nothing at all.
            for line in debugLines(of: file.text) where line.code.contains("\"SIFT_SCRIPT\"") {
                seenInDebug = true
            }
        }

        #expect(seenInDebug, """
            no debug-build code reads SIFT_SCRIPT, so this test is not looking
            at anything. Either the scripting hook is gone, in which case take
            this test and D-300 with it, or `releaseLines` has stopped being
            able to tell the two builds apart.
            """)
        #expect(pacingReads.isEmpty, """
            a release build reads a script's pacing: \(pacingReads.joined(separator: " | "))
            These three variables do nothing but run a script, so a build that
            reads one can be driven. D-300 keeps them out of the download
            because a script presses keys and `trash` is among them: TCC grants
            attach to Sift, so a shipped build honoring this lets any process
            trash the reader's photographs under Sift's consent rather than
            asking for its own.
            """)
        #expect(ungatedReads.isEmpty, """
            a release build reads SIFT_SCRIPT outside `#if !DEBUG`: \(ungatedReads.joined(separator: " | "))
            A read that ships has to be one written for the release build and
            marked as such. `KeyMonitor.drivingItself` was the other kind: it
            swallowed every keystroke whenever the variable was set, in a build
            that would not script anything with it, so the app came up with a
            live window and a dead keyboard (D-278, D-302).
            """)
    }

    /// D-308: a launch variable that survives into the download may shape a
    /// window and may not act on a file.
    ///
    /// The third claim, and the one the first two left a hole under. D-300 and
    /// D-302 asked whether `SIFT_SCRIPT` ships, because a script presses keys
    /// and `trash` is one of them. Nobody asked the same question of the
    /// variable beside it. `SIFT_SHOW=confirm` favorited the photograph under
    /// the cursor and then pressed trash, to assemble the one question the app
    /// asks; a photograph that was *already* a favorite got unfavorited by
    /// that press instead, so `trashTargets` found nothing loved, skipped the
    /// sheet, and trashed the file. Observed on a release bundle, against a
    /// control that left the file alone.
    ///
    /// The fifth pass had this in its hands. It used
    /// `KeyMonitor.peekPinnedForScreenshot` — an ungated `SIFT_SHOW` read
    /// present in both builds — as the **positive control** proving the
    /// `SIFT_SCRIPT` differential could tell the two binaries apart. The
    /// control did its job. Nobody asked what the variable it was made of
    /// could do. A control is not an audit of its own subject.
    ///
    /// So the question stops being asked one name at a time. Every `SIFT_`
    /// literal that survives into a release build, outside a branch somebody
    /// wrote for the release build, has to be on the list below. The list is
    /// the point: it makes the twentieth variable a decision written down
    /// rather than a read that arrives beside nineteen others.
    ///
    /// **What earns a place.** It shapes a window, picks a palette, redirects
    /// preferences, or reports what came up. It does not route a `Command`, it
    /// does not reach `FileOps` or `MetadataIO`, and nothing downstream of it
    /// writes a byte to the reader's folder. Adding a name here is saying that
    /// out loud.
    @Test func noLaunchVariableInAReleaseBuildCanReachAFile() throws {
        /// Shapes what comes up. Writes nothing.
        let shapeTheWindow: Set<String> = [
            "SIFT_APPEARANCE",      // which palette, without storing it
            "SIFT_BAR",             // pins the preview bar up
            "SIFT_FEATURES_OFF",    // switches features off for one launch
            "SIFT_FLOAT",           // keeps the windows above ordinary ones
            "SIFT_GRID",            // thumbnail step
            "SIFT_HEIGHT",          // gallery window height
            "SIFT_HINTS",           // spends the first-time hints
            "SIFT_PREVIEW_HEIGHT",  // preview window height
            "SIFT_PREVIEW_WIDTH",   // preview window width
            "SIFT_SCRATCH_PREFS",   // a throwaway preferences domain
            "SIFT_SETTINGS_AT",     // scrolls the settings form to a section
            "SIFT_SETTINGS_TRAIL",  // opens the History row's list of stored paths
            "SIFT_WIDTH",           // gallery window width
            "SIFT_WINDOW_REPORT",   // prints what is on screen
        ]

        var ungated: [String] = []
        var found: Set<String> = []
        var seenInDebug = false

        for file in try appFiles() {
            for line in releaseLines(of: file.text) {
                // A read inside `#if !DEBUG` is one somebody wrote for the
                // download, which today is the two lines that say a debug tool
                // is being ignored. That branch is reviewed as release code;
                // an ungated read is not (D-302).
                guard !line.releaseOnly else { continue }
                for name in launchVariables(in: line.code) {
                    found.insert(name)
                    guard !shapeTheWindow.contains(name) else { continue }
                    ungated.append("\(file.name):\(line.number) \(name)")
                }
            }
            // The positive control, and it has to be the variable this test is
            // about. Without it the check passes whenever the gate folds the
            // whole mechanism away *and* whenever `releaseLines` has stopped
            // being able to tell the builds apart, which are not the same
            // thing and only one of them is good news.
            for line in debugLines(of: file.text) where launchVariables(in: line.code).contains("SIFT_SHOW") {
                seenInDebug = true
            }
        }

        #expect(seenInDebug, """
            no debug-build code reads SIFT_SHOW, so this test is not looking at
            anything. Either the screenshot mechanism is gone, in which case
            take this test and D-308 with it, or `releaseLines` has stopped
            being able to tell the two builds apart.
            """)
        #expect(ungated.isEmpty, """
            a release build reads a launch variable that is not on the list of
            ones that only shape a window: \(ungated.joined(separator: " | "))
            Either it writes nothing, in which case put it on the list with a
            comment saying so, or it reaches a `Command`, `FileOps` or
            `MetadataIO` and belongs behind `#if DEBUG`. TCC grants attach to
            Sift rather than to whatever launched it, so a variable that ships
            and writes lets a process holding none of the reader's folder
            grants have Sift do the writing under Sift's own consent (D-308).
            """)

        let stale = shapeTheWindow.subtracting(found).sorted().joined(separator: ", ")
        #expect(stale.isEmpty, """
            the list names launch variables no release build reads: \(stale)
            A name nobody reads is a name nobody re-examines, and the list is
            only worth having while every line on it is a live decision.
            """)
    }

    /// The `SIFT_` names a line mentions, as string literals rather than as
    /// prose. `setSize(width: "SIFT_WIDTH", …)` passes the name along, so the
    /// literal and not `environment[…]` is what there is to scan for.
    private func launchVariables(in line: String) -> Set<String> {
        let pattern = #""(SIFT_[A-Z_]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return Set(regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            .compactMap { Range($0.range(at: 1), in: line).map { String(line[$0]) } })
    }

    /// SECURITY.md: "The `SIFT_*` environment variables, listed in
    /// `CONTRIBUTING.md`. They open screens and redirect preferences at launch
    /// [...] say so if one of them reaches further than that."
    ///
    /// That sentence hands one file the job of naming the whole launch surface,
    /// and a reader auditing it cannot see what the list leaves out. It had left
    /// out three: `SIFT_FLOAT`, `SIFT_HINTS` and `SIFT_SETTINGS_AT`, sixteen
    /// rows against the nineteen names the code reads. None of the three reaches
    /// anywhere interesting, which is not the point. An incomplete list reads as
    /// a complete one.
    ///
    /// Both directions. A name the table has and the code does not is the same
    /// failure pointing the other way: a reader checks a variable that no longer
    /// exists and finds nothing, which is indistinguishable from checking it and
    /// finding it safe.
    ///
    /// The table's own rows, not the file. `SIFT_SHOW` and `SIFT_SCRIPT` both
    /// appear in the example commands and in the prose around them, so a test
    /// reading the whole file would pass on a table that had lost every row.
    @Test func everyLaunchVariableTheCodeReadsIsInTheContributingTable() throws {
        func names(in text: String, matching pattern: String) -> Set<String> {
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            return Set(regex?.matches(in: text, range: range).compactMap { match -> String? in
                guard let r = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[r])
            } ?? [])
        }

        var read: Set<String> = []
        for file in try appFiles() {
            read.formUnion(names(in: file.text, matching: #""(SIFT_[A-Z_]+)""#))
        }

        let rows = try Repo.text("CONTRIBUTING.md")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("| `SIFT_") }
            .joined(separator: "\n")
        let listed = names(in: rows, matching: #"`(SIFT_[A-Z_]+)`"#)

        let missing = read.subtracting(listed).sorted().joined(separator: ", ")
        let stale = listed.subtracting(read).sorted().joined(separator: ", ")

        #expect(read.count > 10, """
            the scan found \(read.count) launch variables in the app, which is
            too few to be reading anything. Check the pattern before trusting
            either expectation below.
            """)
        #expect(missing.isEmpty, """
            the code reads launch variables CONTRIBUTING.md does not list: \(missing)
            SECURITY.md sends anybody auditing the launch surface to that table,
            and a list three names short reads exactly like a complete one.
            """)
        #expect(stale.isEmpty, """
            CONTRIBUTING.md lists launch variables the code does not read: \(stale)
            A reader who goes and checks one of these finds nothing, which looks
            the same as checking it and finding it safe.
            """)
    }

    // MARK: what the README promises about a photograph leaving

    private struct Coordinates { let latitude: Double; let longitude: Double }

    /// The coordinates on a pasteboard's JPEG, read out of the bytes that are
    /// on it rather than out of the file they came from.
    @MainActor
    private func gpsOnPasteboard(_ board: NSPasteboard) -> Coordinates? {
        guard let data = board.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
        return Coordinates(latitude: south ? -latitude : latitude,
                           longitude: west ? -longitude : longitude)
    }

    /// The third claim, and the one that had nothing holding it.
    ///
    /// `README.md`'s privacy section said *nothing about your photographs
    /// leaves the machine, including their GPS coordinates* through four
    /// security passes. One command contradicts it. `copyImagesToPasteboard`
    /// writes each frame's own bytes under its own type, and its doc comment
    /// names keeping the EXIF as the point of doing it that way, so the
    /// coordinates go on `NSPasteboard.general`, which macOS carries to the
    /// reader's other devices when Handoff is on (S-30).
    ///
    /// `CopyPathTests.copyingAnImageWritesTheFilesOwnBytesUnderItsOwnType`
    /// reads as if it covered this and does not: it compares the pasted bytes
    /// to the file, and the fixture it compares carries no GPS, so it passes
    /// whether or not EXIF survives. This one reads the coordinates back off
    /// the board, and copies a second frame that has none so that a pass means
    /// something a failure could have looked different from.
    ///
    /// The pair is invented and reads that way on purpose. The test asserts a
    /// round trip, so any two numbers prove the clipboard carried what was
    /// written, and the first draft used a real frame's coordinates off the
    /// demo card, to six places, in a file that publishes with the suite
    /// (S-38). Do not put a real place back.
    @MainActor
    @Test func copyingAGeotaggedPicturePutsItsCoordinatesOnThePasteboard() throws {
        let dir = try Fixture.tempDir("pasteboard-gps")
        defer { try? FileManager.default.removeItem(at: dir) }
        let tagged = dir.appendingPathComponent("tagged.jpg")
        let plain = dir.appendingPathComponent("plain.jpg")
        try Fixture.writeJPEG(tagged, gps: (latitude: 12.345678, longitude: -98.765432))
        try Fixture.writeJPEG(plain)

        let board = NSPasteboard(name: NSPasteboard.Name("com.sift.tests." + UUID().uuidString))
        FileOps.pasteboard = board
        defer { FileOps.pasteboard = .general }

        FileOps.copyImagesToPasteboard([tagged])
        let coordinates = try #require(gpsOnPasteboard(board), """
            The clipboard should carry the frame's own coordinates and did not.
            If the copy has stopped carrying EXIF, README.md's privacy section
            can lose the clipboard paragraph the next test holds it to.
            """)
        #expect(abs(coordinates.latitude - 12.345678) < 0.0001)
        #expect(abs(coordinates.longitude + 98.765432) < 0.0001)

        FileOps.copyImagesToPasteboard([plain])
        #expect(gpsOnPasteboard(board) == nil,
                "a frame written with no GPS IFD has to read back with none, or the check above proves nothing")
    }

    /// One `##` section of a Markdown file, its header to the next one.
    private func section(_ header: String, in text: String) -> String? {
        guard let start = text.range(of: header) else { return nil }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// The sentence the test above makes checkable.
    ///
    /// A promise kept in a document is the thing this file exists to stop, and
    /// this one outlived four passes that each read it and called it absolute.
    /// Two clauses, asserted apart, so a failure says which half moved.
    @Test func theReadmesPrivacyClaimNamesTheClipboard() throws {
        let privacy = try #require(section("## Privacy", in: try Repo.text("README.md")),
                                   "README.md has no Privacy section under that heading")

        #expect(!privacy.contains("Nothing about your photographs leaves the machine"), """
            README.md carries the absolute claim again. Copy Image puts a
            frame's own bytes, GPS with them, on a pasteboard macOS syncs to
            the reader's other devices.
            """)
        #expect(privacy.contains("Copy Image"), """
            README.md's privacy section should name the one command that sends
            a photograph anywhere, so somebody deciding whether to press it can.
            """)
    }

    // MARK: the fence, in every place that names it

    /// By extension rather than by whatever is on the disk: the suite reads
    /// the working tree and not `git ls-files`, so an untracked scratch file
    /// under `Resources/` would otherwise fail a scan for one person and
    /// nobody else.
    private static let publishedExtensions = ["swift", "md", "plist", "entitlements",
                                              "sh", "yml", "txt", "svg"]

    /// The eight files a clone gets that sit outside the published directories.
    /// Named, and read without `try?`, because a scan that quietly covers seven
    /// of them is the shape of a control that passes for the wrong reason.
    private static let publishedLooseFiles = ["README.md", "SECURITY.md", "CONTRIBUTING.md",
                                              "Makefile", "Package.swift", "scripts/bundle.sh",
                                              "scripts/dmg.sh", "scripts/make-icon.swift"]

    /// The files a clone gets, by the same list `scripts/git-hooks/allowed-paths`
    /// enforces on the way out. A file that is not valid UTF-8 is skipped, which
    /// is the icon and nothing else today.
    private func publishedFiles() throws -> [(path: String, text: String)] {
        var out: [(path: String, text: String)] = try Self.publishedLooseFiles.map {
            ($0, try Repo.text($0))
        }
        for root in ["Sift", "Tests", "Resources", ".github"] {
            let found = FileManager.default
                .enumerator(at: Repo.at(root), includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? []
            for url in found where Self.publishedExtensions.contains(url.pathExtension) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let path = url.path.replacingOccurrences(of: Repo.root.path + "/", with: "")
                out.append((path, text))
            }
        }
        return out
    }

    /// The scan covers the three addresses the findings came from.
    ///
    /// Every test below reads `publishedFiles`, and an empty answer from it
    /// passes all of them. One wrong root, one rename, and the suite reports a
    /// clean repository it never opened. Two of these three are where S-32 and
    /// S-39 were found; the third is the file S-30 was about.
    @Test func theScanOpensTheFilesTheFindingsCameFrom() throws {
        let paths = Set(try publishedFiles().map(\.path))
        for wanted in ["README.md", "SECURITY.md", "Resources/Info.plist",
                       "Sift/Files/FolderAccess.swift"] {
            #expect(paths.contains(wanted), "the published scan never opened \(wanted)")
        }
    }

    /// Nothing a reader gets contradicts D-324.
    ///
    /// The sentence D-324 retired on 2026-09-18 turned up in three places on
    /// three different days: SECURITY.md (S-32), the `public` branch (S-35),
    /// and `Resources/Info.plist` (S-39), which `bundle.sh` copies word for
    /// word into every locally built app. Three addresses in one blast radius
    /// is the sign that the report should have been a test.
    ///
    /// Six lines say the app has no fence and are right, because `swift run`
    /// and the suite are outside the bundle and `FolderAccess` refuses nothing
    /// there on purpose. Each is named below with the sentence it is allowed
    /// to say, rather than its file: a file-wide pass would let the next wrong
    /// sentence in beside a right one, which is how S-39 survived S-32.
    @Test func nothingPublishedContradictsTheSandbox() throws {
        // A line carrying the marker is exempt, which is how the four lines
        // below hold the words without failing the test that reads them. It is
        // `DesignSystemTests`' mechanism, spelled the same way.
        let marker = "sandbox-claim:allow"
        let retired = ["unsandboxed", "not sandboxed", "no sandbox", "isn't sandboxed"]  // sandbox-claim:allow
        let allowed: [(path: String, sentence: String)] = [
            // History, dated, in the type that holds the grants and in its suite.
            ("Sift/Files/FolderAccess.swift", "was unsandboxed until 2026-09-18"),  // sandbox-claim:allow
            ("Tests/SiftTests/SandboxTests.swift", "was unsandboxed until 2026-09-18"),  // sandbox-claim:allow
            // What the type and the stored dictionary become outside the bundle,
            // which is where every test in this suite reads them.
            ("Sift/Files/FolderAccess.swift", "this whole type becomes a recorder"),
            ("Sift/Store/Preferences.swift", "and any build whose entitlements went"),
            ("Tests/SiftTests/SandboxTests.swift", "every folder is reachable and nothing is refused"),
            // The build failure when the signed bundle comes back without it.
            ("scripts/bundle.sh", "the signed app is not sandboxed"),  // sandbox-claim:allow
        ]
        var offenders: [String] = []
        for file in try publishedFiles() {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, raw) in lines.enumerated() {
                let line = String(raw)
                guard !line.contains(marker),
                      !allowed.contains(where: { $0.path == file.path && line.contains($0.sentence) })
                else { continue }
                let lower = line.lowercased()
                for phrase in retired where lower.contains(phrase) {
                    offenders.append("\(file.path):\(number + 1) said \"\(phrase)\"")
                }
            }
        }
        #expect(offenders.isEmpty, """
            a published file contradicts D-324: \(offenders.joined(separator: " | "))
            The app has run inside the App Sandbox since 2026-09-18. Either fix
            the sentence, or, if the line is describing `swift run` and the
            suite, which run outside the bundle and outside the fence, add it
            to `allowed` above with the sentence it is allowed to say.
            """)
    }

}
