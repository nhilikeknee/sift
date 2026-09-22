import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Every operation returns its inverse alongside its result (D-5).
enum FileOps {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: trash

    static func trash(_ url: URL) throws -> UndoableOp {
        try trashReturningLocation(url).1
    }

    static func trashReturningLocation(_ url: URL) throws -> (URL, UndoableOp) {
        var trashed: NSURL?
        // The kept original goes with it, or the folder keeps a hidden copy of
        // a photograph that is not there any more (D-165).
        let kept = AdjustRecord.original(for: url)
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        guard let trashedURL = trashed as URL? else { throw Failure(message: "Trash did not report where the file went.") }
        var back: Inverse = .moveBack(from: trashedURL, to: url)
        if let kept {
            var keptTrashed: NSURL?
            if (try? FileManager.default.trashItem(at: kept, resultingItemURL: &keptTrashed)) != nil,
               let keptTrashedURL = keptTrashed as URL? {
                back = .all([.moveBack(from: keptTrashedURL, to: kept), back])
            }
        }
        return (trashedURL, UndoableOp(label: "Move to Trash", inverse: back))
    }

    // MARK: move / rename

    static func move(_ url: URL, into folder: URL) throws -> (URL, UndoableOp) {
        let dest = folder.appendingPathComponent(url.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw Failure(message: "\(dest.lastPathComponent) already exists in \(folder.lastPathComponent).")
        }
        try FileManager.default.moveItem(at: url, to: dest)
        return (dest, UndoableOp(label: "Move", inverse: carrying(from: url, to: dest,
                                                                 .moveBack(from: dest, to: url))))
    }

    /// The kept original goes where the photograph goes, and the inverse
    /// brings it back with it (D-165). A cull moves and renames constantly, so
    /// a record that only survived a photograph sitting still would be a
    /// record that breaks on the first decision made about it.
    ///
    /// Best effort by design: a move whose record cannot follow is still a
    /// move, and the recipe left on the file then reads as what was done
    /// rather than as somewhere to carry on from — which is the state
    /// `AdjustRecord.editable` already refuses to hand the sliders.
    private static func carrying(from url: URL, to dest: URL, _ inverse: Inverse) -> Inverse {
        guard let kept = AdjustRecord.original(for: url) else { return inverse }
        let destKept = AdjustRecord.originalURL(for: dest)
        guard (try? FileManager.default.moveItem(at: kept, to: destKept)) != nil else { return inverse }
        return .all([.moveBack(from: destKept, to: kept), inverse])
    }

    /// Copies rather than moves (D-87). FastRawViewer copies selects out, and
    /// a cull that empties the folder it is culling is one you cannot redo.
    /// The inverse trashes the copy rather than deleting it: undo should not be
    /// the one operation in the app that destroys something outright.
    static func copy(_ url: URL, into folder: URL) throws -> (URL, UndoableOp) {
        var dest = folder.appendingPathComponent(url.lastPathComponent)
        var n = 2
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return (dest, UndoableOp(label: "Copy", inverse: .trash(dest)))
    }

    /// Every app on the machine that says it can open this file, most likely
    /// first, with the ones that only view it left out is not something the
    /// system will tell us — so the list is what it offers and the names are
    /// what the user recognizes (D-88).
    static func editors(for url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    static func appName(_ app: URL) -> String {
        app.deletingPathExtension().lastPathComponent
    }

    /// The part of a filename a rename is about: everything before the
    /// extension, as a range AppKit can select (D-379).
    ///
    /// In UTF-16 units, because that is what `NSTextView` counts and a
    /// photograph named with an emoji or an accent would otherwise select a
    /// character short. The whole name when there is no extension, so
    /// `README` and a dotfile are selected end to end rather than not at all,
    /// and the last dot rather than the first, so `archive.tar.gz` keeps
    /// `.gz` and offers `archive.tar`.
    static func stemRange(of name: String) -> NSRange {
        let stem = (name as NSString).deletingPathExtension
        return NSRange(location: 0, length: (stem as NSString).length)
    }

    /// Opens the whole selection in one named application, rather than handing
    /// each file to whatever owns its extension.
    static func open(_ urls: [URL], with app: URL) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// A new name is a name, not a path.
    ///
    /// `appendingPathComponent` reads a `/` as a separator and `..` as the
    /// parent, so a rename to `../elsewhere.jpg` moves the photograph out of
    /// the folder it is being renamed in, and one slash in a batch pattern
    /// takes the whole selection with it. Undo brings it back, which is not
    /// the same as it not happening (D-173).
    ///
    /// A leading dot is refused for a different reason: the scanner skips
    /// hidden files, so the photograph would not come back on the rescan and
    /// the rename would read as a deletion.
    static func nameOnly(_ proposed: String) throws(Failure) -> String {
        let name = proposed.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw Failure(message: "A name can't be empty.") }
        guard name != ".", name != ".." else { throw Failure(message: "\(name) isn't a name.") }
        // `:` because the Finder shows one as a `/`, which makes a file that
        // has one in it look like it is somewhere it is not.
        guard !name.contains("/"), !name.contains(":") else {
            throw Failure(message: "A name can't contain / or :.")
        }
        guard !name.hasPrefix(".") else {
            throw Failure(message: "A name starting with a dot hides the file.")
        }
        return name
    }

    /// Where an ingest's copies go: the folder that was picked, or one new
    /// folder inside it.
    ///
    /// The **Into** field is a name and goes through `nameOnly`, for the reason
    /// a rename does and by the same route it had not. `appendingPathComponent`
    /// reads `..` as the parent, so an ingest asked for `../../Elsewhere` made
    /// a directory outside the folder the picker named, copied the card into
    /// it, and then opened it, so the screen showed a copy that had gone
    /// somewhere else. A leading dot is the other half: the folder is made,
    /// filled, and then skipped by every scan in the app.
    ///
    /// It matters more here than in a rename. A rename has an inverse and an
    /// ingest has none, because a card is the only copy of a shoot until the
    /// copy finishes, so there is nothing to press ⌘Z on afterwards
    /// (D-303).
    static func ingestDestination(_ destination: URL, subfolder: String) throws(Failure) -> URL {
        let named = subfolder.trimmingCharacters(in: .whitespaces)
        guard !named.isEmpty else { return destination }
        return destination.appendingPathComponent(try nameOnly(named))
    }

    /// Where an ingest's copies would go, or why it cannot run as asked.
    ///
    /// Both typed fields, not one. D-303 made **Into** a name and left
    /// **Rename** beside it taking anything at all, and the two are read by
    /// the same person in the same sitting. The sheet shows what this throws
    /// under the fields and holds the Copy button down on it; the ingest calls
    /// it again before the first file moves, because the sheet is one caller
    /// and a copy has no inverse to press afterwards (D-304).
    static func ingestPlan(destination: URL, subfolder: String,
                           pattern: String) throws(Failure) -> URL {
        // Into first: it is the field above, so a sheet with both wrong names
        // the one the reader would fix first.
        let landing = try ingestDestination(destination, subfolder: subfolder)
        let typed = pattern.trimmingCharacters(in: .whitespaces)
        // An empty pattern means every photograph keeps the name it arrived
        // with, which is the default and not a refusal.
        if !typed.isEmpty { _ = try nameOnly(typed) }
        return landing
    }

    static func rename(_ url: URL, to newName: String) throws -> (URL, UndoableOp) {
        let dest = url.deletingLastPathComponent().appendingPathComponent(try nameOnly(newName))
        guard dest != url else { throw Failure(message: "Same name.") }
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw Failure(message: "\(dest.lastPathComponent) already exists.")
        }
        try FileManager.default.moveItem(at: url, to: dest)
        return (dest, UndoableOp(label: "Rename", inverse: carrying(from: url, to: dest,
                                                                    .moveBack(from: dest, to: url))))
    }

    // MARK: batch rename

    /// What a whole batch rename would do, worked out before a byte moves.
    ///
    /// The shape `ingestPlan` has, for the reason it has it: a pattern is one
    /// string typed once and applied to every photograph, so the run that
    /// refuses it refuses it whole rather than part-way through (D-380).
    struct RenamePlan: Sendable {
        struct Step: Sendable {
            let source: URL
            let dest: URL
        }

        /// The photographs whose name is actually moving, in the order given.
        let changing: [Step]
        /// The ones already carrying the pattern. Not a failure and not a move.
        let unchanged: Int
    }

    /// Where every photograph in a batch rename would land, or why the pattern
    /// cannot be run as typed.
    ///
    /// Three rules. A name that is a path is refused by `nameOnly`, as
    /// everywhere else. A name the photograph already has is an identity, not
    /// an error, which is what makes re-running a pattern a no-op. And two
    /// photographs asking for one name is refused here rather than renaming
    /// the first and leaving the shoot under two schemes.
    ///
    /// A collision with a file *outside* the selection is not checked. Those
    /// are skipped and counted while the run goes on, the way every other
    /// batch treats a file it could not move.
    static func renamePlan(pattern: String, refs: [PhotoRef]) throws(Failure) -> RenamePlan {
        var changing: [RenamePlan.Step] = []
        var unchanged = 0
        var claimed: [URL: String] = [:]
        for (i, ref) in refs.enumerated() {
            let name = try nameOnly(expand(pattern: pattern, ref: ref, index: i + 1))
            let dest = ref.url.deletingLastPathComponent().appendingPathComponent(name)
            if let other = claimed[dest] {
                throw Failure(message: "\(name) would be the name of both \(other) and \(ref.name). Add {n} to the pattern.")
            }
            claimed[dest] = ref.name
            if dest == ref.url { unchanged += 1 } else { changing.append(.init(source: ref.url, dest: dest)) }
        }
        return RenamePlan(changing: changing, unchanged: unchanged)
    }

    /// The kept original goes where its photograph goes, best effort.
    ///
    /// Three callers, which is when to extract: park, place and unpark each
    /// move a photograph and have to take `.<stem>.sift-original.<ext>` with
    /// it, because that name is derived from the photograph's and would
    /// otherwise point at a file that is not there (D-165).
    private static func moveKept(from: URL, to: URL) {
        guard let kept = AdjustRecord.original(for: from) else { return }
        try? FileManager.default.moveItem(at: kept, to: AdjustRecord.originalURL(for: to))
    }

    /// A photograph moved aside under a name no scan shows, so the name it is
    /// vacating is free for whichever photograph is taking it.
    ///
    /// Dot-prefixed for the reason `AdjustRecord.originalURL` is: every scan
    /// passes `.skipsHiddenFiles`, so a parked file is invisible to the grid
    /// and the counts without a filter written for it. It does not go through
    /// `nameOnly`, which refuses a leading dot: that rule is about a name
    /// somebody typed, and `applyRotation` writes an app-made temp the same
    /// way. `sift-renaming` is in the middle so a crash leaves something a
    /// person can find with `ls -a`.
    ///
    /// The stem is cut to leave room for the rest of the park name. A
    /// photograph named near the ceiling would otherwise fail to park, be
    /// counted as skipped, and keep its old name with nothing saying why.
    ///
    /// Measured rather than assumed, because the unit is the trap: macOS caps
    /// a name at 255 UTF-16 code units, not bytes and not characters. A
    /// 255-character CJK name is 765 bytes and is legal; an emoji name stops
    /// at 127 characters because each one is two units. Cutting to a count of
    /// characters would still overflow on grapheme clusters built from
    /// several scalars, where 23 of them already reach 253 units.
    static func park(_ url: URL) throws -> URL {
        let ext = url.pathExtension
        let tag = "sift-renaming-\(UUID().uuidString)"
        // The two dots around the tag, plus the leading one, plus the
        // extension and its own dot when there is one.
        let room = 255 - (2 + tag.utf16.count + (ext.isEmpty ? 0 : 1 + ext.utf16.count))
        // Whole Characters come off, so a cut never splits a cluster.
        var stem = url.deletingPathExtension().lastPathComponent
        while !stem.isEmpty, stem.utf16.count > room { stem.removeLast() }
        let name = ext.isEmpty ? ".\(stem).\(tag)" : ".\(stem).\(tag).\(ext)"
        let parked = url.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: url, to: parked)
        moveKept(from: url, to: parked)
        return parked
    }

    /// A parked photograph down on the name the plan gave it.
    ///
    /// Refuses an occupied destination the way `rename` does. Inside a batch
    /// that can only mean a file nobody selected, since every selected name is
    /// parked by the time this runs, so the caller counts it as a skip rather
    /// than stopping.
    static func place(_ parked: URL, at dest: URL) throws {
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw Failure(message: "\(dest.lastPathComponent) already exists.")
        }
        try FileManager.default.moveItem(at: parked, to: dest)
        moveKept(from: parked, to: dest)
    }

    /// A parked photograph back where it started. What a skip and an Esc both
    /// use: a run that stops has to leave a folder somebody can still see.
    static func unpark(_ parked: URL, to origin: URL) throws {
        moveKept(from: parked, to: origin)
        try moveBack(parked, to: origin)
    }

    static func moveBack(_ from: URL, to: URL) throws {
        if FileManager.default.fileExists(atPath: to.path) {
            throw Failure(message: "Can't restore: \(to.lastPathComponent) already exists there.")
        }
        try FileManager.default.moveItem(at: from, to: to)
    }

    /// The `{date}` stamp, in the one calendar that sorts: Gregorian, ASCII
    /// digits, whatever the machine's locale says (D-259).
    ///
    /// A bare `DateFormatter` takes its calendar and its numerals from the
    /// user, so the same shoot renamed to `2026-05-28` here came out
    /// `2569-05-28` under a Thai locale and in Arabic-Indic digits under
    /// `ar_SA`. A date in a filename is there to sort, and neither of those
    /// sorts beside the files already in the folder.
    ///
    /// The locale is an argument, defaulting to the machine's, so the test can
    /// hand it the ones that used to break it and watch the stamp not move.
    static func dateStamp(_ date: Date, locale: Locale = .current) -> String {
        // Both halves, and the second one is the half that was missed: pinning
        // the calendar alone still wrote `٢٠٢٦-٠٥-٢٨` under `ar_SA`, because
        // the numbering system is the locale's and not the calendar's.
        var components = Locale.Components(locale: locale)
        components.calendar = .gregorian
        components.numberingSystem = Locale.NumberingSystem("latn")
        let f = DateFormatter()
        f.locale = Locale(components: components)
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// `{name}` original stem, `{n}` / `{nn}` / `{nnn}` counter, `{date}` created date, `{ext}` extension.
    static func expand(pattern: String, ref: PhotoRef, index: Int) -> String {
        let stem = ref.url.deletingPathExtension().lastPathComponent
        let date = ref.dateTaken ?? ref.created
        var s = pattern
            .replacingOccurrences(of: "{name}", with: stem)
            .replacingOccurrences(of: "{nnn}", with: String(format: "%03d", index))
            .replacingOccurrences(of: "{nn}", with: String(format: "%02d", index))
            .replacingOccurrences(of: "{n}", with: "\(index)")
            .replacingOccurrences(of: "{date}", with: dateStamp(date))
            .replacingOccurrences(of: "{ext}", with: ref.url.pathExtension)
        if !s.contains(".") { s += "." + ref.url.pathExtension }
        return s
    }

    // MARK: flags and the favorite

    static func setFlag(_ flag: Flag?, on ref: PhotoRef) throws -> UndoableOp {
        let before = ref.flag
        let wasFavorite = ref.favorite
        let label = ref.label?.rawValue
        try MetadataIO.writeFlag(flag, to: ref.url)
        syncSidecar(flag: flag, favorite: wasFavorite, label: label, for: ref.url)
        return UndoableOp(label: "Flag",
                          inverse: .restoreMark(.flag, url: ref.url, flag: before,
                                                favorite: wasFavorite, label: label))
    }

    static func setFavorite(_ favorite: Bool, on ref: PhotoRef) throws -> UndoableOp {
        let before = ref.favorite
        let flag = ref.flag
        let label = ref.label?.rawValue
        try MetadataIO.writeFavorite(favorite, to: ref.url)
        syncSidecar(flag: flag, favorite: favorite, label: label, for: ref.url)
        return UndoableOp(label: "Favorite",
                          inverse: .restoreMark(.favorite, url: ref.url, flag: flag,
                                                favorite: before, label: label))
    }

    static func setLabel(_ label: ColorLabel?, on ref: PhotoRef) throws -> UndoableOp {
        let before = ref.label
        let flag = ref.flag, favorite = ref.favorite
        try MetadataIO.writeLabel(label, to: ref.url)
        syncSidecar(flag: flag, favorite: favorite, label: label?.rawValue, for: ref.url)
        return UndoableOp(label: "Label",
                          inverse: .restoreMark(.label, url: ref.url, flag: flag,
                                                favorite: favorite, label: before?.rawValue))
    }

    /// The sidecar follows the tags, when the preference is on (D-94). A
    /// failure here is deliberately swallowed: the judgment is already written
    /// where it counts, and a folder that will not take a `.xmp` must not make
    /// pressing `p` look like it failed.
    static func syncSidecar(flag: Flag?, favorite: Bool, label: String? = nil, for url: URL) {
        guard Preferences.writeSidecars else { return }
        try? XMPSidecar.write(flag: flag, favorite: favorite, label: label, for: url)
    }


    /// Full resolution, orientation applied, bit depth intact.
    /// `CGImageSourceCreateImageAtIndex` preserves 16-bit samples but ignores the
    /// orientation tag; the thumbnail API applies orientation but normalizes to
    /// 8-bit. Use the first where orientation is already upright, the second only
    /// where there is a rotation to bake in, and never pass a max size smaller
    /// than the image itself.
    private static func fullImage(_ source: CGImageSource) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation == 1 {
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if max(w, h) > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = max(w, h) }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Source metadata for a file whose pixels we just rewrote: everything the
    /// original carried (EXIF, GPS, ICC profile), minus the fields that now
    /// describe the old geometry.
    private static func carriedProperties(_ source: CGImageSource, quality: Double?) -> CFDictionary {
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyPixelWidth] = nil
        props[kCGImagePropertyPixelHeight] = nil
        // The pixels are upright now, so a leftover orientation tag would rotate twice.
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        return props as CFDictionary
    }

    // MARK: rotate

    /// Lossless where the container carries an orientation tag (JPEG, HEIC, TIFF):
    /// only the metadata block is rewritten. PNG is re-encoded, which is also lossless.
    static func rotate(_ url: URL, clockwise: Bool) throws -> UndoableOp {
        // Coordinated, because this replaces the photograph in place (D-214).
        try Coordinated.replacing(url) { try applyRotation($0, clockwise: clockwise) }
        return UndoableOp(label: "Rotate", inverse: .turn(url, clockwise: !clockwise))
    }

    static func applyRotation(_ url: URL, clockwise: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { throw Failure(message: "Can't read \(url.lastPathComponent).") }
        let ext = url.pathExtension.lowercased()
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        if ["jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(ext) {
            // Two sources, deliberately. Reading properties out of a source and
            // then handing that same source to CGImageDestinationCopyImageSource
            // makes the copy return false — no error, no written file — on files
            // carrying vendor blocks such as {ExifAux} and {PictureStyle}. Every
            // frame out of a Lumix does. The copy gets a source nothing has read
            // from.
            let reader = CGImageSourceCreateWithURL(url as CFURL, nil)
            let props = reader.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let current = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let next = rotated(current, clockwise: clockwise)
            guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, type, 1, nil) else {
                throw Failure(message: "Can't write \(url.lastPathComponent).")
            }
            var err: Unmanaged<CFError>?
            let ok = CGImageDestinationCopyImageSource(dest, source, [kCGImageDestinationOrientation: next] as CFDictionary, &err)
            guard ok else { throw Failure(message: "Rotate failed: \(err?.takeRetainedValue().localizedDescription ?? "ImageIO refused the copy")") }
        } else if ext == "png" || ext == "bmp" {
            // No orientation tag in these containers, so the pixels have to move.
            // PNG is lossless, and a 90° turn is a pure permutation of the grid,
            // so this costs nothing as long as depth and profile are preserved.
            guard let oriented = fullImage(source),
                  let turned = oriented.rotated(clockwise: clockwise),
                  let dest = CGImageDestinationCreateWithURL(tmp as CFURL, type, 1, nil)
            else { throw Failure(message: "Can't rotate \(url.lastPathComponent).") }
            CGImageDestinationAddImage(dest, turned, carriedProperties(source, quality: nil))
            guard CGImageDestinationFinalize(dest) else { throw Failure(message: "Rotate failed.") }
        } else {
            throw Failure(message: "Rotating \(ext.uppercased()) would re-encode it. Not supported.")
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    private static func rotated(_ o: UInt32, clockwise: Bool) -> UInt32 {
        let cw: [UInt32: UInt32] = [1: 6, 6: 3, 3: 8, 8: 1, 2: 5, 5: 4, 4: 7, 7: 2]
        if clockwise { return cw[o] ?? 6 }
        return cw.first { $0.value == o }?.key ?? 8
    }

    // MARK: crop

    /// Writes `<name>-crop.<ext>` beside the original. Never touches the original.
    static func cropCopy(_ url: URL, normalized rect: CGRect) throws -> (URL, UndoableOp) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Can't read \(url.lastPathComponent).") }
        guard let full = fullImage(source) else {
            throw Failure(message: "Can't decode \(url.lastPathComponent).")
        }
        let px = pixels(of: rect, in: full)
        guard px.width >= 1, px.height >= 1, let cropped = full.cropping(to: px) else { throw Failure(message: "Crop is empty.") }

        let (dest, type) = sibling(of: url, tagged: "crop")
        guard let d = CGImageDestinationCreateWithURL(dest as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write \(dest.lastPathComponent).")
        }
        // Quality 1.0 for the lossy containers. A JPEG or HEIC crop is a re-encode
        // either way (ImageIO has no MCU-aligned lossless crop), so the copy is one
        // generation down; the original is never touched.
        CGImageDestinationAddImage(d, cropped, carriedProperties(source, quality: 1.0))
        guard CGImageDestinationFinalize(d) else { throw Failure(message: "Crop failed.") }
        keepArrivalFrame(of: url, for: dest)
        return (dest, UndoableOp(label: "Crop", inverse: .trashCopy(dest)))
    }

    /// Writes the crop into the photograph itself, which is the second thing in
    /// the app that changes a file in place (D-239), and leaves the same record
    /// an overwritten adjustment does.
    ///
    /// The pixels cropped are the ones on disk under this name, not the kept
    /// original: a crop is drawn on the photograph as it is being looked at, so
    /// cropping one that was adjusted last week crops the adjusted frame. That
    /// is the difference from `adjustInPlace`, which re-develops the original
    /// every time because six numbers mean the same thing whatever they are
    /// applied to. A rectangle does not.
    ///
    /// Which is also why the recipe comes off and the crop mark goes on. Left
    /// where it was, the recipe would open the panel at six numbers already
    /// baked into these pixels and apply them a second time, and the next
    /// adjustment would develop the uncropped original and put the cropped-out
    /// corner back. `AdjustRecord.base` reads the mark; `editable` reads the
    /// absent recipe.
    ///
    /// The first crop into a photograph keeps its original the way the first
    /// adjustment does — copied aside *before* a byte is written, which is the
    /// part that must not change — and that copy is both the undo and what
    /// Revert reads next week. A photograph that already has one keeps it: the
    /// original is the frame as it arrived, not the frame as it was a minute
    /// ago, so a second crop backs up to the session folder instead.
    ///
    /// Coordinated, because this replaces the photograph in place (D-214).
    static func cropInPlace(_ url: URL, normalized rect: CGRect) throws -> UndoableOp {
        var op: UndoableOp?
        try Coordinated.replacing(url) { op = try cropInPlaceUncoordinated($0, normalized: rect) }
        guard let op else { throw Failure(message: "Couldn't save over \(url.lastPathComponent).") }
        return op
    }

    private static func cropInPlaceUncoordinated(_ url: URL, normalized rect: CGRect) throws -> UndoableOp {
        let ext = url.pathExtension.lowercased()
        guard !["gif", "webp", "bmp"].contains(ext) else {
            throw Failure(message: "Writing a cropped \(ext.uppercased()) over the original would re-encode it into a format it cannot hold. Save a copy instead.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Failure(message: "Can't read \(url.lastPathComponent).")
        }
        guard let full = fullImage(source) else {
            throw Failure(message: "Can't decode \(url.lastPathComponent).")
        }
        guard let cropped = full.cropping(to: pixels(of: rect, in: full)) else {
            throw Failure(message: "Crop is empty.")
        }
        let kept = AdjustRecord.original(for: url)
        let backup = kept == nil
            ? AdjustRecord.originalURL(for: url)
            : sessionBackup(for: url)
        try FileManager.default.copyItem(at: url, to: backup)

        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let type = UTType(filenameExtension: ext) ?? .jpeg
        guard let d = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write \(url.lastPathComponent).")
        }
        CGImageDestinationAddImage(d, cropped, carriedProperties(source, quality: 1.0))
        guard CGImageDestinationFinalize(d) else { throw Failure(message: "Crop failed.") }
        // `replaceItemAt` rather than a move, so the flag, the favorite and the
        // color label stay on the photograph (D-3). The marks go on afterwards
        // for the same reason they do in `adjustInPlace`: written to the
        // temporary file, they are what the replace throws away.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try? AdjustRecord.clear(for: url)
        try AdjustRecord.markDerived(url)
        return UndoableOp(label: "Crop", inverse: .all([.moveBack(from: backup, to: url), .trash(url)]))
    }

    /// The rectangle a normalized crop means in an image's own pixels. One
    /// definition for the copy and for the overwrite: two would be two crops.
    private static func pixels(of rect: CGRect, in image: CGImage) -> CGRect {
        CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
               width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height)).integral
    }

    /// Gives a copy the frame the photograph it came from arrived as, so Revert
    /// on that copy reaches the original rather than the edit it was made from
    /// (D-243).
    ///
    /// Cloned rather than copied where the filesystem can: `copyfile` with
    /// `COPYFILE_CLONE` costs no data blocks and a fraction of a millisecond on
    /// APFS — 500MB of clones measured as 0MB of free space — and falls back to
    /// a real byte copy on a card formatted as exFAT, which is where the cost
    /// is real. Neither file is ever written to again, so the blocks stay
    /// shared for as long as both exist.
    ///
    /// The copy is marked derived at the same time. Its pixels are downstream
    /// of what it now keeps beside it, so an adjustment must develop the copy
    /// rather than the frame it inherited.
    ///
    /// Best effort, deliberately: a copy is written and a copy that could not
    /// take its record with it is still a copy. What it loses is Revert, which
    /// is what it had before this.
    static func keepArrivalFrame(of source: URL, for copy: URL) {
        let arrival = AdjustRecord.arrival(of: source)
        let dest = AdjustRecord.originalURL(for: copy)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        let ok = arrival.withUnsafeFileSystemRepresentation { from in
            dest.withUnsafeFileSystemRepresentation { to in
                copyfile(from, to, nil, copyfile_flags_t(COPYFILE_CLONE))
            }
        }
        guard ok == 0 else { return }
        try? AdjustRecord.markDerived(copy)
    }

    /// Where a copy of `url` goes, and what container it goes in.
    ///
    /// Crop was the only thing writing one of these; adjust is the second, and
    /// the naming is the part that must not drift between them. GIF, WebP and
    /// BMP come out as PNG because re-encoding to those is lossy or
    /// unsupported, and a name already taken takes a number.
    private static func sibling(of url: URL, tagged tag: String) -> (URL, UTType) {
        let ext = url.pathExtension.lowercased()
        let outExt = ["gif", "webp", "bmp"].contains(ext) ? "png" : ext
        let type = UTType(filenameExtension: outExt) ?? .png
        var dest = url.deletingPathExtension().appendingPathExtension("\(tag).\(outExt)")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = url.deletingPathExtension().appendingPathExtension("\(tag)\(n).\(outExt)"); n += 1
        }
        return (dest, type)
    }

    // MARK: adjust

    /// Writes `<name>.adjust.<ext>` beside the original. Never touches the
    /// original, for the reason crop does not: six slider positions are not an
    /// inverse, so the only honest undo is the copy going to the Trash (D-161).
    static func adjustCopy(_ url: URL, _ adjustments: Adjustments) throws -> (URL, UndoableOp) {
        guard !adjustments.isNeutral else {
            throw Failure(message: "Nothing to save: every slider is at 0.")
        }
        // The kept original when this photograph has been overwritten before,
        // so a copy taken afterwards is one generation down rather than two
        // (D-165).
        let base = AdjustRecord.base(for: url)
        guard let source = CGImageSourceCreateWithURL(base as CFURL, nil) else {
            throw Failure(message: "Can't read \(url.lastPathComponent).")
        }
        guard let full = fullImage(source) else {
            throw Failure(message: "Can't decode \(url.lastPathComponent).")
        }
        guard let rendered = adjustments.render(full) else {
            throw Failure(message: "Couldn't render the adjustment for \(url.lastPathComponent).")
        }
        let (dest, type) = sibling(of: url, tagged: "adjust")
        guard let d = CGImageDestinationCreateWithURL(dest as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write \(dest.lastPathComponent).")
        }
        // Quality 1.0, the same as a crop and for the same reason: the copy is
        // one generation down whatever we do, so it is one generation down at
        // the best quality the container has.
        CGImageDestinationAddImage(d, rendered, carriedProperties(source, quality: 1.0))
        guard CGImageDestinationFinalize(d) else { throw Failure(message: "Adjust failed.") }
        keepArrivalFrame(of: url, for: dest)
        return (dest, UndoableOp(label: "Adjust", inverse: .trashCopy(dest)))
    }

    /// Where an original goes before something is written over it, so the
    /// overwrite has an inverse to ship with (D-163).
    ///
    /// One folder per run. The undo stack is this sitting's and does not
    /// survive a quit (D-108), so what it points at does not need to either —
    /// and an inverse whose folder has gone says so rather than failing as
    /// whatever error the filesystem happens to raise (`Inverse.missingFolder`).
    /// The name is unguessable and the directory is the owner's alone (D-173).
    /// It used to be `$TMPDIR/Sift-originals-<pid>`, and
    /// `createDirectory(withIntermediateDirectories: true)` succeeds on a path
    /// that is already there — including one somebody else made first, as a
    /// symlink pointing somewhere they can read. Launched by launchd `$TMPDIR`
    /// is per-user and mode 700, so that was theory; run from a shell with
    /// `TMPDIR` unset it is `/tmp`, which is world-writable, and it was not.
    /// Injectable, and locked, for one reason each (D-242). A test that
    /// exercised the real directory would be deleting the one the rest of the
    /// suite is copying into, and the cleanup and a backup can otherwise land
    /// between each other's two steps — check the directory, then write.
    nonisolated(unsafe) static var sessionBackups: URL = makeSessionDirectory()
    private static let sessionLock = NSLock()

    private static func makeSessionDirectory() -> URL {
        let fm = FileManager.default
        // `.itemReplacementDirectory` is the system's own answer: a fresh
        // directory with a name nobody can predict, created for this process.
        // The fallback is a UUID for the same reason, not the process id.
        let dir = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                               appropriateFor: fm.homeDirectoryForCurrentUser, create: true))
            ?? fm.temporaryDirectory.appendingPathComponent("Sift-originals-\(UUID().uuidString)")
        make(dir)
        return dir
    }

    /// The file that says which process a backup directory belongs to.
    ///
    /// The cleanup on quit only runs on a quit (`applicationWillTerminate`),
    /// and a crash, a force-quit or a logout that takes a hung app never
    /// reaches it — so full-size copies of somebody's photographs sat in the
    /// temporary area until the system's own sweep got to them, which for an
    /// item-replacement directory can be days. A launch sweeps what the last
    /// one left (D-299).
    ///
    /// **Where** the last session's directory was is `Preferences`' job, because
    /// it cannot be found by looking: `.itemReplacementDirectory` puts it inside
    /// `TemporaryItems`, and that folder refuses `contentsOfDirectory` with
    /// `Operation not permitted` even for the process that owns a directory in
    /// it. The first version of this swept the siblings of its own directory,
    /// passed its unit test against an ordinary temporary folder, and could
    /// never have removed anything in a real launch.
    ///
    /// **Whether it may be deleted** is this file's job. A path read back out of
    /// a preference is a path somebody could have edited, and the sweep removes
    /// a directory whole, so the marker is the proof that the directory is one
    /// of ours before anything is taken.
    ///
    /// **A pid and not an age.** Sift can be running twice (`open -n`), and a
    /// session left open for a week is exactly the one an age cutoff would
    /// throw away — taking the undo stack that points at it with it. A pid that
    /// no longer answers `kill(pid, 0)` is a session that ended.
    static let sessionMarker = "sift-session.pid"

    /// Leaves this process's name on the directory, so the next launch can tell
    /// whether the session that made it is still running.
    private static func markSession(_ dir: URL) {
        let marker = dir.appendingPathComponent(sessionMarker)
        try? Data("\(ProcessInfo.processInfo.processIdentifier)".utf8)
            .write(to: marker, options: .atomic)
    }

    /// `withIntermediateDirectories: false` so this fails rather than adopts a
    /// directory that already exists. The one the system just made is exactly
    /// that case, which is why the permissions are set after as well:
    /// `createDirectory` applies attributes only to what it creates.
    private static func make(_ dir: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: false,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    /// Takes away the backup directories of sessions that are over (D-299).
    ///
    /// Given the paths the last sessions wrote down, removes the ones whose
    /// process is no longer running and answers which it took, so the caller
    /// can strike them off the list. Two conditions, and a directory has to
    /// pass both:
    ///
    /// **The marker has to be there.** A path out of a preference is a path
    /// somebody could have edited, and this method deletes a directory whole.
    /// The marker is the proof the directory is one of ours.
    ///
    /// **And the pid in it has to be dead.** Sift can be running twice, and the
    /// other instance's backups are its undo stack. An age cutoff would have
    /// thrown away exactly the session most worth keeping, the one left open
    /// for a week.
    static func forgetEndedSessions(at paths: [String]) -> [String] {
        var swept: [String] = []
        for path in paths {
            let dir = URL(fileURLWithPath: path)
            let marker = dir.appendingPathComponent(sessionMarker)
            guard let text = try? String(contentsOf: marker, encoding: .utf8),
                  let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                // No marker, so this is never going to be swept whatever else
                // happens: either the directory is gone, or it is not ours to
                // delete. Either way the entry buys nothing and keeping it is
                // how the list grows by one a launch and never shrinks.
                swept.append(path)
                continue
            }
            // `kill(pid, 0)` sends nothing and answers whether it could. ESRCH
            // is nobody there; EPERM is somebody there we may not signal, which
            // is still somebody there, so only ESRCH sweeps.
            if kill(pid, 0) == 0 || errno == EPERM { continue }
            forgetBackups(in: dir)
            swept.append(path)
        }
        return swept
    }

    /// Points the session directory at one the caller owns, and takes it away
    /// when the process exits.
    ///
    /// The suite exercises the real `sessionBackups`, so every `swift test` left
    /// a directory behind holding a copy of whatever it had cropped: the
    /// thirty-six that turned up under the old naming were these, and the
    /// mechanism outlived the rename. Nothing in the app sweeps them, because
    /// the sweep reads a path out of `Preferences` and the suite runs on a
    /// scratch domain that is wiped at the start of every run (D-299).
    ///
    /// Idempotent and called from the suites that touch it, the shape
    /// `Preferences.useTestDefaults()` already has. `atexit` rather than a
    /// `deinit`, because the directory is one piece of state shared by every
    /// suite in the process and a per-test teardown would be pulling it out
    /// from under whatever else is mid-write.
    nonisolated(unsafe) private static var usingTestBackups = false
    static func useTestBackups() {
        sessionLock.withLock {
            guard !usingTestBackups else { return }
            usingTestBackups = true
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("sift-test-backups-\(UUID().uuidString)")
            make(dir)
            sessionBackups = dir
            let path = dir.path
            atexit_b { try? FileManager.default.removeItem(atPath: path) }
        }
    }

    /// The launch-time sweep. Puts this session's directory on the list, takes
    /// the ended sessions' directories away, and strikes them off.
    static func forgetEndedSessions() {
        let mine = sessionLock.withLock { () -> URL in
            let dir = sessionBackups
            if !FileManager.default.fileExists(atPath: dir.path) { make(dir) }
            markSession(dir)
            return dir
        }
        // Registering is synchronous: a crash before this line leaves a
        // directory nothing knows about, and the window between marking and
        // registering should be as short as it can be.
        let others = Preferences.registerSessionBackups(mine.path)
        guard !others.isEmpty else { return }
        // The removal is not. What is being deleted is the last session's
        // undo backups, which are full-size copies of photographs and can run
        // to hundreds of megabytes, and this is called from
        // `applicationDidFinishLaunching` — on the main thread, before the
        // window is up. Nothing waits on the answer, and every path in
        // `others` belongs to a session that is not this one, so there is
        // nothing here for the app to race with (D-299).
        Task.detached(priority: .utility) {
            Preferences.forgetSessionBackups(forgetEndedSessions(at: others))
        }
    }

    /// Whether anything is in there, so quitting an app that never overwrote a
    /// photograph does not go looking for a directory to delete.
    nonisolated(unsafe) private static var keptAnything = false

    /// Takes the session's backups away when the app quits (D-242).
    ///
    /// They are copies of the reader's photographs at full size, and the undo
    /// stack that points at them does not survive a quit (D-108), so after one
    /// they are pixels with no purpose sitting in the temporary area until the
    /// machine reboots or the system's own sweep gets to them — which for an
    /// item-replacement directory can be days. The first overwrite's backup is
    /// not in here: that one is the kept original beside the photograph, which
    /// is the reader's to delete and what Revert reads next week.
    /// Unconditional since D-299, where `keptAnything` used to guard it. The
    /// launch now creates and marks the directory whether or not anything is
    /// ever written into it, so the guard would leave one empty marked
    /// directory behind per clean quit — the opposite of the thing it was
    /// added to avoid. `keptAnything` still answers what it is named for, which
    /// is whether anything is *in* there, and `sessionBackupDirectory` still
    /// reads it.
    static func forgetSessionBackups() {
        let mine = sessionLock.withLock { () -> URL in
            forgetBackups(in: sessionBackups)
            keptAnything = false
            return sessionBackups
        }
        // And off the list, or the next launch reads a path to a directory that
        // is not there and carries the entry forever (D-299).
        Preferences.forgetSessionBackups([mine.path])
    }

    /// The removal itself, which is what the test drives — on a directory of
    /// its own, because a test that deleted the running suite's backups would
    /// be taking files out from under the other tests writing into them.
    static func forgetBackups(in dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The session directory, or nil while nothing has been put in it. For the
    /// test that holds the cleanup to what is on disk rather than to the flag
    /// the cleanup itself sets.
    static var sessionBackupDirectory: URL? {
        sessionLock.withLock { keptAnything ? sessionBackups : nil }
    }

    /// Where a backup for this session goes. The directory is remade if it has
    /// gone — a quit is not the only thing that can take a temporary directory
    /// away — so a write is never refused for want of somewhere to put the
    /// bytes it is about to replace.
    private static func sessionBackup(for url: URL) -> URL {
        sessionLock.withLock {
            keptAnything = true
            if !FileManager.default.fileExists(atPath: sessionBackups.path) { make(sessionBackups) }
            // Remade directories lose the marker with everything else, and an
            // unmarked directory is one no later launch will sweep (D-299).
            markSession(sessionBackups)
            return sessionBackups.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        }
    }

    /// Writes the adjustment over the original, which is the one operation in
    /// the app that changes a photograph in place (D-163), and leaves the
    /// record that makes it re-editable next week (D-165).
    ///
    /// The render is of `AdjustRecord.base`, not of what is on disk under this
    /// name: the second overwrite of a photograph develops the kept original
    /// again rather than adjusting an already-adjusted file, so the six
    /// numbers always mean the same thing and ten overwrites are one
    /// generation down rather than ten.
    ///
    /// The first overwrite's kept original is also its undo. It is copied
    /// aside *before* a byte is written, which is the part that must not
    /// change: a failure between the two is the one that costs a photograph.
    /// A later overwrite has an original already kept, so its undo backup is
    /// the session-scoped copy instead — and because `copyItem` carries
    /// extended attributes, moving that backup home brings the recipe that was
    /// on the file back with it.
    ///
    /// The inverse is two steps because it has to be: the adjusted file is
    /// sitting at the name the original wants back, so undo trashes it and
    /// then moves the original home. `.all` runs its parts last-first. The
    /// adjusted version goes to the Trash rather than being deleted, for the
    /// reason a copy's undo does: undo is not the one command in the app that
    /// destroys something outright.
    /// Coordinated, because this replaces the photograph in place (D-214). The
    /// body is `adjustInPlaceUncoordinated`, so the inverse — which restores
    /// the kept original over the adjusted file — can take the same lock.
    static func adjustInPlace(_ url: URL, _ adjustments: Adjustments) throws -> UndoableOp {
        var op: UndoableOp?
        try Coordinated.replacing(url) { op = try adjustInPlaceUncoordinated($0, adjustments) }
        guard let op else { throw Failure(message: "Couldn't save over \(url.lastPathComponent).") }
        return op
    }

    private static func adjustInPlaceUncoordinated(_ url: URL, _ adjustments: Adjustments) throws -> UndoableOp {
        guard !adjustments.isNeutral else {
            throw Failure(message: "Nothing to save: every slider is at 0.")
        }
        let ext = url.pathExtension.lowercased()
        guard !["gif", "webp", "bmp"].contains(ext) else {
            throw Failure(message: "Writing an adjusted \(ext.uppercased()) over the original would re-encode it into a format it cannot hold. Save a copy instead.")
        }
        let kept = AdjustRecord.original(for: url)
        // `base`, not the kept original directly: a photograph that has been
        // cropped in place since develops the cropped pixels, or this write
        // would put the cropped-out corner back (D-239).
        let base = AdjustRecord.base(for: url)
        guard let source = CGImageSourceCreateWithURL(base as CFURL, nil) else {
            throw Failure(message: "Can't read \(url.lastPathComponent).")
        }
        guard let full = fullImage(source) else {
            throw Failure(message: "Can't decode \(url.lastPathComponent).")
        }
        guard let rendered = adjustments.render(full) else {
            throw Failure(message: "Couldn't render the adjustment for \(url.lastPathComponent).")
        }
        // Where the bytes that are about to be replaced go. The first
        // overwrite's backup *is* the kept original, so one copy serves both
        // the undo and every later re-edit; a later one keeps its backup for
        // the session only, because the original it would be is already kept.
        let backup = kept == nil
            ? AdjustRecord.originalURL(for: url)
            : sessionBackup(for: url)
        try FileManager.default.copyItem(at: url, to: backup)

        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let type = UTType(filenameExtension: ext) ?? .jpeg
        guard let d = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write \(url.lastPathComponent).")
        }
        CGImageDestinationAddImage(d, rendered, carriedProperties(source, quality: 1.0))
        guard CGImageDestinationFinalize(d) else { throw Failure(message: "Adjust failed.") }
        // `replaceItemAt` rather than a move, so the file keeps the original's
        // extended attributes — which is where the flag, the favorite and the
        // color label live (D-3). Rotation writes in place the same way. The
        // recipe goes on after the replace for that same reason: written to
        // the temporary file it would be the thing the replace discards.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try AdjustRecord.write(adjustments, for: url)
        return UndoableOp(label: "Adjust", inverse: .all([.moveBack(from: backup, to: url), .trash(url)]))
    }

    /// Puts the kept original back and takes the record off: the undo an
    /// overwrite gets in a session it was not made in (D-165).
    ///
    /// The adjusted file goes somewhere safe first, the way the overwrite put
    /// the original there, because a revert is a write over a photograph too.
    /// Undoing one has to rebuild both halves of the record, so its inverse
    /// copies the restored original aside again before the adjusted file goes
    /// back over it — the recipe rides home on the backup's own extended
    /// attributes.
    ///
    /// Flags, favorites and labels are the live file's and stay that way: a
    /// photograph flagged after it was adjusted keeps that flag through the
    /// revert, because `replaceItemAt` keeps the metadata of the file being
    /// replaced rather than of the one replacing it.
    static func revertAdjust(_ url: URL) throws -> UndoableOp {
        guard let kept = AdjustRecord.original(for: url) else {
            throw Failure(message: "No original is kept for \(url.lastPathComponent).")
        }
        let ext = url.pathExtension.lowercased()
        let backup = sessionBackup(for: url)
        try FileManager.default.copyItem(at: url, to: backup)

        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(at: kept, to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try? AdjustRecord.clear(for: url)
        // And the crop mark, for the same reason the recipe comes off: the
        // pixels under this name are the original's again, so nothing about
        // them has been cropped (D-239).
        try? AdjustRecord.clearDerived(for: url)
        try? FileManager.default.removeItem(at: kept)
        // Three steps, run last-first: the restored original is copied back to
        // the hidden file, the copy sitting at the photograph's name goes to
        // the Trash, and the adjusted version moves home with its recipe still
        // on it. `moveBack` refuses to write over something, which is what
        // makes the middle step necessary rather than tidy.
        return UndoableOp(label: "Revert",
                          inverse: .all([.moveBack(from: backup, to: url),
                                         .trash(url),
                                         .copyAside(from: url, to: kept)]))
    }

    // MARK: misc

    static func revealInFinder(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    /// Where a copy goes. The system pasteboard in the app; the test suite
    /// points this at one of its own, because a pasteboard is shared with
    /// everything else running on the machine and a test run has no business
    /// throwing away what somebody had on their clipboard (D-54).
    @MainActor static var pasteboard: NSPasteboard = .general

    @MainActor
    static func copyToPasteboard(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    static func openWithDefaultApp(_ urls: [URL]) { urls.forEach { NSWorkspace.shared.open($0) } }

    /// The photographs themselves, rather than references to their files.
    ///
    /// `copyToPasteboard` writes file URLs, which is what Finder pastes and
    /// what `⌘V` inside Sift reads. Nothing about that is a picture: a paste
    /// into Mail or a chat window gets an attachment where a picture was meant.
    /// This writes each frame's own bytes under its own type, so the receiving
    /// app decodes exactly the file on disk — no re-encode, no lost EXIF, and
    /// no quality spent on a trip through the clipboard.
    ///
    /// A single copy also carries a TIFF, for the apps that read only the older
    /// bitmap types. Only a single one: a TIFF of a 25-megapixel frame is about
    /// 100MB, which is worth paying once as a fallback and is not worth paying
    /// six times for a selection nobody is going to paste six pictures of.
    @MainActor
    static func copyImagesToPasteboard(_ urls: [URL]) {
        pasteboard.clearContents()
        var items: [NSPasteboardItem] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let type = UTType(filenameExtension: url.pathExtension)
            else { continue }
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
            // The name rides along, so a paste into a text field says which
            // photograph it was rather than dropping nothing at all.
            item.setString(url.lastPathComponent, forType: .string)
            if urls.count == 1, let tiff = NSImage(contentsOf: url)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            items.append(item)
        }
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    /// Plain text, so it pastes into a terminal or a text field as a usable path.
    @MainActor
    static func copyText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private extension CGImage {
    /// A 90° turn into a context matching this image's own depth, color space, and
    /// alpha, with interpolation off. Same pixels, different order.
    func rotated(clockwise: Bool) -> CGImage? {
        let w = height, h = width
        let space = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let gray = space.model == .monochrome
        let opaque = alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast
        var info: UInt32 = gray
            ? CGImageAlphaInfo.none.rawValue
            : (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
        if bitsPerComponent == 16 { info |= CGBitmapInfo.byteOrder16Little.rawValue }

        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
                            space: space, bitmapInfo: info)
            // 16-bit gray and exotic profiles can be refused; 8-bit sRGB always works.
            ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { return nil }

        ctx.interpolationQuality = .none
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: (clockwise ? -1 : 1) * .pi / 2)
        ctx.draw(self, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height)))
        return ctx.makeImage()
    }
}
