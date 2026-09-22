import Foundation

/// What undoing an operation actually does, as a description rather than as a
/// closure (D-108).
///
/// Every operation still ships with its inverse (D-5); the inverse is now
/// something you can look at. A closure can only be run, which means the undo
/// stack could not be tested except by performing it, could not say what it was
/// about to do, and could not be checked for reachability before it tried. It
/// is `Codable` so that persisting the stack across a quit becomes a decision
/// about whether that is wanted rather than a rewrite of this file.
enum Inverse: Sendable, Codable, Equatable {
    /// Put a file back where it was. Trash, move and rename all undo this way.
    case moveBack(from: URL, to: URL)
    /// Take a file this app created back out. Undoing a copy or a crop trashes
    /// what was written rather than deleting it: undo is not the one command in
    /// the app that destroys something outright.
    case trash(URL)
    /// The same, and the hidden original the copy inherited goes with it, so
    /// undoing a copy leaves the folder exactly as it found it (D-243).
    case trashCopy(URL)
    /// Put one of the three marks back, and the sidecar with it. The other two
    /// come along because the sidecar carries all three and a sync that knew
    /// only one would clear the others.
    case restoreMark(Mark, url: URL, flag: Flag?, favorite: Bool, label: String?)
    /// Turn a photo back the way it came.
    case turn(URL, clockwise: Bool)
    /// Put a copy back where one was taken from, replacing whatever is at the
    /// destination. Undoing a revert needs the original it just restored
    /// copied aside again before the adjusted file goes back over it (D-165).
    case copyAside(from: URL, to: URL)
    /// A whole batch rename, taken back.
    ///
    /// Not a list of `moveBack`s, and that is the point of the case existing.
    /// A renumber is a permutation of a set of names — `01`→`02`, `02`→`03`,
    /// `03`→`01` — and `moveBack` refuses to clobber, so putting the first
    /// file back lands it on the second whichever order the list is replayed
    /// in. Undo therefore goes the way the rename went: everything out of the
    /// way first, everything home after (D-380).
    case renameBack([Hop])
    /// A batch, undone last first, the way it was built.
    indirect case all([Inverse])

    /// One photograph's way home: the name it is under now, and the name it
    /// had before the batch.
    struct Hop: Sendable, Codable, Equatable {
        let from: URL
        let to: URL
    }

    enum Mark: String, Sendable, Codable {
        case flag, favorite, label
    }

    /// The folder whose absence stops this inverse: an undo aimed at a card
    /// that has been unplugged should say so rather than fail as whatever error
    /// the filesystem happens to raise.
    var folders: [URL] {
        switch self {
        case let .moveBack(from, to): [from.deletingLastPathComponent(), to.deletingLastPathComponent()]
        case let .trash(url): [url.deletingLastPathComponent()]
        case let .trashCopy(url): [url.deletingLastPathComponent()]
        case let .restoreMark(_, url, _, _, _): [url.deletingLastPathComponent()]
        case let .turn(url, _): [url.deletingLastPathComponent()]
        case let .copyAside(from, to): [from.deletingLastPathComponent(), to.deletingLastPathComponent()]
        case let .renameBack(hops): hops.flatMap { [$0.from.deletingLastPathComponent(), $0.to.deletingLastPathComponent()] }
        case let .all(inverses): inverses.flatMap(\.folders)
        }
    }

    /// The first folder this inverse needs that is not there, or nil when all
    /// of them are.
    func missingFolder(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL? {
        folders.first { !exists($0) }
    }

    func run() throws {
        if let missing = missingFolder() {
            throw FileOps.Failure(message: "\(missing.lastPathComponent) is not there any more, so this can't be undone.")
        }
        try perform()
    }

    /// The work itself, with the reachability check already done: a batch is
    /// checked once at the top rather than once per file.
    private func perform() throws {
        switch self {
        case let .moveBack(from, to):
            try FileOps.moveBack(from, to: to)
        case let .trash(url):
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        case let .trashCopy(url):
            // The inherited original goes with it, the same rule trashing a
            // photograph keeps (D-243). Not `.trash`, which is also how the
            // undo of an overwrite clears the way for the original it is about
            // to move home — that one must leave the kept file exactly where
            // it is, because it is the file being moved.
            if let kept = AdjustRecord.original(for: url) {
                try? FileManager.default.trashItem(at: kept, resultingItemURL: nil)
            }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        case let .restoreMark(mark, url, flag, favorite, label):
            switch mark {
            case .flag: try MetadataIO.writeFlag(flag, to: url)
            case .favorite: try MetadataIO.writeFavorite(favorite, to: url)
            case .label: try MetadataIO.writeLabel(label.flatMap(ColorLabel.init(rawValue:)), to: url)
            }
            FileOps.syncSidecar(flag: flag, favorite: favorite, label: label, for: url)
        case let .turn(url, clockwise):
            try FileOps.applyRotation(url, clockwise: clockwise)
        case let .copyAside(from, to):
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            try FileManager.default.copyItem(at: from, to: to)
        case let .renameBack(hops):
            // Park names are made here rather than carried in the case, so
            // nothing stale is written into the undo stack and undoing the
            // same batch twice cannot collide with the first pass's leftovers.
            // The first refusal is what gets reported, and every other
            // photograph is still put somewhere visible before it is.
            var refused: (any Error)?
            var parked: [(temp: URL, hop: Hop)] = []
            for hop in hops {
                do { parked.append((try FileOps.park(hop.from), hop)) }
                // Counted rather than skipped in silence: a photograph that
                // will not move during an undo is the one thing the reader
                // needs told about.
                catch { refused = refused ?? error }
            }
            for (temp, hop) in parked {
                do { try FileOps.place(temp, at: hop.to) }
                catch {
                    refused = refused ?? error
                    try? FileOps.unpark(temp, to: hop.from)
                }
            }
            if let refused { throw refused }
        case let .all(inverses):
            for inverse in inverses.reversed() { try inverse.perform() }
        }
    }
}
