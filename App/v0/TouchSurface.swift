import SwiftUI
import UIKit

/// What the painter's fingers do on the wall, in the wall's own points.
struct TouchEvents {
    /// A finger lands: a tessera may rise under it.
    var down: (CGPoint) -> Void = { _ in }
    /// One finger moved, once past a little slop: laying a row, or moving the wall.
    var drag: (_ from: CGPoint, _ to: CGPoint) -> Void = { _, _ in }
    /// It lifted; `tap` if it never moved. Answers whether the tap did something (a tap that did
    /// nothing, twice, zooms).
    var up: (_ at: CGPoint, _ tap: Bool) -> Bool = { _, _ in false }
    /// A second finger came, or the system took the touch: no tap.
    var cancel: () -> Void = {}
    /// Two fingers moved the wall: by `pan`, scaled by `scale` round `around`.
    var navigate: (_ pan: CGSize, _ scale: CGFloat, _ around: CGPoint) -> Void = { _, _, _ in }
    var navigated: () -> Void = {}
    var doubleTap: (CGPoint) -> Void = { _ in }
}

/// The wall's touch surface: one finger lays (or, as an option, moves), two fingers move and zoom.
/// Plain touches rather than gesture recognizers, so a tessera can rise the moment a finger lands
/// and a row can be laid without waiting to tell a drag from a pan.
struct TouchSurface: UIViewRepresentable {
    var events: TouchEvents

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.events = events
        return v
    }

    func updateUIView(_ v: TouchView, context: Context) { v.events = events }
}

final class TouchView: UIView {
    var events = TouchEvents()

    private enum Mode { case idle, single, navigating, done }
    private var mode = Mode.idle
    private var start = CGPoint.zero, last = CGPoint.zero, moved = false
    private var pair: (centre: CGPoint, distance: CGFloat)?
    private var lastIdleTap: (at: CGPoint, when: TimeInterval)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func active(_ event: UIEvent?) -> [UITouch] {
        (event?.allTouches ?? []).filter { $0.view === self && $0.phase != .ended && $0.phase != .cancelled }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = active(event)
        switch mode {
        case .idle where now.count == 1:
            mode = .single
            start = now[0].location(in: self); last = start; moved = false
            events.down(start)
        case .idle, .single:
            if mode == .single { events.cancel() }
            mode = now.count >= 2 ? .navigating : .done
            pair = measure(now)
        case .navigating, .done:
            if now.count >= 2 { mode = .navigating; pair = measure(now) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = active(event)
        switch mode {
        case .single:
            guard let t = now.first else { return }
            let p = t.location(in: self)
            if !moved, hypot(p.x - start.x, p.y - start.y) > 6 { moved = true }
            if moved { events.drag(last, p); last = p }
        case .navigating:
            guard now.count >= 2, let old = pair, let new = measure(now) else { return }
            events.navigate(CGSize(width: new.centre.x - old.centre.x, height: new.centre.y - old.centre.y),
                            old.distance > 0 ? new.distance / old.distance : 1, new.centre)
            pair = new
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(event, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(event, cancelled: true) }

    private func finish(_ event: UIEvent?, cancelled: Bool) {
        let now = active(event)
        switch mode {
        case .single:
            mode = .idle
            if cancelled { events.cancel(); return }
            let did = events.up(last, !moved)
            if moved { events.navigated(); lastIdleTap = nil; return }
            // A tap that did nothing, twice in the same place: zoom there.
            let t = ProcessInfo.processInfo.systemUptime
            if !did {
                if let prev = lastIdleTap, t - prev.when < 0.35, hypot(prev.at.x - last.x, prev.at.y - last.y) < 40 {
                    lastIdleTap = nil
                    events.doubleTap(last)
                } else {
                    lastIdleTap = (last, t)
                }
            } else {
                lastIdleTap = nil
            }
        case .navigating, .done:
            if now.count >= 2 { pair = measure(now); return }
            if now.isEmpty { mode = .idle; pair = nil; events.navigated() } else { mode = .done }
        case .idle:
            break
        }
    }

    private func measure(_ touches: [UITouch]) -> (centre: CGPoint, distance: CGFloat)? {
        guard touches.count >= 2 else { return nil }
        // The same two fingers each time, whatever order the event lists them in.
        let two = touches.sorted { $0.hash < $1.hash }
        let a = two[0].location(in: self), b = two[1].location(in: self)
        return (CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), hypot(a.x - b.x, a.y - b.y))
    }
}
