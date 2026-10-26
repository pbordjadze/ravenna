import CoreGraphics
import Foundation
import Observation

/// The hand-off from Start Painting to the painting, so that the journey from the create flow's
/// settings to the canvas is one picture moving.
///
/// `AppShellView` owns one and passes it through the environment (`\.startHandoff`) to the create
/// flow's cover and, through the navigation stack, to the painting. The sequence:
///
/// 1. Start has saved the painting (with Settings › The Making-of on, after its show): the shell
///    `begin`s the hand-off and pushes the painting *under* the cover (its zoom runs unseen). The
///    cover stays up and shows what it showed.
/// 2. The painting loads, and once its canvas has its first frame on screen it reports the
///    template's rect in global coordinates (`paintingDrew`: `PaintView.reportTemplate`), and again
///    if a layout moves the template while the flow is still on its way there.
/// 3. The create flow, which observes `phase`, moves its picture (the making-of's, or the
///    preview's) to that rect while everything else fades to clear, cross-fades the picture into
///    the canvas beneath it, and `complete`s.
/// 4. The shell takes the cover away without a slide (`isFinished`) and `reset`s.
///
/// A painting that has not drawn within `StartHandoffPlan.fallback` (a slow open, an error that
/// shows the recovery screen) `timeOut`s: the cover fades out alone and the painting stays pushed.
/// `StartHandoffLogic` holds the rules without the timer, for the tests.
@Observable
final class StartHandoff {
    private(set) var logic = StartHandoffLogic()
    private let timeout: Duration
    @ObservationIgnored private var fallback: Task<Void, Never>?

    init(timeout: Duration = StartHandoffPlan.fallback) {
        self.timeout = timeout
    }

    var phase: StartHandoffLogic.Phase { logic.phase }
    /// A hand-off is under way or waiting to be taken in: the cover is up for it.
    var isRunning: Bool { logic.isRunning }
    /// The create flow is done with its dissolve: the shell takes the cover away.
    var isFinished: Bool { logic.isFinished }

    func isOpening(_ id: UUID) -> Bool { logic.isOpening(id) }

    /// Start has saved the painting `id`. True when the shell is to push it now; false when a
    /// hand-off is already under way, so a second Start does not push it twice.
    func begin(_ id: UUID) -> Bool {
        guard logic.begin(id) else { return false }
        fallback = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.timeOut()
        }
        return true
    }

    /// The painting `id` has its first frame on screen, its template at `templateRect` (global
    /// coordinates), or a layout has moved the template since. Ignored unless that painting is the
    /// one being opened, and once the flow has dissolved.
    func paintingDrew(_ id: UUID, templateRect: CGRect) {
        guard logic.paintingDrew(id, templateRect: templateRect) else { return }
        fallback?.cancel()
        fallback = nil
    }

    /// The create flow has dissolved into the painting (or faded out of its way).
    func complete() {
        logic.complete()
    }

    /// The cover is gone, or a new flow replaced the one handing over.
    func reset() {
        fallback?.cancel()
        fallback = nil
        logic.reset()
    }

    private func timeOut() {
        fallback = nil
        logic.timeOut()
    }
}

/// The rules of `StartHandoff`, without its timer.
nonisolated struct StartHandoffLogic: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        case idle
        /// The painting is pushed under the cover and has not drawn yet.
        case opening(UUID)
        /// The painting drew its first frame, its template at the rect (global coordinates).
        case ready(UUID, CGRect)
        /// It did not draw in time: the cover goes alone.
        case timedOut(UUID)
        /// The create flow has dissolved; the cover can go.
        case finished(UUID)
    }

    private(set) var phase = Phase.idle

    var isRunning: Bool { phase != .idle }

    var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    func isOpening(_ id: UUID) -> Bool {
        if case .opening(let current) = phase { return current == id }
        return false
    }

    /// Whether this call began a hand-off: only one runs at a time.
    mutating func begin(_ id: UUID) -> Bool {
        guard phase == .idle else { return false }
        phase = .opening(id)
        return true
    }

    /// Accepted from the painting being opened, and again, with a new rect, while the flow is on
    /// its way (a layout moved the template); a report after the timeout or the flow's end, from
    /// another painting or before any hand-off is ignored.
    @discardableResult
    mutating func paintingDrew(_ id: UUID, templateRect: CGRect) -> Bool {
        switch phase {
        case .opening(let current) where current == id:
            phase = .ready(id, templateRect)
            return true
        case .ready(let current, let rect) where current == id && rect != templateRect:
            phase = .ready(id, templateRect)
            return true
        default:
            return false
        }
    }

    @discardableResult
    mutating func timeOut() -> Bool {
        guard case .opening(let id) = phase else { return false }
        phase = .timedOut(id)
        return true
    }

    /// From a painting that drew, or one that timed out.
    @discardableResult
    mutating func complete() -> Bool {
        switch phase {
        case .ready(let id, _), .timedOut(let id):
            phase = .finished(id)
            return true
        case .idle, .opening, .finished:
            return false
        }
    }

    mutating func reset() {
        phase = .idle
    }

    /// The painting is pushed once: not again if it is on the stack already.
    static func shouldPush(_ id: UUID, onto path: [UUID]) -> Bool {
        !path.contains(id)
    }
}

/// How the pieces of the hand-off move and for how long. Reduce Motion moves nothing: cross-fades
/// only, over the same time.
nonisolated enum StartHandoffPlan {
    nonisolated enum Motion: Equatable, Sendable {
        /// The picture moves to where the painting's template is.
        case fly
        /// Everything fades into the painting where it stands.
        case crossFade
    }

    /// How the picture reaches `target` (global coordinates): it flies unless Reduce Motion is on or
    /// there is nowhere to fly to.
    static func motion(reduceMotion: Bool, target: CGRect?) -> Motion {
        guard !reduceMotion, let target, target.isPlace else { return .crossFade }
        return .fly
    }

    /// Where the show's picture starts, `from` being where the preview's picture was (global
    /// coordinates); nil: it starts in its place and fades in.
    static func entry(reduceMotion: Bool, from: CGRect?) -> CGRect? {
        guard !reduceMotion, let from, from.isPlace else { return nil }
        return from
    }

    /// A move: about 0.45 s with a gentle spring.
    static var move: Double { 0.45 * timeScale }
    static let bounce = 0.12
    /// The rest of the screen fades to clear while the picture moves.
    static var fade: Double { 0.3 * timeScale }
    /// A picture that comes in fades in over this time.
    static var appear: Double { 0.2 * timeScale }
    /// The picture starts to cross-fade into the canvas this long after it started to move.
    static var landAfter: Double { 0.4 * timeScale }
    /// The picture lands once the template has stayed where it is this long.
    static let settle = Duration.milliseconds(350)
    /// The cross-fade into the canvas.
    static var crossFade: Double { 0.2 * timeScale }
    /// The show's card and Skip come in after the picture has moved.
    static var chromeDelay: Double { 0.4 * timeScale }
    /// How long the painting has to draw its first frame before the cover leaves alone.
    static var fallback: Duration {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "handoffFallback")
        if seconds > 0 { return .milliseconds(Int(seconds * 1000)) }
        #endif
        return .milliseconds(Int(2500 * timeScale))
    }

    /// Debug launches can slow every duration down (`-handoffSlowdown 4`) so that a burst of
    /// screenshots catches the motion, and set how long the painting has (`-handoffFallback 20`,
    /// in seconds: CI's simulators take several to open one).
    private static var timeScale: Double {
        #if DEBUG
        let scale = UserDefaults.standard.double(forKey: "handoffSlowdown")
        return scale >= 1 ? min(scale, 10) : 1
        #else
        return 1
        #endif
    }
}

extension CGRect {
    /// A rectangle a picture can be put in: finite and at least a point each way.
    nonisolated var isPlace: Bool {
        guard !isNull, !isInfinite, origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite
        else { return false }
        return size.width >= 1 && size.height >= 1
    }
}

/// Carrying a view that fills its container, with a picture drawn at `home` in it, so the picture
/// sits at `destination`: a scale about the container's top-leading corner, then an offset. The
/// picture's width sets the scale and the two centers meet, so a rounding difference in aspect
/// splits between top and bottom.
nonisolated struct PictureTravel: Equatable, Sendable {
    var scale: CGFloat
    var dx: CGFloat
    var dy: CGFloat

    static let none = PictureTravel(scale: 1, dx: 0, dy: 0)

    init(scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        self.scale = scale
        self.dx = dx
        self.dy = dy
    }

    /// No travel for a missing or unusable destination (or home).
    init(home: CGRect, destination: CGRect?) {
        guard let destination, destination.isPlace, home.isPlace else {
            self = .none
            return
        }
        let scale = destination.width / home.width
        self.init(scale: scale, dx: destination.midX - home.midX * scale, dy: destination.midY - home.midY * scale)
    }

    /// Where `rect` of the container ends up.
    func applied(to rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + dx, y: rect.minY * scale + dy, width: rect.width * scale, height: rect.height * scale)
    }
}
