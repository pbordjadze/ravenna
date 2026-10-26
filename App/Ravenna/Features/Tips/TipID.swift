import Foundation

/// Where in the app a tip lives. The words are the design's (October 17): the shelf is the gallery,
/// New Painting the create flow's picking of a photo, its preview, the bench the painting screen
/// and the drawer Settings. (Ravenna's seam: Refine and its tips are left out.)
nonisolated enum TipPlace: String, CaseIterable, Codable, Sendable {
    case shelf, newPainting, preview, bench, drawer

    /// How far in front of the others the screen is when several are up at once (the shelf under the
    /// create flow, Settings or a painting). Whichever is most in front is
    /// the one whose tips may speak, however the screens' appearing happened to be ordered.
    var depth: Int {
        switch self {
        case .shelf: 0
        case .bench, .drawer: 1
        case .newPainting: 2
        case .preview: 3
        }
    }
}

/// The tips, by the design's ids (Paint by Moonlight's 23 but Refine's three). Pure data: the tips themselves (TipKit) are made from these in
/// `TipID.tip`, and everything that decides when one may appear (`TipPacing`, `TipMoments`) speaks
/// of ids alone.
nonisolated enum TipID: String, CaseIterable, Codable, Sendable {
    case shelfStarter, shelfNewPainting, shelfHold, shelfTimeLapse, shelfSettings
    case newPaintingSamples
    case newPaintingDivider, newPaintingSuggested, newPaintingReset, newPaintingSliders
    case benchTap, benchZoom, benchFind, benchDrag, benchPencil, benchShowPhoto, benchReplay, benchZen, benchFeedback
    case drawerWorthALook

    /// The tips about a button in a navigation bar, a card with no arrow at the top of its screen
    /// (`barTips`), or atop the gallery's pages (`barTipsInline`).
    var liesUnderTheBar: Bool {
        switch self {
        case .shelfSettings, .shelfNewPainting: true
        default: false
        }
    }

    /// The tips that hang from a painting's card on the shelf, in a popover of SwiftUI's own
    /// (`cardTip`): TipKit's popover tip never came up on a card (CI, October 17: the turn
    /// given, nothing on screen), where the card's own confirmation dialogs do.
    var hangsFromCard: Bool { self == .shelfHold || self == .shelfTimeLapse }

    /// The tips about the page itself, a card at the top of the page with no arrow (`TipDesk.pageTip`):
    /// Paul, October 18, shown the arrow and none, "No arrow".
    var liesOnThePage: Bool { self == .benchZoom || self == .benchDrag || self == .benchPencil }

    /// Tips the app draws itself, in a popover of SwiftUI's own or as a card on the screen. They have no display
    /// limit of TipKit's, which would retire the tip from under its own view: closing, using or leaving
    /// it unread (`TipDesk`) says it once.
    var isDrawnByTheApp: Bool { liesUnderTheBar || hangsFromCard || liesOnThePage }

    /// How to use a screen at all, so it waits for neither the gap nor something done
    /// (`TipPacing`): Tap to Paint.
    var isHowTo: Bool { self == .benchTap }

    var place: TipPlace {
        switch self {
        case .shelfStarter, .shelfNewPainting, .shelfHold, .shelfTimeLapse, .shelfSettings: .shelf
        case .newPaintingSamples: .newPainting
        case .newPaintingDivider, .newPaintingSuggested, .newPaintingReset, .newPaintingSliders: .preview
        case .benchTap, .benchZoom, .benchFind, .benchDrag, .benchPencil, .benchShowPhoto, .benchReplay, .benchZen,
             .benchFeedback: .bench
        case .drawerWorthALook: .drawer
        }
    }
}

/// The tips a view can point, as bits. A modifier holding them is plain data, which SwiftUI
/// compares bit for bit, so its body is skipped when the screen renders again with the same tips.
/// An array is new at each render and never compared equal: every tip modifier on a screen ran
/// with each of the screen's renders, 300 to 600 times a second over the painting screen as it
/// opened on CI (October 19).
nonisolated struct TipSet: Hashable, Sendable {
    private var bits: UInt32 = 0

    init(_ ids: some Sequence<TipID>) {
        for id in ids { bits |= Self.bit[id, default: 0] }
    }

    func contains(_ id: TipID) -> Bool { bits & Self.bit[id, default: 0] != 0 }

    /// Its tips, in `TipID`'s order.
    var ids: [TipID] { TipID.allCases.filter(contains) }

    private static let bit = Dictionary(
        uniqueKeysWithValues: TipID.allCases.enumerated().map { ($1, UInt32(1) << UInt32($0)) })
}
