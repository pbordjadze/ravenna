import SwiftUI
import UIKit

/// Where the mosaic sits on screen: fitted, then zoomed and moved by the painter.
struct Viewport {
    var size: CGSize
    var canvas: CGSize
    var zoom: CGFloat
    var offset: CGSize

    var scale: CGFloat {
        guard canvas.width > 0, canvas.height > 0 else { return 1 }
        return min(size.width / canvas.width, size.height / canvas.height) * 0.94 * zoom
    }

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width + (p.x - canvas.width / 2) * scale,
                y: size.height / 2 + offset.height + (p.y - canvas.height / 2) * scale)
    }

    func toCanvas(_ q: CGPoint) -> CGPoint {
        CGPoint(x: canvas.width / 2 + (q.x - size.width / 2 - offset.width) / scale,
                y: canvas.height / 2 + (q.y - size.height / 2 - offset.height) / scale)
    }
}

/// The painter's lens on the wall: how far in, and where. A class, so the touch surface reads it as
/// it is now rather than as it was when the wall was last drawn.
@Observable
final class Lens {
    var size: CGSize = .zero
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    /// Where an animated move (a double tap's zoom) set out from, and when; `zoom` and `offset`
    /// are already where it is going.
    var flight: Flight?

    struct Flight {
        var zoom: CGFloat
        var offset: CGSize
        var start: Date
    }

    static let longest = 0.35

    static func viewport(_ size: CGSize, _ canvas: CGSize, zoom: CGFloat, offset: CGSize, flight: Flight?, at now: Date) -> Viewport {
        guard let f = flight else { return Viewport(size: size, canvas: canvas, zoom: zoom, offset: offset) }
        let t = min(max(now.timeIntervalSince(f.start) / longest, 0), 1)
        let e = CGFloat(1 - pow(1 - t, 3))
        // Zoom eases in proportion, so the move feels even at every scale.
        let z = f.zoom * pow(zoom / f.zoom, e)
        return Viewport(size: size, canvas: canvas, zoom: z,
                        offset: CGSize(width: f.offset.width + (offset.width - f.offset.width) * e,
                                       height: f.offset.height + (offset.height - f.offset.height) * e))
    }
}

/// The wall: tiles set and to set, the paint in hand picked out, and the fingers on it. One finger
/// lays (a tap sets a tile, a drag along a row sets the row), two move and zoom; or, as an option,
/// one finger moves the wall and a tap sets, as in v0.
struct Wall: View {
    let bench: Bench
    let finish: Finish
    let bed: UIImage?
    let save: (Setting) -> Void

    @AppStorage(Keys.finger) private var finger = OneFinger.lays
    @AppStorage(Keys.sound) private var sound = true
    @AppStorage(Keys.touch) private var touch = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var lens = Lens()

    static let maxZoom: CGFloat = 14

    var body: some View {
        let canvas = CGSize(width: CGFloat(bench.mosaic.width), height: CGFloat(bench.mosaic.height))
        // Read here, in body, so SwiftUI redraws the wall when they change.
        let state = WallState(setting: bench.setting, held: bench.paint, recent: bench.recent, press: bench.press,
                              rake: bench.rake, zoom: lens.zoom, offset: lens.offset, flight: lens.flight)
        let moving = !state.recent.isEmpty || state.press != nil || state.rake != nil || state.flight != nil
        TimelineView(.animation(paused: !moving)) { timeline in
            Canvas { ctx, size in
                draw(&ctx, Lens.viewport(size, canvas, zoom: state.zoom, offset: state.offset, flight: state.flight, at: timeline.date),
                     state, now: timeline.date)
            }
        }
        .overlay { TouchSurface(events: events(canvas)).accessibilityHidden(true) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { lens.size = $0 }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The wall")
        .accessibilityValue(spoken)
        .accessibilityHint("Use the actions to set tiles of the paint in hand, or choose a paint from the tray.")
        .accessibilityAction(named: "Set the next tile") { setNearest(1, canvas) }
        .accessibilityAction(named: "Set ten tiles") { setNearest(10, canvas) }
        .accessibilityAction(named: "Zoom in") { fly(zoom: lens.zoom * 2, around: centre, canvas) }
        .accessibilityAction(named: "Zoom out") { fly(zoom: lens.zoom / 2, around: centre, canvas) }
        .onDisappear { ended(bench.endStroke()) }
    }

    private struct WallState {
        var setting: Setting
        var held: Int?
        var recent: [Int: Date]
        var press: Int?
        var rake: Date?
        var zoom: CGFloat
        var offset: CGSize
        var flight: Lens.Flight?
    }

    private var centre: CGPoint { CGPoint(x: lens.size.width / 2, y: lens.size.height / 2) }

    private func viewport(_ canvas: CGSize) -> Viewport {
        Viewport(size: lens.size, canvas: canvas, zoom: lens.zoom, offset: lens.offset)
    }

    // MARK: The hand

    private func events(_ canvas: CGSize) -> TouchEvents {
        var e = TouchEvents()
        e.down = { p in
            lens.flight = nil
            if touch { TileTouch.shared.prepare() }
            bench.pressDown(tile(at: p, canvas))
        }
        e.drag = { a, b in
            switch finger {
            case .lays: lay(from: a, to: b, canvas)
            case .moves:
                bench.press = nil
                pan(CGSize(width: b.x - a.x, height: b.y - a.y), canvas)
            }
        }
        e.up = { p, tap in
            if tap { return setTile(at: p, canvas) }
            if finger == .lays { ended(bench.endStroke()) }
            return true
        }
        e.cancel = { ended(bench.endStroke()) }
        e.navigate = { d, k, around in
            lens.flight = nil
            zoom(by: k, around: around, canvas)
            pan(d, canvas)
        }
        e.doubleTap = { p in
            if lens.zoom < 2.2 { fly(zoom: 3.5, around: p, canvas) } else { fly(zoom: 1, around: nil, canvas) }
        }
        return e
    }

    private func tile(at q: CGPoint, _ canvas: CGSize) -> Int? {
        let vp = viewport(canvas), p = vp.toCanvas(q)
        return bench.index.tile(at: SIMD2(Float(p.x), Float(p.y)), slop: Float(14 / vp.scale))
    }

    /// A tap: sets the tile if it takes the paint in hand. Answers whether it did anything.
    private func setTile(at q: CGPoint, _ canvas: CGSize) -> Bool {
        guard let i = tile(at: q, canvas) else { bench.press = nil; return false }
        switch bench.tap(i) {
        case .set(let at):
            feel([(i, at)])
            ended(bench.afterSetting())
            return true
        case .miss:
            if touch { TileTouch.shared.miss() }
            return true
        case .nothing:
            return false
        }
    }

    /// A drag along a row: every tile of the paint in hand it passes over goes in, one after another.
    private func lay(from a: CGPoint, to b: CGPoint, _ canvas: CGSize) {
        let vp = viewport(canvas), pa = vp.toCanvas(a), pb = vp.toCanvas(b)
        let passed = bench.index.tiles(along: SIMD2(Float(pa.x), Float(pa.y)), SIMD2(Float(pb.x), Float(pb.y)),
                                       step: Float(3 / vp.scale), slop: Float(4 / vp.scale))
        feel(bench.lay(passed))
    }

    /// The sound and the tap on the finger, as each tile touches the bed.
    private func feel(_ laid: [(tile: Int, at: Date)]) {
        let sound = self.sound, touch = self.touch, m = bench.mosaic
        guard sound || touch, !laid.isEmpty else { return }
        for (i, at) in laid {
            let voice = Voice.of(m.tiles[i], in: m), size = bench.weight(i)
            let delay = max(at.timeIntervalSinceNow + Motion.contact, 0)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                if sound { TileSound.shared.play(voice, variant: i, loudness: Float(0.55 + 0.35 * size)) }
                if touch { TileTouch.shared.set(voice, size: size) }
            }
        }
    }

    /// After tiles go in: save, and mark a paint running out or the work being set.
    private func ended(_ o: Bench.Outcome) {
        if o.changed { save(bench.setting) }
        if o.finished {
            if touch { TileTouch.shared.finished() }
            if !reduceMotion { bench.beginRake() }
        } else if o.ranOut {
            if touch { TileTouch.shared.paintDone() }
            if UIAccessibility.isVoiceOverRunning, let p = bench.paint {
                AccessibilityNotification.Announcement("That paint is done. Paint \(p + 1) in hand.").post()
            }
        }
    }

    /// VoiceOver's way to set: the nearest tiles of the paint in hand to the middle of the view.
    private func setNearest(_ n: Int, _ canvas: CGSize) {
        let c = viewport(canvas).toCanvas(centre)
        var laid: [(tile: Int, at: Date)] = []
        for _ in 0..<n {
            guard let p = bench.paint, let i = bench.setting.nearestUnset(of: p, to: SIMD2(Float(c.x), Float(c.y)), in: bench.mosaic),
                  case .set(let at) = bench.tap(i) else { break }
            laid.append((i, at))
            ended(bench.afterSetting())
        }
        feel(laid)
        var said = laid.count == 1 ? "One tile set." : "\(laid.count) tiles set."
        if laid.isEmpty { said = "Nothing left to set." }
        if let p = bench.paint { said += " Paint \(p + 1), \(bench.setting.remaining(in: bench.mosaic)[p]) left." }
        AccessibilityNotification.Announcement(said).post()
    }

    private var spoken: String {
        let m = bench.mosaic, s = bench.setting
        var v = "\(s.set.count.formatted()) of \(m.tiles.count.formatted()) tiles set."
        if let p = bench.paint { v += " Paint \(p + 1) in hand, \(s.remaining(in: m)[p].formatted()) left." }
        return v
    }

    // MARK: Moving the wall

    private func zoom(by k: CGFloat, around a: CGPoint, _ canvas: CGSize) {
        let z = min(max(lens.zoom * k, 1), Self.maxZoom)
        let r = z / lens.zoom, cx = lens.size.width / 2, cy = lens.size.height / 2
        // Keep the point under the fingers where it is.
        lens.offset = CGSize(width: a.x - cx - (a.x - cx - lens.offset.width) * r,
                             height: a.y - cy - (a.y - cy - lens.offset.height) * r)
        lens.zoom = z
        clamp(canvas)
    }

    private func pan(_ d: CGSize, _ canvas: CGSize) {
        lens.offset.width += d.width
        lens.offset.height += d.height
        clamp(canvas)
    }

    /// The wall can't be lost off screen: its middle stays in view.
    private func clamp(_ canvas: CGSize) {
        let s = viewport(canvas).scale
        let x = canvas.width * s / 2, y = canvas.height * s / 2
        lens.offset = CGSize(width: min(max(lens.offset.width, -x), x), height: min(max(lens.offset.height, -y), y))
    }

    /// A zoom that moves: to `zoom` round a point, or back to the whole wall.
    private func fly(zoom target: CGFloat, around a: CGPoint?, _ canvas: CGSize) {
        let from = Lens.Flight(zoom: lens.zoom, offset: lens.offset, start: .now)
        if let a {
            zoom(by: target / lens.zoom, around: a, canvas)
        } else {
            lens.zoom = min(max(target, 1), Self.maxZoom)
            lens.offset = .zero
        }
        guard !reduceMotion else { return }
        lens.flight = from
        let lens = self.lens, start = from.start
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Lens.longest + 0.02))
            if lens.flight?.start == start { lens.flight = nil }
        }
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, _ vp: Viewport, _ state: WallState, now: Date) {
        let m = bench.mosaic, d = bench.drawing(finish), s = vp.scale
        let wall = CGRect(origin: .zero, size: vp.canvas)
        let settling = state.recent.filter { now.timeIntervalSince($0.value) < Motion.total }
        // Tiles that have finished settling go into the wall's image; until then they're drawn live.
        let image = bench.wall(finish, bed: bed)
        let live = image.map { bench.bakeSettled($0, settling: settling) } ?? []

        var g = ctx
        g.translateBy(x: vp.size.width / 2 + vp.offset.width, y: vp.size.height / 2 + vp.offset.height)
        g.scaleBy(x: s, y: s)
        g.translateBy(x: -vp.canvas.width / 2, y: -vp.canvas.height / 2)
        if let cg = image?.current {
            g.draw(Image(decorative: cg, scale: 1), in: wall)
        } else {
            g.fill(Path(wall), with: .color(Color(m.grout)))
        }

        let lo = vp.toCanvas(.zero), hi = vp.toCanvas(CGPoint(x: vp.size.width, y: vp.size.height))
        let visible = bench.index.tiles(in: SIMD2(Float(lo.x), Float(lo.y)), SIMD2(Float(hi.x), Float(hi.y)))
        // Zoomed in past the image's own detail: draw the tiles on screen sharp.
        let sharp = s * displayScale > (image?.scale ?? 0) * 1.4
        let reduce = reduceMotion
        g.withCGContext { cg in
            for i in live where !sharp { d.draw(i, in: cg) }
            if sharp {
                for i in visible where settling[i] == nil && state.setting.isSet(i) { d.draw(i, in: cg) }
                for i in visible where !state.setting.isSet(i) { cg.addPath(d.paths[i]) }
                cg.setStrokeColor(d.outline)
                cg.setLineWidth(0.8 / s)
                cg.strokePath()
            }
            // The tessera under a finger, held over its place.
            if let p = state.press, !state.setting.isSet(p) {
                if reduce {
                    cg.addPath(d.paths[p]); cg.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor); cg.fillPath()
                } else {
                    raised(p, lift: 1, glint: nil, d, cg)
                }
            }
            // Tiles settling: down from their raised place, catching the light once.
            for (i, at) in settling {
                let t = now.timeIntervalSince(at)
                guard t >= 0, vp.canvas.width > 0 else { continue }
                if reduce {
                    cg.saveGState(); cg.setAlpha(Motion.fade(t))
                    d.draw(i, in: cg, glint: Motion.glinting(t))
                    cg.restoreGState()
                } else {
                    raised(i, lift: 1 - Motion.settled(t), glint: Motion.glinting(t), d, cg)
                }
            }
        }

        // The paint in hand, picked out where it goes.
        if let held = state.held {
            var marks = Path()
            for i in visible where m.tiles[i].paint == held && !state.setting.isSet(i) && i != state.press { marks.addPath(Path(d.paths[i])) }
            g.fill(marks, with: .color(.white.opacity(0.16)))
        }

        // Light raking once across the finished wall, as a lamp carried past it.
        if let r = state.rake {
            let t = now.timeIntervalSince(r) / Bench.rakeTime
            if t > 0, t < 1 {
                let at = -0.3 + 1.6 * t
                var lit = g
                lit.blendMode = .plusLighter
                lit.fill(Path(wall), with: .linearGradient(
                    Gradient(stops: [.init(color: .clear, location: max(at - 0.18, 0)),
                                     .init(color: Theme.gold.opacity(0.32 * sin(.pi * t)), location: min(max(at, 0), 1)),
                                     .init(color: .clear, location: min(max(at + 0.18, 0), 1))]),
                    startPoint: .zero, endPoint: CGPoint(x: wall.maxX, y: wall.maxY)))
            }
        }

        // Numbers, once a tile is big enough on screen to read one.
        var texts: [Int: GraphicsContext.ResolvedText] = [:]
        let ink = finish.paintedBed ? Theme.plaster : Color(red: 0.25, green: 0.23, blue: 0.21)
        for i in visible where !state.setting.isSet(i) && i != state.press {
            let side = d.sizes[i] * s
            guard side >= 16 else { continue }
            let paint = m.tiles[i].paint
            let size = Int(min(max(side * 0.4, 8), 20))
            let key = paint * 64 + size
            let text = texts[key] ?? ctx.resolve(Text("\(paint + 1)")
                .font(.system(size: CGFloat(size), weight: .semibold, design: .serif))
                .foregroundStyle(ink))
            texts[key] = text
            ctx.draw(text, at: vp.toScreen(d.centres[i]))
        }
    }

    /// A tile over its place: `lift` 1 is held up (larger, turned a little, its shadow below), 0 is
    /// set; slightly below 0 is pressed a hair into the bed.
    private func raised(_ i: Int, lift: Double, glint: Double?, _ d: Drawing, _ cg: CGContext) {
        let c = d.centres[i], k = 1 + CGFloat(Motion.lift) * CGFloat(lift)
        let turn = CGFloat(0.035 * Double(TileColor.wobble(i, salt: 5)) * max(lift, 0))
        cg.saveGState()
        if lift > 0.02 {
            cg.saveGState()
            cg.translateBy(x: d.sizes[i] * 0.14 * lift, y: d.sizes[i] * 0.2 * lift)
            turnAbout(c, k, turn, cg)
            cg.addPath(d.paths[i])
            cg.setFillColor(UIColor.black.withAlphaComponent(0.45 * lift).cgColor)
            cg.fillPath()
            cg.restoreGState()
        }
        turnAbout(c, k, turn, cg)
        d.draw(i, in: cg, glint: glint)
        cg.restoreGState()
    }

    private func turnAbout(_ c: CGPoint, _ k: CGFloat, _ turn: CGFloat, _ cg: CGContext) {
        cg.translateBy(x: c.x, y: c.y)
        cg.rotate(by: turn)
        cg.scaleBy(x: k, y: k)
        cg.translateBy(x: -c.x, y: -c.y)
    }
}
