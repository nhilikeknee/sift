import Foundation

/// What an overwrite leaves beside a photograph so the edit can be taken back
/// or taken further in a session it was not made in (D-165).
///
/// Two halves, and neither is a catalog: the pixels as they were before the
/// first overwrite, in a hidden file next to the photograph, and the six
/// numbers that were applied, in an extended attribute on the photograph
/// itself. Both travel in a Finder copy of the folder — the record is in the
/// shoot, not in a database somewhere else — and both are readable without
/// this app, which is the point of D-3 applied to a develop recipe.
///
/// What the pair buys is that a second adjustment develops the *original*
/// again rather than adjusting an already-adjusted file. Ten overwrites are
/// one generation down, not ten.
enum AdjustRecord {
    /// Namespaced the way a Finder extended attribute is, so anything else
    /// reading the file sees whose it is.
    static let attribute = "com.sift.adjust"

    /// `DSC_0001.jpg` keeps its original as `.DSC_0001.sift-original.jpg`.
    ///
    /// Dot-prefixed because every scan in this app already passes
    /// `.skipsHiddenFiles`, so the copy is invisible to the grid, the
    /// filmstrip and the counts without a single filter written for it. The
    /// real extension stays on the end: ImageIO sniffs content rather than
    /// names, but a person who finds this file in a terminal should not have
    /// to.
    static func originalURL(for photo: URL) -> URL {
        let ext = photo.pathExtension
        let stem = photo.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? ".\(stem).sift-original" : ".\(stem).sift-original.\(ext)"
        return photo.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// The kept original, when there is one on disk.
    static func original(for photo: URL) -> URL? {
        let url = originalURL(for: photo)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The pixels an adjustment is developed from: the kept original when
    /// there is one, the photograph itself otherwise. Every render of a recipe
    /// goes through here — the preview beside the sliders and the full-size
    /// write both — or the two would disagree about what they are adjusting.
    ///
    /// **Unless the photograph is downstream of that original.** Then it is the
    /// wrong pixels to develop: the original is the whole frame, and rendering
    /// it would put back the corner a crop took out. A crop in place, or a copy
    /// written from an edited photograph, is a decision about what this file
    /// *is*, so it becomes the base and the kept original goes on serving
    /// Revert alone (D-239, D-243).
    static func base(for photo: URL) -> URL {
        isDerived(photo) ? photo : (original(for: photo) ?? photo)
    }

    /// The frame as it arrived, which is what a copy inherits and what Revert
    /// puts back: the kept original when there is one, the file itself when it
    /// has never been written into (D-243).
    static func arrival(of photo: URL) -> URL { original(for: photo) ?? photo }

    /// Set on a photograph whose pixels are downstream of the original kept
    /// beside it: cropped into, or written as a copy of something that was
    /// already edited. It holds the date it happened.
    ///
    /// Presence is the fact and nothing reads the value back: what was done
    /// lives in the pixels now, and a second copy of it here would be a second
    /// place one fact lives. The date is there for somebody reading the
    /// attributes in a terminal, which is what D-3 asks of everything this app
    /// writes (D-239, widened by D-243).
    static let derivedAttribute = "com.sift.derived"

    static func isDerived(_ photo: URL) -> Bool { Xattr.get(derivedAttribute, at: photo) != nil }

    static func markDerived(_ photo: URL, at when: Date = Date()) throws {
        let stamp = ISO8601DateFormatter().string(from: when)
        try Xattr.set(derivedAttribute, Data(stamp.utf8), at: photo)
    }

    static func clearDerived(for photo: URL) throws { try Xattr.remove(derivedAttribute, at: photo) }

    /// The six numbers last written over this photograph, whether or not the
    /// original they were applied to is still there.
    static func recipe(for photo: URL) -> Adjustments? {
        guard let data = Xattr.get(attribute, at: photo) else { return nil }
        return try? JSONDecoder().decode(Adjustments.self, from: data)
    }

    /// What the panel opens at. A recipe whose original has gone — the
    /// photograph was renamed or moved by something that is not this app — is
    /// deliberately *not* returned: putting those numbers on the sliders over
    /// baked pixels would mean the next drag applied them twice. It is
    /// history at that point, which `summary` says and `editable` does not.
    static func editable(for photo: URL) -> Adjustments? {
        guard original(for: photo) != nil, !isDerived(photo) else { return nil }
        return recipe(for: photo)
    }

    /// Whether this photograph can be put back the way it was, whether what
    /// was written into it was an adjustment, a crop, or both: one kept
    /// original, one Revert (D-239).
    static func isRevertable(_ photo: URL) -> Bool { original(for: photo) != nil }

    static func write(_ adjustments: Adjustments, for photo: URL) throws {
        try Xattr.set(attribute, JSONEncoder().encode(adjustments), at: photo)
    }

    /// Takes the numbers off. The original is the caller's to deal with: the
    /// revert consumes it, and an undo of an overwrite carries it home.
    static func clear(for photo: URL) throws {
        try Xattr.remove(attribute, at: photo)
    }
}
