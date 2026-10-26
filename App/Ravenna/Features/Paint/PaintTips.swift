import Foundation
import os
import SwiftUI
import TipKit

// The bench's tips of the first version, in the gentle tips' words and rules (the app's design
// panel's design of October 17; the other 17 are in `Features/Tips`). The tip types are
// `nonisolated`: TipKit reads them off the main actor. Their rules are the tips-on parameter and
// the events painting donates (`PaintTips.record`); `TipDesk` decides when one may appear. Tip and
// event ids carry a generation that Settings ▸ Show Tips Again bumps, so tips return at once with
// fresh counts, and the ids of the first version are kept: whoever closed one has it closed.

/// The first painting: how to paint at all. Tap to Paint.
nonisolated struct FirstPaintTip: Tip {
    /// Whether the open painting has paint already. A rule rather than an invalidation, so
    /// the tip still comes back on the next fresh painting after Show Tips Again.
    @Parameter static var hasPaint: Bool = false

    var id: String { PaintTips.scoped("tip.firstPaint") }
    var title: Text { Text("Tap to Paint") }
    var message: Text? { Text("Pick a color, then tap an area marked with its number to fill it.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(Self.$hasPaint) { $0 == false }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(PaintTips.swatchTipDisplays) }
}

/// A minute with no fill while the selected color has areas left: the selected swatch shows where to paint.
nonisolated struct HintTip: Tip {
    var id: String { PaintTips.scoped("tip.hint") }
    var title: Text { Text("Can’t Find It?") }
    var message: Text? { Text("Tap the selected color again, or the lightbulb, to be shown an area to paint.") }
    var image: Image? { Image(systemName: "lightbulb") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.stalls) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(PaintTips.swatchTipDisplays) }
}

/// After two taps beside areas too small to hit at this zoom.
nonisolated struct ZoomTip: Tip {
    var id: String { PaintTips.scoped("tip.zoom") }
    var title: Text { Text("Zoom In on Small Areas") }
    var message: Text? { Text("Double-tap the page to zoom in. Pinch to zoom back out.") }
    var image: Image? { Image(systemName: "plus.magnifyingglass") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.smallMisses) { $0.donations.count >= 2 }
    }
}

/// After 15 single fills: one stroke paints many areas.
nonisolated struct DragPaintTip: Tip {
    var id: String { PaintTips.scoped("tip.dragPaint") }
    var title: Text { Text("Paint Several Areas") }
    var message: Text? { Text("Touch and hold, then drag across areas with this number to fill them in one stroke.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.singleTaps) { $0.donations.count >= 15 }
    }
}

/// The first Pencil touch on the page: the Pencil paints while fingers navigate.
nonisolated struct PencilTip: Tip {
    var id: String { PaintTips.scoped("tip.pencil") }
    var title: Text { Text("Paint with Apple Pencil") }
    var message: Text? { Text("The Pencil paints while fingers move the page. Double-tap the Pencil for the next color.") }
    var image: Image? { Image(systemName: "applepencil") }
    var rules: [Tips.Rule] {
        #Rule(TipSwitch.$tipsOn) { $0 == true }
        #Rule(TipEvents.pencilStrokes) { $0.donations.count >= 1 }
    }
}

/// Configuration, the Tips switch, and the bridge from what the painter does to TipKit donations
/// and invalidations; the desk (`TipDesk`) gives the tips their turns.
enum PaintTips {
    nonisolated static let generationKey = "tipsGeneration"

    nonisolated static func generation(_ defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: generationKey)
    }

    /// `name` in the current generation of tips.
    nonisolated static func scoped(_ name: String, defaults: UserDefaults = .standard) -> String {
        "\(name).\(generation(defaults))"
    }

    /// New tip and event ids: every tip is new again. (`Tips.resetDatastore()` only works
    /// before `Tips.configure`, so it can't serve Settings.)
    static func bumpGeneration(_ defaults: UserDefaults = .standard) {
        defaults.set(generation(defaults) + 1, forKey: generationKey)
    }

    /// Gives the tips their turns. Made after `configure` has cleared a demo's or a test's state.
    static let desk = TipDesk()

    /// Call once at launch. Demo and test runs start from an empty datastore and the Tips switch at
    /// its default, so screenshots and tests never depend on what an earlier run saw or donated;
    /// they show no tip but the scenarios' own.
    static func configure() {
        #if DEBUG
        let isolatedRun = DemoMode.isActive || DemoMode.isTestHost
        let demo = DemoMode.scenario.flatMap { demoScenarios[$0] }
        if isolatedRun {
            try? Tips.resetDatastore()
            TipStore().reset()
            TipPreference.forget()
            if demo == nil, DemoMode.forcedTip == nil { Tips.hideAllTipsForTesting() }
        }
        #endif
        do {
            try Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        } catch {
            Log.tips.error("TipKit configuration failed: \(String(describing: error), privacy: .public)")
        }
        // The rules of every tip read this: on unless Settings says otherwise.
        TipSwitch.tipsOn = TipPreference.isEnabled()
        desk.beginSession()
        #if DEBUG
        if let demo {
            desk.isMuted = demo.isMuted
            setEnabled(demo.enabled)
            for id in demo.closed { id.tip.invalidate(reason: .tipClosed) }
        } else {
            desk.isMuted = isolatedRun
        }
        // The forced tip itself waits for the scenario's content (`DemoMode.markReady`).
        if DemoMode.forcedTip != nil { donateEveryRule() }
        #endif
    }

    // MARK: The switch

    /// Tips on or off: Settings › Tips' switch.
    static func setEnabled(_ enabled: Bool) {
        TipPreference.record(enabled)
        TipSwitch.tipsOn = enabled
        desk.answered(tipsOn: enabled)
    }

    /// Settings ▸ Show Tips Again: tips on, and every tip as new.
    static func showAgain() {
        bumpGeneration()
        donated.removeAll()
        invalidated.removeAll()
        TipPreference.record(true)
        TipSwitch.tipsOn = true
        desk.startOver()
        desk.answered(tipsOn: true)
    }

    // MARK: Using a thing

    /// The painter used what `id` is about: the tip never shows, or goes if it does.
    static func used(_ id: TipID) {
        desk.stop(id)
        invalidate(id.tip)
    }

    /// The painter dismissed the tip that has the turn in a way TipKit doesn't see (a tap outside
    /// the popover of `cardTip`): it stays closed, as it does when TipKit's own popover is dismissed.
    static func closed(_ id: TipID) {
        guard desk.turn == id else { return }
        desk.stop(id)
        id.tip.invalidate(reason: .tipClosed)
    }

    // MARK: The bench

    /// Tips on the selected swatch move with the selection, and each move presents the popover
    /// anew, which TipKit counts as another display. Using the gesture invalidates them anyway.
    nonisolated static let swatchTipDisplays = 3

    /// What happened while painting, as far as tips are concerned.
    enum Signal: Equatable {
        case tapPainted, strokePainted, strokeEnded, wrongColor, missedSmallArea, hintShown
        case zoomed, pencilUsed
    }

    /// The tip signal of a session event (`isStroking`: a drag or Pencil stroke is under way).
    static func signal(for event: PaintEvent, isStroking: Bool) -> Signal? {
        switch event {
        case .painted: isStroking ? Signal.strokePainted : Signal.tapPainted
        case .strokeEnded: Signal.strokeEnded
        case .rejected: Signal.wrongColor
        case .missedSmallArea: Signal.missedSmallArea
        case .hintShown: Signal.hintShown
        case .colorCompleted, .artworkCompleted, .undone: nil
        }
    }

    static func record(_ signal: Signal) {
        desk.noteActivity()
        switch signal {
        case .tapPainted:
            desk.filled()
            used(.benchTap)
            donate(TipEvents.singleTaps, limit: 20)
        case .strokePainted:
            desk.filled()
            used(.benchTap)
        case .strokeEnded:
            used(.benchDrag)
        case .wrongColor:
            break
        case .missedSmallArea:
            donate(TipEvents.smallMisses, limit: 4)
        case .hintShown:
            used(.benchFind)
        case .zoomed:
            used(.benchZoom)
        case .pencilUsed:
            donate(TipEvents.pencilStrokes, limit: 2)
        }
    }

    /// A painting that already has paint needs no first tip.
    static func paintingOpened(hasProgress: Bool) {
        FirstPaintTip.hasPaint = hasProgress
    }

    // MARK: Donations and invalidations

    /// Donations per event and launch: every rule is met well below its limit, and a painting's
    /// thousands of taps must not grow the datastore.
    private static var donated: [String: Int] = [:]

    /// Donates `event`, up to `limit` times a launch.
    static func donate(_ event: Tips.Event<Tips.EmptyDonation>, limit: Int = 8) {
        let count = donated[event.id, default: 0]
        guard count < limit else { return }
        donated[event.id] = count + 1
        Task { await event.donate() }
    }

    /// Tips invalidated this launch. Strokes report paint per segment, many times a second;
    /// each invalidation is a datastore write, and the first one already settles the tip.
    private static var invalidated: Set<String> = []

    private static func invalidate(_ tip: some Tip) {
        guard invalidated.insert(tip.id).inserted else { return }
        tip.invalidate(reason: .actionPerformed)
    }

    // MARK: Demos

    #if DEBUG
    /// A scenario that lets tips speak (the rest hide every one): the tip it waits for before it
    /// signals readiness (none: it waits for nothing), whether the Tips switch is on, the tips
    /// already closed when it begins, and whether the desk is muted (nothing is offered at all).
    private struct DemoScenario {
        var tip: TipID?
        var enabled = true
        var closed: [TipID] = []
        var isMuted = false
    }

    /// `paint-tip-fill` and `gallery-tips-off` (the switch off, the real gate) are for UI tests.
    private static let demoScenarios: [String: DemoScenario] = [
        "paint-tip": DemoScenario(tip: .benchTap),
        "paint-tip-fill": DemoScenario(tip: .benchTap),
        "gallery-tip": DemoScenario(tip: .shelfStarter),
        "gallery-tip-dark": DemoScenario(tip: .shelfStarter),
        "gallery-tip-long-text": DemoScenario(tip: .shelfStarter),
        "gallery-tip-gear": DemoScenario(tip: .shelfSettings),
        "gallery-tips-off": DemoScenario(enabled: false),
        "create-tip": DemoScenario(tip: .newPaintingSuggested, closed: [.newPaintingDivider]),
        "settings-tips": DemoScenario(isMuted: true),
        "settings-tip": DemoScenario(tip: .drawerWorthALook),
    ]

    /// The tip the running scenario shows.
    static var demoTip: TipID? { DemoMode.forcedTip ?? DemoMode.scenario.flatMap { demoScenarios[$0] }?.tip }

    /// Every event 20 times, more than any tip's rule waits for, so that whichever tip a `--tip-`
    /// scenario forces is eligible. The counts themselves are written only in the rules, since
    /// TipKit's `#Rule` takes a literal and this list can't share it; every rule is a `>=`.
    private static func donateEveryRule() {
        let events = [
            TipEvents.smallMisses, TipEvents.singleTaps, TipEvents.pencilStrokes, TipEvents.stalls, TipEvents.quarters,
            TipEvents.finishes, TipEvents.sessions, TipEvents.pagesMade, TipEvents.sliderReleases, TipEvents.linesDrawn,
        ]
        Task {
            for event in events {
                for _ in 0..<20 { await event.donate() }
            }
        }
    }

    /// Waits until the scenario's tip is up (TipKit presents it a moment after the turn is given).
    static func awaitDemoTip() async {
        guard let expected = demoTip else { return }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(120)
        while desk.turn != expected, clock.now < deadline { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .seconds(1.2))
    }
    #endif
}
