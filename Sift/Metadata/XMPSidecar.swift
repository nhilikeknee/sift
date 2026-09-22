import Foundation

/// A sidecar beside the photo, so Lightroom and Bridge read what Sift wrote
/// (D-94). Finder tags remain the truth (D-3); this is a translation of them
/// into the one format every other photo application reads.
///
/// Off by default. It writes a file into the shoot, which a viewer with no
/// catalog has otherwise never done, and that is the user's call to make.
enum XMPSidecar {
    /// `photo.jpg` gets `photo.xmp`, which is where Adobe looks. Not
    /// `photo.jpg.xmp`, which is where nothing looks.
    static func url(for photo: URL) -> URL {
        photo.deletingPathExtension().appendingPathExtension("xmp")
    }

    /// Lightroom's own numbers: -1 is Rejected and 5 is the top of the scale.
    /// Keep lands at 1 because "I am keeping this" is the smallest positive
    /// thing a rating can say, and a favorite at 5 because it is the largest.
    /// Nil means the photo has nothing to declare.
    static func rating(flag: Flag?, favorite: Bool) -> Int? {
        if flag == .reject { return -1 }
        if favorite { return 5 }
        if flag == .keep { return 1 }
        return nil
    }

    /// Writes the two fields Sift owns into the sidecar, and takes them out
    /// again when the photo has nothing left to declare.
    ///
    /// A sidecar that is already there belongs to whatever wrote it — Lightroom
    /// keeps develop settings, keywords and a crop in one — so it is edited
    /// rather than replaced (D-107). Only `xmp:Rating` and `xmp:Label` are
    /// touched; every other byte comes back out the way it went in.
    static func write(flag: Flag?, favorite: Bool, label: String? = nil, for photo: URL) throws {
        let dest = url(for: photo)
        let rating = rating(flag: flag, favorite: favorite)
        let existing = try? String(contentsOf: dest, encoding: .utf8)

        guard rating != nil || label != nil else {
            guard let existing else { return }
            // Ours and empty is a stale file and goes. Somebody else's keeps
            // everything but the two fields we put in it: a sidecar we did not
            // write is not ours to delete.
            if isOurs(existing) {
                try FileManager.default.removeItem(at: dest)
            } else {
                let stripped = setting("xmp:Label", to: nil, in: setting("xmp:Rating", to: nil, in: existing))
                try Data(stripped.utf8).write(to: dest, options: .atomic)
            }
            return
        }

        if let existing {
            var merged = setting("xmp:Rating", to: rating.map(String.init), in: existing)
            merged = setting("xmp:Label", to: label.map(escaped), in: merged)
            try Data(merged.utf8).write(to: dest, options: .atomic)
            return
        }

        var fields = ""
        if let rating { fields += "\n   xmp:Rating=\"\(rating)\"" }
        if let label { fields += "\n   xmp:Label=\"\(escaped(label))\"" }
        let xml = [
            "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>",
            "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"\(writer)\">",
            " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">",
            "  <rdf:Description rdf:about=\"\"",
            "   xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"\(fields)/>",
            " </rdf:RDF>",
            "</x:xmpmeta>",
            "<?xpacket end=\"w\"?>",
            ""
        ].joined(separator: "\n")
        try Data(xml.utf8).write(to: dest, options: .atomic)
    }

    /// What Sift stamps its own sidecars with, and how it recognizes one later.
    static let writer = "Sift"

    /// A sidecar nothing else has touched. Anything else is somebody's work.
    static func isOurs(_ text: String) -> Bool {
        text.contains("x:xmptk=\"\(writer)\"")
    }

    /// Sets one field in an existing packet, or takes it out when `value` is
    /// nil. XMP allows both an attribute on `rdf:Description` and a child
    /// element, and different applications write different ones, so both are
    /// recognized; a field that is in neither is added as an attribute.
    static func setting(_ key: String, to value: String?, in text: String) -> String {
        if let range = attributeRange(of: key, in: text) {
            guard let value else { return text.replacingCharacters(in: range, with: "") }
            return text.replacingCharacters(in: range, with: " \(key)=\"\(value)\"")
        }
        if let range = elementRange(of: key, in: text) {
            guard let value else { return text.replacingCharacters(in: range, with: "") }
            return text.replacingCharacters(in: range, with: "<\(key)>\(value)</\(key)>")
        }
        guard let value else { return text }
        return inserting(" \(key)=\"\(value)\"", intoDescriptionOf: text)
    }

    /// The whole attribute, leading whitespace included, so removing it does
    /// not leave a double space behind.
    private static func attributeRange(of key: String, in text: String) -> Range<String.Index>? {
        // `\s+` rather than `\s*`: an attribute always follows whitespace
        // inside a tag, and without it `xmp:Rating` would match the tail of
        // somebody else's prefix.
        range(#"\s+"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*"[^"]*""#, in: text)
    }

    private static func elementRange(of key: String, in text: String) -> Range<String.Index>? {
        let k = NSRegularExpression.escapedPattern(for: key)
        return range("<" + k + #"(\s[^>]*)?>[^<]*</"# + k + ">", in: text)
    }

    private static func range(_ pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return Range(match.range, in: text)
    }

    /// Adds an attribute to the first `rdf:Description` start tag, declaring
    /// the xmp namespace beside it when the packet has not already.
    private static func inserting(_ attribute: String, intoDescriptionOf text: String) -> String {
        guard let tag = range(#"<rdf:Description\b[^>]*?/?>"#, in: text) else { return text }
        var head = String(text[tag])
        let close = head.hasSuffix("/>") ? "/>" : ">"
        head.removeLast(close.count)
        if !text.contains("xmlns:xmp=") { head += " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"" }
        return text.replacingCharacters(in: tag, with: head + attribute + close)
    }

    /// Reads back what a sidecar claims, for the test and for anyone checking
    /// that the translation went the way they expected.
    static func read(for photo: URL) -> (rating: Int?, label: String?)? {
        guard let text = try? String(contentsOf: url(for: photo), encoding: .utf8) else { return nil }
        return (value("xmp:Rating", in: text).flatMap(Int.init), value("xmp:Label", in: text))
    }

    /// Either shape: the attribute on `rdf:Description`, or the child element
    /// some applications write instead. A merged sidecar keeps whichever shape
    /// it arrived in (D-107), so reading has to know both.
    static func value(_ key: String, in text: String) -> String? {
        if let start = text.range(of: "\(key)=\""),
           let end = text.range(of: "\"", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound])
        }
        guard let open = text.range(of: "<\(key)>"),
              let close = text.range(of: "</\(key)>", range: open.upperBound..<text.endIndex)
        else { return nil }
        return String(text[open.upperBound..<close.lowerBound])
    }

    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
