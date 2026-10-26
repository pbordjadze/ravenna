import Foundation

/// How many of a painting's areas a replay has on screen at a moment of it, which the progress
/// badge shows while the canvas plays it (`CanvasView.replay`, `PaintingSession.replayed`).
nonisolated enum ReplayProgress {
    /// While the paint lifts, `elapsed` seconds into a lift of `lift` seconds: all of the areas as
    /// it starts, fewer as it goes, none once it has gone (none at once when there is no lift, as
    /// under Reduce Motion).
    static func lifting(total: Int, elapsed: Float, lift: Float) -> Int {
        guard lift > 0 else { return 0 }
        let left = 1 - min(max(elapsed / lift, 0), 1)
        return Int((Float(total) * left).rounded(.down))
    }

    /// While the areas fill again, `elapsed` seconds after the first began and one every `step`
    /// seconds: each counts from the moment its fill begins.
    static func filling(total: Int, elapsed: Float, step: Float) -> Int {
        guard total > 0, step > 0, elapsed >= 0 else { return 0 }
        return min(total, Int(min(elapsed / step, Float(total))) + 1)
    }
}
