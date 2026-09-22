import Testing
import Foundation

/// The repository on disk, for the tests that read the source, the documents
/// and the `Info.plist` rather than the built app.
///
/// `#filePath` expands where it is written, so this is the path of *this* file
/// and three levels up is the root. Fifteen tests were each spelling that walk
/// out, four of them with the count written as a comment beside it, and the
/// suite gained two more of them in one stretch. One of the fifteen reached a
/// different depth than its neighbors and nothing would have said so (D-307).
///
/// It is only right while this file sits in `Tests/SiftTests/`. Moving it one
/// directory changes what every source-reading test looks at, and changes it
/// silently, which is what `RepoRootTests` below is for.
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SiftTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the repository

    /// A file in the repository, read as text. The path is relative to the
    /// root, the way `git` spells it.
    static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// A folder in the repository.
    static func at(_ path: String) -> URL { root.appendingPathComponent(path) }
}

@Suite struct RepoRootTests {
    /// The walk lands on this repository rather than on a parent of it.
    ///
    /// Every test that reads source, the design document, the README or
    /// the plist is downstream of this one constant now. A root one level
    /// too high still resolves, still reads files, and answers a different
    /// repository's questions — so the three things named here are the
    /// ones only this checkout has.
    @Test func theRootIsThisRepository() throws {
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: Repo.at("Package.swift").path))
        #expect(fm.fileExists(atPath: Repo.at("Sift/SiftApp.swift").path))
        #expect(fm.fileExists(atPath: Repo.at("Tests/SiftTests/RepoRoot.swift").path))
        #expect(try Repo.text("Package.swift").contains("Sift"))
    }
}
