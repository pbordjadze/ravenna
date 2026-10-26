import CoreGraphics
import Foundation
import MakingOf
import Observation
import os
import PaintCore

/// Plays a painting's making-of show for `MakingOfView`. It makes the show off the main actor
/// (`MakingOfShow.build`), then either plays it in time, or under Reduce Motion steps through
/// stills.
///
/// - In time: `time(at:)` from `origin`. A background task composites the picture on the CPU
///   (`FieldShow.composite`: the layers, the ink and the fronts' tide lines, the part of a frame a
///   shader would do) at most `frameInterval` apart into one plane it keeps, and hands each as
///   `picture`; the view draws the rest of every frame itself from `FieldShow.frame(at:)` (numbers,
///   the real template, seed rings, sparks, stars, the card). The photo and the finished drawing
///   don't change, so they are composited once. VoiceOver hears each step's card as it comes in.
/// - Reduce Motion: no moving marks and no reveal: `stills`, the picture as each step leaves it
///   with that step's card at full strength, `ShowSpec.Timing.step` apart (the view cross-fades
///   them), and the real template last.
///
/// It ends once, through `onFinish`: the show over, Skip or a tap (`skip`), or a show that
/// couldn't be made; the screen then shows its last frame until it goes, and `release` lets go of
/// the show. A show cancelled because its screen went (never by the painter) calls nothing: what
/// took the screen away decides what comes next.
@Observable
final class MakingOfPlayer {
    enum Phase: Equatable {
        /// The show is being made: the photo shows, which is how the show begins.
        case preparing
        /// In time (`time(at:)`, `picture`).
        case playing
        /// Reduce Motion: `stills[still]`.
        case stills
        /// Over, skipped or failed: the last frame holds until the screen goes.
        case finished
    }

    /// A still of Reduce Motion: a frame without the moving marks, its picture, and its card's
    /// step (nil for the real template at the end).
    nonisolated struct Still: Sendable {
        let frame: ShowFrame
        let picture: CGImage?
        let step: Int?
    }

    private(set) var phase = Phase.preparing
    private(set) var built: MakingOfShow?
    /// The newest composited picture while playing.
    private(set) var picture: CGImage?
    private(set) var stills: [Still] = []
    private(set) var still = 0
    /// When the show's time 0 is, once it plays.
    @ObservationIgnored private(set) var origin = Date.distantFuture
    /// The show's time it ended at, which its last frame holds.
    @ObservationIgnored private(set) var endedAt: Double?
    @ObservationIgnored private var onFinish: (() -> Void)?
    @ObservationIgnored private var work: Task<Void, Never>?

    /// At most 30 pictures a second: the reveals are soft, and the marks over them (the numbers,
    /// rings, sparks and stars) are drawn at the display's rate.
    nonisolated static let frameInterval = 1.0 / 30
    /// The show starts this long after it is made, so its first picture is ready when it is due.
    static let lead = 0.1
    /// A card is announced this long into its step, as it has faded in.
    static let announceAfter = 0.15
    /// Reduce Motion: how long the real template shows at the end.
    static let lastStill = 1.5

    /// The show's time at `date`.
    func time(at date: Date) -> Double {
        endedAt ?? date.timeIntervalSince(origin)
    }

    /// Makes the show from `source` and plays it (Reduce Motion: its stills), then calls
    /// `onFinish`, unless the task is cancelled first (the screen went).
    func run(_ source: MakingOfSource, reduceMotion: Bool, onFinish: @escaping () -> Void) async {
        guard work == nil, phase == .preparing else { return }
        self.onFinish = onFinish
        let work = Task { await self.perform(source, reduceMotion: reduceMotion) }
        self.work = work
        await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// Ends the show now and opens the painting.
    func skip() {
        work?.cancel()
        finish()
    }

    /// Lets go of the show (its screen has gone).
    func release() {
        work?.cancel()
        onFinish = nil
        built = nil
        picture = nil
        stills = []
    }

    private func perform(_ source: MakingOfSource, reduceMotion: Bool) async {
        do {
            let built = try await MakingOfShow.build(source)
            try Task.checkCancellation()
            self.built = built
            if reduceMotion {
                try await playStills(built)
            } else {
                try await play(built)
            }
            finish()
        } catch is CancellationError {
            // Skipped, or the screen went.
        } catch {
            Log.create.error("Making-of couldn't be made: \(String(describing: error), privacy: .public)")
            finish()
        }
    }

    private func finish() {
        guard phase != .finished else { return }
        if phase == .playing, let built { endedAt = min(max(time(at: .now), 0), built.show.duration) }
        phase = .finished
        let done = onFinish
        onFinish = nil
        done?()
    }

    // MARK: In time

    private func play(_ built: MakingOfShow) async throws {
        let origin = Date.now.addingTimeInterval(Self.lead)
        self.origin = origin
        phase = .playing
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await Self.composite(built, from: origin, to: self) }
            try await self.narrate(built)
            group.cancelAll()
        }
    }

    /// Sleeps through the show, announcing each card as it comes in.
    private func narrate(_ built: MakingOfShow) async throws {
        let timing = built.show.timeline.timing
        for k in 0..<ScheduleTiming.steps {
            try await sleep(until: timing.start(k) + Self.announceAfter)
            Announcer.announce(built.cards[k].spoken)
        }
        try await sleep(until: built.show.duration)
    }

    private func sleep(until t: Double) async throws {
        let wait = origin.addingTimeInterval(t).timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
    }

    private func present(_ image: CGImage) {
        guard phase == .playing else { return }
        picture = image
    }

    /// Composites the picture of the moment, again and again until cancelled or the show is over,
    /// and hands each to `player`.
    @concurrent
    private static func composite(_ built: MakingOfShow, from origin: Date, to player: MakingOfPlayer) async {
        let show = built.show
        var pixels = Plane<SIMD4<UInt8>>(width: show.size.width, height: show.size.height, repeating: .zero)
        var shownStage: Int?
        var shownInk: [InkLine] = []
        while !Task.isCancelled {
            let began = Date.now
            let t = max(began.timeIntervalSince(origin), 0)
            guard t <= show.duration else { return }
            let frame = show.frame(at: t)
            let stage = frame.picture.stage
            // the photo, and the finished drawing once its lines are still, don't change
            let settled = stage < 0 || stage >= ScheduleTiming.steps
            if !(settled && shownStage == stage && shownInk == frame.ink) {
                if let image = built.picture(frame, into: &pixels) { await player.present(image) }
                shownStage = stage
                shownInk = frame.ink
            }
            let spent = Date.now.timeIntervalSince(began)
            try? await Task.sleep(for: .seconds(max(frameInterval - spent, 0.002)))
        }
    }

    // MARK: Reduce Motion

    private func playStills(_ built: MakingOfShow) async throws {
        stills = await Self.stills(of: built)
        try Task.checkCancellation()
        still = 0
        phase = .stills
        for i in stills.indices {
            still = i
            if let k = stills[i].step { Announcer.announce(built.cards[k].spoken) }
            try await Task.sleep(for: .seconds(stills[i].step == nil ? Self.lastStill : built.spec.timing.step))
        }
    }

    /// Reduce Motion's stills (`MakingOfShow.stillTimes`), without the seed rings, sparks or stars.
    @concurrent
    static func stills(of built: MakingOfShow) async -> [Still] {
        let show = built.show
        var pixels = Plane<SIMD4<UInt8>>(width: show.size.width, height: show.size.height, repeating: .zero)
        var stills: [Still] = []
        for (i, t) in MakingOfShow.stillTimes(show.timeline.timing).enumerated() {
            var frame = show.frame(at: t)
            frame.seedRings = []
            frame.sparks = []
            frame.stars = []
            stills.append(Still(
                frame: frame, picture: built.picture(frame, into: &pixels), step: i < ScheduleTiming.steps ? i : nil))
        }
        return stills
    }
}

#if DEBUG
extension MakingOfPlayer {
    /// Demo scenarios: makes the show and holds it at `time` (Reduce Motion: at still number
    /// `time`), then calls `onReady` once it has had a moment to draw.
    func hold(_ source: MakingOfSource, at time: Double, reduceMotion: Bool, onReady: @escaping () -> Void) async {
        do {
            let built = try await MakingOfShow.build(source)
            self.built = built
            if reduceMotion {
                stills = await Self.stills(of: built)
                still = min(max(Int(time), 0), stills.count - 1)
                phase = .stills
            } else {
                endedAt = time
                origin = .now
                picture = await Self.picture(of: built, at: time)
                phase = .playing
            }
            try await Task.sleep(for: .seconds(1))
            onReady()
        } catch {
            Log.demo.error("Making-of demo failed: \(String(describing: error), privacy: .public)")
        }
    }

    @concurrent
    private static func picture(of built: MakingOfShow, at time: Double) async -> CGImage? {
        let show = built.show
        var pixels = Plane<SIMD4<UInt8>>(width: show.size.width, height: show.size.height, repeating: .zero)
        return built.picture(show.frame(at: time), into: &pixels)
    }
}
#endif
