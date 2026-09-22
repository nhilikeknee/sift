import Testing
import Foundation
@testable import Sift

/// A stored mutable static is a test-isolation bug until it has a seam (D-329).
///
/// The rule is old and it kept being broken, which means the wording was never
/// the problem: nothing fired when a new one was added. D-54 found the
/// pasteboard because the suite had been throwing away whatever was on the real
/// clipboard for weeks. D-86 found the preferences because tests run in
/// parallel and one of them wrote what another read. D-149 made the image
/// caches task-local for the same reason, and `SandboxTests` had to be marked
/// `.serialized` because the fence is a static and two tests at once read each
/// other's folders — which looks like the rule being wrong rather than the
/// suite being parallel, and that is the expensive part.
///
/// So the allowlist below is the point, not the ban. Every entry names the seam
/// a test gets past it by. Adding a process-global means writing that sentence,
/// which is the moment the question gets asked.
@Suite struct GlobalStateTests {
    /// Each stored mutable static in the app, and how a test gets past it.
    /// `@TaskLocal` is a seam by construction and needs no entry.
    private static let seams: [String: String] = [
        "SiftApp.swift:screenChecks": "@MainActor, appended to only by the launch flags; the suite never launches",
        "Launch.swift:claimed": "@MainActor latch over launch variables, which the suite does not set",
        "FolderAccess.swift:isSandboxed": "FolderAccess.pretendingSandboxed (D-324)",
        "FolderAccess.swift:held": "the same seam; SandboxTests is .serialized for it",
        "FileOps.swift:sessionBackups": "FileOps.useTestBackups()",
        "FileOps.swift:usingTestBackups": "FileOps.useTestBackups()",
        "FileOps.swift:keptAnything": "FileOps.useTestBackups()",
        "FileOps.swift:pasteboard": "assign a test pasteboard (D-54)",
        "Announcer.swift:say": "assign a closure; AnnouncementTests does (A-11)",
        "LibraryStore.swift:capsLockIsDown": "assign a closure (D-97)",
        "Tokens.swift:increaseContrast": "assign a closure; ContrastTests does (D-340)",
        "Preferences.swift:backing": "Preferences.useTestDefaults() (D-86)",
        "Preferences.swift:isTestDomain": "Preferences.useTestDefaults() (D-86)",
        "GalleryToolbar.swift:watchKey": "not state: its address is the associated-object key the observation hangs off, and nothing reads the value (D-381)",
        "GalleryToolbar.swift:rearranging": "@MainActor re-entrancy latch around NSToolbar edits; the rule it guards is `spacePlan(for:)`, which is pure and is what the tests drive (D-381)",
    ]

    /// The app's source, read once. Both tests below walk every file in
    /// `Sift/`, and each was doing its own enumerate-and-read of all 85.
    private static let sources: [(name: String, lines: [String])] = {
        let dir = Repo.root.appendingPathComponent("Sift")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return files.sorted { $0.path < $1.path }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent,
                    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        }
    }()

    /// Computed and stored read the same at a glance and are nothing alike:
    /// `static var fast: Animation? { ... }` holds nothing, and
    /// `static var pasteboard = .general` is shared by every test in the
    /// process. A brace before the first `=` is the difference.
    private static func isStored(_ declaration: String) -> Bool {
        let brace = declaration.firstIndex(of: "{")
        let equals = declaration.firstIndex(of: "=")
        guard let brace else { return true }
        guard let equals else { return false }
        return equals < brace
    }

    @Test func everyProcessGlobalNamesTheSeamATestGetsPastItBy() throws {
        var undeclared: [String] = []
        for (file, lines) in Self.sources {
            for (i, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.contains("static var"), !line.hasPrefix("//") else { continue }
                if line.contains("@TaskLocal") { continue }
                let after = String(line.components(separatedBy: "static var")[1])
                guard Self.isStored(after) else { continue }
                let name = after.drop(while: \.isWhitespace).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if Self.seams["\(file):\(name)"] == nil {
                    undeclared.append("\(file):\(i + 1) \(name) — a process-global with no seam named in GlobalStateTests.seams")
                }
            }
        }

        #expect(undeclared.isEmpty, """
            A stored mutable static is shared by every test in the process. Give it a
            seam — a task-local, an injected closure, a `useTest…()` — and name the
            seam in `GlobalStateTests.seams`:
            \(undeclared.joined(separator: "\n"))
            """)
    }

    /// The other half, and the one that was destructive rather than flaky:
    /// reaching for the machine's own copy in the middle of an expression,
    /// where nothing can stand in front of it.
    ///
    /// Naming it once, as a parameter default or the seam's own declaration, is
    /// the shape that works: `Breadcrumb` takes `home:` and every test passes
    /// its own. Those lines are the allowlist below; each says which seam it is.
    @Test func nothingReadsTheMachineWhereASeamAlreadyExists() throws {
        let banned = ["UserDefaults.standard", "NSPasteboard.general",
                      "FileManager.default.homeDirectoryForCurrentUser"]
        /// file:name of the declaration that stands in front of the machine.
        let seamDeclarations: [String: String] = [
            "FileOps.swift:pasteboard": "the pasteboard seam itself (D-54)",
            "Preferences.swift:backing": "the preferences seam itself (D-86)",
            "Breadcrumb.swift:home": "an injected default; every caller may pass its own",
        ]
        var found: [String] = []

        for (file, lines) in Self.sources {
            // The names allowlisted for this file, worked out once rather than
            // once per line that mentions the machine.
            let declared = seamDeclarations.keys
                .filter { $0.hasPrefix(file + ":") }
                .map { String($0.components(separatedBy: ":")[1]) }
            for (i, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//"), banned.contains(where: line.contains) else { continue }
                // A declaration whose name is allowlisted for this file is the
                // seam, not a use of it.
                if declared.contains(where: { line.contains($0 + ":") || line.contains("var " + $0) }) { continue }
                found.append("\(file):\(i + 1) \(line)")
            }
        }

        #expect(found.isEmpty, """
            This reads the machine's own state where nothing can stand in front of it.
            Take it as a parameter with this as the default, or go through the seam,
            and name the declaration in `seamDeclarations`:
            \(found.joined(separator: "\n"))
            """)
    }
}
