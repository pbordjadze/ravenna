import SwiftUI
import TipKit

// The gentle tips (the app's design panel's design of October 17): 17 of the 22 tips; the five bench
// tips of the first version are in `PaintTips.swift`. A tip type only says what it is, in the
// design's words, and what TipKit may count on to show it: the tips-on parameter, and the events and
// parameters the moment needs. When it may appear is `TipDesk`'s (`TipPacing`: one at a time, the
// gap, the limits, quiet moments); where it points is its view's (`gentleTip`). A tip closes with its
// own close button and stays closed; the switch in Settings › Tips is the only way to turn them off.
//
// The tip types are `nonisolated`: TipKit reads them off the main actor.

/// Whether tips are on, for every tip's rules: Settings › Tips' switch, set by `PaintTips.setEnabled`.
/// A parameter rather than only the desk's say-so, so that turning tips off takes a tip that is
/// showing off the screen at once.
nonisolated struct TipSwitch {
    @Parameter static var tipsOn: Bool = false
}

/// The counts the tips' rules are made of. Ids carry the generation Show Tips Again bumps, so every
/// count starts over. Donated by `PaintTips`.
nonisolated enum TipEvents {
    /// Taps beside an area too small to hit at this zoom.
    static var smallMisses: Tips.Event<Tips.EmptyDonation> { event("smallMiss") }
    /// Taps that each filled one area.
    static var singleTaps: Tips.Event<Tips.EmptyDonation> { event("singleTap") }
    static var pencilStrokes: Tips.Event<Tips.EmptyDonation> { event("pencilStroke") }
    /// A minute with no fill while the selected color has areas left.
    static var stalls: Tips.Event<Tips.EmptyDonation> { event("stall") }
    /// A page about a quarter painted.
    static var quarters: Tips.Event<Tips.EmptyDonation> { event("quarter") }
    /// A page finished on the bench, its shine over.
    static var finishes: Tips.Event<Tips.EmptyDonation> { event("finished") }
    /// A painting screen left after a fill: a painting session.
    static var sessions: Tips.Event<Tips.EmptyDonation> { event("session") }
    /// A page made with Start Painting.
    static var pagesMade: Tips.Event<Tips.EmptyDonation> { event("pageMade") }
    /// A preview slider let go.
    static var sliderReleases: Tips.Event<Tips.EmptyDonation> { event("sliderReleased") }
    /// A line drawn in Refine.
    static var linesDrawn: Tips.Event<Tips.EmptyDonation> { event("lineDrawn") }

    private static func event(_ name: String) -> Tips.Event<Tips.EmptyDonation> {
        // Typed by the init alone, as the first version's events were: no donation value.
        let event = Tips.Event(id: PaintTips.scoped("event.\(name)"))
        return event
    }
}

// MARK: The shelf

/// The first shelf visit, once the starters are ready. Inline in Ready to Paint, where a popover has
/// nothing to point at. Stops when any painting is opened.
nonisolated struct ShelfStarterTip: Tip {
    var id: String { PaintTips.scoped("tip.shelfStarter") }
    var title: Text { Text("A Page Is Waiting") }
    var message: Text? { Text("Tap a page in Ready to Paint to begin. Nothing needs setting up first.") }
    var image: Image? { Image(systemName: "paintbrush.pointed") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    // Inline, it may come back on a visit or two while no painting has been opened.
    var options: [any TipOption] { Tips.MaxDisplayCount(3) }
}

/// Back on the shelf after the first painting session: where a new page begins. At the + button.
nonisolated struct ShelfNewPaintingTip: Tip {
    var id: String { PaintTips.scoped("tip.shelfNewPainting") }
    var title: Text { Text("Make Your Own Page") }
    var message: Text? { Text("Tap + to turn one of your photos, or a sample, into a page to paint.") }
    var image: Image? { Image(systemName: "plus.circle") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.sessions) { $0.donations.count >= 1 }
    }
}

/// From day two on, with two or more paintings: what a touch and hold on a painting offers.
nonisolated struct ShelfHoldTip: Tip {
    var id: String { PaintTips.scoped("tip.shelfHold") }
    var title: Text { Text("More for Each Painting") }
    var message: Text? { Text("Touch and hold a painting to favorite, rename, share, print or start it over.") }
    var image: Image? { Image(systemName: "ellipsis.circle") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
}

/// A painting is finished and the shelf shows it: the time-lapse, on a later visit than the hold.
nonisolated struct ShelfTimeLapseTip: Tip {
    var id: String { PaintTips.scoped("tip.shelfTimeLapse") }
    var title: Text { Text("Share the Making") }
    var message: Text? { Text("Touch and hold a finished painting and choose Share for a time-lapse of it.") }
    var image: Image? { Image(systemName: "timelapse") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
}

/// The shelf after the first finished painting: where the tips can be turned off. At the gear.
nonisolated struct ShelfSettingsTip: Tip {
    var id: String { PaintTips.scoped("tip.shelfSettings") }
    var title: Text { Text("Settings and Tips") }
    var message: Text? { Text("The gear holds paper tone, sound and painting length. Tips can be turned off there.") }
    var image: Image? { Image(systemName: "gearshape") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
}

// MARK: New Painting

/// The first time New Painting opens: samples, for whoever has no photo at hand.
nonisolated struct NewPaintingSamplesTip: Tip {
    var id: String { PaintTips.scoped("tip.newPaintingSamples") }
    var title: Text { Text("No Photo at Hand") }
    var message: Text? { Text("Samples has paintings and photographs ready to use.") }
    var image: Image? { Image(systemName: "photo.on.rectangle") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The first preview, once loaded: the divider. Stops when the divider is dragged.
nonisolated struct NewPaintingDividerTip: Tip {
    var id: String { PaintTips.scoped("tip.newPaintingDivider") }
    var title: Text { Text("Compare Photo and Page") }
    var message: Text? { Text("Drag the divider to compare the photo and the page. Pinch to look closer.") }
    var image: Image? { Image(systemName: "rectangle.split.2x1") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The first preview, after the divider's tip is over: the settings are the suggestion. At its chip.
/// Stops when any slider moves.
nonisolated struct NewPaintingSuggestedTip: Tip {
    var id: String { PaintTips.scoped("tip.newPaintingSuggested") }
    var title: Text { Text("Already Chosen for You") }
    var message: Text? { Text("These settings were picked for this photo. You can just tap Start Painting.") }
    var image: Image? { Image(systemName: "sparkles") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The first time a slider is let go: the way back. At Reset to Suggested. Stops when it is used.
nonisolated struct NewPaintingResetTip: Tip {
    var id: String { PaintTips.scoped("tip.newPaintingReset") }
    var title: Text { Text("You Can Always Go Back") }
    var message: Text? { Text("Watch the preview change. Reset to Suggested returns every slider to where it started.") }
    var image: Image? { Image(systemName: "arrow.counterclockwise") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.sliderReleases) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The second page made, once its preview is up: what Colors and Detail do. Stops when either moves.
nonisolated struct NewPaintingSlidersTip: Tip {
    var id: String { PaintTips.scoped("tip.newPaintingSliders") }
    var title: Text { Text("Fewer or More Areas") }
    var message: Text? { Text("Fewer colors and less detail make a calmer page. More makes a longer, finer one.") }
    var image: Image? { Image(systemName: "slider.horizontal.3") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.pagesMade) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The third page made, once its preview is up: Refine, which is optional. At the Refine button.
nonisolated struct NewPaintingRefineTip: Tip {
    var id: String { PaintTips.scoped("tip.newPaintingRefine") }
    var title: Text { Text("Shape the Lines Yourself") }
    var message: Text? { Text("Refine, top right, lets you draw or erase lines and fill shapes. It is optional.") }
    var image: Image? { Image(systemName: "pencil.tip") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.pagesMade) { $0.donations.count >= 2 }
    }
}

// MARK: Refine

/// Refine opened: how its canvas works, said once (it was a line under the tools until Paul's calmer
/// menus, October 18). At the Pen. Stops at the first change made.
nonisolated struct RefineDrawTip: Tip {
    var id: String { PaintTips.scoped("tip.refineDraw") }
    var title: Text { Text("Draw Your Own Lines") }
    var message: Text? { Text("Draw lines exactly as you draw them. Two fingers zoom and move, and a two‑finger tap undoes.") }
    var image: Image? { Image(systemName: "pencil.tip") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The first line drawn inside Refine: filling a closed shape. At Fill. Stops when a fill is made.
nonisolated struct RefineFillTip: Tip {
    var id: String { PaintTips.scoped("tip.refineFill") }
    var title: Text { Text("Make a Shape Its Own") }
    var message: Text? { Text("Draw a closed shape, then fill it to make it an area with its own number.") }
    var image: Image? { Image(systemName: "drop.fill") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.linesDrawn) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

// MARK: The bench

/// About a quarter of a page painted: the photo, held or kept showing. At the Photo control.
nonisolated struct BenchShowPhotoTip: Tip {
    var id: String { PaintTips.scoped("tip.benchShowPhoto") }
    var title: Text { Text("Peek at the Photo") }
    var message: Text? { Text("Hold Show Photo to see the original. Tap it to keep it showing.") }
    var image: Image? { Image(systemName: "photo") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.quarters) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The first page finished, its shine over: the replay, the only hint after a finish. At Replay.
nonisolated struct BenchReplayTip: Tip {
    var id: String { PaintTips.scoped("tip.benchReplay") }
    var title: Text { Text("Watch It Again") }
    var message: Text? { Text("Replay Painting plays your page back from the first fill.") }
    var image: Image? { Image(systemName: "play") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.finishes) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The second painting session, in a pause with no stroke: Zen Mode, in More.
nonisolated struct BenchZenTip: Tip {
    var id: String { PaintTips.scoped("tip.benchZen") }
    var title: Text { Text("A Calmer Way to Paint") }
    var message: Text? { Text("In More, Zen Mode moves the page to the next area after each fill.") }
    var image: Image? { Image(systemName: "leaf") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.sessions) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// Opening the third painting, at least a day after the first page was finished: Give Feedback.
nonisolated struct BenchFeedbackTip: Tip {
    var id: String { PaintTips.scoped("tip.benchFeedback") }
    var title: Text { Text("Tell Us What You Think") }
    var message: Text? { Text("In More, Give Feedback lets you mark the page and say what is wrong or right.") }
    var image: Image? { Image(systemName: "exclamationmark.bubble") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

// MARK: The drawer

/// The first time Settings opens: Painting Length, and the Making-of.
nonisolated struct DrawerWorthALookTip: Tip {
    var id: String { PaintTips.scoped("tip.drawerWorthALook") }
    var title: Text { Text("Worth a Look Here") }
    var message: Text? {
        Text("Painting Length sets how long new pages take. The Making-of shows a photo becoming its page.")
    }
    var image: Image? { Image(systemName: "sparkles") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

// MARK: Ids to tips

extension TipID {
    /// The tip of this id, made afresh: tip types are values, their ids those of their kind.
    nonisolated var tip: any Tip {
        switch self {
        case .shelfStarter: ShelfStarterTip()
        case .shelfNewPainting: ShelfNewPaintingTip()
        case .shelfHold: ShelfHoldTip()
        case .shelfTimeLapse: ShelfTimeLapseTip()
        case .shelfSettings: ShelfSettingsTip()
        case .newPaintingSamples: NewPaintingSamplesTip()
        case .newPaintingDivider: NewPaintingDividerTip()
        case .newPaintingSuggested: NewPaintingSuggestedTip()
        case .newPaintingReset: NewPaintingResetTip()
        case .newPaintingSliders: NewPaintingSlidersTip()
        case .newPaintingRefine: NewPaintingRefineTip()
        case .refineDraw: RefineDrawTip()
        case .refineFill: RefineFillTip()
        case .benchTap: FirstPaintTip()
        case .benchZoom: ZoomTip()
        case .benchFind: HintTip()
        case .benchDrag: DragPaintTip()
        case .benchPencil: PencilTip()
        case .benchShowPhoto: BenchShowPhotoTip()
        case .benchReplay: BenchReplayTip()
        case .benchZen: BenchZenTip()
        case .benchFeedback: BenchFeedbackTip()
        case .drawerWorthALook: DrawerWorthALookTip()
        }
    }

    /// Where TipKit stands on this tip, for `TipDesk`: eligible by its rules, not yet, or over.
    @MainActor var progress: TipProgress {
        let status = tip.status
        if case .available = status { return .available }
        guard case .invalidated(let reason) = status else { return .pending }
        if case .tipClosed = reason { return .over(.closed) }
        if case .actionPerformed = reason { return .over(.used) }
        return .over(.shownEnough)
    }
}

/// Where TipKit stands on a tip (`Tips.Status`, without its payload).
nonisolated enum TipProgress: Equatable, Sendable {
    case available, pending
    case over(Ending)

    /// Why a tip is over: the painter closed it, its thing was used, or TipKit retired it for having
    /// been shown (`MaxDisplayCount`), which can come while it is still on screen.
    enum Ending: Equatable, Sendable {
        case closed, used, shownEnough
    }
}
