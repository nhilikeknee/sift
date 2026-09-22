import SwiftUI

@MainActor
struct GridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    /// Scroll target for the folder row, which has no photo id of its own.
    private static let folderRowID = "folder-row"
    /// The coordinate space the cell frames and the rubber band share.
    private static let space = "grid"

    /// Where every cell is, so a drag across the canvas knows what it crossed
    /// and so a drag that starts on a photo is left alone (D-92).
    @State private var frames: [Int: CGRect] = [:]
    @State private var band: CGRect?
    @State private var bandBase: Set<URL> = []

    private var cell: CGFloat { store.cellSize }
    /// The thumbnail plus the name under it (D-115).
    private var cellHeight: CGFloat { cell + Tokens.Space.s4 + Tokens.Layout.cellLabelHeight }
    private let gap = Tokens.Space.s12

    private func sectionID(_ start: Int) -> String { "section-\(start)" }

    /// The padding around the grid, which is the part of the width the cells
    /// never get. Named because the column count has to subtract it and used
    /// to not, and a number written twice is a number that disagrees with
    /// itself (D-345).
    private static let inset = Tokens.Space.s16

    /// How many fixed columns fit, which is not how many the width divides by.
    ///
    /// It divided the whole width by the pitch and ignored the inset, so for an
    /// eight-point band below every boundary it asked for one column more than
    /// there was room for: the row then overflowed the padding it sits in, and
    /// a centered grid pushed the outer cells under both edges. A sidebar drag
    /// crosses one of those bands at every boundary, which is a jump out and a
    /// jump back on the way through (D-345).
    static func columns(fitting width: CGFloat, cell: CGFloat, gap: CGFloat,
                        inset: CGFloat) -> Int {
        let room = width - inset * 2
        return max(1, Int((room + gap) / (cell + gap)))
    }

    /// One run of photos. Every cell knows its index into `store.photos`, which
    /// is the same array whether or not the view is sectioned.
    @ViewBuilder
    private func grid(columns: Int, range: Range<Int>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: columns), spacing: gap) {
            ForEach(range, id: \.self) { index in
                let ref = store.photos[index]
                GridCell(ref: ref, size: cell, isCursor: index == store.cursor,
                         isSelected: store.selected.contains(ref.url),
                         isCompareAnchor: store.compareAnchor == ref.url)
                    .id(ref.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[index] = $0 }
                    .contextMenu { PhotoMenu(ref: ref, store: store, router: router) }
                    // One tap gesture, not two. A `count: 2` beside a `count: 1`
                    // makes every single click wait out the double-click
                    // interval before the cell lights up, which is the whole of
                    // the delay between clicking a photo and selecting it
                    // (D-75). AppKit has already counted the clicks for us.
                    .onTapGesture { click(index) }
                    // A tap gesture is not an action. Without these the cell
                    // reads out a photograph's name from an element with
                    // nothing to press, while the pointer beside it selects on
                    // one click and opens on two (A-9). Both run the paths the
                    // pointer runs, so there is one behavior and two ways in.
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { click(index) }
                    .accessibilityAction(named: "Open") { open(index) }
            }
        }
    }

    /// A click on a cell. The second click of a double arrives here as its own
    /// tap carrying `clickCount == 2`, so the first one selects immediately and
    /// the second opens the preview — instead of both waiting to find out
    /// whether the other was coming.
    ///
    /// Through `Activation` for the reason `FolderTile` gives: the count is
    /// only there when a pointer put it there, and the cell now has an
    /// accessibility action that can run this with no mouse event in sight
    /// (A-7, A-9, D-367). A press takes the cursor and the selection both, which is
    /// what one click does; opening has its own named action beside it.
    private func click(_ index: Int) {
        let event = NSApp.currentEvent
        store.folderCursor = nil
        if case .click(let count) = Activation.of(event), count >= 2 {
            open(index)
            return
        }
        // `modifierFlags` is valid on every event, unlike the count above, so
        // this needs no guard; `NSEvent.modifierFlags` is what is held right
        // now, for an activation that arrived with no event of its own.
        let mods = event?.modifierFlags ?? NSEvent.modifierFlags
        // Inside `fromPointer`, so none of the three branches scrolls. The
        // cell is under the hand already, and centering it moved the grid
        // out from under the click that had just landed (D-374).
        store.fromPointer {
            if mods.contains(.command) {
                store.cursor = index
                store.toggleSelectCurrent()
            } else if mods.contains(.shift), let c = store.cursor {
                store.move(by: index - c, extendingSelection: true)
            } else {
                // Not just the cursor: a plain click is also the whole
                // selection, so clicking one of thirty chosen cells leaves one
                // chosen (D-377).
                store.selectOnly(index)
            }
        }
    }

    /// The second half of a double click, and the cell's named accessibility
    /// action. One function because the two must not drift: a reader pressing
    /// **Open** is asking for what the pointer gets from a second click, and
    /// two copies of three lines is where that stops being true.
    private func open(_ index: Int) {
        store.folderCursor = nil
        store.fromPointer { store.cursor = index }
        router.perform(.enterSingle)
    }

    private func onACell(_ point: CGPoint) -> Bool {
        frames.values.contains { $0.contains(point) }
    }

    /// Every photo the box has crossed, plus whatever was already selected when
    /// the drag began with shift down.
    ///
    /// Asked of the lattice rather than of the measured frames (D-106): a box
    /// dragged past the bottom edge is asking for the rows past it, and those
    /// rows have not been drawn.
    private func selectInsideBand() {
        guard let band else { return }
        var picked = bandBase
        for lattice in lattices() {
            for index in lattice.indices(in: band) where store.photos.indices.contains(index) {
                picked.insert(store.photos[index].url)
            }
        }
        store.selected = picked
    }

    /// One lattice per run of photos: a sectioned grid starts new rows under
    /// every heading, so each section is its own. A run with nothing drawn in it
    /// has no anchor to work back from and is skipped — the reader has not
    /// scrolled anywhere near it.
    private func lattices() -> [CellLattice] {
        let sections = store.sections
        let ranges = sections.isEmpty
            ? [store.photos.indices.startIndex..<store.photos.indices.endIndex]
            : sections.map { $0.start..<($0.start + $0.count) }
        return ranges.compactMap { range in
            guard let anchor = frames.keys.filter({ range.contains($0) }).min(),
                  let frame = frames[anchor] else { return nil }
            return CellLattice(anchor: anchor, frame: frame, cellWidth: cell, cellHeight: cellHeight,
                               gap: gap, columns: store.gridColumns, range: range)
        }
    }

    /// How far the pointer moves before a drag on the canvas is a box, and how
    /// solid the box is over the photos it crosses.
    private static let bandThreshold: CGFloat = 4
    private static let bandFill: Double = 0.12

    var body: some View {
        GeometryReader { geo in
            let columns = Self.columns(fitting: geo.size.width, cell: cell,
                                       gap: gap, inset: Self.inset)
            ScrollViewReader { proxy in
                ScrollView {
                    let folders = store.folderRow
                    if !folders.isEmpty {
                        FolderOverflowNote(shown: folders.count,
                                           leftOut: store.subfoldersLeftOut)
                            .padding(.horizontal, Tokens.Space.s16)
                            .padding(.top, Tokens.Space.s16)
                        FolderRow(entries: folders,
                                  size: cell,
                                  columns: columns,
                                  cursor: store.folderCursor,
                                  select: { i in
                                      // The two cursors are one place at a
                                      // time: putting the keyboard on a folder
                                      // takes it off the photographs, the way
                                      // clicking a photograph takes it off the
                                      // folders (D-353). Not
                                      // `clearCursorAndSelection`, which
                                      // clears the folder cursor as well and
                                      // would undo the line after it.
                                      store.clearSelection()
                                      store.cursor = nil
                                      store.folderCursor = i
                                  },
                                  open: { router.open($0) },
                                  openInTab: { router.openInNewTab($0) },
                                  drop: { folder, urls in router.drop(urls, on: folder) })
                            .padding(.horizontal, Tokens.Space.s16)
                            .padding(.top, Tokens.Space.s16)
                            .id(Self.folderRowID)
                    }
                    let sections = store.sections
                    if sections.isEmpty {
                        grid(columns: columns, range: store.photos.indices)
                            .padding(Self.inset)
                    } else {
                        LazyVStack(alignment: .leading, spacing: Tokens.Space.s24, pinnedViews: [.sectionHeaders]) {
                            ForEach(sections) { section in
                                Section {
                                    grid(columns: columns, range: section.start..<(section.start + section.count))
                                } header: {
                                    // The folder headings are chrome too, and
                                    // bare takes the gallery's chrome (D-150).
                                    if !store.isBare(.gallery) {
                                        SectionHeader(section: section) { folder in router.open(folder) }
                                            .id(sectionID(section.start))
                                    }
                                }
                            }
                        }
                        .padding(Self.inset)
                    }
                }
                .coordinateSpace(name: Self.space)
                // A click on the canvas, not on a photo, drops the selection
                // and the cursor both. The cells and the folder tiles take
                // their own taps first, so this only ever sees the space
                // between and around them.
                .contentShape(Rectangle())
                .onTapGesture {
                    guard store.cursor != nil || store.folderCursor != nil
                            || !store.selected.isEmpty else { return }
                    store.clearCursorAndSelection()
                }
                // Finder, Bridge and Capture One all draw a box (D-92). A drag
                // that starts on a photo is that photo being dragged out, so
                // the band only begins in the space between them.
                .simultaneousGesture(
                    DragGesture(minimumDistance: Self.bandThreshold, coordinateSpace: .named(Self.space))
                        .onChanged { v in
                            if band == nil {
                                guard !onACell(v.startLocation) else { return }
                                bandBase = NSEvent.modifierFlags.contains(.shift) ? store.selected : []
                            }
                            band = CGRect(origin: v.startLocation, size: .zero)
                                .union(CGRect(origin: v.location, size: .zero))
                            selectInsideBand()
                        }
                        .onEnded { _ in band = nil; bandBase = [] }
                )
                .overlay {
                    if let band {
                        Rectangle()
                            .fill(Tokens.Border.selected.opacity(Self.bandFill))
                            .overlay(Rectangle().strokeBorder(Tokens.Border.selected, lineWidth: Tokens.Border.hoverWidth))
                            .frame(width: band.width, height: band.height)
                            .position(x: band.midX, y: band.midY)
                            .allowsHitTesting(false)
                    }
                }
                .onAppear { store.gridColumns = columns }
                .onChange(of: columns) { _, c in store.gridColumns = c }
                .onChange(of: store.cellSize) { _, _ in
                    guard let cursor = store.cursor, store.photos.indices.contains(cursor) else { return }
                    proxy.scrollTo(store.photos[cursor].id, anchor: .center)
                }
                // `revealCursor`, not `cursor`. A cursor the pointer moved
                // is on a cell the reader is already looking at (D-374).
                .onChange(of: store.revealCursor, initial: true) { _, cursor in
                    guard store.folderCursor == nil, let cursor, store.photos.indices.contains(cursor) else { return }
                    proxy.scrollTo(store.photos[cursor].id, anchor: .center)
                }
                .onChange(of: store.folderCursor) { _, folderCursor in
                    guard folderCursor != nil else { return }
                    proxy.scrollTo(Self.folderRowID, anchor: .top)
                }
            }
        }
        // Bare takes the ground dark in both palettes, the way the preview
        // already did (D-62, D-150): with nothing else on screen the surround
        // is doing the whole job of saying what a photograph's tones are.
        .background(store.isBare(.gallery) ? Tokens.Surface.judging : Tokens.Surface.canvas)
    }
}

/// Names the folder a run of photos came from, and opens it. Sticky, so the
/// answer to "what am I looking at" stays on screen while the run scrolls.
@MainActor
private struct SectionHeader: View {
    let section: GridSection
    let open: (URL) -> Void

    @State private var hovering = false

    var body: some View {
        Group {
            if let folder = section.folder {
                Button { open(folder) } label: { label }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
                    .pointerStyle(.link)
                    .help("Open \(folder.path)")
            } else {
                // A scene is a time, not a place. Nothing to open, so nothing
                // that looks like it opens.
                label
            }
        }
    }

    private var label: some View {
        HStack(spacing: Tokens.Space.s8) {
            if section.folder != nil { Glyph.draw(Glyph.Folder()) }
            Text(section.title)
                .textStyle(.heading)
            Text("\(section.count)")
                .textStyle(.quiet)
            Spacer()
        }
        // Without this the header reads as its two words and then a bare
        // number with no unit on it (D-343).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
        .accessibilityValue("\(section.count) photos")
        // Said again here because combining rebuilds the element out of its
        // children, and the trait `.heading` puts on the title is the thing
        // the rotor jumps between (D-338). Cheap to state, and the cost of
        // losing it is a grid with nothing to jump to.
        .accessibilityAddTraits(.isHeader)
        .foregroundStyle(section.folder != nil && hovering ? Tokens.Text.primary : Tokens.Text.secondary)
        .padding(.vertical, Tokens.Space.s8)
        .background(Tokens.Surface.canvas)
        .contentShape(Rectangle())
    }
}

@MainActor
private struct GridCell: View {
    @Environment(LibraryStore.self) private var store
    @Environment(CommandRouter.self) private var router

    let ref: PhotoRef
    let size: CGFloat
    let isCursor: Bool
    let isSelected: Bool
    let isCompareAnchor: Bool

    @State private var hovering = false
    @State private var frame: CGRect = .zero
    @State private var windowFrame: CGRect = .zero
    @StateObject private var drag = DragOutHandle()

    /// Whether this cell offers its mark: the one under the pointer and the one
    /// the keyboard is on (D-142, D-156).
    private var offersMark: Bool {
        CellOffer.offeredMark(hovering: hovering, isCursor: isCursor)
    }

    /// A drag off a cell that is part of a multi-selection takes the whole
    /// selection, the way a drop on a folder tile already did. Any other cell
    /// goes alone (D-72).
    private var dragsSelection: Bool { isSelected && store.selected.count > 1 }

    /// How far the pointer moves before a press becomes a drag. Far enough
    /// that a click that wobbles is still a click.
    private static let dragThreshold: CGFloat = 8

    var body: some View {
        // Finder's shape: the thumbnail on a rounded backing, the name on its
        // own pill under it, and nothing drawn around the photograph at all
        // (D-115, D-119).
        VStack(spacing: Tokens.Space.s4) {
            thumbnail
            // Bare is the photographs and nothing else, so the names go with
            // the header and the sidebar (D-150). They would also be the one
            // thing on screen still inked for a light canvas, on a ground that
            // has gone near-black.
            if !store.isBare(.gallery) { name }
        }
        .background(DragOut(urls: { store.targets(for: ref).map(\.url) }, handle: drag))
        // One path for one file and for thirty. SwiftUI's own `onDrag`
        // can only ever offer one, and two drag sessions racing each
        // other is worse than the bug it would be fixing (D-72).
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.dragThreshold)
                .onChanged { _ in
                    // A drag that cannot start says why, where every other
                    // failure in the app is said (D-103). Silence here is
                    // indistinguishable from a photo that will not move.
                    if let message = drag.begin()?.message { store.showError(message) }
                }
        )
        // Where this cell is, for the peek to sit beside (D-131). Kept on the
        // cell and published when it is the hovered one, because a scroll
        // moves every cell and only one of them is being looked at.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RootView.gallerySpace)) } action: { new in
            frame = new
            if store.hovered?.url == ref.url { store.hoveredFrame = new }
        }
        // And where it is in the window, for the warp a recording makes (D-297).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { new in
            windowFrame = new
            if store.hovered?.url == ref.url { store.hoveredWindowFrame = new }
        }
        // `SIFT_SHOW=peek` sets the hover without a pointer, so the frame has
        // to follow the claim as well as the geometry (D-118, D-130).
        .onChange(of: store.hovered?.url) { _, hovered in
            if hovered == ref.url {
                store.hoveredFrame = frame
                store.hoveredWindowFrame = windowFrame
            }
        }
        .onHover { inside in
            hovering = inside
            // A cell only ever clears its own claim. AppKit delivers the new
            // cell's enter before the old cell's exit, so an unconditional
            // clear on the way out wipes the cell the pointer just arrived on
            // and the peek blinks off mid-sweep (D-130).
            store.pointer(inside, on: ref, frame: frame)
        }
        // The pointer says what the fill only implies: this is a thing you
        // click, not a picture sitting on a page (D-75).
        .pointerStyle(.link)
        .animation(Tokens.Motion.fast, value: hovering)
        .animation(Tokens.Motion.fast, value: isSelected)
        .animation(Tokens.Motion.fast, value: isCursor)
        .help(ref.name)
        // The name is which photograph this is; being one of a selection is
        // something that happens to it and stops happening (D-343).
        .accessibilityLabel(ref.name)
        .accessibilityValue(dragsSelection ? "1 of \(store.selected.count) selected" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The name, in the pill Finder puts it in: accent-filled with white text
    /// while selected, nothing at all behind it otherwise. Truncated in the
    /// middle, because the end of a filename is the frame number and the
    /// beginning is the shoot.
    private var name: some View {
        Text(ref.name)
            .textStyle(.label, color: isSelected ? Tokens.Text.onSelection : Tokens.Text.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Tokens.Space.s8)
            .frame(height: Tokens.Layout.cellLabelHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                        .fill(Tokens.State.selection)
                }
            }
            .frame(maxWidth: size)
    }

    /// The square the photograph is fitted into, inset inside the cell. The
    /// inset scales with the cell: at 96 a constant 8 took a sixth of the
    /// picture away (D-120).
    private var photoBox: CGFloat { size - Tokens.Layout.cellInset(for: size) * 2 }

    /// What the picture was actually painted at. A 4:3 frame fitted into a
    /// square leaves an empty band top and bottom, and every mark used to be
    /// placed against the square, so the heart sat half on the photograph and
    /// half on the chrome above it (D-120).
    @State private var drawn: CGSize = .zero

    /// Where a mark sits: `space.s4` in from the picture's edge, not from the
    /// box's. Falls back to the box while the decode is still in flight, which
    /// is the old behavior and is invisible — there is no photograph under it
    /// yet to be in the corner of.
    private var markInset: EdgeInsets {
        guard drawn.width > 0, drawn.height > 0 else {
            return EdgeInsets(top: Tokens.Space.s4, leading: Tokens.Space.s4,
                              bottom: Tokens.Space.s4, trailing: Tokens.Space.s4)
        }
        let x = max(0, (photoBox - drawn.width) / 2) + Tokens.Space.s4
        let y = max(0, (photoBox - drawn.height) / 2) + Tokens.Space.s4
        return EdgeInsets(top: y, leading: x, bottom: y, trailing: x)
    }

    private var thumbnail: some View {
        PhotoImage(ref: ref, full: false, cell: photoBox, onDrawnSize: { drawn = $0 })
            .frame(width: photoBox, height: photoBox)
            // The two marks that are about the photo itself, in the corner
            // they have always been in: the flag, then the color beside it.
            // Two dots rather than a stripe, because the cell already has a
            // vocabulary and a colored edge would be a second one (D-96).
            .overlay(alignment: .topLeading) {
                HStack(spacing: Tokens.Space.s4) {
                    if let flag = ref.flag {
                        // Off the cell, like the heart in the other corner: a
                        // 12pt disc that read at 96 was a speck on a 300pt
                        // cell, and the decision is the thing the grid is being
                        // swept for (D-228).
                        FlagMark(flag: flag, size: Tokens.Layout.flagBadge(for: photoBox))
                    }
                    if let label = ref.label {
                        LabelDot(label: label)
                    }
                }
                .padding(markInset)
            }
            // The favorite is one mark that is also its own control (D-73):
            // filled and permanent once it is set, because it has to be
            // findable by sweeping a grid, and an empty outline the rest of the
            // time — on the photo under the pointer, and on the photo the
            // cursor is on, so a run done on the keyboard is offered it rather
            // than having to know (D-105). At every cell size, unlike the pill
            // below: the set heart draws at 96px, so the empty one has to be
            // there too or clearing a favorite takes the control away with it
            // (D-142). Top right, opposite the flag dot, so a photo can wear
            // both without them touching.
            .overlay(alignment: .topTrailing) {
                FavoriteMarkButton(ref: ref, subject: ref.name,
                                   size: Tokens.Layout.favoriteMark(for: photoBox),
                                   revealed: offersMark) {
                    router.perform(.toggleFavorite, on: ref)
                }
                .padding(markInset)
            }
            // Keep and reject had a pill here, on the photo under the pointer
            // and the photo the cursor is on. It is out for now (D-170); `p`,
            // `x` and the right-click menu still flag, and the corner still
            // carries the dot that says what a photograph is flagged as.
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if isCompareAnchor { Badge("A") }
                }
                .padding(markInset)
            }
            // A burst stands behind its first frame, with a count and a way in
            // (D-84). Bottom left, opposite the controls, so it never moves.
            .overlay(alignment: .bottomLeading) {
                if let n = store.stackCounts[ref.url] {
                    StackBadge(count: n, open: store.expandedStacks.contains(ref.url)) {
                        store.toggleStack(ref.url)
                    }
                    .padding(markInset)
                }
            }
            // The backing sits *around* the photograph rather than under it,
            // and only when there is something to say. Unselected and
            // untouched, a thumbnail is a picture on the canvas with nothing
            // drawn around it, which is what Finder shows and what keeps a
            // grid of photographs reading as photographs (D-116).
            .padding(Tokens.Space.s8)
            .frame(width: size, height: size)
            .background {
                // Finder says one fact with two marks at once, a tile behind
                // the icon and a filled pill under it, because in Finder the
                // keyboard's place and the chosen set are the same thing.
                // Here they are not, so the two marks split across the two
                // facts: the tile is where the keyboard is, the pill is what
                // is chosen. One selected photo is tile and pill together,
                // which is Finder exactly; a select-all is eight pills and
                // one tile, which says where you would land (D-119).
                //
                // Nothing is stroked. Finder draws no border on a selected
                // item at any radius, and the 2px keyline that used to sit
                // around this cell sampled #060606 on a white canvas: the
                // loudest mark in the app, spent on its quietest fact.
                //
                // Selected wins over the cursor, which is the reversal of
                // D-119: with a plain click now choosing as well as landing,
                // the gray tile sat on the one cell somebody had just clicked
                // and read as a hole in the blue run rather than as a place
                // (D-377). Where the keyboard is inside a selection is said in
                // the same hue a step heavier; the gray tile is what a cursor
                // with nothing chosen still wears.
                if isSelected {
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .fill(isCursor ? Tokens.Surface.selectedCursor : Tokens.Surface.selected)
                } else if isCursor {
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .fill(Tokens.Surface.cursor)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .fill(Tokens.Surface.hovered)
                }
            }
    }
}

/// How many frames a cell stands for, and the control that opens them. The
/// chevron turns down when the stack is open, which is the same shape Finder
/// and every outline on the platform uses for the same idea.
private struct StackBadge: View {
    let count: Int
    let open: Bool
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            HStack(spacing: Tokens.Space.s4) {
                Text("\(count)")
                    .textStyle(.label)
                Glyph.draw(Glyph.Chevron())
                    .rotationEffect(.degrees(open ? -90 : 90))
            }
            .foregroundStyle(hovering ? Tokens.Text.primary : Tokens.Text.secondary)
            .padding(.horizontal, Tokens.Space.s8)
            .padding(.vertical, Tokens.Space.s4)
            .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Tokens.Motion.fast, value: hovering)
        .pointerStyle(.link)
        .help(open ? "Close this burst of \(count)" : "Show all \(count) frames of this burst")
        // How many frames is the badge's value and it changes as a burst is
        // culled; open and shut is the control's own state (D-343).
        .accessibilityLabel(open ? "Collapse burst" : "Expand burst")
        .accessibilityValue("\(count) frames")
    }
}

/// A word or a mark on the raised pill the cell's readouts share.
private struct Badge<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(.horizontal, Tokens.Space.s8)
            .padding(.vertical, Tokens.Space.s4)
            .background(Tokens.Surface.raised, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}

private extension Badge where Content == Text {
    init(_ text: String) {
        self.init {
            // design-system:allow — a `Text` in, a `Text` out: this initializer
            // is constrained to Content == Text, so the role is applied as its
            // own font and color rather than through the `textStyle` modifier,
            // which erases the type. Still the role, not a literal.
            Text(text)
                .font(TextRole.label.font)            // design-system:allow
                .foregroundColor(TextRole.label.color) // design-system:allow
        }
    }
}
