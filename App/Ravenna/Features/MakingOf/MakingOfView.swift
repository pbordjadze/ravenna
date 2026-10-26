import CoreGraphics
import Foundation
import MosaicKit
import SwiftUI

/// What the making-of show of a painting is made from: its mosaic, the photo it was laid from,
/// the finish its tiles are set in, and the model's card (the picture's title and credit).
nonisolated struct MakingOfSource: Sendable {
    let mosaic: Mosaic
    let photo: CGImage
    let finish: Finish
    let title: String
    let credit: String

    /// A library picture's credit on the model's card, as its `library.json` record has it.
    static func credit(of sample: Sample) -> String {
        guard let p = sample.provenance else { return "" }
        return String(localized: "makingOf.model.credit", defaultValue: "\(p.creator), \(p.year). \(p.credit)",
                      comment: "The making-of's first card, under the picture's title: who made the library picture, when, and its collection. Proper names and dates, shown as library.json has them")
    }

    /// The model's card for the painter's own photo.
    static var ownPhotoCredit: String {
        String(localized: "makingOf.model.ownPhoto", defaultValue: "Your photo, which stays on this device.",
               comment: "The making-of's first card, under the painting's title, when it was made from the painter's own photo")
    }
}

/// The making-of show, full screen over the create flow after Start Painting (Settings › The
/// Making-of, on by default in Ravenna): the mosaic set the way the old workshops set one, each
/// step's technique named on a card (MosaicKit's `MakingOf.Show` plans it; docs/making-of.md has
/// the cards' sources). The glass first, then the drawing on the bed, the painted bed, the face,
/// the outlines, the rows that echo them, and a light crossing the finished work. Tiles are set,
/// never painted: each drops in, a little large, its shadow under it, settles, and catches a warm
/// light as it lands. Skip, a tap anywhere or the show's end calls `onFinish`, which opens the
/// painting Start has already saved. With Reduce Motion it moves a scene at a time, each shown as
/// it stands at its end.
///
/// Ravenna's seam: v0's show (`App/v0/MakingOfView.swift`) in place of Paint by Moonlight's field
/// show (its `MakingOf` package product is not linked), keeping its hand-off. The show comes and
/// goes as one picture moving (`StartHandoff`): it comes in from the preview (its picture starts
/// where the preview's was, `entry`, global coordinates), and goes to the painting Start has opened
/// beneath the cover (`leaving`): the picture moves to the template's place there (`moving`) while
/// the card, Skip and the paper fade to clear, then cross-fades into the canvas (`landed`).
struct MakingOfView: View {
    /// How the show goes, once the painting beneath the cover has drawn its first frame.
    enum Leaving: Equatable {
        /// The show plays, or holds its last frame while the painting opens.
        case staying
        /// The picture moves to the template's rect (global coordinates) while the rest fades.
        case moving(CGRect)
        /// The picture fades into the painting, at the template's rect once it has moved there, or
        /// in place (nil: Reduce Motion, or no place to move to).
        case landed(CGRect?)
    }

    private let source: MakingOfSource
    private let entry: CGRect?
    private let leaving: Leaving
    private let onFinish: () -> Void
    #if DEBUG
    /// Demo scenarios: the time the show is held at, and what to call once it shows.
    private var heldAt: Double?
    private var forcesReduceMotion = false
    private var onReady: () -> Void = {}
    #endif
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @ScaledMetric(relativeTo: .title3) private var band: CGFloat = 210
    // The show's options, until Paul narrows them (docs/making-of.md), as v0 kept them. The cards
    // name the makers, as Paul asked (`MakingOf.Options.names`, on by default).
    @AppStorage("makingOf.sinopia") private var sinopia = MakingOf.Options.Sinopia.red
    @AppStorage("makingOf.hand") private var hand = false
    @AppStorage("makingOf.flow") private var flow = MakingOf.Options.Flow.scenes
    @State private var stage: MakingOfStage?
    @State private var origin = Date.now
    @State private var finished = false
    /// The show has come in (it starts where it is not yet seen).
    @State private var entered = false

    /// Room at the top for Skip.
    private static let top: CGFloat = 64

    init(source: MakingOfSource, entry: CGRect? = nil, leaving: Leaving = .staying, onFinish: @escaping () -> Void) {
        self.source = source
        self.entry = entry
        self.leaving = leaving
        self.onFinish = onFinish
    }

    #if DEBUG
    init(demo source: MakingOfSource, heldAt: Double, reduceMotion: Bool, onReady: @escaping () -> Void) {
        self.init(source: source, onFinish: {})
        self.heldAt = heldAt
        forcesReduceMotion = reduceMotion
        self.onReady = onReady
        // The scenarios hold the show for a screenshot: it is simply there.
        _entered = State(initialValue: true)
    }
    #endif

    private var options: MakingOf.Options { MakingOf.Options(sinopia: sinopia, hand: hand, flow: flow) }

    private var reduceMotion: Bool {
        #if DEBUG
        if forcesReduceMotion { return true }
        #endif
        return systemReducesMotion
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = MakingOfLayout(
                size: geometry.size, picture: pictureSize, band: min(band, geometry.size.height * 0.42), top: Self.top)
            let move = travel(of: layout, from: geometry.frame(in: .global).origin)
            show(layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(showsPicture ? 1 : 0)
                .animation(pictureAnimation, value: showsPicture)
                .scaleEffect(move.scale, anchor: .topLeading)
                .offset(x: move.dx, y: move.dy)
        }
        .background {
            Theme.paper.ignoresSafeArea()
                .opacity(showsPaper ? 1 : 0)
                .animation(paperAnimation, value: showsPaper)
        }
        .contentShape(.rect)
        .onTapGesture { finish() }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                optionsMenu
                Button("Skip") { finish() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityIdentifier("making-of-skip")
            }
            .padding(16)
            .opacity(chromeOpacity)
            .animation(chromeAnimation, value: chromeOpacity)
        }
        // Nothing to skip, or to touch beneath, while the picture is on its way to the painting.
        .allowsHitTesting(leaving == .staying)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("making-of")
        .task(id: options) { await start() }
        .onAppear {
            let coming = entry == nil
                ? Animation.easeInOut(duration: StartHandoffPlan.move)
                : .spring(duration: StartHandoffPlan.move, bounce: StartHandoffPlan.bounce)
            withAnimation(coming) { entered = true }
        }
    }

    /// The show's creative forks, as v0 offered them over it.
    private var optionsMenu: some View {
        Menu {
            Picker("The Drawing", selection: $sinopia) {
                Text("Red earth, as at Ravenna").tag(MakingOf.Options.Sinopia.red)
                Text("Indigo, as at Hagia Sophia").tag(MakingOf.Options.Sinopia.indigo)
            }
            Picker("The Build", selection: $flow) {
                Text("A scene a step").tag(MakingOf.Options.Flow.scenes)
                Text("One continuous build").tag(MakingOf.Options.Flow.continuous)
            }
            Toggle("The Setter’s Hand", isOn: $hand)
        } label: {
            SwiftUI.Label("Options", systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityIdentifier("making-of-options")
    }

    // MARK: Playing

    /// Plans the show off the main actor, then plays it from the start; its end opens the painting.
    private func start() async {
        let mosaic = source.mosaic, finish = source.finish, options = options, photo = source.photo
        let made = await Task.detached(priority: .userInitiated) {
            MakingOfStage(mosaic, show: MakingOf.Show(mosaic, options: options), drawing: MosaicDrawing(mosaic, finish: finish),
                          photo: photo)
        }.value
        guard !Task.isCancelled else { return }
        stage = made
        origin = .now
        #if DEBUG
        if heldAt != nil {
            onReady()
            return
        }
        #endif
        try? await Task.sleep(for: .seconds(made.show.duration))
        guard !Task.isCancelled else { return }
        finish()
    }

    /// Skip, a tap, or the end: the painting opens (once), and the show holds where it is.
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    /// The show's time now (held in demos, and once it has finished).
    private func time(at date: Date, _ show: MakingOf.Show) -> Double {
        #if DEBUG
        if let heldAt { return min(heldAt, show.duration) }
        #endif
        let t = min(date.timeIntervalSince(origin), show.duration)
        return reduceMotion ? Self.still(t, show) : t
    }

    /// With Reduce Motion, each scene as it stands at its end, for the scene's length.
    private static func still(_ t: Double, _ show: MakingOf.Show) -> Double {
        let (scene, _) = show.scene(at: t)
        guard let span = show.times[scene] else { return t }
        return span.start + span.length - 0.001
    }

    @ViewBuilder
    private func show(_ layout: MakingOfLayout) -> some View {
        if let stage {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: finished)) { timeline in
                let t = time(at: timeline.date, stage.show)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in stage.draw(at: t, in: &context, rect: layout.picture) }
                        .accessibilityLabel(Text(verbatim: caption(t, stage.show)))
                    MakingOfCardView(card: stage.show.card(at: t), options: options, source: source)
                        .frame(width: layout.band.width, height: layout.band.height, alignment: .top)
                        .offset(x: layout.band.minX, y: layout.band.minY)
                        .opacity(chromeOpacity)
                        .animation(chromeAnimation, value: chromeOpacity)
                }
            }
        } else {
            // The photo, while the show is planned: it is how the show begins.
            Image(decorative: source.photo, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: layout.picture.width, height: layout.picture.height)
                .offset(x: layout.picture.minX, y: layout.picture.minY)
                .accessibilityHidden(true)
        }
    }

    /// The card at `t`, as VoiceOver reads the picture.
    private func caption(_ t: Double, _ show: MakingOf.Show) -> String {
        guard let c = show.card(at: t) else { return String(localized: "The Making-of") }
        let card = MakingOf.Card(c.scene, options: options, modelTitle: source.title, modelCredit: source.credit)
        return [card.title, card.line, card.credit, card.method].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// The mosaic's size in canvas units, or the photo's while the show is planned.
    private var pictureSize: CGSize {
        let m = source.mosaic
        if m.width > 0, m.height > 0 { return CGSize(width: CGFloat(m.width), height: CGFloat(m.height)) }
        return CGSize(width: source.photo.width, height: source.photo.height)
    }

    // MARK: Coming and going

    /// The picture is seen: it has come in, and is not yet cross-faded into the painting.
    private var showsPicture: Bool {
        if case .landed = leaving { return false }
        return entered
    }

    /// The paper behind the show, which fades in as the picture settles and out as it leaves.
    private var showsPaper: Bool { entered && leaving == .staying }

    /// The card, Skip and the options: in after the picture has moved, out as soon as it leaves.
    private var chromeOpacity: Double { entered && leaving == .staying ? 1 : 0 }

    /// Whether the show leaves where it stands: Reduce Motion, or no place to move to.
    private var leavesInPlace: Bool {
        if case .landed(let target) = leaving { return target == nil }
        return false
    }

    private var pictureAnimation: Animation {
        if showsPicture { return .easeOut(duration: entry == nil ? StartHandoffPlan.move : StartHandoffPlan.appear) }
        return leavesInPlace ? .easeInOut(duration: StartHandoffPlan.move) : .easeOut(duration: StartHandoffPlan.crossFade)
    }

    private var paperAnimation: Animation {
        if showsPaper { return entry == nil ? .easeInOut(duration: StartHandoffPlan.move) : .easeOut(duration: StartHandoffPlan.move) }
        return leavesInPlace ? .easeInOut(duration: StartHandoffPlan.move) : .easeOut(duration: StartHandoffPlan.fade)
    }

    private var chromeAnimation: Animation {
        chromeOpacity > 0
            ? .easeOut(duration: 0.25).delay(StartHandoffPlan.chromeDelay)
            : .easeOut(duration: StartHandoffPlan.fade / 2)
    }

    /// Where the picture is carried to: the preview's picture before the show has come in, the
    /// painting's template as it leaves, otherwise nowhere (`layout` is its place). `origin` is
    /// where this view starts, in global coordinates.
    private func travel(of layout: MakingOfLayout, from origin: CGPoint) -> PictureTravel {
        let destination: CGRect? = switch leaving {
        case .moving(let target): target
        case .landed(let target): target
        case .staying: entered ? nil : entry
        }
        return PictureTravel(home: layout.picture, destination: destination?.offsetBy(dx: -origin.x, dy: -origin.y))
    }
}

/// Where the show goes on a screen of `size`: the picture as large as it fits under `top` and
/// over a band of `band` points for the card, the two centered together.
nonisolated struct MakingOfLayout: Equatable, Sendable {
    let picture: CGRect
    let band: CGRect

    static let margin: CGFloat = 16

    init(size: CGSize, picture aspect: CGSize, band: CGFloat, top: CGFloat) {
        let margin = Self.margin
        let room = CGSize(width: max(size.width - 2 * margin, 1), height: max(size.height - top - band - margin, 1))
        let scale = min(room.width / max(aspect.width, 1), room.height / max(aspect.height, 1))
        let (w, h) = (aspect.width * scale, aspect.height * scale)
        let y = top + max((room.height - h) / 2, 0)
        picture = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
        self.band = CGRect(x: margin, y: picture.maxY, width: max(size.width - 2 * margin, 1), height: band)
    }
}

/// The card under the picture: the technique's name beside a single gold tessera, a line on it,
/// who is credited, and the algorithm Ravenna uses for the step. Fades as the plan says. The
/// cards' words are MosaicKit's (`MakingOf.Card`), each with its source in docs/making-of.md, and
/// stay as written there.
private struct MakingOfCardView: View {
    let card: (scene: MakingOf.Scene, opacity: Double)?
    let options: MakingOf.Options
    let source: MakingOfSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let card {
                let text = MakingOf.Card(card.scene, options: options, modelTitle: source.title, modelCredit: source.credit)
                HStack(spacing: 12) {
                    Rectangle().fill(Theme.gold).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(verbatim: text.title).font(.display(.title2, weight: .semibold))
                }
                Text(verbatim: text.line).font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: text.credit).font(.subheadline).italic().foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !text.method.isEmpty {
                    // The algorithm behind the step, credited like the technique.
                    Text(verbatim: text.method).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .opacity(card?.opacity ?? 0)
        // The picture's label reads the card.
        .accessibilityHidden(true)
    }
}

/// What the show draws from: the plan, the tiles' drawing and the painted bed, and the tiles set
/// so far, baked into an image as they settle (baked again if the show goes back). Made off the
/// main actor and then drawn only from the view's canvas. As v0 drew it (`MakingOfStage`).
nonisolated final class MakingOfStage: @unchecked Sendable {
    let show: MakingOf.Show
    let drawing: MosaicDrawing
    private let photo: CGImage?
    private let bed: CGImage?
    private let grout: Color
    private let size: CGSize
    private let set: CGContext?
    private let scale: CGFloat
    /// Tiles in the order they settle, and how many of them are baked.
    private let settling: [Int]
    private var baked = 0
    private var image: CGImage?
    private let palette: [SIMD3<Float>]

    /// The lime plaster the bed is spread on.
    static let lime = Color(red: 0.84, green: 0.81, blue: 0.75)
    /// Behind the smalti's cakes: the dark of the glassmaker's shop.
    static let shop = Color(red: 0.11, green: 0.10, blue: 0.10)

    init(_ m: Mosaic, show: MakingOf.Show, drawing: MosaicDrawing, photo: CGImage?, longest: CGFloat = 1800) {
        self.show = show
        self.drawing = drawing
        self.photo = photo
        palette = m.palette
        grout = Color(red: Double(m.grout.x), green: Double(m.grout.y), blue: Double(m.grout.z))
        size = CGSize(width: CGFloat(m.width), height: CGFloat(m.height))
        scale = min(3, longest / max(size.width, size.height, 1))
        let w = max(Int(size.width * scale), 1), h = max(Int(size.height * scale), 1)
        bed = drawing.finish.paintedBed ? MosaicPicture.bed(of: m, width: w / 2 + 1, height: h / 2 + 1) : nil
        set = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: MosaicDrawing.space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
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

    /// The show at `t`, its picture filling `rect`.
    func draw(at t: Double, in context: inout GraphicsContext, rect: CGRect) {
        guard size.width > 0, size.height > 0 else { return }
        let k = rect.width / size.width
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
        guard front > 0 else { return }
        let laid = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * min(front, 1.1))
        var under = context
        under.clip(to: Path(laid))
        if let bed {
            under.draw(Image(decorative: bed, scale: 1), in: rect)
        } else {
            // The flat finish's bed: its light grout.
            under.fill(Path(rect), with: .color(grout))
        }
        // The drawing shows faintly through the fresh bed.
        under.stroke(lines, with: .color(ink.opacity(0.15)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    /// The drawing's strokes, as far as the brush has gone.
    private func sinopia(_ progress: Double, rect: CGRect, k: CGFloat) -> Path {
        var path = Path()
        func pt(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: rect.minX + CGFloat(p.x) * k, y: rect.minY + CGFloat(p.y) * k) }
        for (s, span) in zip(show.strokes, show.strokeSpans) where progress > span.from && s.count >= 2 {
            path.move(to: pt(s[0]))
            if progress >= span.to {
                for p in s.dropFirst() { path.addLine(to: pt(p)) }
                continue
            }
            // Part way along this stroke.
            var lengths = [0.0]
            for j in 1..<s.count { lengths.append(lengths[j - 1] + MakingOf.distance(s[j - 1], s[j])) }
            let upto = (progress - span.from) / max(span.to - span.from, 1e-9) * (lengths.last ?? 0)
            for j in 1..<s.count {
                if lengths[j] <= upto { path.addLine(to: pt(s[j])); continue }
                let f = (upto - lengths[j - 1]) / max(lengths[j] - lengths[j - 1], 1e-9)
                path.addLine(to: pt(s[j - 1] + f * (s[j] - s[j - 1])))
                break
            }
        }
        return path
    }

    /// Tiles in flight: each shadow first, then each tile dropping into place, catching a warm light
    /// as it lands; and the setter's hand, when shown.
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
            // The setter's hand, as the shadow of a finger pressing the tile home from the lower
            // right: a fingertip two or three tiles wide, its edge soft.
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

    /// The glass: each paint a cake, glowing orange as it is poured, cooling to its colour, then
    /// cut into tesserae that part.
    private func drawSmalti(_ u: Double, in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(Self.shop))
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
