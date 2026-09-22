import Testing
import Foundation
import AppKit
import SwiftUI
@testable import Sift

/// A symbol is drawn at the step, not asked for at it (D-201).
///
/// `Glyph.extent` is a table of measurements, and a table of measurements is a
/// second place a fact lives. This is the first place: every number in it is
/// re-measured against the symbol the system actually ships, so a wrong row, a
/// missing row, or a symbol Apple redraws in a point release fails here rather
/// than going ragged on screen where nothing is watching.
@Suite struct GlyphExtentTests {
    /// The share of its own point size a symbol's ink takes on its larger side,
    /// rendered at 8x and measured off the pixels.
    private func extent(of name: String, at point: CGFloat) throws -> CGFloat {
        let symbol = try #require(NSImage(systemSymbolName: name, accessibilityDescription: nil)
            .flatMap { $0.withSymbolConfiguration(.init(pointSize: point, weight: .regular)) },
                                  "\(name) is not a symbol on this system")
        let scale = 8
        let w = Int(symbol.size.width.rounded(.up)) * scale
        let h = Int(symbol.size.height.rounded(.up)) * scale
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()

        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        try #require(x1 >= 0, "\(name) drew nothing at \(point)")
        let side = max(CGFloat(x1 - x0 + 1), CGFloat(y1 - y0 + 1)) / CGFloat(scale)
        return side / point
    }

    /// The row is what this is for: every mark's bounding box lands on the step
    /// it was asked for, whatever its point size had to be to get there.
    ///
    /// A twelfth, and not tighter, for two reasons that are both the set's.
    /// A symbol's extent drifts a little between one point size and the next —
    /// it is optically sized, so it is not one shape scaled — and one number
    /// per symbol cannot follow that. And the renderer quantizes to whole
    /// pixels, so a mark asked for at 27.9 comes back at 28. The worst miss is
    /// 7%. Before the table it was 67%, which is `xmark` at 0.81 of its point
    /// size standing next to `folder.badge.plus` at 1.35.
    @Test func everyMarkIsDrawnAtTheStepItIsAskedFor() throws {
        for name in Glyph.everySymbol {
            for step in Tokens.Layout.glyphSteps {
                let point = Glyph.pointSize(for: name, at: step)
                let drawn = try extent(of: name, at: point) * point
                #expect(abs(drawn - step) < step / 12,
                        "\(name) is drawn at \(drawn) when the step is \(step)")
            }
        }
    }

    /// And the table is what makes that true, so it has to be right and it has
    /// to be complete. A fortieth is tighter than the drift between one point
    /// size and the next, which is what a single number per symbol costs.
    @Test func theExtentTableMatchesTheSymbolsTheSystemShips() throws {
        for name in Glyph.everySymbol {
            let measured = try Tokens.Layout.glyphSteps
                .map { try extent(of: name, at: $0) }
                .reduce(0, +) / CGFloat(Tokens.Layout.glyphSteps.count)
            let stored = Glyph.pointSize(for: name, at: 1)
            #expect(stored != 1 || abs(measured - 1) < 0.025,
                    "\(name) has no row in Glyph.extent: measured \(measured)")
            #expect(abs(1 / stored - measured) < 0.025,
                    "\(name) is listed at \(1 / stored) and measures \(measured)")
        }
    }
}
