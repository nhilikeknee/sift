import Foundation

/// D-3: judgments live on the file, not in a database.
/// Flags are Finder tags ("Keep" / "Reject") and so is the favorite
/// ("Favorite"), all visible in Finder and findable in Spotlight.
///
/// The flag and the favorite are orthogonal — a photo can be kept and a
/// favorite, or a favorite and nothing else — so each write reads the file's
/// whole tag list, replaces only the tags it owns, and puts the rest back
/// (D-55).
enum MetadataIO {
    static let favoriteTag = "Favorite"

    static func flag(fromTags tags: [String]) -> Flag? {
        if tags.contains(Flag.keep.rawValue) { return .keep }
        if tags.contains(Flag.reject.rawValue) { return .reject }
        return nil
    }

    static func favorite(fromTags tags: [String]) -> Bool {
        tags.contains(favoriteTag)
    }

    static func label(fromTags tags: [String]) -> ColorLabel? {
        tags.compactMap(ColorLabel.init(rawValue:)).first
    }

    static func writeLabel(_ label: ColorLabel?, to url: URL) throws {
        try write(to: url) { tags in
            tags.removeAll { ColorLabel(rawValue: $0) != nil }
            if let label { tags.append(label.rawValue) }
        }
    }

    static func writeFlag(_ flag: Flag?, to url: URL) throws {
        try write(to: url) { tags in
            tags.removeAll { Flag(rawValue: $0) != nil }
            if let flag { tags.append(flag.rawValue) }
        }
    }

    static func writeFavorite(_ favorite: Bool, to url: URL) throws {
        try write(to: url) { tags in
            tags.removeAll { $0 == favoriteTag }
            if favorite { tags.append(favoriteTag) }
        }
    }

    /// Read, edit, write back. Tags this app knows nothing about — a color a
    /// person set in Finder, a tag from another tool — survive untouched.
    private static func write(to url: URL, _ edit: (inout [String]) -> Void) throws {
        var tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        edit(&tags)
        try (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
    }
}

enum Xattr {
    static func get(_ name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path in
            let len = getxattr(path, name, nil, 0, 0, 0)
            guard len > 0 else { return nil }
            var data = Data(count: len)
            let got = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, len, 0, 0) }
            return got == len ? data : nil
        }
    }

    static func set(_ name: String, _ data: Data, at url: URL) throws {
        let r = url.withUnsafeFileSystemRepresentation { path in
            data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
        }
        if r != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func remove(_ name: String, at url: URL) throws {
        let r = url.withUnsafeFileSystemRepresentation { removexattr($0, name, 0) }
        if r != 0 && errno != ENOATTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
