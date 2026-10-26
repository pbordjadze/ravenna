import Foundation
import Observation
import PaintCore
import SwiftUI
import UIKit

/// Transient chrome reactions to painting events, undo registration, and the tips they feed: the
/// moments of the bench at which a tip may speak (see `TipDesk`), and what keeps them quiet.
@Observable
final class PaintChromeState {
    /// Per color: bumped to shake its swatch.
    var shakes: [Int: Int] = [:]
    /// Quiet painting (`QuietPainting`): an area was painted since the progress ring last brought
    /// the top bar back.
    var wantsQuiet = false
    /// The window's undo manager: every fill is registered with it (⌘Z, the Edit menu,
    /// three-finger undo and redo).
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var observed: ObjectIdentifier?

    // The tips' view of the bench.
    @ObservationIgnored private weak var tipSession: PaintingSession?
    /// Give Feedback is on: no hint speaks.
    @ObservationIgnored var isGivingFeedback = false
    /// Since when a finger has been moving or zooming the page (the canvas reports it).
    @ObservationIgnored private var handDownSince: ContinuousClock.Instant?
    @ObservationIgnored private var lastFill: ContinuousClock.Instant?
    @ObservationIgnored private var finishedAt: ContinuousClock.Instant?
    @ObservationIgnored private var singleFills = 0
    @ObservationIgnored private var fillsThisVisit = 0
    @ObservationIgnored private var passedQuarter = false
    @ObservationIgnored private var idle: Task<Void, Never>?
    @ObservationIgnored private var afterShine: Task<Void, Never>?

    /// The longest a finger is taken to hold the page without the canvas reporting a change.
    private static let handLimit: Duration = .seconds(10)
    /// A fill lands in this long.
    private static let fillSettle: Duration = .milliseconds(900)
    /// Zen Mode flies to the next area after a fill; after a finished color's shine first.
    private static let zenDrift: Duration = .seconds(3)
    /// The finish: the last fill, the camera's flight to the whole page and its shine.
    private static let shine: Duration = .seconds(4)
    /// A pause with no stroke, for the second session's Zen Mode; and a minute with no fill while
    /// the selected color has areas left, for where to find one.
    private static let calmPause: Duration = .seconds(20)
    private static let stallPause: Duration = .seconds(60)
    /// Every this many single fills, Paint Several Areas is looked at (Ravenna's seam: every 5 in
    /// Paint by Moonlight, which offers it after 15; Ravenna after 3, `DragPaintTip`).
    private static let dragCheckEvery = 3
    /// About a quarter of a page.
    private static let quarter = 0.25

    func observe(_ session: PaintingSession) {
        guard observed != ObjectIdentifier(session) else { return }
        observed = ObjectIdentifier(session)
        tipSession = session
        PaintTips.paintingOpened(hasProgress: session.isStarted)
        passedQuarter = session.fractionComplete >= Self.quarter
        PaintTips.desk.enter(.bench)
        benchOpened(session)
        session.onEvent { [weak self, weak session] event in
            if let session, let signal = PaintTips.signal(for: event, isStroking: session.isStroking) {
                self?.tipSignal(signal)
            }
            switch event {
            case let .painted(regions, _):
                if let session, !session.isStroking { self?.registerUndo(of: regions.count, in: session) }
            case let .strokeEnded(regions):
                if let session { self?.registerUndo(of: regions.count, in: session) }
            case let .rejected(_, expected):
                // Without animation the shake's whole-number step leaves the swatch in place.
                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .linear(duration: 0.45)) {
                    self?.shakes[expected, default: 0] += 1
                }
            case let .colorCompleted(color):
                // The fill that finishes the painting finishes a color too: only the painting is
                // announced.
                if let session, !session.isComplete {
                    Announcer.announce(PaintSpeech.colorFinished(number: color + 1, name: session.colorNames[color], nickname: session.nickname(of: color)))
                }
            case .artworkCompleted:
                // The canvas flies out to the whole painting (`CanvasView.finish`).
                Announcer.announce(PaintSpeech.paintingFinished)
                self?.pageFinished()
            default:
                break
            }
        }
    }

    /// Undo takes back the fills of one tap or one whole stroke. Redoing paints them again,
    /// which registers the next undo through the same event.
    private func registerUndo(of count: Int, in session: PaintingSession) {
        guard let undoManager else { return }
        // UndoManager calls back on the thread that undoes: the main thread.
        undoManager.registerUndo(withTarget: session) { [weak self] session in
            MainActor.assumeIsolated { self?.undoFills(count, in: session) }
        }
        undoManager.setActionName(String(localized: "Paint"))
    }

    private func undoFills(_ count: Int, in session: PaintingSession) {
        let undone = (0..<count).compactMap { _ in session.undo() }
        guard let undoManager, let first = undone.first else { return }
        undoManager.registerUndo(withTarget: session) { session in
            MainActor.assumeIsolated {
                let origin = session.template.labels(ofRegion: first).first?.position ?? .zero
                session.paint(undone.reversed(), from: origin, animated: true)
            }
        }
        undoManager.setActionName(String(localized: "Paint"))
    }

    // MARK: Tips

    /// What the painter did, as far as the tips go: donations and what the thing used silences
    /// (`PaintTips.record`), then the moments it makes.
    func tipSignal(_ signal: PaintTips.Signal) {
        PaintTips.record(signal)
        restartIdle()
        switch signal {
        case .tapPainted:
            filled()
            singleFills += 1
            if singleFills.isMultiple(of: Self.dragCheckEvery) { offer([.benchDrag]) }
        case .strokePainted, .strokeEnded:
            filled()
        case .missedSmallArea:
            offer([.benchZoom])
        case .pencilUsed:
            offer([.benchPencil])
        case .wrongColor, .hintShown, .zoomed:
            break
        }
    }

    /// The painter chose a color, or did anything else on the screen.
    func activity() {
        PaintTips.desk.noteActivity()
        restartIdle()
    }

    /// A finger took hold of the page to move or zoom it, or let go.
    func handChanged(_ down: Bool) {
        handDownSince = down ? ContinuousClock.now : nil
        activity()
    }

    /// The painting screen goes: a painting session, if the painter filled anything in it.
    func close() {
        idle?.cancel()
        afterShine?.cancel()
        PaintTips.desk.leave(.bench)
        PaintTips.desk.paintingClosed()
        if fillsThisVisit > 0 { PaintTips.donate(TipEvents.sessions, limit: 20) }
    }

    private func filled() {
        lastFill = ContinuousClock.now
        // Strokes paint many times a second: set once, so the bar's observers aren't woken each time.
        if QuietPainting.isAvailable && !wantsQuiet { wantsQuiet = true }
        fillsThisVisit += 1
        guard !passedQuarter, let session = tipSession, session.fractionComplete >= Self.quarter else { return }
        passedQuarter = true
        PaintTips.donate(TipEvents.quarters, limit: 2)
        offer([.benchShowPhoto])
    }

    /// The painting opens: a fresh one says how to paint; the third painting, or one past a
    /// quarter, may have something to say once the hand has rested (`TipMoments.benchOpened`).
    private func benchOpened(_ session: PaintingSession) {
        restartIdle()
        guard !session.isComplete else { return }
        let fresh = !session.isStarted
        if passedQuarter { PaintTips.donate(TipEvents.quarters, limit: 2) }
        let due = TipMoments.benchOpened(fresh: fresh, feedbackIsDue: PaintTips.desk.feedbackIsDue, pastQuarter: passedQuarter)
        offer(due, rest: fresh ? .milliseconds(700) : .seconds(2))
    }

    /// The last area is painted: once the camera has flown out and the shine has passed, the only
    /// hint is the replay.
    private func pageFinished() {
        finishedAt = ContinuousClock.now
        PaintTips.desk.finished()
        let wait = UIAccessibility.isReduceMotionEnabled ? Duration.milliseconds(1500) : Self.shine + .milliseconds(500)
        afterShine?.cancel()
        afterShine = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.tipSession?.isComplete == true else { return }
            PaintTips.donate(TipEvents.finishes, limit: 2)
            offer([.benchReplay], rest: .seconds(1))
        }
    }

    /// Two checks while the painter sits still: after a short pause with no stroke, the second
    /// painting session's Zen Mode; after a minute with no fill while the selected color has areas
    /// left, where to find one.
    private func restartIdle() {
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: Self.calmPause)
            guard !Task.isCancelled else { return }
            self?.paused()
            try? await Task.sleep(for: Self.stallPause - Self.calmPause)
            guard !Task.isCancelled else { return }
            self?.stalled()
        }
    }

    private func paused() {
        guard let session = tipSession, !session.isComplete else { return }
        offer([.benchZen], rest: .zero)
    }

    private func stalled() {
        guard let session = tipSession, !session.isComplete, let color = session.selectedColor,
              session.remainingByColor[color] > 0 else { return }
        PaintTips.donate(TipEvents.stalls, limit: 4)
        offer([.benchFind], rest: .zero)
    }

    /// A moment of the bench. Nothing but Tap to Paint speaks before the first fill.
    private func offer(_ ids: [TipID], rest: Duration = .milliseconds(1500)) {
        let ids = ids.filter { $0 == .benchTap || PaintTips.desk.hasFilled }
        PaintTips.desk.offer(ids, in: .bench, rest: rest) { [weak self] in self?.quiet ?? [] }
    }

    /// What keeps the hints away just now (`TipPacing.Quiet`).
    private var quiet: TipPacing.Quiet {
        guard let session = tipSession else { return [] }
        let now = ContinuousClock.now
        var quiet: TipPacing.Quiet = []
        // A hand that the canvas never reported lifting (a fling stopped by a touch) is not on the
        // page for ever.
        if let handDownSince, now - handDownSince < Self.handLimit { quiet.insert(.handOnPage) }
        if session.isStroking { quiet.insert(.handOnPage) }
        if let lastFill, now - lastFill < Self.fillSettle { quiet.insert(.filling) }
        if let lastFill, session.flowsToNextArea, now - lastFill < Self.zenDrift { quiet.insert(.zenDrifting) }
        if session.replayed != nil { quiet.insert(.replay) }
        if isGivingFeedback { quiet.insert(.feedback) }
        if session.isComplete {
            quiet.insert(.pageFinished)
            let shine = UIAccessibility.isReduceMotionEnabled ? Duration.milliseconds(1200) : Self.shine
            if let finishedAt, now - finishedAt < shine { quiet.insert(.shine) }
        }
        return quiet
    }
}
