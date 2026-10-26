import Foundation

// The moments of the shelf, New Painting and the drawer at which a tip may speak, and what
// the painter does there that silences one. The bench's are in `PaintChromeState`. A moment hands
// the tips it may offer to the desk, which finds the first TipKit says is eligible and gives it the
// turn if the pacing allows; a thing used invalidates its tip (`PaintTips.used`).

extension Library {
    /// The shelf as the tips see it: the library as a whole, whatever the gallery's filter shows.
    var tipFacts: TipMoments.Shelf {
        TipMoments.Shelf(
            artworks: artworks.count, started: inProgress.count, ready: readyToPaint.count, finished: finished.count,
            preparing: !placeholders.isEmpty)
    }
}

extension PaintTips {
    // MARK: The shelf

    /// The shelf appeared, its library changed, or tips were switched on.
    static func shelfMoment(_ library: Library) {
        desk.offer(desk.shelfCandidates(library.tipFacts), in: .shelf, rest: .milliseconds(900))
    }

    // MARK: The bench

    /// A painting opens for painting (the bench's own moments are in `PaintChromeState`): the page
    /// that waits on the shelf has been answered, and the first painting has its own limit.
    static func artworkOpened(_ id: UUID) {
        used(.shelfStarter)
        desk.paintingOpened(id.uuidString)
    }

    // MARK: New Painting

    /// Choosing a photo opens: Samples, for whoever has no photo at hand.
    static func newPaintingOpened() {
        desk.enter(.newPainting)
        used(.shelfNewPainting)
        desk.offer([.newPaintingSamples], in: .newPainting, rest: .milliseconds(1200))
    }

    /// A photo or a sample was chosen.
    static func photoChosen() {
        used(.newPaintingSamples)
    }

    /// The preview's template is final: the divider, the suggestion, what the sliders do.
    static func previewFinal(isSuggested: Bool) {
        var dividerIsOver = false
        if case .over = TipID.newPaintingDivider.progress { dividerIsOver = true }
        let due = TipMoments.preview(dividerIsOver: dividerIsOver, isSuggested: isSuggested)
        desk.offer(due, in: .preview, rest: .milliseconds(1200))
    }

    static func dividerMoved() {
        desk.noteActivity()
        used(.newPaintingDivider)
    }

    /// A slider moved: Colors and Detail are what Fewer or More Areas is about.
    static func sliderMoved(colorsOrDetail: Bool) {
        desk.noteActivity()
        used(.newPaintingSuggested)
        if colorsOrDetail { used(.newPaintingSliders) }
    }

    /// A slider was let go, and the settings are the painter's own: the way back.
    static func sliderReleased(isCustom: Bool) {
        donate(TipEvents.sliderReleases, limit: 3)
        guard isCustom else { return }
        desk.offer([.newPaintingReset], in: .preview, rest: .milliseconds(1200))
    }

    static func resetUsed() {
        used(.newPaintingReset)
    }

    /// Start Painting made a page.
    static func pageMade() {
        donate(TipEvents.pagesMade, limit: 4)
    }

    // MARK: The drawer

    /// Settings opened.
    static func drawerOpened() {
        desk.enter(.drawer)
        used(.shelfSettings)
    }

    /// The Painting Length row is on screen (the form builds only the rows near it, so on a phone
    /// that is when it is scrolled to): Painting Length and the Making-of.
    static func drawerRowReached() {
        desk.offer([.drawerWorthALook], in: .drawer, rest: .milliseconds(1200))
    }
}
