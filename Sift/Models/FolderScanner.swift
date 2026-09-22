import Foundation

/// How many photos a folder holds.
struct FolderPreview: Sendable, Equatable {
    let count: Int
    /// The first few photographs in the folder, by the same name order a
    /// folder opens in, so the tile shows the frames the grid will start with
    /// rather than whichever ones the file system handed back first (D-350).
    /// Empty for a folder with no photographs in it. At most `coverCount`:
    /// the tile draws one large and three small, and a fifth would be decoded
    /// for nobody (D-351).
    var covers: [PhotoRef] = []

    /// One lead frame and a strip of three.
    static let coverCount = 4

    var caption: String {
        switch count {
        case 0: "no photos"
        case 1: "1 photo"
        default: "\(count) photos"
        }
    }
}

/// Reads a folder and returns the images in it. Subfolders are opt-in.
enum FolderScanner {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp",
    ]

    static let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey, .tagNamesKey,
    ]

    /// One spelling per folder. `/private/var/folders/…` and `/var/folders/…`
    /// are the same place, and `contentsOfDirectory` hands back whichever it
    /// likes, so the folders this file returns go through here and every
    /// comparison elsewhere is against the same spelling (D-34).
    ///
    /// Photo URLs are deliberately left as scanned: a `URL` caches the resource
    /// values read through it, so handing back a copy would leave tags written
    /// through one instance invisible to another.
    static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Whether `folder` is `inner` or holds it somewhere below. Path prefixes
    /// with the separator put back on, because `/Users/a/Photos` is not inside
    /// `/Users/a/Photo` and `hasPrefix` on its own says it is.
    static func contains(_ folder: URL, _ inner: URL) -> Bool {
        let outer = folder.standardizedFileURL.path
        let under = inner.standardizedFileURL.path
        return under == outer || under.hasPrefix(outer == "/" ? "/" : outer + "/")
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func scan(_ folder: URL, recursive: Bool = false) throws -> [PhotoRef] {
        let keys = Array(resourceKeys)
        if recursive {
            guard let e = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            var out: [PhotoRef] = []
            for case let url as URL in e { if let r = ref(for: url) { out.append(r) } }
            return out
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )
        return urls.compactMap(ref(for:))
    }

    /// The visible subfolders of a folder, sorted the way Finder sorts them.
    /// Packages (a .app, a .photoslibrary) are files as far as walking goes.
    /// How many photos are under a folder, without building a `PhotoRef` for
    /// each. The ingest sheet asks before it has permission to do anything, so
    /// it asks the cheapest question it can (D-89).
    static func count(_ folder: URL, recursive: Bool) -> Int {
        (try? scan(folder, recursive: recursive).count) ?? 0
    }

    static func subfolders(of folder: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            guard let v = try? url.resourceValues(forKeys: keys) else { return false }
            return v.isDirectory == true && v.isPackage != true
        }
        .map(canonical)
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Whether a folder is worth putting in a menu: it holds photographs, or it
    /// holds folders, which means it leads somewhere (D-152).
    ///
    /// A shoot folder sits beside export directories, `.lrdata` bundles and
    /// directories of sidecars, and `⌘↓` listed all of them, so the menu that
    /// exists to get you into the photographs was mostly rows that open onto
    /// an empty grid. Dead ends are what it drops, not "folders with no
    /// photographs": an SD card's DCIM holds no images itself and is the way
    /// to every one of them.
    ///
    /// One `contentsOfDirectory` that stops at the first thing that answers,
    /// which is what makes this cheap enough to ask about every sibling while
    /// a menu is being built.
    static func leadsSomewhere(_ folder: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return false }
        for url in urls {
            if isImage(url) { return true }
            guard let v = try? url.resourceValues(forKeys: keys) else { continue }
            if v.isDirectory == true, v.isPackage != true { return true }
        }
        return false
    }

    /// What a subfolder holds, for the tile that stands for it. One level only —
    /// a folder of folders reads as empty, which is what it is as far as photos
    /// go.
    static func preview(of folder: URL) -> FolderPreview {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        let images = urls.filter(isImage)
        return FolderPreview(count: images.count,
                             covers: firstByName(images, limit: FolderPreview.coverCount)
                                 .compactMap(ref(for:)))
    }

    /// The `limit` smallest names, kept in order, without sorting the folder.
    ///
    /// A card can hold nineteen thousand frames and this runs on every tile
    /// (D-318). Sorting to take four of them is a comparison count nobody
    /// needs, and `localizedStandardCompare` is not a cheap comparison: this
    /// walks the list once, holding four.
    static func firstByName(_ urls: [URL], limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        var best: [URL] = []
        for url in urls {
            let name = url.lastPathComponent
            var at = best.count
            while at > 0,
                  name.localizedStandardCompare(best[at - 1].lastPathComponent) == .orderedAscending {
                at -= 1
            }
            guard at < limit else { continue }
            best.insert(url, at: at)
            if best.count > limit { best.removeLast() }
        }
        return best
    }

    static func ref(for url: URL) -> PhotoRef? {
        guard isImage(url) else { return nil }
        guard let v = try? url.resourceValues(forKeys: resourceKeys), v.isRegularFile == true else { return nil }
        return PhotoRef(
            url: url,
            fileSize: v.fileSize ?? 0,
            created: v.creationDate ?? .distantPast,
            modified: v.contentModificationDate ?? .distantPast,
            flag: MetadataIO.flag(fromTags: v.tagNames ?? []),
            favorite: MetadataIO.favorite(fromTags: v.tagNames ?? []),
            label: MetadataIO.label(fromTags: v.tagNames ?? [])
        )
    }
}
