import UIKit

/// What the finger feels: the system's own taps, rigid for glass, soft for stone, firmer for gold,
/// as strong as the tile is large; a light tick when a paint runs out; success when a work is set.
final class TileTouch {
    static let shared = TileTouch()

    private let glass = UIImpactFeedbackGenerator(style: .rigid)
    private let stone = UIImpactFeedbackGenerator(style: .soft)
    private let gold = UIImpactFeedbackGenerator(style: .medium)
    private let notice = UINotificationFeedbackGenerator()
    private let tick = UISelectionFeedbackGenerator()
    private var last = Date.distantPast

    /// Ready the engine: a finger has landed and a tile may follow.
    func prepare() { glass.prepare(); stone.prepare(); gold.prepare() }

    /// A tile touching the bed; `size` 0...1 against the mosaic's tiles.
    func set(_ voice: Voice, size: Double) {
        let now = Date.now
        guard now.timeIntervalSince(last) > 0.04 else { return }
        last = now
        let g = switch voice {
        case .glass: glass
        case .stone: stone
        case .gold: gold
        }
        g.impactOccurred(intensity: 0.45 + 0.45 * min(max(size, 0), 1))
        g.prepare()
    }

    func miss() { notice.notificationOccurred(.error) }
    func paintDone() { tick.selectionChanged() }
    func finished() { notice.notificationOccurred(.success) }
}
