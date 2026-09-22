import Foundation
import CoreGraphics

/// Where every cell of one grid run sits, worked back from a single cell whose
/// frame was actually measured (D-106).
///
/// `LazyVGrid` builds only what is on screen, so a rubber band that asked the
/// measured frames what it had crossed could only ever select what had been
/// drawn: drag past the bottom edge and the selection stopped at the last row
/// the scroll view had got around to. The cells are on a lattice, though —
/// fixed size, fixed gap, fixed column count — so one measured cell fixes the
/// position of all of them, including the ones that do not exist yet.
///
/// One measured cell rather than a computed origin because the grid's own
/// leading edge depends on how `LazyVGrid` distributes the width left over
/// after the columns, which is SwiftUI's business and not a number to assume.
struct CellLattice: Equatable {
    /// The top-left of the cell at `range.lowerBound`.
    let firstOrigin: CGPoint
    /// A cell is not square any more: the thumbnail is, and the name sits
    /// under it (D-115). The two pitches are different and the band cares.
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let gap: CGFloat
    let columns: Int
    /// The photo indices this run lays out. A sectioned grid has one lattice
    /// per section, since each section starts its own rows.
    let range: Range<Int>

    private var pitchX: CGFloat { cellWidth + gap }
    private var pitchY: CGFloat { cellHeight + gap }

    /// Builds the lattice from one cell's measured frame. Nil when the anchor
    /// is not part of this run, or when the metrics could not lay anything out.
    init?(anchor index: Int, frame: CGRect, cellWidth: CGFloat, cellHeight: CGFloat,
          gap: CGFloat, columns: Int, range: Range<Int>) {
        guard columns > 0, cellWidth > 0, cellHeight > 0, range.contains(index) else { return nil }
        let local = index - range.lowerBound
        let row = local / columns
        let column = local % columns
        self.firstOrigin = CGPoint(x: frame.minX - CGFloat(column) * (cellWidth + gap),
                                   y: frame.minY - CGFloat(row) * (cellHeight + gap))
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.gap = gap
        self.columns = columns
        self.range = range
    }

    /// Where a photo's cell is, whether or not it has been drawn.
    func frame(of index: Int) -> CGRect? {
        guard range.contains(index) else { return nil }
        let local = index - range.lowerBound
        let row = CGFloat(local / columns)
        let column = CGFloat(local % columns)
        return CGRect(x: firstOrigin.x + column * pitchX,
                      y: firstOrigin.y + row * pitchY,
                      width: cellWidth, height: cellHeight)
    }

    /// Every photo the rectangle touches. Only the rows the rectangle's own
    /// height can reach are looked at, so a band over a folder of thousands
    /// costs the rows on screen rather than all of them.
    func indices(in rect: CGRect) -> [Int] {
        guard !range.isEmpty else { return [] }
        let lastRow = (range.count - 1) / columns
        let from = Int(floor((rect.minY - firstOrigin.y) / pitchY))
        let to = Int(floor((rect.maxY - firstOrigin.y) / pitchY))
        let rows = max(0, min(from, lastRow))...max(0, min(to, lastRow))
        guard rect.maxY >= firstOrigin.y else { return [] }

        var found: [Int] = []
        for row in rows {
            for column in 0..<columns {
                let index = range.lowerBound + row * columns + column
                guard range.contains(index), let frame = frame(of: index) else { continue }
                // The gaps between cells are not the cells: a band that covers
                // only the space between two photos has crossed neither.
                if frame.intersects(rect) { found.append(index) }
            }
        }
        return found
    }
}
