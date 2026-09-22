import Foundation

/// What `/` accepts (D-98). Bare words match the filename, the way they always
/// have. A `key:value` matches one field, so "camera:x-t5 iso:6400" is two
/// conditions and both have to hold.
///
/// Bridge and Lightroom filter by camera, lens and ISO; Sift was already
/// reading all three for the info panel and searching none of them.
struct PhotoQuery: Sendable {
    /// Bare words, matched against the filename.
    var words: [String] = []
    var camera: String?
    var lens: String?
    /// A number, or a range written `iso:800-6400`.
    var isoRange: ClosedRange<Int>?
    /// A prefix of a formatted date, so `date:2026-09` is a month.
    var date: String?
    /// Anything typed after a key this does not know.
    var unknownKeys: [String] = []

    /// True when nothing but filename words were typed, which is the old
    /// behavior and the one that needs no EXIF.
    var isNameOnly: Bool { camera == nil && lens == nil && isoRange == nil && date == nil }
    var isEmpty: Bool { words.isEmpty && isNameOnly && unknownKeys.isEmpty }

    static let keys = ["camera", "lens", "iso", "date"]

    init(_ text: String) {
        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
            let piece = String(token)
            guard let colon = piece.firstIndex(of: ":"), colon != piece.startIndex else {
                words.append(piece)
                continue
            }
            let key = piece[piece.startIndex..<colon].lowercased()
            let value = String(piece[piece.index(after: colon)...])
            guard !value.isEmpty else { continue }
            switch key {
            case "camera": camera = value
            case "lens": lens = value
            case "iso": isoRange = Self.range(value)
            case "date": date = value
            default: unknownKeys.append(key)
            }
        }
    }

    private static func range(_ value: String) -> ClosedRange<Int>? {
        let parts = value.split(separator: "-", maxSplits: 1).map(String.init)
        if parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]), lo <= hi { return lo...hi }
        guard let n = Int(value) else { return nil }
        return n...n
    }

    /// Whether a folder answers this query. A folder has a name and nothing
    /// else, so only the bare words can match one: a query naming a camera or
    /// an ISO is a question about photographs, and no folder is an answer to
    /// it (D-318).
    func matchesFolder(named name: String) -> Bool {
        guard isNameOnly, unknownKeys.isEmpty else { return false }
        return words.allSatisfy { name.localizedCaseInsensitiveContains($0) }
    }

    func matches(_ p: PhotoRef) -> Bool {
        for word in words where !p.name.localizedCaseInsensitiveContains(word) { return false }
        if let camera, !(p.camera?.localizedCaseInsensitiveContains(camera) ?? false) { return false }
        if let lens, !(p.lens?.localizedCaseInsensitiveContains(lens) ?? false) { return false }
        if let isoRange {
            guard let iso = p.iso, isoRange.contains(iso) else { return false }
        }
        if let date {
            let taken = p.dateTaken ?? p.created
            guard Self.stamp(taken).hasPrefix(date) else { return false }
        }
        return true
    }

    /// `2026-09-14 18:32`, so a prefix is a year, a month, a day or an hour.
    static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}
