import CoreHaptics
import Foundation

/// Custom Core Haptics patterns shaped to match what the user sees: a soft press followed
/// by a swell that decays as the paint spreads, a gentle "nope", a bright triple for a
/// finished color and a rising shimmer for a finished painting.
///
/// The engine and everything below live on `queue`, which plays the patterns in the order
/// they're asked for: starting the engine blocks its caller, and building a pattern and a
/// player for every fill is work the painting screen's main thread, which also draws the
/// canvas, is better without (as `SoundPlayer` does for sounds).
nonisolated final class HapticsPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pbordjadze.paintbynumber.haptics", qos: .userInitiated)
    private var engine: CHHapticEngine?
    private let isSupported: Bool
    private var lastPaint: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    #if DEBUG
    /// What was asked to play, in order (on `queue`): `played()`.
    private var asked: [String] = []
    #endif

    /// `isSupported` true runs the queue where Core Haptics has no engine (CI's simulators), for
    /// a test to see what it plays.
    init(isSupported: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics) {
        self.isSupported = isSupported
    }

    /// Paint spreading over a region. `strength` 0…1 (bigger regions feel heavier),
    /// `duration` matches the fill animation.
    func paint(strength: Float, duration: TimeInterval) {
        let now = clock.now
        perform { [self] in
            // Drag painting can fire many fills per second; keep it a texture, not a buzz.
            if let last = lastPaint, now - last < .milliseconds(45) { return }
            lastPaint = now

            let s = min(max(strength, 0), 1)
            let d = min(max(duration, 0.12), 0.8)
            let press = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [param(.hapticIntensity, 0.45 + 0.4 * s), param(.hapticSharpness, 0.45)],
                relativeTime: 0)
            let swell = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [param(.hapticIntensity, 0.25 + 0.35 * s), param(.hapticSharpness, 0.12)],
                relativeTime: 0.015, duration: d)
            let fade = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 1),
                    .init(relativeTime: d * 0.35, value: 0.6),
                    .init(relativeTime: d, value: 0),
                ],
                relativeTime: 0.015)
            play("paint", [press, swell], curves: [fade])
        }
    }

    /// Tapped a region that wants a different color.
    func reject() {
        perform { [self] in
            play("reject", [
                CHHapticEvent(eventType: .hapticTransient, parameters: [param(.hapticIntensity, 0.5), param(.hapticSharpness, 0.15)], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [param(.hapticIntensity, 0.35), param(.hapticSharpness, 0.15)], relativeTime: 0.085),
            ])
        }
    }

    /// Every region of a color is painted.
    func colorComplete() {
        perform { [self] in
            play("colorComplete", (0..<3).map { i in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [param(.hapticIntensity, 0.55 + 0.2 * Float(i)), param(.hapticSharpness, 0.6 + 0.15 * Float(i))],
                    relativeTime: 0.12 + 0.075 * Double(i))
            })
        }
    }

    /// The whole painting is finished.
    func celebrate() {
        perform { [self] in
            var events = [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [param(.hapticIntensity, 0.6), param(.hapticSharpness, 0.25)],
                    relativeTime: 0, duration: 0.7),
            ]
            let rise = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [.init(relativeTime: 0, value: 0.1), .init(relativeTime: 0.55, value: 1), .init(relativeTime: 0.7, value: 0)],
                relativeTime: 0)
            var rng = SystemRandomNumberGenerator()
            for i in 0..<9 {
                let t = 0.6 + 0.09 * Double(i) + Double.random(in: 0...0.03, using: &rng)
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [param(.hapticIntensity, 0.9 - 0.08 * Float(i)), param(.hapticSharpness, 0.85)],
                    relativeTime: t))
            }
            play("celebrate", events, curves: [rise])
        }
    }

    /// Light detent, e.g. picking a color or undoing.
    func tick() {
        perform { [self] in
            play("tick", [CHHapticEvent(eventType: .hapticTransient, parameters: [param(.hapticIntensity, 0.4), param(.hapticSharpness, 0.8)], relativeTime: 0)])
        }
    }

    /// Spins the engine up ahead of the first interaction so the first paint isn't late.
    func prepare() {
        perform { [self] in _ = ensureEngine() }
    }

    // MARK: Engine (on `queue`)

    /// Runs `work` on `queue`, on devices that have haptics (iPads don't).
    private func perform(_ work: @escaping @Sendable () -> Void) {
        guard isSupported else { return }
        queue.async(execute: work)
    }

    private func param(_ id: CHHapticEvent.ParameterID, _ value: Float) -> CHHapticEventParameter {
        CHHapticEventParameter(parameterID: id, value: value)
    }

    private func ensureEngine() -> CHHapticEngine? {
        if let engine { return engine }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            // No reset/stopped handlers: they run on arbitrary threads. A failed play below
            // drops the engine and the next interaction rebuilds it.
            try engine.start()
            self.engine = engine
            return engine
        } catch {
            return nil
        }
    }

    #if DEBUG
    /// What was asked to play so far, in order, once the work asked before this call has run.
    func played() -> [String] { queue.sync { asked } }
    #endif

    private func play(_ name: String, _ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(queue))
        asked.append(name)
        #endif
        guard let engine = ensureEngine() else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Engine may have been stopped by the system; rebuild on next use.
            self.engine = nil
        }
    }
}
