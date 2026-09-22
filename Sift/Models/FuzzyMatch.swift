import Foundation

/// Subsequence matching for the jump sheet: "d2" finds "Day 2", "ice" finds
/// "Iceland 2026". Scored so that a run of letters at the start of a word beats
/// the same letters scattered through the middle.
enum FuzzyMatch {
    /// Nil when the needle is not a subsequence of the name. Higher is better.
    static func score(_ needle: String, in name: String) -> Int? {
        let needle = Array(needle.lowercased())
        guard !needle.isEmpty else { return 0 }
        let chars = Array(name.lowercased())
        var score = 0
        var n = 0
        var lastHit = -2
        for (i, c) in chars.enumerated() {
            guard n < needle.count, c == needle[n] else { continue }
            score += 10
            if i == lastHit + 1 { score += 8 }                       // a run reads as one word
            if i == 0 { score += 12 }                                // the name starts with it
            else if !chars[i - 1].isLetter && !chars[i - 1].isNumber { score += 6 }  // a word does
            lastHit = i
            n += 1
        }
        guard n == needle.count else { return nil }
        // A short name matching the whole needle is a better answer than a long one.
        return score - max(0, chars.count - needle.count) / 4
    }
}
