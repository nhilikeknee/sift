import AppKit
import CoreGraphics
import Foundation

// Renders Resources/AppIcon.svg at every size with Core Graphics, so each one is
// drawn from the geometry rather than resampled from one bitmap. The SVG is the
// only place that geometry lives (D-249). The contract it has to keep: the first
// <rect> in document order is the plate, every rect after it is drawn in order
// clipped to that plate, and a missing attribute or a fill this script cannot
// read stops the build instead of drawing a default.

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

/// A rounded rectangle in the SVG's own user units.
struct Rounded {
    let x, y, width, height, radius: Double
    let fill: CGColor
}

func attribute(_ name: String, of element: XMLElement) -> String {
    guard let value = element.attribute(forName: name)?.stringValue else {
        die("<\(element.localName ?? "?")> has no \(name)")
    }
    return value
}

func number(_ name: String, of element: XMLElement) -> Double {
    let text = attribute(name, of: element)
    guard let value = Double(text) else {
        die("<\(element.localName ?? "?")> has \(name)=\"\(text)\", which is not a number")
    }
    return value
}

func color(_ text: String) -> CGColor {
    guard text.hasPrefix("#"), text.count == 7, let bits = UInt32(text.dropFirst(), radix: 16) else {
        die("fill=\"\(text)\" is not a #rrggbb color")
    }
    return CGColor(srgbRed: Double((bits >> 16) & 0xFF) / 255,
                   green: Double((bits >> 8) & 0xFF) / 255,
                   blue: Double(bits & 0xFF) / 255,
                   alpha: 1)
}

/// Every <rect> under `element`, in document order, however deeply grouped.
func rects(in element: XMLElement) -> [XMLElement] {
    (element.children ?? []).compactMap { $0 as? XMLElement }.flatMap { child in
        child.localName == "rect" ? [child] : rects(in: child)
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgURL = root.appendingPathComponent("Resources/AppIcon.svg")

let document: XMLDocument
do {
    document = try XMLDocument(contentsOf: svgURL)
} catch {
    die("could not read \(svgURL.path): \(error.localizedDescription)")
}

guard let svg = document.rootElement(), svg.localName == "svg" else {
    die("\(svgURL.lastPathComponent) does not start with an <svg>")
}

let box = attribute("viewBox", of: svg)
    .split(whereSeparator: { $0 == " " || $0 == "," })
    .compactMap { Double($0) }
guard box.count == 4 else { die("viewBox needs four numbers") }
guard box[0] == 0, box[1] == 0, box[2] == box[3] else {
    die("viewBox must start at 0 0 and be square; the icon is rendered square")
}
let extent = box[2]

let shapes = rects(in: svg).map {
    Rounded(x: number("x", of: $0), y: number("y", of: $0),
            width: number("width", of: $0), height: number("height", of: $0),
            radius: number("rx", of: $0), fill: color(attribute("fill", of: $0)))
}
guard let plate = shapes.first else { die("\(svgURL.lastPathComponent) has no <rect> to use as the plate") }
let frames = shapes.dropFirst()

func render(size: Int) -> CGImage {
    let s = Double(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip to top-left origin so the numbers match the SVG.
    ctx.translateBy(x: 0, y: CGFloat(s))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)

    func path(_ shape: Rounded) -> CGPath {
        CGPath(roundedRect: CGRect(x: shape.x / extent * s, y: shape.y / extent * s,
                                   width: shape.width / extent * s, height: shape.height / extent * s),
               cornerWidth: CGFloat(shape.radius / extent * s),
               cornerHeight: CGFloat(shape.radius / extent * s),
               transform: nil)
    }

    ctx.addPath(path(plate))
    ctx.setFillColor(plate.fill)
    ctx.fillPath()

    // Frames are clipped to the plate so a large one never bleeds past the corner.
    ctx.saveGState()
    ctx.addPath(path(plate))
    ctx.clip()
    for frame in frames {
        ctx.addPath(path(frame))
        ctx.setFillColor(frame.fill)
        ctx.fillPath()
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

let iconset = root.appendingPathComponent("build/Sift.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = base * scale
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try write(render(size: px), to: iconset.appendingPathComponent(name))
}

print("wrote \(iconset.path)")
