import Foundation
import ImageIO

struct ExifInfo: Sendable {
    var width: Int?
    var height: Int?
    var camera: String?
    var lens: String?
    var dateTaken: Date?
    var exposure: String?
    var aperture: String?
    var iso: Int?
    var focalLength: String?
    var latitude: Double?
    var longitude: Double?

    /// One line of the info panel. `measured` is what decides whether the
    /// value is set in monospace: DESIGN says monospace is for code and for
    /// data that lines up in a column or gets compared character by character,
    /// and half of what a camera writes is neither. "1/250" and "ISO 400" are
    /// measurements a reader scans down a column of; "NIKON Z 6" and
    /// "Sep 16, 2026 at 10:56 AM" are a name and a sentence, and setting them
    /// in mono made the date wrap onto two lines it did not need (D-121).
    ///
    /// Carried here rather than decided in the view, because whether a value
    /// is a measurement is a fact about the value.
    struct Fact: Sendable, Equatable {
        let key: String
        let value: String
        let measured: Bool
    }

    var facts: [Fact] {
        var out: [Fact] = []
        func measured(_ key: String, _ value: String) { out.append(Fact(key: key, value: value, measured: true)) }
        func named(_ key: String, _ value: String) { out.append(Fact(key: key, value: value, measured: false)) }

        if let width, let height { measured("Size", "\(width) × \(height)") }
        if let camera { named("Camera", camera) }
        if let lens { named("Lens", lens) }
        if let dateTaken { named("Taken", dateTaken.formatted(date: .abbreviated, time: .shortened)) }
        if let exposure { measured("Exposure", exposure) }
        if let aperture { measured("Aperture", aperture) }
        if let iso { measured("ISO", "\(iso)") }
        if let focalLength { measured("Focal", focalLength) }
        if let latitude, let longitude {
            measured("GPS", String(format: "%.5f, %.5f", latitude, longitude))
        }
        return out
    }
}

enum EXIFReader {
    private static let exifDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func read(_ url: URL) -> ExifInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        var info = ExifInfo()
        info.width = props[kCGImagePropertyPixelWidth] as? Int
        info.height = props[kCGImagePropertyPixelHeight] as? Int

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        if let model { info.camera = (make.map { model.hasPrefix($0) ? model : "\($0) \(model)" }) ?? model }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            info.lens = exif[kCGImagePropertyExifLensModel] as? String
            if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String { info.dateTaken = exifDate.date(from: s) }
            if let t = exif[kCGImagePropertyExifExposureTime] as? Double {
                info.exposure = t >= 1 ? String(format: "%.1fs", t) : "1/\(Int((1 / t).rounded()))s"
            }
            if let f = exif[kCGImagePropertyExifFNumber] as? Double { info.aperture = String(format: "f/%.1f", f) }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { info.iso = iso }
            if let fl = exif[kCGImagePropertyExifFocalLength] as? Double { info.focalLength = String(format: "%.0f mm", fl) }
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            info.latitude = latRef == "S" ? -lat : lat
            info.longitude = lonRef == "W" ? -lon : lon
        }
        return info
    }

    static func dateTaken(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        return exifDate.date(from: s)
    }
}
