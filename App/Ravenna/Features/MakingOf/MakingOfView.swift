import CoreGraphics
import MakingOf
import SwiftUI

/// The making-of show, full screen over the create flow after Start Painting when Settings › The
/// Making-of is on (`SettingsKey.playsMakingOf`, off by default): the painter's photo becoming its
/// painting in six steps (`Sources/MakingOf`, `FieldShow`: each step grows from seeds over the
/// picture itself), and under the picture a faint card for each step. Skip, a tap anywhere or the
/// show's end calls `onFinish`, which opens the painting Start has already saved; so does a show
/// that can't be made.
///
/// `MakingOfPlayer` makes and times the show; this draws it (`MakingOfCanvas`): the picture fitted
/// above the card's band (`MakingOfLayout`), on the screen's paper in either appearance (the
/// picture is a sheet of its own paper, like the canvas's). Reduce Motion plays the cards over
/// still pictures, cross-faded. The photo shows while the show is being made, which is how it
/// begins.
///
/// The show comes and goes as one picture moving (`StartHandoff`). It comes in from the preview:
/// its picture starts where the preview's was (`entry`, global coordinates), moves to its place
/// while the paper behind it fades in, and the card and Skip come in after it. Without an `entry`
/// (Reduce Motion) it fades in where it stands. It goes to the painting Start has opened beneath
/// the cover (`leaving`): the picture moves to the template's place there (`moving`) while the
/// card, Skip and the paper fade to clear, then cross-fades into the canvas (`landed`).
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
    /// Demo scenarios: the time the show is held at (Reduce Motion: the still), and what to call
    /// once it shows.
    private var heldAt: Double?
    private var forcesReduceMotion = false
    private var onReady: () -> Void = {}
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var band: CGFloat = 150
    @State private var player = MakingOfPlayer()
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

    var body: some View {
        GeometryReader { geometry in
            let layout = MakingOfLayout(
                size: geometry.size, picture: pictureSize, band: min(band, geometry.size.height * 0.4), top: Self.top)
            let move = travel(of: layout, from: geometry.frame(in: .global).origin)
            stage(layout)
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
        .onTapGesture { player.skip() }
        .overlay(alignment: .topTrailing) {
            Button("Skip") { player.skip() }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(16)
                .opacity(chromeOpacity)
                .animation(chromeAnimation, value: chromeOpacity)
                .accessibilityIdentifier("making-of-skip")
        }
        // Nothing to skip, or to touch beneath, while the picture is on its way to the painting.
        .allowsHitTesting(leaving == .staying)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("making-of")
        .task { await start() }
        .onAppear {
            let coming = entry == nil
                ? Animation.easeInOut(duration: StartHandoffPlan.move)
                : .spring(duration: StartHandoffPlan.move, bounce: StartHandoffPlan.bounce)
            withAnimation(coming) { entered = true }
        }
        .onDisappear { player.release() }
    }

    // MARK: Coming and going

    /// The picture is seen: it has come in, and is not yet cross-faded into the painting.
    private var showsPicture: Bool {
        if case .landed = leaving { return false }
        return entered
    }

    /// The paper behind the show, which fades in as the picture settles and out as it leaves.
    private var showsPaper: Bool { entered && leaving == .staying }

    /// The card and Skip: in after the picture has moved, out as soon as it leaves.
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

    private func start() async {
        #if DEBUG
        if let heldAt {
            await player.hold(source, at: heldAt, reduceMotion: forcesReduceMotion, onReady: onReady)
            return
        }
        #endif
        await player.run(source, reduceMotion: reduceMotion, onFinish: onFinish)
    }

    /// The pictures' size, or the photo's while the show is being made.
    private var pictureSize: CGSize {
        if let size = player.built?.show.size { return CGSize(width: size.width, height: size.height) }
        return CGSize(width: source.photo.width, height: source.photo.height)
    }

    @ViewBuilder
    private func stage(_ layout: MakingOfLayout) -> some View {
        if let built = player.built, player.phase == .playing || (player.phase == .finished && player.stills.isEmpty) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: player.phase != .playing)) { timeline in
                inTime(built, at: player.time(at: timeline.date), in: layout)
            }
        } else if let built = player.built, player.stills.indices.contains(player.still) {
            ZStack {
                still(built, player.stills[player.still], in: layout)
                    .id(player.still)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.6), value: player.still)
        } else {
            ZStack(alignment: .topLeading) {
                Image(decorative: source.photo, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.picture.width, height: layout.picture.height)
                    .clipShape(.rect(cornerRadius: MakingOfCanvas.cornerRadius))
                    .offset(x: layout.picture.minX, y: layout.picture.minY)
                    .accessibilityHidden(true)
                if player.phase == .preparing {
                    ProgressView()
                        .frame(width: layout.band.width)
                        .offset(x: layout.band.minX, y: layout.band.minY + 24)
                        .accessibilityLabel(Text("Preparing the Making-of"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The show at time `t`, with its card.
    private func inTime(_ built: MakingOfShow, at t: Double, in layout: MakingOfLayout) -> some View {
        let frame = built.show.frame(at: t)
        return ZStack(alignment: .topLeading) {
            MakingOfCanvas(built: built, frame: frame, picture: player.picture ?? source.photo, layout: layout, marks: true)
            if let card = frame.card {
                cardView(built.cards[card.step], opacity: card.opacity, footnote: card.footnoteOpacity, in: layout)
            }
        }
    }

    /// A still of Reduce Motion, with its step's card at full strength.
    private func still(_ built: MakingOfShow, _ still: MakingOfPlayer.Still, in layout: MakingOfLayout) -> some View {
        let cards = built.spec.cards
        return ZStack(alignment: .topLeading) {
            MakingOfCanvas(built: built, frame: still.frame, picture: still.picture ?? source.photo, layout: layout, marks: false)
            if let k = still.step {
                cardView(built.cards[k], opacity: cards.opacity, footnote: cards.opacity * cards.footnote, in: layout)
            }
        }
    }

    private func cardView(_ card: MakingOfCard, opacity: Double, footnote: Double, in layout: MakingOfLayout) -> some View {
        MakingOfCardView(card: card, opacity: opacity, footnoteOpacity: footnote)
            .padding(.top, 16)
            .frame(width: layout.band.width, height: layout.band.height, alignment: .top)
            .offset(x: layout.band.minX, y: layout.band.minY)
            .opacity(chromeOpacity)
            .animation(chromeAnimation, value: chromeOpacity)
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

/// One frame of the show, as `ShowFrame`'s doc comment says: the picture (layers and ink,
/// composited by `MakingOfPlayer`), the real template at its hand-off, the numbers, the seed rings,
/// and the sparks and stars of the field show, in ink over the rest. The real template comes in
/// under the numbers rather than over them: it is drawn without its numbers
/// (`MakingOfShow.handoff`), and the show's are the template's own, in place.
struct MakingOfCanvas: View {
    let built: MakingOfShow
    let frame: ShowFrame
    let picture: CGImage
    let layout: MakingOfLayout
    /// The seed rings, sparks and stars; Reduce Motion's stills have none of them.
    let marks: Bool

    nonisolated static let cornerRadius: CGFloat = 6
    /// The size digits are set at, then scaled to each number's.
    nonisolated private static let digitSize: CGFloat = 64
    /// A spark is a filled circle of `sparkRadius + sparkGrowth * heat` picture pixels at
    /// `sparkOpacity * heat` (`Spark`'s doc comment: `230 * heat / 255`), a star an outline
    /// `starWidth` pixel wide; all in `RevealStyle.ink`, scaled to the view like the rings.
    nonisolated private static let sparkRadius = 1.6
    nonisolated private static let sparkGrowth = 1.6
    nonisolated private static let sparkOpacity = 230.0 / 255
    nonisolated private static let starWidth: CGFloat = 1
    nonisolated private static let paper = color(RevealStyle.standard.paper)
    nonisolated private static let ink = color(RevealStyle.standard.ink)

    nonisolated private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(.sRGB, red: rgb.x / 255, green: rgb.y / 255, blue: rgb.z / 255)
    }

    var body: some View {
        let built = built, frame = frame, picture = picture, rect = layout.picture, marks = marks
        Canvas { context, _ in
            Self.draw(built, frame, picture: picture, in: rect, marks: marks, context: &context)
        }
        .accessibilityHidden(true)
    }

    /// Places of the pictures' pixels on screen.
    nonisolated private struct Placement {
        let rect: CGRect
        /// Points per pixel of the pictures.
        let scale: CGFloat

        func callAsFunction(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(x) * scale, y: rect.minY + CGFloat(y) * scale)
        }
    }

    nonisolated private static func draw(
        _ built: MakingOfShow, _ frame: ShowFrame, picture: CGImage, in rect: CGRect, marks: Bool,
        context: inout GraphicsContext
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let place = Placement(rect: rect, scale: rect.width / CGFloat(max(built.show.size.width, 1)))
        var sheet = context
        sheet.clip(to: Path(roundedRect: rect, cornerRadius: cornerRadius))
        sheet.draw(Image(decorative: picture, scale: 1).interpolation(.high), in: rect)
        let handoff = frame.picture.handoff
        if handoff > 0, let template = built.handoff {
            sheet.opacity = handoff
            sheet.draw(Image(decorative: template, scale: 1).interpolation(.high), in: rect)
        }
        drawNumbers(built, frame, place: place, context: context)
        if marks {
            drawRings(frame, place: place, context: context)
            drawSparks(frame, place: place, context: context)
            drawStars(frame, place: place, context: context)
        }
    }

    nonisolated private static func drawNumbers(
        _ built: MakingOfShow, _ frame: ShowFrame, place: Placement, context: GraphicsContext
    ) {
        guard !frame.numbers.isEmpty else { return }
        var digits: [Int: GraphicsContext.ResolvedText] = [:]
        for (i, alpha) in frame.numbers.enumerated() where alpha > 0.01 && i < built.numbers.count && i < built.digits.count {
            let value = built.digits[i]
            let text: GraphicsContext.ResolvedText
            if let resolved = digits[value] {
                text = resolved
            } else {
                text = context.resolve(
                    Text(verbatim: String(value)).font(.system(size: digitSize, design: .serif)).foregroundStyle(ink))
                digits[value] = text
            }
            let number = built.numbers[i]
            var c = context
            c.opacity = alpha
            let at = place(number.x, number.y)
            c.translateBy(x: at.x, y: at.y)
            let s = CGFloat(number.size) * place.scale / digitSize
            c.scaleBy(x: s, y: s)
            c.draw(text, at: .zero, anchor: .center)
        }
    }

    /// Each k-means++ seed's ring, as `SeedRing` says: an ink circle over a paper halo, a dot in
    /// its middle.
    nonisolated private static func drawRings(_ frame: ShowFrame, place: Placement, context: GraphicsContext) {
        let k = place.scale
        for ring in frame.seedRings where ring.alpha > 0 {
            let center = place(ring.x, ring.y)
            let r = CGFloat(ring.radius) * k
            let width = CGFloat(SeedRing.lineWidth) * k
            var c = context
            c.opacity = ring.alpha
            c.fill(disc(center, r + CGFloat(SeedRing.halo) * k), with: .color(paper))
            c.stroke(disc(center, r - width / 2), with: .color(ink), lineWidth: width)
            c.fill(disc(center, CGFloat(SeedRing.dotRadius) * k), with: .color(ink))
        }
    }

    /// The hot tips of the lines burning in the ink step (`Spark`): a filled ink circle at each,
    /// bigger and stronger while hot, normally blended over the picture and the rings.
    nonisolated private static func drawSparks(_ frame: ShowFrame, place: Placement, context: GraphicsContext) {
        let k = place.scale
        for spark in frame.sparks where spark.heat > 0 {
            let heat = min(spark.heat, 1)
            var c = context
            c.opacity = sparkOpacity * heat
            c.fill(disc(place(spark.x, spark.y), CGFloat(sparkRadius + sparkGrowth * heat) * k), with: .color(ink))
        }
    }

    /// The faint rings that open round the numbers as they come out in the last step (`Star`): a
    /// circle outline one picture pixel wide in ink, its outer edge at the star's radius.
    nonisolated private static func drawStars(_ frame: ShowFrame, place: Placement, context: GraphicsContext) {
        let k = place.scale
        let width = starWidth * k
        for star in frame.stars where star.alpha > 0 {
            var c = context
            c.opacity = min(star.alpha, 1)
            let radius = max(CGFloat(star.radius) * k - width / 2, 0)
            c.stroke(disc(place(star.x, star.y), radius), with: .color(ink), lineWidth: width)
        }
    }

    nonisolated private static func disc(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }
}
