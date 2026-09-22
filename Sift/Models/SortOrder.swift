import Foundation

/// Which way round a sort runs.
///
/// Not ascending and descending. Those are the right words for a column of
/// numbers and the wrong ones for six different fields: ascending sharpness is
/// the blurred frames first, which nobody would guess, and ascending dates is
/// a question about the calendar rather than about the shoot. `natural` is
/// whichever way round the field was already sorted before there was a choice,
/// so nothing moved when this arrived, and the menu names what each one
/// actually does — oldest first, largest first, sharpest first (D-349).
enum SortDirection: String, CaseIterable, Sendable {
    case natural, reversed

    var flipped: SortDirection { self == .natural ? .reversed : .natural }
}

enum SortOrder: String, CaseIterable, Sendable {
    case name, dateTaken, created, modified, size, sharpness

    var label: String {
        switch self {
        case .name: "Name"
        case .dateTaken: "Date taken"
        case .created: "Date created"
        case .modified: "Date modified"
        case .size: "Size"
        // Was "Sharpest first", which was the direction baked into the field's
        // name back when there was only one. The direction is its own row now.
        case .sharpness: "Sharpness"
        }
    }

    /// What a direction means for *this* field, in the words somebody choosing
    /// would use. A menu row saying "Descending" under a list of six fields
    /// makes the reader work out which end of which field it is about.
    func label(_ direction: SortDirection) -> String {
        let natural = direction == .natural
        switch self {
        case .name: return natural ? "A to Z" : "Z to A"
        case .dateTaken, .created, .modified: return natural ? "Oldest first" : "Newest first"
        case .size: return natural ? "Smallest first" : "Largest first"
        case .sharpness: return natural ? "Sharpest first" : "Softest first"
        }
    }

    func sort(_ photos: [PhotoRef], _ direction: SortDirection = .natural) -> [PhotoRef] {
        let ordered = sortedNaturally(photos)
        return direction == .natural ? ordered : reverse(ordered)
    }

    /// Reversing the finished order rather than flipping every comparison, so
    /// the two directions cannot disagree about anything but their order, and
    /// so the one field with a rule about missing values keeps it in both.
    private func reverse(_ photos: [PhotoRef]) -> [PhotoRef] {
        guard case .sharpness = self else { return photos.reversed() }
        // An unknown is not a winner, and it is not a loser either: a frame
        // nobody has measured yet stays at the end whichever way round the
        // measured ones are. Reversing the whole array would march every
        // unmeasured frame to the front of "softest first", which reads as an
        // answer and is the absence of one.
        let measured = photos.filter { $0.sharpness != nil }
        let unknown = photos.filter { $0.sharpness == nil }
        return measured.reversed() + unknown
    }

    private func sortedNaturally(_ photos: [PhotoRef]) -> [PhotoRef] {
        switch self {
        case .name:
            photos.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateTaken:
            // Falls back to creation date so undated files still land somewhere sensible.
            photos.sorted { ($0.dateTaken ?? $0.created) < ($1.dateTaken ?? $1.created) }
        case .created:
            photos.sorted { $0.created < $1.created }
        case .modified:
            photos.sorted { $0.modified < $1.modified }
        case .size:
            photos.sorted { $0.fileSize < $1.fileSize }
        case .sharpness:
            // Descending, because the only question this sort answers is
            // "which of these is the sharp one". A frame not yet measured
            // sorts last rather than first: an unknown is not a winner.
            photos.sorted { ($0.sharpness ?? -1) > ($1.sharpness ?? -1) }
        }
    }
}

enum PhotoFilter: Hashable, Sendable {
    case all, keep, reject, unflagged, favorite
    case colored(ColorLabel)

    var label: String {
        switch self {
        case .all: "All"
        case .keep: "Keep"
        case .reject: "Reject"
        case .unflagged: "Unflagged"
        case .favorite: "Favorites"
        case .colored(let c): c.rawValue
        }
    }

    static let menuCases: [PhotoFilter] = [.all, .keep, .reject, .unflagged, .favorite]
        + ColorLabel.allCases.map { .colored($0) }

    func includes(_ p: PhotoRef) -> Bool {
        switch self {
        case .all: true
        case .keep: p.flag == .keep
        case .reject: p.flag == .reject
        case .unflagged: p.flag == nil
        case .favorite: p.favorite
        case .colored(let c): p.label == c
        }
    }
}
