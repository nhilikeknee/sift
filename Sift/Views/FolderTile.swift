import SwiftUI

/// What a capped folder list says about the folders it is not drawing (D-318).
///
/// One line, under the tiles it belongs to, and absent when nothing was left
/// out. It names the filter rather than the key, because the filter has a
/// control in the toolbar and the key is the addition on top of it.
struct FolderOverflowNote: View {
    let shown: Int
    let leftOut: Int

    var body: some View {
        if leftOut > 0 {
            Text("Showing \(shown) of \(shown + leftOut) folders. Filter by name to find the one you want.")
                .textStyle(.quiet)
        }
    }
}

/// The subfolders of the open folder, as tiles you can click into. Shown where
/// a folder holds no photos of its own, which is what an SD card looks like
/// (D-31).
struct FolderGrid: View {
    let folders: [URL]
    /// The grid's own cell edge, so folders resize with the photos beside them.
    var size: CGFloat = Tokens.Layout.folderTile
    let openInTab: (URL) -> Void
    let open: (URL) -> Void

    /// Photo counts, read once off the main actor. A count is the one fact that
    /// decides which folder to open first.
    @State private var previews: [URL: FolderPreview] = [:]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: size), spacing: Tokens.Space.s12, alignment: .top)],
            spacing: Tokens.Space.s12
        ) {
            ForEach(folders, id: \.self) { folder in
                FolderTile(folder: folder,
                           preview: previews[folder],
                           size: size,
                           openInTab: { openInTab(folder) }) { open(folder) }
            }
        }
        .task(id: folders) {
            let found = await Task.detached(priority: .userInitiated) {
                folders.reduce(into: [URL: FolderPreview]()) { $0[$1] = FolderScanner.preview(of: $1) }
            }.value
            previews = found
        }
    }
}

/// The same tiles as a row above the photos, with the cursor able to sit in
/// them. The row is the ways in and only the ways in; going up is the header's
/// job (D-33, D-111).
struct FolderRow: View {
    let entries: [FolderEntry]
    var size: CGFloat = Tokens.Layout.folderTile
    /// How many columns the photographs below are on. The row is laid out on
    /// exactly those columns, so the first tile and the first photograph start
    /// at the same x (D-146).
    let columns: Int
    let cursor: Int?
    /// Which tile the keyboard is on, set by a single click (D-353).
    let select: (Int) -> Void
    let open: (URL) -> Void
    let openInTab: (URL) -> Void
    let drop: (URL, [URL]) -> Void

    @State private var previews: [URL: FolderPreview] = [:]

    var body: some View {
        // `.fixed`, not `.adaptive`. Adaptive fits as many columns of at least
        // `size` as the width allows and then stretches them to fill it, which
        // is right for a screen of nothing but folders and wrong for a row
        // sitting above a grid: it gave the tiles their own pitch and their own
        // left edge, a little wider and a little further left than the
        // photographs under them (D-146).
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(size), spacing: Tokens.Space.s12, alignment: .top),
                           count: max(1, columns)),
            spacing: Tokens.Space.s12
        ) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                FolderTile(folder: entry.url,
                           preview: previews[entry.url],
                           size: size,
                           isCursor: i == cursor,
                           drop: { drop(entry.url, $0) },
                           select: { select(i) },
                           openInTab: { openInTab(entry.url) }) { open(entry.url) }
            }
        }
        .task(id: entries) {
            let urls = entries.map(\.url)
            let found = await Task.detached(priority: .userInitiated) {
                urls.reduce(into: [URL: FolderPreview]()) { $0[$1] = FolderScanner.preview(of: $1) }
            }.value
            previews = found
        }
    }
}

/// A folder drawn the way a photograph is: a square, then its name under the
/// square (D-350).
///
/// It used to be a filled card with a folder mark in the corner and the name
/// inside it, which made it a different kind of object from every cell beside
/// it — the only card in a grid of bare thumbnails, with the only empty square
/// and the only name that was not underneath. The square holds the folder's
/// first frame now, with the edges of one or two more behind it, so a folder
/// looks like what is in it and still cannot be mistaken for a single
/// photograph.
@MainActor
struct FolderTile: View {
    let folder: URL
    let preview: FolderPreview?
    var size: CGFloat = Tokens.Layout.folderTile
    var isCursor = false
    /// Photos dropped on the tile, moved into the folder it stands for.
    var drop: (([URL]) -> Void)?

    /// One click puts the keyboard on this folder; two open it. A folder is a
    /// place, and walking into one by brushing a trackpad is a navigation
    /// nobody asked for — the same reason a photograph takes two clicks to
    /// open in the preview window (D-75, D-353).
    var select: (() -> Void)?

    /// The same folder, in a tab of this window. `⌘` held on the click that
    /// opens is the platform's way of asking for it, and **Open in New Tab**
    /// on the context menu is the one that can be found without knowing
    /// (D-370). Declared above `open` so that stays the trailing closure.
    var openInTab: (() -> Void)?

    let open: () -> Void

    @State private var hovering = false
    @State private var targeted = false

    /// The tab's height, and so how far the pocket sits below the top of the
    /// square. Also the depth of tab a reader actually sees.
    private static let tab = Tokens.Space.s8
    /// How far the tab runs across the top. Finder's is about two fifths and
    /// so is this: shorter reads as a chip stuck on a corner, longer stops
    /// reading as a tab at all. Held to the 4pt scale like every other
    /// measurement.
    private var tabWidth: CGFloat { (size * 0.42 / Tokens.Space.s4).rounded() * Tokens.Space.s4 }

    private var covers: [PhotoRef] { preview?.covers ?? [] }
    /// The three under the lead frame.
    private var strip: [PhotoRef] { Array(covers.dropFirst()) }

    /// The pocket lifts under the pointer, the way every other button in the
    /// app says it is one.
    /// A card lifted off the page, which is the reversal of D-353's well
    /// (D-354). A well separates as well as a card does and puts the
    /// photographs it holds in a hole, and a shadow under a sunken ground is
    /// two claims about the same edge. It lifts a further step under the
    /// pointer, which is how every other button in the app says it is one.
    private var pocketFill: Color {
        hovering || targeted ? Tokens.Surface.raised : Tokens.Surface.folder
    }

    /// The folder itself: one silhouette, filled and stroked, with the frames
    /// inside it.
    ///
    /// It was two rounded rectangles with only the tab stroked, because
    /// stroking both would have drawn the join. That kept the edge off three
    /// sides of the shape, and a fill two hex steps from the canvas is not an
    /// edge: the outline was there and could not be seen. One path is stroked
    /// once, all the way round, in the token that exists to be seen (D-352).
    private var pocket: some View {
        let shape = FolderOutline(tabHeight: Self.tab,
                                  tabWidth: tabWidth,
                                  radius: Tokens.Radius.sm)
        return shape
            .fill(pocketFill)
            // No border. An element takes a shadow or a border, never both:
            // two definitions of one edge, and the keyline was the harsh half
            // of the pair. The shadow is the whole separation now, which is
            // what a card on a page has (D-354).
            .shadow(color: Tokens.Elevation.tile.color,
                    radius: Tokens.Elevation.tile.radius,
                    y: Tokens.Elevation.tile.y)
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                contents.padding(Tokens.Space.s12)
            }
            .animation(Tokens.Motion.fast, value: hovering)
    }

    /// What is in the pocket: one frame across the top and up to three along
    /// the foot. The foot takes a quarter of the height, so the lead keeps the
    /// three quarters that decide whether anybody recognizes the folder.
    ///
    /// Every frame is given both its width and its height. A picture drawn
    /// `fills:` ignores a proposal it can overflow, so `maxWidth: .infinity`
    /// sized the layout and the picture separately and the strip ran out past
    /// the pocket on two sides. Explicit numbers, then `clipped()` (D-351).
    @ViewBuilder
    private var contents: some View {
        if covers.isEmpty {
            Glyph.draw(Glyph.Folder(), size: Tokens.Layout.glyphTile)
                .foregroundStyle(hovering ? Tokens.Text.primary : Tokens.Text.secondary)
                .frame(width: inner.width, height: inner.height)
        } else if strip.isEmpty {
            cell(covers[0], width: inner.width, height: inner.height)
        } else {
            VStack(spacing: Tokens.Space.s4) {
                cell(covers[0], width: inner.width, height: leadHeight)
                HStack(spacing: Tokens.Space.s4) {
                    ForEach(strip, id: \.id) { cell($0, width: stripWidth, height: footHeight) }
                    // The foot keeps three places whether or not there are
                    // three frames, so a folder of two does not draw one wide
                    // frame under the lead and call it a strip.
                    ForEach(0..<(3 - strip.count), id: \.self) { _ in
                        Color.clear.frame(width: stripWidth, height: footHeight)
                    }
                }
            }
            .frame(width: inner.width, height: inner.height)
        }
    }

    /// The room inside the pocket, once the tab is off the top and the inset
    /// is off all four sides.
    private var inner: CGSize {
        CGSize(width: size - Tokens.Space.s24,
               height: size - Self.tab - Tokens.Space.s24)
    }

    /// A quarter of the room, on the 4pt scale like everything else.
    private var footHeight: CGFloat {
        ((inner.height - Tokens.Space.s4) / 4 / Tokens.Space.s4).rounded() * Tokens.Space.s4
    }

    private var leadHeight: CGFloat { inner.height - footHeight - Tokens.Space.s4 }

    /// Not held to the scale: three across a width that is, so the division
    /// is what it is and rounding it would leave a gap at one end.
    private var stripWidth: CGFloat { (inner.width - Tokens.Space.s8) / 3 }



    private func cell(_ ref: PhotoRef, width: CGFloat, height: CGFloat) -> some View {
        PhotoImage(ref: ref, full: false, cell: size, fills: true)
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }

    /// AppKit has already counted the clicks, so the first one acts at once
    /// rather than waiting out the double-click interval to find out whether
    /// another is coming (D-75).
    ///
    /// Through `Activation` rather than off `NSApp.currentEvent` directly,
    /// because a button is pressed as well as clicked and the count is not
    /// there to be read when it is: the old line's answer to a VoiceOver press
    /// was whatever event happened to be lying around, and one of the things
    /// that can be lying around ends the process (A-7, D-367). A press opens,
    /// which is the verb this tile's tooltip already offers and the only one
    /// it has — selecting is the pointer's first step, and somebody who
    /// reached the tile with the keyboard has taken it.
    private func click() {
        let event = NSApp.currentEvent
        guard let select else { primary(event); return }
        if Activation.of(event).wantsThePrimaryAction { primary(event) } else { select() }
    }

    /// Opening, here or in a tab. Which one is a question about the event, so
    /// it is asked once, of the event the click carried, rather than of the
    /// keyboard as it stands by the time this runs (D-370).
    private func primary(_ event: NSEvent?) {
        if let openInTab, Activation.wantsASecondPlace(event) { openInTab() } else { open() }
    }

    var body: some View {
        Button(action: click) {
            VStack(spacing: Tokens.Space.s4) {
                pocket
                // The two lines of text take a fixed block, sized for a name
                // that wraps, whether or not this one does. Without it a tile
                // is as tall as its own name, and a row of tiles with names of
                // different lengths is a row of squares at different heights:
                // the grid centers each cell in a row sized by the tallest, so
                // one wrapped name pushed every square beside it down (D-369).
                VStack(spacing: Tokens.Space.s4) {
                    Text(folder.lastPathComponent)
                        .textStyle(.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(preview?.caption ?? " ")
                        .textStyle(.quiet)
                        .lineLimit(1)
                }
                .frame(width: size,
                       height: Tokens.Layout.folderTextHeight,
                       alignment: .top)
            }
            .frame(width: size)
            .overlay {
                // A drop target says so with the same ring the cursor uses: this
                // is where the photos are about to land.
                if targeted {
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Border.selected, lineWidth: Tokens.Border.ringWidth)
                }
            }
            .overlay {
                if isCursor {
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Border.focus, lineWidth: Tokens.Border.ringWidth)
                        .padding(-Tokens.Space.s4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .pointerStyle(.link)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .animation(Tokens.Motion.fast, value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let drop else { return false }
            let images = urls.filter(FolderScanner.isImage)
            guard !images.isEmpty else { return false }
            drop(images)
            return true
        } isTargeted: { targeted = $0 && drop != nil }
        .contextMenu {
            Button("Open") { open() }
            if let openInTab { Button("Open in New Tab", action: openInTab) }
        }
        .help("Open \(folder.path)")
        // The name is the folder; the caption counts what is in it and is
        // still being counted while the tile is on screen (D-343).
        .accessibilityLabel(folder.lastPathComponent)
        .accessibilityValue(preview?.caption ?? "folder")
    }
}

/// The folder: a tab along part of the top, then the pocket under it, as one
/// closed path so a single stroke goes all the way round (D-352).
struct FolderOutline: Shape {
    let tabHeight: CGFloat
    let tabWidth: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = radius
        // The flat top of the tab. The diagonal takes `tabHeight` more, so the
        // whole tab has to fit inside the width with the corner radius spare.
        let tab = min(max(tabWidth, r * 3), w - tabHeight - r * 2)
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: tab - r / 2, y: 0))
        // The tab falls away to the pocket rather than stepping down to it, at
        // the 45 degrees a manila folder does (D-353). One diagonal, and the
        // only one in the app, which is the argument against it and the reason
        // it reads as a folder from across the room.
        p.addQuadCurve(to: CGPoint(x: tab + r / 2, y: r / 2), control: CGPoint(x: tab, y: 0))
        p.addLine(to: CGPoint(x: tab + tabHeight - r / 2, y: tabHeight - r / 2))
        p.addQuadCurve(to: CGPoint(x: tab + tabHeight + r / 2, y: tabHeight),
                       control: CGPoint(x: tab + tabHeight, y: tabHeight))
        p.addLine(to: CGPoint(x: w - r, y: tabHeight))
        p.addQuadCurve(to: CGPoint(x: w, y: tabHeight + r), control: CGPoint(x: w, y: tabHeight))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}
