import SwiftUI
import UIKit

/// The making-of: the mosaic set the way the old workshops set one, each step's technique named on a
/// card (`MakingOf` in MosaicKit plans it; docs/making-of.md has the cards' sources). The glass first,
/// then the drawing on the bed, the painted bed, the face, the outlines, the rows that echo them, and
/// a light crossing the finished work. Tiles are set, never painted: each drops in, a little large,
/// its shadow under it, settles, and catches a warm light as it lands.
///
/// With Reduce Motion it moves a scene at a time, each shown as it stands at its end.
struct MakingOfView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let work: Work

    // The show's options, until Paul narrows them (docs/making-of.md). The closing card's names stay
    // off here until he says: `MakingOf.Options.names`.
    @AppStorage("makingOf.sinopia") private var sinopia = MakingOf.Options.Sinopia.red
    @AppStorage("makingOf.hand") private var hand = false
    @AppStorage("makingOf.flow") private var flow = MakingOf.Options.Flow.scenes

    @State private var stage: MakingOfStage?
    @State private var failed = false
    @State private var origin = Date.now
    @State private var pausedAt: Double?

    private var options: MakingOf.Options { MakingOf.Options(sinopia: sinopia, hand: hand, flow: flow) }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            if let stage {
                TimelineView(.animation(paused: pausedAt != nil)) { tl in
                    let t = min(pausedAt ?? tl.date.timeIntervalSince(origin), stage.show.duration)
                    let at = shown(t, stage.show)
                    VStack(spacing: 0) {
                        Canvas { context, size in
                            stage.draw(at: at, in: &context, size: size)
                        }
                        .accessibilityLabel(Text(caption(t, stage.show)))
                        // At least the card's usual room, more when the text is large.
                        CardView(card: stage.show.card(at: t), options: options, work: work)
                            .frame(minHeight: 210)
                    }
                }
            } else if failed {
                ContentUnavailableView("Couldn't open this mosaic", systemImage: "square.grid.3x3",
                                       description: Text("Its file is missing from the app."))
            } else {
                ProgressView().tint(Theme.tint)
            }
        }
        .overlay(alignment: .top) { controls }
        .task(id: options) { await load() }
    }

    /// With Reduce Motion, each scene as it stands at its end, for the scene's length.
    private func shown(_ t: Double, _ show: MakingOf.Show) -> Double {
        guard reduceMotion else { return t }
        let (scene, _) = show.scene(at: t)
        let (s, d) = show.times[scene]!
        return s + d - 0.001
    }

    private func caption(_ t: Double, _ show: MakingOf.Show) -> String {
        guard let c = show.card(at: t) else { return "The making-of" }
        let card = MakingOf.Card(c.scene, options: options, modelTitle: work.title, modelCredit: work.credit)
        return "\(card.title). \(card.line) \(card.credit)"
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button("Close", systemImage: "xmark") { dismiss() }
            Spacer()
            Menu("Options", systemImage: "slider.horizontal.3") {
                Picker("The drawing", selection: $sinopia) {
                    Text("Red earth, as at Ravenna").tag(MakingOf.Options.Sinopia.red)
                    Text("Indigo, as at Hagia Sophia").tag(MakingOf.Options.Sinopia.indigo)
                }
                Picker("The build", selection: $flow) {
                    Text("A scene a step").tag(MakingOf.Options.Flow.scenes)
                    Text("One continuous build").tag(MakingOf.Options.Flow.continuous)
                }
                Toggle("The setter's hand", isOn: $hand)
            }
            Button("Again", systemImage: "arrow.counterclockwise") { origin = .now; pausedAt = nil }
            Button(pausedAt == nil ? "Pause" : "Play", systemImage: pausedAt == nil ? "pause" : "play") {
                if let p = pausedAt { origin = Date.now.addingTimeInterval(-p); pausedAt = nil }
                else { pausedAt = Date.now.timeIntervalSince(origin) }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .tint(Theme.tint)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func load() async {
        do {
            let mosaic = try await library.mosaic(work, library.detail)
            let options = options
            let photo = library.image(work, "photo")?.cgImage, bed = library.image(work, "bed")?.cgImage
            // The plan and the tiles' drawing are worked out off the main thread.
            let (show, drawing) = await Task.detached(priority: .userInitiated) {
                (MakingOf.Show(mosaic, options: options), Drawing(mosaic, finish: .material))
            }.value
            stage = MakingOfStage(mosaic, show: show, drawing: drawing, photo: photo, bed: bed)
            origin = .now
            pausedAt = nil
        } catch {
            failed = true
        }
    }
}

/// The card under the picture: the technique's name beside a single gold tessera, a line on it, and
/// who is credited. Fades as the plan says.
private struct CardView: View {
    let card: (scene: MakingOf.Scene, opacity: Double)?
    let options: MakingOf.Options
    let work: Work

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let card {
                let text = MakingOf.Card(card.scene, options: options, modelTitle: work.title, modelCredit: work.credit)
                HStack(spacing: 12) {
                    Rectangle().fill(Theme.gold).frame(width: 10, height: 10)
                    Text(text.title).font(Theme.title(22)).foregroundStyle(Theme.plaster)
                }
                Text(text.line).font(Theme.body(17)).foregroundStyle(Theme.plaster.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text(text.credit).font(Theme.body(14)).italic().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .opacity(card?.opacity ?? 0)
    }
}

/// What the show draws from: the plan, the tiles' drawing, the picture and the painted bed, and the
/// tiles set so far, baked into an image as they settle (rebaked if the show goes back). Made off
/// the main thread's way and then drawn only from the view's canvas, like `WallImage`.
nonisolated final class MakingOfStage: @unchecked Sendable {
    let show: MakingOf.Show
    let drawing: Drawing
    private let photo: CGImage?
    private let bed: CGImage?
    private let size: CGSize
    private let set: CGContext?
    private let scale: CGFloat
    /// Tiles in the order they settle, and how many of them are baked.
    private let settling: [Int]
    private var baked = 0
    private var image: CGImage?
    private let palette: [SIMD3<Float>]

    static let lime = Color(red: 0.84, green: 0.81, blue: 0.75)

    init(_ m: Mosaic, show: MakingOf.Show, drawing: Drawing, photo: CGImage?, bed: CGImage?, longest: CGFloat = 1800) {
        self.show = show
        self.drawing = drawing
        self.photo = photo
        self.bed = bed
        palette = m.palette
        size = CGSize(width: CGFloat(m.width), height: CGFloat(m.height))
        scale = min(3, longest / max(size.width, size.height))
        set = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: Drawing.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Canvas units, y down.
        set?.translateBy(x: 0, y: size.height * scale)
        set?.scaleBy(x: scale, y: -scale)
        settling = show.start.indices.sorted { (show.start[$0], $0) < (show.start[$1], $1) }
    }

    /// Bakes every tile settled by `t`; starts again if `t` went back.
    private func bake(to t: Double) {
        guard let set else { return }
        let settled = { (k: Int) in self.show.start[self.settling[k]] + MakingOf.setTime <= t }
        if baked > 0, !settled(baked - 1) {
            set.saveGState(); set.resetClip()
            set.clear(CGRect(origin: .zero, size: size))
            set.restoreGState()
            baked = 0; image = nil
        }
        while baked < settling.count, settled(baked) {
            drawing.draw(settling[baked], in: set); baked += 1; image = nil
        }
        if image == nil { image = set.makeImage() }
    }

    func draw(at t: Double, in context: inout GraphicsContext, size view: CGSize) {
        let k = min(view.width / size.width, view.height / size.height) * 0.94
        let rect = CGRect(x: (view.width - size.width * k) / 2, y: (view.height - size.height * k) / 2,
                          width: size.width * k, height: size.height * k)
        let (scene, u) = show.scene(at: t)
        switch scene {
        case .model:
            if let photo { context.draw(Image(decorative: photo, scale: 1), in: rect) }
            context.fill(Path(rect), with: .color(Self.lime.opacity(MakingOf.ease((u - 0.75) / 0.25))))
        case .smalti:
            drawSmalti(u, in: &context, rect: rect)
            context.fill(Path(rect), with: .color(Self.lime.opacity(MakingOf.ease((u - 0.9) / 0.1))))
        default:
            drawUnder(t, in: &context, rect: rect, k: k)
            bake(to: t)
            if let image { context.draw(Image(decorative: image, scale: 1), in: rect) }
            if scene == .light || scene == .hold { drawLight(t, in: &context, rect: rect, k: k) }
            else { drawFlying(t, in: &context, rect: rect, k: k) }
        }
    }

    /// Lime, the drawing so far, and the painted bed laid down over it so far.
    private func drawUnder(_ t: Double, in context: inout GraphicsContext, rect: CGRect, k: CGFloat) {
        context.fill(Path(rect), with: .color(Self.lime))
        let ink = show.options.sinopia == .red ? Color(red: 0.60, green: 0.25, blue: 0.16) : Color(red: 0.20, green: 0.25, blue: 0.48)
        let lines = sinopia(show.sinopia(at: t), rect: rect, k: k)
        context.stroke(lines, with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        let front = show.bed(at: t)
        guard front > 0, let bed else { return }
        let laid = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * min(front, 1.1))
        var under = context
        under.clip(to: Path(laid))
        under.draw(Image(decorative: bed, scale: 1), in: rect)
        // The drawing shows faintly through the fresh bed.
        under.stroke(lines, with: .color(ink.opacity(0.15)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    /// The drawing's strokes, as far as the brush has gone.
    private func sinopia(_ progress: Double, rect: CGRect, k: CGFloat) -> Path {
        var path = Path()
        func pt(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: rect.minX + CGFloat(p.x) * k, y: rect.minY + CGFloat(p.y) * k) }
        for (s, span) in zip(show.strokes, show.strokeSpans) where progress > span.from {
            path.move(to: pt(s[0]))
            if progress >= span.to {
                for p in s.dropFirst() { path.addLine(to: pt(p)) }
                continue
            }
            // Part way along this stroke.
            var lengths = [0.0]
            for j in 1..<s.count { lengths.append(lengths[j - 1] + MakingOf.distance(s[j - 1], s[j])) }
            let upto = (progress - span.from) / (span.to - span.from) * lengths.last!
            for j in 1..<s.count {
                if lengths[j] <= upto { path.addLine(to: pt(s[j])); continue }
                let f = (upto - lengths[j - 1]) / max(lengths[j] - lengths[j - 1], 1e-9)
                path.addLine(to: pt(s[j - 1] + f * (s[j] - s[j - 1])))
                break
            }
        }
        return path
    }

    /// Tiles in flight: each shadow first, then each tile dropping into place, catching a warm light as
    /// it lands; and the setter's hand, when shown.
    private func drawFlying(_ t: Double, in context: inout GraphicsContext, rect: CGRect, k: CGFloat) {
        var flying: [(Int, MakingOf.Flight)] = []
        let near = show.start.indices.filter { show.start[$0] <= t && t < show.start[$0] + MakingOf.setTime }
        for i in near { if case .flying(let f) = show.tile(i, at: t) { flying.append((i, f)) } }
        guard !flying.isEmpty else { return }
        for (i, f) in flying {
            let c = drawing.centres[i]
            var tf = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k)
            tf = tf.translatedBy(x: c.x + f.lift * 0.3, y: c.y + f.lift * 0.4)
            tf = tf.scaledBy(x: 1 + (f.scale - 1) / 3, y: 1 + (f.scale - 1) / 3).translatedBy(x: -c.x, y: -c.y)
            context.fill(Path(drawing.paths[i]).applying(tf), with: .color(.black.opacity(f.shadow * 0.7)))
        }
        for (i, f) in flying {
            let c = drawing.centres[i]
            context.withCGContext { cg in
                cg.translateBy(x: rect.minX, y: rect.minY)
                cg.scaleBy(x: k, y: k)
                cg.translateBy(x: c.x, y: c.y - f.lift)
                cg.scaleBy(x: f.scale, y: f.scale)
                cg.translateBy(x: -c.x, y: -c.y)
                drawing.draw(i, in: cg)
                cg.addPath(drawing.paths[i])
                cg.setFillColor(CGColor(srgbRed: 0.79, green: 0.64, blue: 0.29, alpha: f.glow))
                cg.fillPath()
            }
        }
        if let h = show.hand(at: t) {
            // The setter's hand, as the shadow of a finger pressing the tile home from the lower right: a
            // fingertip two or three tiles wide, its edge soft.
            let r = show.pitch * k * 1.2
            let tip = CGPoint(x: rect.minX + h.x * k + r * 0.3, y: rect.minY + h.y * k + r * 0.3)
            var finger = Path()
            finger.move(to: tip)
            finger.addLine(to: CGPoint(x: tip.x + r * 2.3, y: tip.y + r * 4.1))
            var shade = context
            shade.addFilter(.blur(radius: r * 0.35))
            shade.stroke(finger, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: r * 2, lineCap: .round))
        }
    }

    /// The finished mosaic under a light crossing it: each tile flares where its tilt meets it.
    private func drawLight(_ t: Double, in context: inout GraphicsContext, rect: CGRect, k: CGFloat) {
        let tf = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: k, y: k)
        for i in drawing.paths.indices {
            let g = show.light(i, at: t)
            guard g > 0.02 else { continue }
            let warm = drawing.gold[i] ? Color(red: 1, green: 0.84, blue: 0.45) : Color(red: 1, green: 0.93, blue: 0.78)
            context.fill(Path(drawing.paths[i]).applying(tf), with: .color(warm.opacity(min(g * 0.45, 0.8))))
        }
    }

    /// The glass: each paint a cake, glowing orange as it is poured, cooling to its colour, then cut
    /// into tesserae that part.
    private func drawSmalti(_ u: Double, in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(Theme.ground))
        let n = palette.count, cols = n <= 16 ? 4 : 5, rows = (n + cols - 1) / cols
        let cw = rect.width / CGFloat(cols), ch = min(rect.height / CGFloat(max(rows, 1)), cw * 1.05)
        let oy = rect.minY + (rect.height - CGFloat(rows) * ch) / 2, r = 0.36 * min(cw, ch)
        let hot = SIMD3<Double>(1, 0.62, 0.22)
        for (rank, p) in show.cakeOrder.enumerated() {
            let cake = show.cake(p, at: u)
            guard cake.shown > 0 else { continue }
            let c = CGPoint(x: rect.minX + (CGFloat(rank % cols) + 0.5) * cw, y: oy + (CGFloat(rank / cols) + 0.5) * ch)
            let paint = SIMD3(Double(palette[p].x), Double(palette[p].y), Double(palette[p].z))
            let col = paint * cake.cool + hot * (1 - cake.cool)
            let color = Color(red: col.x, green: col.y, blue: col.z)
            if cake.cut > 0.05 {
                let sz = r / 2
                for gy in 0..<4 {
                    for gx in 0..<4 {
                        let px = c.x - r + (CGFloat(gx) + 0.5) * sz, py = c.y - r + (CGFloat(gy) + 0.5) * sz
                        guard (px - c.x) * (px - c.x) + (py - c.y) * (py - c.y) <= r * r * 1.04 else { continue }
                        let spread = 1 + 0.22 * cake.cut, half = sz / 2 * (1 - 0.14 * cake.cut)
                        let q = CGPoint(x: c.x + (px - c.x) * spread, y: c.y + (py - c.y) * spread)
                        context.fill(Path(CGRect(x: q.x - half, y: q.y - half, width: half * 2, height: half * 2)),
                                     with: .color(color.opacity(cake.shown)))
                    }
                }
            }
            if cake.cut < 1 {
                let whole = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                context.fill(whole, with: .color(color.opacity(cake.shown * (1 - cake.cut))))
            }
        }
    }
}
