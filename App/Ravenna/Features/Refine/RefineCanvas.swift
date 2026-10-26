import PaintCore
import SwiftUI
import UIKit

/// The edits sent on the Refine screen that the template doesn't show yet, in the order they were
/// sent, over the drawing in `rect` (view coordinates): lines drawn in the drawing's own
/// ink and weight, and the eraser's passes and the lines tapped away showing the paper, photo or
/// painting beneath, so whatever they took out is gone at once. `trace` is the pen's line, the
/// shape or the eraser's pass still under the finger; while the eraser is down a ring shows its
/// reach.
struct RefineInkLayer: View {
    /// A Paint Brush stroke: its path (normalized to the picture), its reach either side (a
    /// fraction of the picture's long side) and its paint.
    nonisolated struct Brush: Equatable {
        var points: [SIMD2<Float>]
        var radius: Float
        var color: Color
    }

    let lines: [TemplateRefinements.Line]
    let trace: [SIMD2<Float>]?
    /// The trace is the line as it will be drawn (a shape), not the finger's samples.
    let traceIsDrawn: Bool
    /// The trace is the eraser's, not the pen's.
    let erasing: Bool
    /// The trace is a Cell Edge's, a line that won't be drawn: dashed.
    var dashed = false
    /// The trace is Merge's, a path that draws nothing: in the signature color.
    var merging = false
    /// The Paint Brush's strokes the template doesn't show yet, and the one under the finger, laid
    /// in their paint (Refine gives them a layer of their own, under the drawing).
    var brushes: [Brush] = []
    /// The eraser's reach either side of its pass, a fraction of the picture's long side.
    let eraserRadius: Float
    let rect: CGRect
    /// The drawing's line width, in points.
    let lineWidth: CGFloat
    /// The photo or the painting, when it shows beneath the drawing; nil: the paper does.
    let beneath: CGImage?
    /// The ink is edged in white, as the drawing is over the photo.
    let halo: Bool

    var body: some View {
        let lines = lines, trace = trace, erasing = erasing, eraserRadius = eraserRadius, rect = rect
        let lineWidth = lineWidth, beneath = beneath, halo = halo, traceIsDrawn = traceIsDrawn, dashed = dashed
        let merging = merging, brushes = brushes, signature = Theme.signature
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            let long = max(rect.width, rect.height)
            func point(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
            }
            var canvas = context
            canvas.clip(to: Path(rect))
            // A single point (a dab) is a segment to nowhere, which a round cap still draws.
            func polyline(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points.count == 1 ? [points[0], points[0]] : points)
                return path
            }
            func ink(_ path: Path) {
                if halo {
                    canvas.stroke(path, with: .color(.white.opacity(0.75)), style: Self.style(lineWidth + 2.5))
                }
                canvas.stroke(path, with: .color(LineArtDrawing.ink), style: Self.style(lineWidth))
            }
            // What lies beneath the drawing, over `covered`.
            func uncover(_ covered: Path) {
                var under = canvas
                under.clip(to: covered)
                if let beneath {
                    under.draw(Image(decorative: beneath, scale: 1), in: rect)
                } else {
                    under.fill(Path(rect), with: .color(LineArtDrawing.paper))
                }
            }
            func erase(_ path: Path, radius: Float) {
                uncover(path.strokedPath(Self.style(2 * CGFloat(radius) * long)))
            }
            for brush in brushes where !brush.points.isEmpty {
                let path = polyline(brush.points.map(point))
                canvas.stroke(path, with: .color(brush.color.opacity(0.85)), style: Self.style(2 * CGFloat(brush.radius) * long))
            }
            for line in lines where !line.points.isEmpty {
                let path = polyline(line.points.map(point))
                switch line.kind {
                case .draw:
                    ink(path)
                case .erase:
                    erase(path, radius: line.radius)
                case .eraseLine:
                    // The line itself, its own path, and not what meets it at its ends.
                    let width = lineWidth + (halo ? 4 : 1.5)
                    uncover(path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round)))
                case .fill:
                    // `RefineFillLayer` shows fills.
                    break
                }
            }
            if let trace, let last = trace.last {
                let points = trace.map(point)
                if erasing {
                    erase(polyline(points), radius: eraserRadius)
                    let r = CGFloat(eraserRadius) * long
                    let ring = Path(ellipseIn: CGRect(x: point(last).x - r, y: point(last).y - r, width: 2 * r, height: 2 * r))
                    canvas.fill(ring, with: .color(.white.opacity(0.25)))
                    canvas.stroke(ring, with: .color(LineArtDrawing.ink.opacity(0.45)), lineWidth: 1)
                } else if merging {
                    canvas.stroke(polyline(points), with: .color(signature), style: Self.style(max(lineWidth, 2.5)))
                } else if dashed {
                    var style = Self.style(lineWidth)
                    style.dash = [lineWidth * 2.5, lineWidth * 2.5]
                    canvas.stroke(Path(PenPath.path(points)), with: .color(LineArtDrawing.ink.opacity(0.7)), style: style)
                } else {
                    ink(traceIsDrawn ? polyline(points) : Path(PenPath.path(points)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func style(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// The painter's fills over the drawing in `rect` (view coordinates): each area a fill made in
/// the template on screen (`base`'s detail areas holding a fill's point) tinted its paint,
/// multiplied in so the drawing's ink stays on top and the paper or photo shows through, and a
/// swatch of the photo's color (`LineEdit.photoColor`, what the fill paints it with) where each
/// fill the template doesn't have yet was tapped, until the template that has it comes. Over the
/// painting (`showsAreas` off) the areas are painted already: only the swatches show.
struct RefineFillLayer: View, Equatable {
    /// A fill sent and not shown yet: where it was tapped (normalized to the picture) and the
    /// photo's color there (OKLab).
    nonisolated struct Swatch: Equatable {
        let point: SIMD2<Float>
        let color: SIMD3<Float>
    }

    let base: CreateModel.Preview?
    /// Where the fills the template has were tapped, normalized to the picture.
    let fills: [SIMD2<Float>]
    let swatches: [Swatch]
    /// The photo's color space, for the swatches' color; the same while Refine is open.
    let space: RGBColorSpace?
    let rect: CGRect
    var showsAreas = true

    /// How opaque an area's paint is laid over the drawing.
    static let areaOpacity: Double = 0.75
    /// A swatch's radius, in points on screen.
    static let swatchRadius: CGFloat = 6

    nonisolated static func == (a: RefineFillLayer, b: RefineFillLayer) -> Bool {
        a.base?.id == b.base?.id && a.fills == b.fills && a.swatches == b.swatches && a.rect == b.rect && a.space == b.space
            && a.showsAreas == b.showsAreas
    }

    var body: some View {
        let areas = showsAreas ? Self.areas(base?.template, fills: fills) : [], rect = rect
        let dots = swatches.compactMap { swatch -> (SIMD2<Float>, Color)? in
            guard let space else { return nil }
            let rgb = ColorScience.okLabToEncoded(swatch.color, space: space)
            let color = Color(space == .displayP3 ? .displayP3 : .sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
            return (swatch.point, color)
        }
        let size = base.map { CGSize(width: $0.template.width, height: $0.template.height) } ?? .zero
        let opacity = Self.areaOpacity, r = Self.swatchRadius
        ZStack {
            Canvas { context, _ in
                guard size.width > 0, size.height > 0, rect.width > 0 else { return }
                // Filled into the picture as the drawing is (`LineArtLayer`).
                let s = max(rect.width / size.width, rect.height / size.height)
                let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
                var tinted = context
                tinted.clip(to: Path(rect))
                tinted.translateBy(x: origin.x, y: origin.y)
                tinted.scaleBy(x: s, y: s)
                for area in areas {
                    var path = Path()
                    for ring in area.rings where ring.count >= 3 {
                        path.addLines(ring.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                        path.closeSubpath()
                    }
                    tinted.fill(path, with: .color(area.paint.opacity(opacity)), style: FillStyle(eoFill: true))
                }
            }
            .blendMode(.multiply)
            Canvas { context, _ in
                for (point, color) in dots {
                    let centre = CGPoint(x: rect.minX + CGFloat(point.x) * rect.width, y: rect.minY + CGFloat(point.y) * rect.height)
                    let dot = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
                    context.fill(dot, with: .color(color))
                    // A white ring edged in ink reads on paper, photo and paint alike.
                    context.stroke(dot, with: .color(.white), lineWidth: 2)
                    let edge = Path(ellipseIn: CGRect(x: centre.x - r - 1, y: centre.y - r - 1, width: 2 * r + 2, height: 2 * r + 2))
                    context.stroke(edge, with: .color(LineArtDrawing.ink.opacity(0.4)), lineWidth: 0.75)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The areas of `template` a fill made (its detail areas holding one of the `fills`): their
    /// rings in canvas units and their paint.
    static func areas(_ template: Template?, fills: [SIMD2<Float>]) -> [(rings: [[SIMD2<Float>]], paint: Color)] {
        guard let template, !template.detailRegions.isEmpty else { return [] }
        let size = SIMD2(Float(template.width), Float(template.height))
        var filled = Set<Int>()
        for point in fills {
            if let r = template.region(at: point * size), template.isDetailRegion(r) { filled.insert(r) }
        }
        return filled.sorted().map { (template.polygons(ofRegion: $0), PaletteBar.paint(template, Int(template.regions[$0].colorIndex))) }
    }
}

/// Areas outlined in the signature color, in screen points even while zooming: every area of the
/// paint Edit Paint or a card picked, or the cell Select picked. Each area's closed rings include
/// its holes, just as `RefineFillLayer`'s even-odd paths do.
struct RefinePaintGlow: View, Equatable {
    let base: CreateModel.Preview?
    /// The regions of `base`'s template that glow.
    let areas: [Int]
    let rect: CGRect
    let reduceMotion: Bool

    @State private var haloOpacity = 0.22

    nonisolated static func == (a: RefinePaintGlow, b: RefinePaintGlow) -> Bool {
        a.base?.id == b.base?.id && a.areas == b.areas && a.rect == b.rect && a.reduceMotion == b.reduceMotion
    }

    nonisolated static func areas(of paint: Int, in template: Template) -> [Int] {
        template.regions.indices.filter { Int(template.regions[$0].colorIndex) == paint }
    }

    var body: some View {
        ZStack {
            outlines(width: 8)
                .blur(radius: 2)
                .opacity(reduceMotion ? 0.22 : haloOpacity)
            outlines(width: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: areas) {
            haloOpacity = 0.22
            guard !areas.isEmpty, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { haloOpacity = 0.42 }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { haloOpacity = 0.22 }
        }
        .onChange(of: reduceMotion) { _, _ in haloOpacity = 0.22 }
    }

    private func outlines(width: CGFloat) -> some View {
        let rings = base.map { base in
            areas.filter { $0 < base.template.regions.count }.map { base.template.polygons(ofRegion: $0) }
        } ?? []
        let size = base.map { CGSize(width: $0.template.width, height: $0.template.height) } ?? .zero
        let rect = rect, color = Theme.signature
        return Canvas { context, _ in
            guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return }
            let s = max(rect.width / size.width, rect.height / size.height)
            let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
            var glowing = context
            glowing.clip(to: Path(rect))
            glowing.translateBy(x: origin.x, y: origin.y)
            glowing.scaleBy(x: s, y: s)
            for area in rings {
                var path = Path()
                for ring in area where ring.count >= 3 {
                    path.addLines(ring.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                    path.closeSubpath()
                }
                glowing.stroke(path, with: .color(color), style: RefineInkLayer.style(width / s))
            }
        }
    }
}

/// A line the eraser was tapped on, glowing in the signature color as it goes (its view fades it).
struct RefineTappedLine: View {
    let points: [SIMD2<Float>]
    let rect: CGRect
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.addLines(points.map {
                CGPoint(x: rect.minX + CGFloat($0.x) * rect.width, y: rect.minY + CGFloat($0.y) * rect.height)
            })
        }
        .stroke(Theme.signature, style: RefineInkLayer.style(max(2.5 * lineWidth, 4)))
        .shadow(color: Theme.signature.opacity(0.6), radius: 6)
        .allowsHitTesting(false)
    }
}

/// What Refine tells the painter (`RefineNote`): a glass capsule at the top that takes no touches,
/// like the app's other toasts (`Toast`), which VoiceOver is told of when it comes
/// (`CreateModel.say`). Nothing without a note.
struct RefineNoteToast: View {
    let note: RefineNote?

    var body: some View {
        if let note {
            Toast(text: note.text, systemImage: note.systemImage, edge: .top)
                .padding(.horizontal, 20)
                .allowsHitTesting(false)
                .accessibilityIdentifier("refine-note")
        }
    }
}

/// The refinements over the picture in `rect`: brushed areas tinted (more detail in the
/// signature color, less in slate; the eraser clears both), and the lines of text boxed in
/// orange, found or marked, a line turned off dashed. `refinements` include the stroke still
/// under the finger, `marking` the line being dragged out.
struct RefineMarks: View {
    let refinements: TemplateRefinements
    let found: [[SIMD2<Float>]]
    let marking: (SIMD2<Float>, SIMD2<Float>)?
    let rect: CGRect
    /// The Text tool is up: lines stand out.
    let emphasizesText: Bool

    static let more = Theme.signature
    static let less = Color(red: 0.36, green: 0.45, blue: 0.56)
    static let text = Color.orange

    var body: some View {
        let refinements = refinements, found = found, marking = marking, rect = rect, emphasizesText = emphasizesText
        let more = Self.more, less = Self.less, text = Self.text
        Canvas { context, _ in
            let long = max(rect.width, rect.height)
            func point(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
            }
            // Each stroke opaque in one layer, the layer translucent: overlaps don't darken, and a
            // later stroke covers the earlier ones as it does in the template.
            var areas = context
            areas.opacity = 0.42
            areas.drawLayer { layer in
                for stroke in refinements.strokes {
                    var path = Path()
                    path.addLines(stroke.points.map(point) + (stroke.points.count == 1 ? stroke.points.map(point) : []))
                    let style = StrokeStyle(lineWidth: 2 * CGFloat(stroke.radius) * long, lineCap: .round, lineJoin: .round)
                    switch stroke.kind {
                    case .more:
                        layer.blendMode = .normal
                        layer.stroke(path, with: .color(more), style: style)
                    case .less:
                        layer.blendMode = .normal
                        layer.stroke(path, with: .color(less), style: style)
                    case .erase:
                        layer.blendMode = .clear
                        layer.stroke(path, with: .color(.black), style: style)
                    }
                }
            }
            var lines = context
            lines.opacity = emphasizesText ? 1 : 0.55
            for line in found {
                let hidden = refinements.hiddenText.contains { TemplateRefinements.sameLine(line, $0) }
                Self.box(line.map(point), hidden: hidden, color: text, in: &lines)
            }
            for line in refinements.addedText {
                Self.box(line.map(point), hidden: false, color: text, in: &lines)
            }
            if let marking {
                Self.box(TemplateRefinements.textLine(from: marking.0, to: marking.1).map(point), hidden: true, color: text, in: &lines)
            }
        }
        .allowsHitTesting(false)
    }

    /// A line of text's box: filled and solid when it counts as text, dashed when it doesn't.
    nonisolated private static func box(_ corners: [CGPoint], hidden: Bool, color: Color, in context: inout GraphicsContext) {
        guard let first = corners.first else { return }
        var path = Path()
        path.move(to: first)
        for corner in corners.dropFirst() { path.addLine(to: corner) }
        path.closeSubpath()
        if hidden {
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [5, 4]))
        } else {
            context.fill(path, with: .color(color.opacity(0.16)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }
}

/// A part of the picture to bring up close (normalized, 0…1), each request with its own `id`.
struct RefineFocus: Equatable {
    let id: Int
    let rect: CGRect
    let animated: Bool
}

/// Where a finger is in a stroke on the refine canvas.
enum RefineTouch {
    case began, moved, ended, cancelled
}

/// The refine canvas's touches: an invisible scroll view zooms and moves the picture with two
/// fingers, with the system's feel (the painting canvas's way), while one finger draws or taps;
/// a tap of two fingers undoes, as in drawing apps. Once an Apple Pencil touches it (or with
/// Only Draw with Apple Pencil on), the Pencil draws and taps, and one finger moves the picture
/// too, as on the painting canvas; the Pencil's double tap is reported. A finger (or the Pencil)
/// held still on the picture for a moment is a long press, which no tool draws with: it opens the
/// area's card. Reports where the picture is in its frame and its zoom, and touches in picture
/// coordinates (0…1, origin top-left).
struct RefineTouchSurface: UIViewRepresentable {
    var aspectRatio: CGFloat
    var onLayout: (CGRect, CGFloat) -> Void
    var onDraw: (RefineTouch, SIMD2<Float>) -> Void
    var onTap: (SIMD2<Float>) -> Void
    var onUndo: () -> Void
    var onPencilTap: () -> Void
    var onLongPress: (SIMD2<Float>) -> Void = { _ in }
    var focus: RefineFocus?

    func makeUIView(context: Context) -> RefineSurfaceView { RefineSurfaceView() }

    func updateUIView(_ view: RefineSurfaceView, context: Context) {
        view.onLayout = onLayout
        view.onDraw = onDraw
        view.onTap = onTap
        view.onUndo = onUndo
        view.onPencilTap = onPencilTap
        view.onLongPress = onLongPress
        view.aspectRatio = aspectRatio
        // Zooming reports the layout, which sets state: never within SwiftUI's update.
        if let focus, focus.id != view.focusedRequest {
            view.focusedRequest = focus.id
            Task { @MainActor in view.focus(on: focus) }
        }
    }
}

final class RefineSurfaceView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var aspectRatio: CGFloat = 1 {
        didSet { if aspectRatio != oldValue { setNeedsLayout() } }
    }
    var onLayout: ((CGRect, CGFloat) -> Void)?
    var onDraw: ((RefineTouch, SIMD2<Float>) -> Void)?
    var onTap: ((SIMD2<Float>) -> Void)?
    var onUndo: (() -> Void)?
    var onPencilTap: (() -> Void)?
    var onLongPress: ((SIMD2<Float>) -> Void)?

    /// The Pencil draws and fingers only move the picture: an Apple Pencil touched the canvas,
    /// or Only Draw with Apple Pencil is on. Stays so while the screen is open.
    private(set) var pencilDraws = false

    /// Deep enough that a Pencil outlines a star of a few canvas units comfortably (to Fill it).
    static let maximumZoom: CGFloat = 12
    /// Room around the picture at zoom 1, so it reads as a card.
    static let margin: CGFloat = 12
    /// How long a touch is held still before it is a long press, iOS's own half second, and how
    /// far it may wander meanwhile: little, so a slow, careful stroke still draws.
    static let pressDuration: TimeInterval = 0.5
    static let pressMovement: CGFloat = 4

    private let scrollView = UIScrollView()
    /// The picture at zoom 1, which the scroll view zooms: touches read in its coordinates.
    private let content = UIView()
    private let brush = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private let press = UILongPressGestureRecognizer()
    /// Where the brush's finger came down: the stroke starts there, not where the pan began, past
    /// its slop (UIKit's translation at `.began` doesn't reach back to the touch).
    private var touchDown: CGPoint?
    private var fittedSize: CGSize = .zero
    private var reported: (rect: CGRect, zoom: CGFloat)?
    private var isLayingOut = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.scrollsToTop = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = Self.maximumZoom
        // One finger is the brush's: the picture moves with two.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        content.isUserInteractionEnabled = false
        scrollView.addSubview(content)
        addSubview(scrollView)

        brush.addTarget(self, action: #selector(handleBrush(_:)))
        brush.maximumNumberOfTouches = 1
        brush.delegate = self
        scrollView.addGestureRecognizer(brush)
        tap.addTarget(self, action: #selector(handleTap(_:)))
        scrollView.addGestureRecognizer(tap)
        // Held still, a touch is a long press; moved, the brush's. A tap waits for the press to
        // fail, which it does the moment the finger lifts early.
        press.addTarget(self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = Self.pressDuration
        press.allowableMovement = Self.pressMovement
        press.delegate = self
        scrollView.addGestureRecognizer(press)
        tap.require(toFail: press)
        let undo = UITapGestureRecognizer(target: self, action: #selector(handleUndo(_:)))
        undo.numberOfTouchesRequired = 2
        scrollView.addGestureRecognizer(undo)
        addInteraction(UIPencilInteraction(delegate: self))
        if UIPencilInteraction.prefersPencilOnlyDrawing { drawWithPencil() }
    }

    /// From now on the Pencil (and a pointer) draws and taps; one finger moves the picture, two
    /// zoom it.
    private func drawWithPencil() {
        guard !pencilDraws else { return }
        pencilDraws = true
        let drawing = [UITouch.TouchType.pencil, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        brush.allowedTouchTypes = drawing
        tap.allowedTouchTypes = drawing
        press.allowedTouchTypes = drawing
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [UITouch.TouchType.direct, .indirectPointer]
            .map { NSNumber(value: $0.rawValue) }
    }

    /// While the Pencil draws, a palm or a finger beside it neither moves the picture nor ends
    /// the stroke.
    private func holdPicture(_ held: Bool) {
        guard pencilDraws else { return }
        scrollView.panGestureRecognizer.isEnabled = !held
        scrollView.pinchGestureRecognizer?.isEnabled = !held
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        isLayingOut = true
        defer { isLayingOut = false }
        super.layoutSubviews()
        scrollView.frame = bounds
        let fitted = CompareView.fitted(aspectRatio, in: bounds.insetBy(dx: Self.margin, dy: Self.margin).size)
        if fitted != fittedSize {
            fittedSize = fitted
            scrollView.zoomScale = 1
            content.frame = CGRect(origin: .zero, size: fitted)
            scrollView.contentSize = fitted
        }
        centre()
        report()
    }

    /// Insets that centre the picture while it is smaller than the frame.
    private func centre() {
        let size = content.frame.size
        let x = max(0, (bounds.width - size.width) / 2), y = max(0, (bounds.height - size.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    /// The last focus asked for (`RefineFocus.id`).
    var focusedRequest: Int?

    /// Zooms in on `focus.rect` (normalized to the picture).
    func focus(on focus: RefineFocus) {
        focusedRequest = focus.id
        guard fittedSize.width > 0, fittedSize.height > 0 else { return }
        let rect = CGRect(
            x: focus.rect.minX * fittedSize.width, y: focus.rect.minY * fittedSize.height,
            width: focus.rect.width * fittedSize.width, height: focus.rect.height * fittedSize.height)
        scrollView.zoom(to: rect, animated: focus.animated)
    }

    private func report() {
        let rect = content.frame.offsetBy(dx: -scrollView.contentOffset.x, dy: -scrollView.contentOffset.y)
        let zoom = scrollView.zoomScale
        if let reported, reported.rect == rect, reported.zoom == zoom { return }
        reported = (rect, zoom)
        // Never inside a layout pass SwiftUI may be running.
        if isLayingOut {
            Task { @MainActor [weak self] in self?.onLayout?(rect, zoom) }
        } else {
            onLayout?(rect, zoom)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { report() }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cancelDrawing() }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { cancelDrawing() }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        report()
    }

    /// Two fingers came down while one was drawing: they move the picture, and the stroke goes.
    /// (The Pencil's stroke holds the picture still instead, `holdPicture`.)
    private func cancelDrawing() {
        guard brush.state == .began || brush.state == .changed else { return }
        brush.isEnabled = false
        brush.isEnabled = true
    }

    // MARK: Touches

    @objc private func handleBrush(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: content)
        switch recognizer.state {
        case .began:
            holdPicture(true)
            // The stroke starts where the finger came down, before the pan's slop (a stroke's
            // first ten points or so were lost, so a shape drawn in strokes didn't close).
            let moved = recognizer.translation(in: content)
            let start = touchDown ?? CGPoint(x: location.x - moved.x, y: location.y - moved.y)
            touchDown = nil
            onDraw?(.began, normalized(start))
            onDraw?(.moved, normalized(location))
        case .changed:
            onDraw?(.moved, normalized(location))
        case .ended:
            holdPicture(false)
            touchDown = nil
            onDraw?(.ended, normalized(location))
        default:
            holdPicture(false)
            touchDown = nil
            onDraw?(.cancelled, normalized(location))
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?(normalized(recognizer.location(in: content)))
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress?(normalized(recognizer.location(in: content)))
    }

    @objc private func handleUndo(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onUndo?()
    }

    private func normalized(_ p: CGPoint) -> SIMD2<Float> {
        guard fittedSize.width > 0, fittedSize.height > 0 else { return .zero }
        return SIMD2(Float(p.x / fittedSize.width), Float(p.y / fittedSize.height))
    }

    /// A pinch may begin as a stroke: the scroll view's gestures run beside the brush's and
    /// cancel its stroke (`cancelDrawing`) rather than lose to it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A press and a stroke are one finger's: whichever comes first has it.
        !(gestureRecognizer === press && other === brush) && !(gestureRecognizer === brush && other === press)
    }

    /// A stroke can't begin under a press that has begun, nor a press under a stroke.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === brush { return press.state != .began && press.state != .changed }
        if gestureRecognizer === press { return brush.state != .began && brush.state != .changed }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// The first touch of an Apple Pencil hands drawing to it (the brush sees every touch until
    /// then).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.type == .pencil { drawWithPencil() }
        // Only a touch that can start the stroke: the first, of a kind the brush takes.
        if gestureRecognizer === brush, brush.numberOfTouches == 0,
           brush.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue)) {
            touchDown = touch.location(in: content)
        }
        return true
    }
}

extension RefineSurfaceView: UIPencilInteractionDelegate {
    // Honour the Apple Pencil settings: the double tap may be turned off there.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilTap?()
    }
}
