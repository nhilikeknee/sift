import Foundation

enum Flag: String, Sendable, Codable, CaseIterable {
    case keep = "Keep"
    case reject = "Reject"
}

/// The five color labels Lightroom has, named for the Finder tags they are
/// stored as, so Finder colors them too (D-96). Not a sixth flag: keep and
/// reject are a judgment about the photo, and a color is a judgment about where
/// it is going.
enum ColorLabel: String, Sendable, Codable, CaseIterable {
    case red = "Red"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
}

/// One image file on disk. The URL is the identity; flag, favorite and dateTaken
/// are read from the file (Finder tags, EXIF) and cached here.
struct PhotoRef: Identifiable, Hashable, Sendable {
    let url: URL
    let fileSize: Int
    let created: Date
    let modified: Date
    var flag: Flag? = nil
    var favorite = false
    var label: ColorLabel? = nil
    var dateTaken: Date? = nil
    /// Variance of a Laplacian over the thumbnail. Read lazily, like
    /// `dateTaken`, and only when something asks to sort by it (D-77).
    var sharpness: Double? = nil
    /// Read lazily, and only when somebody searches for one (D-98).
    var camera: String? = nil
    var lens: String? = nil
    var iso: Int? = nil

    var id: URL { url }
    /// What a view keys its decode on. The URL alone is not enough: a rotate
    /// replaces the bytes and leaves the name, so a view watching the URL keeps
    /// showing the frame it decoded before the turn. Size and mtime both move
    /// when the file is rewritten.
    var contentID: String { "\(url.path)|\(fileSize)|\(modified.timeIntervalSince1970)" }
    var name: String { url.lastPathComponent }
    var isAnimated: Bool { url.pathExtension.lowercased() == "gif" }

    func renamed(to newURL: URL) -> PhotoRef {
        var copy = self
        copy = PhotoRef(url: newURL, fileSize: fileSize, created: created, modified: modified,
                        flag: flag, favorite: favorite, label: label, dateTaken: dateTaken,
                        sharpness: sharpness, camera: camera, lens: lens, iso: iso)
        return copy
    }
}
