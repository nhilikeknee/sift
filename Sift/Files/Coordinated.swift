import Foundation

/// A write that tells the rest of the machine it is happening (D-214).
///
/// Sift overwrites photographs in two places — rotating one, and saving an
/// adjustment over the original — and both did it with a plain
/// `replaceItemAt`. That works, and it is the one kind of write on this
/// platform where working is not enough: another app with the same file open
/// gets no chance to save first, and its next save puts back what Sift just
/// wrote. `NSFileCoordinator` is how a Mac app says "I am about to replace
/// this" and waits for everyone who cares.
///
/// Only the in-place rewrites go through here. Reading and watching do not:
/// this app browses a folder rather than owning documents in it, so it has no
/// business registering as an `NSFilePresenter` for files it is only looking
/// at — Finder does not either. Moves, renames and trashing go through
/// `FileManager`, which coordinates them itself.
enum Coordinated {
    /// Runs `write` inside a coordinated write for `url`.
    ///
    /// The coordinator's own error is thrown when it has one; otherwise the
    /// error out of `write` is. Both are reported rather than swallowed,
    /// because a rotation that silently did nothing is the failure this app
    /// spent a session on once (D-43).
    static func replacing(_ url: URL, _ write: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing,
                               error: &coordinationError) { actual in
            // The URL the coordinator hands back, not the one passed in: it
            // can differ, and writing to the original behind its back is the
            // whole thing this is here to stop.
            do { try write(actual) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
