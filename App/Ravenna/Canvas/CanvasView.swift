import CoreGraphics
import Foundation
import Metal
import MosaicKit
import PaintCore
import QuartzCore
import UIKit
import os
import simd

/// Where the canvas looks when it first lays out (demo scenarios, restored sessions).
struct CanvasCamera: Equatable {
    /// Zoom relative to "fit the whole canvas".
    var zoom: CGFloat
    /// Canvas point to centre in the visible area.
    var center: SIMD2<Float>
}

enum PencilAction {
    case tap, squeeze
    /// The Pencil left the canvas after a stroke.
    case lifted
}

/// The painting surface: a `CAMetalLayer` driven by an invisible `UIScrollView` overlay so
/// pan, pinch, deceleration and rubber-banding are exactly the system's. Renders with a
/// display link only while something changes (gesture, deceleration, paint animation).
///
/// Gestures: tap paints (with tolerance), a quick second tap on something unpaintable zooms,
/// press-and-drag paints every matching region under the finger, Apple Pencil paints
/// directly while fingers navigate, and Pencil hover previews the region under the tip.
/// A held Photo control fades the source photo in over the canvas; while it shows, any
/// canvas touch (tap or long press) hides it again instead of painting blind.
///
/// VoiceOver and Switch Control see the canvas as a container of the unpainted areas of the
/// selected color that are in view (activating one paints it), with custom actions (paint
/// next, zoom to next, hint, zoom to fit), an "Unpainted areas" rotor and three-finger page
/// scrolling. `reduceMotion` makes fills land at once, drops the finishing shine and steps
/// the replay.
///
/// Finishing the painting (`finish`): its last fill lingers, the camera then eases out to the
/// whole painting, and a shine sweeps all of it as the camera lands; in SideStore and Debug
/// builds night then falls over it for about three seconds (`Nightfall`). A flight to the whole
/// painting follows layout changes on the way (the completion bar replacing the palette, a
/// rotation) instead of stopping.
///
/// A mosaic (`PaintingSession.wall`, Ravenna's seam) is drawn as tiles (`TileScene`): each tile set
/// is pressed, settles and catches the light (MosaicKit's `Motion`), the tiles of one stroke
/// settling `Motion.rowGap` apart, instead of paint spreading and sparkles; finishing it, light
/// rakes across the wall instead of the shine and the night (v0's finish), and a used-up paint's
/// tiles catch a lesser light. Under Reduce Motion tiles fade in and nothing rakes. With
/// `OneFinger.lays` (`TileOptions`) one finger lays a row as it drags, and two move the wall.
final class CanvasView: UIView, PaintingCanvas {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    let session: PaintingSession
    /// Areas covered by floating chrome; the canvas fits inside and can scroll clear of them.
    var chromeInsets: UIEdgeInsets = .zero {
        didSet { if chromeInsets != oldValue { setNeedsLayout() } }
    }
    var showsNumbers = true {
        didSet { if showsNumbers != oldValue { numbersChanged() } }
    }
    var initialCamera: CanvasCamera?
    var onPencilAction: ((PencilAction) -> Void)?
    /// Scales fill, sparkle and replay durations (demo scenarios catch them mid-way).
    var fillDurationScale: Float = 1
    /// Loads the photo the painting was made from, the first time it is shown.
    var photoLoader: SourcePhotoLoader?
    /// Fades the source photo in over the canvas (loading it first if needed).
    var showsPhoto = false {
        didSet { if showsPhoto != oldValue { photoChanged() } }
    }
    /// The photo couldn't be loaded (no loader, no Metal, or no readable file).
    var onPhotoUnavailable: (() -> Void)?
    /// A canvas touch asked to hide the photo.
    var onDismissPhoto: (() -> Void)?
    /// Whether the first frame is watched for (`hasShownFirstFrame`): the start of a painting is
    /// handed over to it (`StartHandoff`). Set before the canvas is in a window; nothing draws
    /// before it has been laid out.
    var watchesFirstFrame = false
    /// The first frame is on screen (a tenth of a second after the GPU finished it).
    private(set) var hasShownFirstFrame = false
    /// The painter zoomed the canvas: a double tap or a pinch.
    var onZoomStep: (() -> Void)?
    /// A finger took hold of the canvas to move or zoom it (true), or let go and the camera came to
    /// rest (false): the gentle tips wait for the hand.
    var onHandChange: ((Bool) -> Void)?
    /// The zoom relative to the fitted canvas changed (pinch, double tap, camera moves).
    var onZoomChange: ((CGFloat) -> Void)?
    /// Set from SwiftUI's `accessibilityReduceMotion`: camera moves jump, fills and undos land
    /// at once, finishing doesn't shine, the replay steps through the fills, and hints and
    /// wrong-paint numbers light up and fade instead of throbbing or popping.
    var reduceMotion = false
    /// Settings › Paper: which paper the canvas shows. `automatic` follows the system appearance,
    /// re-resolved on every trait change like the backdrop.
    var paperAppearance = PaperAppearance.default {
        didSet { if paperAppearance != oldValue { paperChanged() } }
    }
    /// Settings › Line Weight: how heavy a coloring book's drawing is. The next frame uses it,
    /// so a change shows at once; classic templates ignore it.
    var lineWeight = LineWeight.default {
        didSet { if lineWeight != oldValue, scene?.isColoringBook == true { requestRender() } }
    }
    /// Feedback mode (`MarkupCanvas`): the drawing canvas over this one takes every touch and
    /// moves the camera (`follow`). VoiceOver isn't offered areas to paint meanwhile.
    var isAnnotating = false {
        didSet { if isAnnotating != oldValue { annotatingChanged() } }
    }

    private let template: Template
    /// The mosaic, when the painting is one: drawn as tiles.
    private let wall: TileWall?
    private let scene: CanvasScene?
    private let renderer: CanvasRenderer?
    private let scrollView = UIScrollView()
    private let zoomView = UIView()
    private var displayLink: CADisplayLink?
    private let epoch = CACurrentMediaTime()

    // Render scheduling
    private var needsRender = true
    private var idleTicks = 0
    private var activeUntil: Float = 0
    private var lastCamera: Camera?

    // Visual state fed to the shaders (renderer clock, seconds)
    private var selectionTime = CanvasClock.never
    private var pulseRegion = -1
    private var pulseStart = CanvasClock.never
    private var bumpRegion = -1
    private var bumpStart = CanvasClock.never
    private var hoverRegion = -1
    private var brushPoint: CGPoint?
    private var numbersFade = Fade(from: 1, to: 1, duration: 0.25)
    /// When the finishing shine starts (renderer clock; tests read it).
    private(set) var shineStart = CanvasClock.never
    private var replayTask: Task<Void, Never>?
    private var isReplaying = false
    private var shineColor = -1
    /// The fill moment's gold sparkles: a few layers over the canvas, reused in turn.
    private var sparkleLayers: [CAShapeLayer] = []
    private var nextSparkle = 0
    private var lastSparkles: CFTimeInterval = 0
    private var photoTexture: (any MTLTexture)?
    private var photoTask: Task<Void, Never>?
    private var photoFade = Fade(from: 0, to: 0, duration: 0.2)
    /// When every fill painted so far has landed (renderer clock).
    private var fillsLand = CanvasClock.never
    /// The finish's flight, waiting for the last fill to land (`finish`).
    private var finishTask: Task<Void, Never>?
    /// The painting was finished by a stroke still under way: the finish flies once it ends.
    private var finishAwaitsStroke = false
    #if UNRELEASED
    /// Night falling over the painting just finished (`Nightfall`), while it plays.
    private var nightfall: Nightfall?
    private var nightfallTask: Task<Void, Never>?
    /// When the latest night over the finished painting was at its fullest (media time; demos
    /// wait for it).
    private(set) var nightfallPeak: CFTimeInterval?
    #endif

    // Camera
    private var fitZoom: CGFloat = 1
    private var laidOutSize: CGSize = .zero
    private var laidOutInsets: UIEdgeInsets = .zero
    private var cameraAnimation: CameraAnimation?
    private var isApplyingCamera = false

    // Tiles (a mosaic)
    /// The painted bed's texture, once made (`TileScene.bed`).
    private var bedTexture: (any MTLTexture)?
    private var bedTask: Task<Void, Never>?
    /// When the last tile set so far starts settling, and when every one has settled (the lift
    /// pass draws until then).
    private var lastSettleStart = CanvasClock.never
    private var liftUntil = CanvasClock.never

    // Gestures
    private var tapRecognizer: UITapGestureRecognizer!
    private var tapBeganWhileMoving = false
    private var tapWasFinger = false
    private var lastTap: (time: CFTimeInterval, point: CGPoint, painted: Bool)?
    private var dragLast: SIMD2<Float>?

    // Accessibility
    /// Per region: where its number sits (the bounds centre when it has none), the number's
    /// free radius, and per color its regions.
    private let anchors: [SIMD2<Float>]
    private let labelRadii: [Float]
    private let regionsByColor: [[Int]]
    /// The elements VoiceOver sees; nil when stale (rebuilt on demand).
    private var accessibleItems: [NSObject]?
    /// Reused across rebuilds so VoiceOver focus survives camera moves.
    private var areaElements: [Int: CanvasAreaElement] = [:]
    private lazy var placeholder = UIAccessibilityElement(accessibilityContainer: self)
    #if DEBUG
    /// Keep identities alive between UIKit's enumeration and attribute reads.
    private var playElements: [String: UIAccessibilityElement] = [:]
    #endif
    /// Where VoiceOver focus goes once the camera settles (after a hint or an action).
    private(set) var pendingFocus: PendingFocus?
    /// The last area "Zoom to next area" visited, in reading order over the whole canvas.
    private var tourKey: CanvasAccessibility.ReadingKey?
    /// True while VoiceOver paints an area: that path moves focus and speaks itself.
    private var isAccessibilityPainting = false

    enum PendingFocus: Equatable {
        case region(Int)
        case first
    }

    static let margin: CGFloat = 16
    private static let tapTolerance: CGFloat = 14
    private static let brushRadius: CGFloat = 11

    /// The finish (`finish`): the fill that finishes the painting spreads this much slower (0.9 s
    /// at most), the camera rests on it this long once it has landed, then eases out to the whole
    /// painting for `finishFlight` seconds, unless it is within `finishFitSlack` of it already.
    private static let lastFillSlowdown: Float = 1.5
    private static let finishPause: Float = 0.35
    private static let finishFlight: CFTimeInterval = 0.8
    private static let finishFitSlack: CGFloat = 0.05

    private struct Camera: Equatable {
        var zoom: CGFloat
        var origin: CGPoint
    }

    private struct CameraAnimation {
        var fromZoom: CGFloat
        var toZoom: CGFloat
        var fromOffset: CGPoint
        var toOffset: CGPoint
        var start: CFTimeInterval
        var duration: CFTimeInterval
        /// Heading for the whole painting: a layout change on the way retargets it to the new fit.
        var fits: Bool
    }

    init(session: PaintingSession) {
        self.session = session
        let template = session.template
        self.template = template
        anchors = template.regions.indices.map { template.anchor(ofRegion: $0) }
        labelRadii = template.regions.indices.map { i in
            template.labels(ofRegion: i).first?.radius ?? template.regions[i].inscribedRadius
        }
        var byColor = [[Int]](repeating: [], count: template.palette.count)
        for (i, region) in template.regions.enumerated() { byColor[Int(region.colorIndex)].append(i) }
        regionsByColor = byColor
        wall = session.wall
        let context = RenderContext.shared
        let scene = context.flatMap { CanvasScene(template: session.template, context: $0, wall: session.wall) }
        self.scene = scene
        if let context, let scene {
            renderer = CanvasRenderer(
                scene: scene, context: context,
                states: CanvasView.settledStates(template: session.template, progress: session.progress))
        } else {
            renderer = nil
        }
        super.init(frame: .zero)
        configureLayer(device: context?.device)
        configureScrollView()
        configureGestures()
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = PaintSpeech.canvasLabel
        accessibilityIdentifier = "canvas"
        accessibilityCustomActions = accessibilityActionList
        accessibilityCustomRotors = [areasRotor]
        registerForTraitChanges([UITraitUserInterfaceStyle.self], action: #selector(paperChanged))
        tracePaper()
        session.canvas = self
        session.onEvent { [weak self] event in self?.celebrate(event) }
        loadBed()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// False when Metal couldn't be set up for this painting: nothing would ever be drawn.
    var isRenderable: Bool { renderer != nil }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private static func settledStates(template: Template, progress: PaintProgress) -> [RegionState] {
        template.regions.indices.map { RegionState.settled(painted: progress.isPainted($0)) }
    }

    // MARK: Setup

    private func configureLayer(device: (any MTLDevice)?) {
        let layer = metalLayer
        layer.device = device
        layer.pixelFormat = RenderContext.colorFormat
        layer.framebufferOnly = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        layer.maximumDrawableCount = 3
        layer.presentsWithTransaction = false
        layer.isOpaque = true
        backgroundColor = .systemGroupedBackground
    }

    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.scrollsToTop = false
        zoomView.frame = CGRect(x: 0, y: 0, width: template.width, height: template.height)
        zoomView.isUserInteractionEnabled = false
        scrollView.addSubview(zoomView)
        scrollView.contentSize = zoomView.bounds.size
        addSubview(scrollView)
    }

    private static let fingerTouches = [
        NSNumber(value: UITouch.TouchType.direct.rawValue),
        NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
    ]

    private func configureGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.allowedTouchTypes = Self.fingerTouches
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        tapRecognizer = tap

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleDragPaint(_:)))
        press.minimumPressDuration = 0.28
        press.allowableMovement = 12
        press.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(press)

        if wall != nil, TileOptions.oneFinger() == .lays {
            // One finger lays a row as it drags, at once; two move and zoom the wall.
            press.isEnabled = false
            let lay = UIPanGestureRecognizer(target: self, action: #selector(handleLay(_:)))
            lay.maximumNumberOfTouches = 1
            lay.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            scrollView.addGestureRecognizer(lay)
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        }

        let pencil = UILongPressGestureRecognizer(target: self, action: #selector(handlePencil(_:)))
        pencil.minimumPressDuration = 0
        pencil.allowableMovement = .greatestFiniteMagnitude
        pencil.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        scrollView.addGestureRecognizer(pencil)

        scrollView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:))))
        addInteraction(UIPencilInteraction(delegate: self))
    }

    /// Fingers navigate; the Pencil paints.
    private func restrictNavigationToFingers() {
        scrollView.panGestureRecognizer.allowedTouchTypes = Self.fingerTouches
            + [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = Self.fingerTouches
    }

    // MARK: Lifecycle

    override var canBecomeFirstResponder: Bool { true }
    /// None while a replay plays: ⌘Z, the Edit menu and three-finger undo would take fills off
    /// the painting being played back.
    override var undoManager: UndoManager? { isReplaying ? nil : super.undoManager }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            setNeedsLayout()
            requestRender()
            // First responder so the window's undo manager serves three-finger undo and ⌘Z.
            Task { self.becomeFirstResponder() }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        if contentScaleFactor != scale { contentScaleFactor = scale }
        let drawable = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if metalLayer.drawableSize != drawable { metalLayer.drawableSize = drawable }
        if scrollView.frame != bounds { scrollView.frame = bounds }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard bounds.size != laidOutSize || chromeInsets != laidOutInsets else { return }

        // Keep looking at the same place across rotation / chrome changes.
        let relative: CGFloat
        let center: SIMD2<Float>
        if laidOutSize != .zero {
            relative = scrollView.zoomScale / fitZoom
            let old = CGRect(origin: .zero, size: laidOutSize).inset(by: laidOutInsets)
            center = canvasPoint(forView: CGPoint(x: old.midX, y: old.midY))
        } else if let initial = initialCamera {
            relative = initial.zoom
            center = initial.center
        } else {
            relative = 1
            center = SIMD2(Float(template.width), Float(template.height)) / 2
        }
        laidOutSize = bounds.size
        laidOutInsets = chromeInsets
        updateZoomLimits()
        restrictNavigationToFingers()
        let z = clampZoom(fitZoom * relative)
        let flight = cameraAnimation
        cameraAnimation = nil
        apply(zoom: z, offset: offset(centering: center, zoom: z))
        if let flight, flight.fits {
            // On from here to the new fit, landing when it would have.
            flyToFit(duration: max(0.2, flight.start + flight.duration - CACurrentMediaTime()))
        } else {
            cameraDidSettle()
        }
    }

    /// The paper, backdrop and ink the next frame draws with.
    private var canvasPalette: CanvasPalette {
        .resolve(paperAppearance, interfaceIsDark: traitCollection.userInterfaceStyle == .dark)
    }

    /// The Paper preference or the system appearance changed.
    @objc private func paperChanged() {
        tracePaper()
        requestRender()
    }

    /// `-tracePaper YES`: the canvas's accessibility identifier names the paper it resolved,
    /// so a UI test can see the preference reach the canvas.
    private func tracePaper() {
        #if DEBUG
        guard DemoMode.tracesPaper else { return }
        let dark = paperAppearance.usesDarkPaper(interfaceIsDark: traitCollection.userInterfaceStyle == .dark)
        accessibilityIdentifier = dark ? "canvas-paper-dark" : "canvas-paper-light"
        #endif
    }

    // MARK: Camera

    private func updateZoomLimits() {
        let avail = bounds.inset(by: chromeInsets).insetBy(dx: Self.margin, dy: Self.margin)
        let fit = max(1e-3, min(avail.width / CGFloat(template.width), avail.height / CGFloat(template.height)))
        fitZoom = fit
        // Deep enough that small numbers read comfortably, never absurd.
        let legible = 15 / CGFloat(max(scene?.smallLabelSize ?? 4, 0.25))
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = min(max(legible, fit * 4), fit * 40)
    }

    private func clampZoom(_ z: CGFloat) -> CGFloat {
        min(max(z, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
    }

    /// Content insets that centre the canvas when it is smaller than the visible area.
    private func insets(forZoom z: CGFloat) -> UIEdgeInsets {
        let avail = bounds.inset(by: chromeInsets).insetBy(dx: Self.margin, dy: Self.margin)
        let w = CGFloat(template.width) * z, h = CGFloat(template.height) * z
        let ex = max(0, (avail.width - w) / 2), ey = max(0, (avail.height - h) / 2)
        return UIEdgeInsets(
            top: chromeInsets.top + Self.margin + ey, left: chromeInsets.left + Self.margin + ex,
            bottom: chromeInsets.bottom + Self.margin + ey, right: chromeInsets.right + Self.margin + ex)
    }

    private func clampedOffset(_ o: CGPoint, zoom z: CGFloat) -> CGPoint {
        let ins = insets(forZoom: z)
        let w = CGFloat(template.width) * z, h = CGFloat(template.height) * z
        let minX = -ins.left, maxX = max(minX, w + ins.right - bounds.width)
        let minY = -ins.top, maxY = max(minY, h + ins.bottom - bounds.height)
        return CGPoint(x: min(max(o.x, minX), maxX), y: min(max(o.y, minY), maxY))
    }

    /// Content offset that shows canvas point `c` in the middle of the visible area.
    private func offset(centering c: SIMD2<Float>, zoom z: CGFloat) -> CGPoint {
        let avail = bounds.inset(by: chromeInsets)
        return clampedOffset(CGPoint(x: CGFloat(c.x) * z - avail.midX, y: CGFloat(c.y) * z - avail.midY), zoom: z)
    }

    private func apply(zoom z: CGFloat, offset o: CGPoint) {
        isApplyingCamera = true
        if scrollView.zoomScale != z { scrollView.zoomScale = z }
        scrollView.contentInset = insets(forZoom: z)
        scrollView.contentOffset = o
        isApplyingCamera = false
        // Runs every animation frame: invalidate only, the settle announces the new layout.
        accessibilityChanged(post: false)
        requestRender()
        onZoomChange?(relativeZoom)
    }

    private func animateCamera(zoom: CGFloat, offset: CGPoint, duration: CFTimeInterval, fits: Bool = false) {
        if reduceMotion {
            cameraAnimation = nil
            apply(zoom: zoom, offset: offset)
            cameraDidSettle()
            return
        }
        cameraAnimation = CameraAnimation(
            fromZoom: scrollView.zoomScale, toZoom: zoom, fromOffset: scrollView.contentOffset, toOffset: offset,
            start: CACurrentMediaTime(), duration: duration, fits: fits)
        requestRender()
    }

    private func stepCameraAnimation(at time: CFTimeInterval) {
        guard let a = cameraAnimation else { return }
        let t = min(1, max(0, (time - a.start) / a.duration))
        let e = CGFloat(1 - pow(1 - t, 3))
        let z = a.fromZoom * pow(a.toZoom / a.fromZoom, e)
        var o: CGPoint
        if abs(a.toZoom - a.fromZoom) < a.fromZoom * 1e-4 {
            o = CGPoint(x: a.fromOffset.x + (a.toOffset.x - a.fromOffset.x) * e,
                        y: a.fromOffset.y + (a.toOffset.y - a.fromOffset.y) * e)
        } else {
            // Scale about the fixed point of the start→end similarity: one continuous motion.
            let cx = (a.toOffset.x - a.fromOffset.x) / (a.toZoom - a.fromZoom)
            let cy = (a.toOffset.y - a.fromOffset.y) / (a.toZoom - a.fromZoom)
            let fx = cx * a.fromZoom - a.fromOffset.x, fy = cy * a.fromZoom - a.fromOffset.y
            o = CGPoint(x: cx * z - fx, y: cy * z - fy)
        }
        if t >= 1 {
            o = a.toOffset
            cameraAnimation = nil
        }
        apply(zoom: t >= 1 ? a.toZoom : z, offset: o)
        if t >= 1 { cameraDidSettle() }
    }

    /// The current view transform (view = origin + canvas · zoom). Reads presentation values
    /// only while UIKit animates the scroll view (e.g. zoom bounce), so ordinary scrolling
    /// never lags a frame behind the model values.
    private func currentCamera() -> Camera {
        let zl = zoomView.layer, sl = scrollView.layer
        let animating = !(zl.animationKeys()?.isEmpty ?? true) || !(sl.animationKeys()?.isEmpty ?? true)
        let z = animating ? (zl.presentation() ?? zl) : zl
        let s = animating ? (sl.presentation() ?? sl) : sl
        let scale = z.transform.m11
        let size = z.bounds.size
        return Camera(
            zoom: scale,
            origin: CGPoint(
                x: z.position.x - z.anchorPoint.x * size.width * scale - s.bounds.origin.x,
                y: z.position.y - z.anchorPoint.y * size.height * scale - s.bounds.origin.y))
    }

    /// View point → canvas point (internal for tests).
    func canvasPoint(forView p: CGPoint) -> SIMD2<Float> {
        let c = currentCamera()
        return SIMD2(Float((p.x - c.origin.x) / c.zoom), Float((p.y - c.origin.y) / c.zoom))
    }

    /// Canvas point → view point (accessibility frames and tests).
    func viewPoint(forCanvas p: SIMD2<Float>) -> CGPoint {
        let c = currentCamera()
        return CGPoint(x: c.origin.x + CGFloat(p.x) * c.zoom, y: c.origin.y + CGFloat(p.y) * c.zoom)
    }

    private func canvasPoint(_ zoomViewPoint: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(zoomViewPoint.x), Float(zoomViewPoint.y))
    }

    /// Canvas point at the middle of the visible area.
    var visibleCenter: SIMD2<Float> {
        let avail = bounds.inset(by: chromeInsets)
        return canvasPoint(forView: CGPoint(x: avail.midX, y: avail.midY))
    }

    /// Zoom relative to the fitted canvas: 1 shows the whole painting.
    var relativeZoom: CGFloat { fitZoom > 0 ? scrollView.zoomScale / fitZoom : 1 }

    /// Whether a camera flight is under way (tests and demos wait for one to land).
    var isCameraFlying: Bool { cameraAnimation != nil }

    /// Where the camera looks (where a camera move in flight is heading), so a canvas of another
    /// template of the same size can open there.
    var camera: CanvasCamera {
        guard let a = cameraAnimation, fitZoom > 0, a.toZoom > 0 else {
            return CanvasCamera(zoom: relativeZoom, center: visibleCenter)
        }
        // View point = zoomed canvas point − content offset.
        let avail = bounds.inset(by: chromeInsets)
        let center = SIMD2(Float((a.toOffset.x + avail.midX) / a.toZoom), Float((a.toOffset.y + avail.midY) / a.toZoom))
        return CanvasCamera(zoom: a.toZoom / fitZoom, center: center)
    }

    /// Animates to `relative` times the fitted zoom, about the middle of the visible area.
    func zoom(toRelative relative: CGFloat) {
        guard scrollView.zoomScale > 0 else { return }
        zoom(by: relative * fitZoom / scrollView.zoomScale)
    }

    func zoomToFit(animated: Bool = true) {
        if animated {
            flyToFit(duration: 0.5)
        } else {
            cameraAnimation = nil
            apply(zoom: fitZoom, offset: fitOffset)
            cameraDidSettle()
        }
    }

    /// The content offset that centres the whole painting at the fitted zoom.
    private var fitOffset: CGPoint {
        offset(centering: SIMD2(Float(template.width), Float(template.height)) / 2, zoom: fitZoom)
    }

    /// Flies to the whole painting; a layout change on the way retargets the flight to the new
    /// fit (`layoutSubviews`).
    private func flyToFit(duration: CFTimeInterval) {
        animateCamera(zoom: fitZoom, offset: fitOffset, duration: duration, fits: true)
    }

    /// Keyboard zoom about the middle of the visible area.
    func zoom(by factor: CGFloat) {
        let avail = bounds.inset(by: chromeInsets)
        let anchor = CGPoint(x: avail.midX, y: avail.midY)
        let target = clampZoom(scrollView.zoomScale * factor)
        let c = canvasPoint(forView: anchor)
        let o = clampedOffset(CGPoint(x: CGFloat(c.x) * target - anchor.x, y: CGFloat(c.y) * target - anchor.y), zoom: target)
        animateCamera(zoom: target, offset: o, duration: 0.3)
    }

    /// Double-tap: zoom in around the point, or back out to fit when already deep.
    private func zoomStep(at view: CGPoint) {
        let z = scrollView.zoomScale, maxZ = scrollView.maximumZoomScale
        if z > maxZ * 0.8 {
            zoomToFit()
            return
        }
        let target = clampZoom(max(z * 2.5, fitZoom * 2.5))
        let c = canvasPoint(forView: view)
        let o = clampedOffset(CGPoint(x: CGFloat(c.x) * target - view.x, y: CGFloat(c.y) * target - view.y), zoom: target)
        animateCamera(zoom: target, offset: o, duration: 0.42)
    }

    /// Reveals a region: zoom until its number reads comfortably (without overflowing the
    /// view), centre it, then pulse it.
    func reveal(region: Int) {
        let r = template.regions[region]
        let center = anchors[region]
        let labelSize = CGFloat(max(scene?.labelSizes[region] ?? 8, 0.5))
        let extent = CGFloat(max(r.bounds.width, r.bounds.height, 1))
        let avail = bounds.inset(by: chromeInsets)
        let legible = 17 / labelSize
        let roomy = 0.45 * min(avail.width, avail.height) / extent
        // Always fly in a little so the eye follows to the spot, but never past a view-filling region.
        let z = clampZoom(max(scrollView.zoomScale, min(roomy, max(legible, fitZoom * 2))))
        animateCamera(zoom: z, offset: offset(centering: center, zoom: z), duration: 0.55)
        pulseRegion = region
        // Pulse as the flight lands; under Reduce Motion the camera is already there.
        pulseStart = now() + (reduceMotion ? 0 : 0.4)
        activeUntil = max(activeUntil, pulseStart + 2.1)
    }

    /// Asks the session for a hint near what the user is looking at.
    func showHint() {
        session.showHint(near: visibleCenter)
    }

    // MARK: Camera of another scroll view

    /// The camera as a scroll view holds it (`zoom` points per canvas unit, `offset` the content
    /// offset over the zoomed canvas) and the zooms it allows: what a scroll view that takes
    /// over navigation starts from (`MarkupCanvas`).
    struct ScrollCamera: Equatable {
        var zoom: CGFloat
        var offset: CGPoint
        var zoomRange: ClosedRange<CGFloat>
    }

    var scrollCamera: ScrollCamera {
        let low = scrollView.minimumZoomScale
        return ScrollCamera(
            zoom: scrollView.zoomScale, offset: scrollView.contentOffset,
            zoomRange: low...max(low, scrollView.maximumZoomScale))
    }

    /// The content insets the canvas keeps at zoom `z`: clear of the chrome, centring a canvas
    /// smaller than the view.
    func contentInsets(forZoom z: CGFloat) -> UIEdgeInsets { insets(forZoom: z) }

    /// Shows what another scroll view looks at (`ScrollCamera`'s units), on this canvas's own
    /// scroll view too.
    func follow(zoom: CGFloat, offset: CGPoint) {
        cameraAnimation = nil
        apply(zoom: zoom, offset: offset)
    }

    /// The part of the canvas in view, clear of the chrome (canvas units).
    var visibleCanvasRect: CGRect {
        let area = bounds.inset(by: chromeInsets)
        let a = canvasPoint(forView: CGPoint(x: area.minX, y: area.minY))
        let b = canvasPoint(forView: CGPoint(x: area.maxX, y: area.maxY))
        let seen = CGRect(x: CGFloat(a.x), y: CGFloat(a.y), width: CGFloat(b.x - a.x), height: CGFloat(b.y - a.y))
        return seen.intersection(CGRect(x: 0, y: 0, width: template.width, height: template.height))
    }

    /// Points on screen per canvas unit now.
    var pointsPerUnit: CGFloat { currentCamera().zoom }

    private func annotatingChanged() {
        accessibilityElementsHidden = isAnnotating
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-playHarness") { accessibilityElementsHidden = false }
        #endif
        if isAnnotating {
            // The markup canvas starts from where the camera is: a flight would carry on alone.
            cameraAnimation = nil
            hoverRegion = -1
            pendingFocus = nil
        }
        accessibilityChanged()
        requestRender()
    }

    // MARK: Rendering

    private func now() -> Float { Float(CACurrentMediaTime() - epoch) }

    func requestRender() {
        needsRender = true
        idleTicks = 0
        displayLink?.isPaused = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        stepCameraAnimation(at: CACurrentMediaTime())
        let time = Float(link.targetTimestamp - epoch)
        let camera = currentCamera()
        let moving = scrollView.isTracking || scrollView.isDecelerating || scrollView.isZooming
            || scrollView.isZoomBouncing || cameraAnimation != nil
            || !(zoomView.layer.animationKeys()?.isEmpty ?? true) || !(scrollView.layer.animationKeys()?.isEmpty ?? true)
        guard needsRender || moving || time < activeUntil || camera != lastCamera else {
            idleTicks += 1
            if idleTicks > 3 { link.isPaused = true }
            return
        }
        idleTicks = 0
        guard let renderer else { return }
        #if DEBUG
        let began = CACurrentMediaTime()
        #endif
        let palette = canvasPalette
        let uniforms = makeUniforms(time: time, camera: camera, palette: palette)
        let content = RenderContext.Content(
            outlines: true, numbers: true, brush: brushPoint != nil,
            shadowMargin: Float(44 * contentScaleFactor),
            clear: MTLClearColor(
                red: Double(palette.background.x), green: Double(palette.background.y),
                blue: Double(palette.background.z), alpha: 1),
            photo: uniforms.photo.x > 0.001 ? photoTexture : nil,
            bed: bedTexture, lift: time < liftUntil)
        // The first frame that shows the fitted painting: the one the start of a painting is
        // handed over to, announced once it is on screen.
        var presented: (@Sendable () -> Void)?
        if watchesFirstFrame, !isAwaitingFirstFrame, laidOutSize != .zero {
            presented = Self.firstFrameReport(of: self)
        }
        if renderer.draw(in: metalLayer, uniforms: uniforms, content: content, onPresented: presented) {
            if presented != nil { isAwaitingFirstFrame = true }
            needsRender = false
            lastCamera = camera
            framesRendered += 1
            #if DEBUG
            let drawn = CACurrentMediaTime()
            FrameMeter.shared.drew(cpu: drawn - began, at: drawn)
            #endif
            skippedFrames = 0
        } else {
            skippedFrames += 1
            if skippedFrames == 120 { Log.canvas.error("canvas: no frame produced for 120 ticks") }
        }
    }

    /// Frames presented so far (diagnostics and tests).
    private(set) var framesRendered = 0
    private var skippedFrames = 0
    /// The frame `watchesFirstFrame` waits for is on its way to the screen.
    private var isAwaitingFirstFrame = false

    /// What Metal's thread calls when that frame is up (built outside the main actor: Metal
    /// calls it on a thread of its own).
    nonisolated private static func firstFrameReport(of view: CanvasView) -> @Sendable () -> Void {
        { [weak view] in
            guard let view else { return }
            Task { @MainActor in view.hasShownFirstFrame = true }
        }
    }

    /// Where the template is now, in this view's coordinates.
    var templateFrame: CGRect {
        let camera = currentCamera()
        return CGRect(
            x: camera.origin.x, y: camera.origin.y, width: CGFloat(template.width) * camera.zoom,
            height: CGFloat(template.height) * camera.zoom)
    }

    /// The paint state the shaders currently see for a region (tests).
    func regionState(_ region: Int) -> RegionState? { renderer?.states[region] }

    /// The shader constants a frame drawn now would get (tests).
    func frameUniforms() -> CanvasUniforms {
        makeUniforms(time: now(), camera: currentCamera(), palette: canvasPalette)
    }

    private func makeUniforms(time: Float, camera: Camera, palette: CanvasPalette) -> CanvasUniforms {
        let s = Float(contentScaleFactor)
        let finish = TileOptions.finish()
        let tiles = scene?.tiles.map { TileLook(finish: finish, hasBed: bedTexture != nil, grout: $0.grout, pace: fillDurationScale) }
        let palette = tiles == nil ? palette : palette.onTiles(finish)
        // Line art gets finer and lighter when zoomed out, where regions are small on screen.
        let depth = Float(log2(max(camera.zoom / fitZoom, 1)))
        let widthPt = ClassicLook.widthPoints(depth: depth)
        // A replay shows the painting as it was made, without the brush's highlight.
        let selected = isReplaying ? nil : session.selectedColor
        let paint = selected.flatMap { selected in
            scene.flatMap { selected < $0.paletteLinear.count ? $0.paletteLinear[selected] : nil }
        }
        let lines: CanvasFrame.Lines = scene?.isColoringBook == true
            ? .coloringBook(width: ColoringBookLook.widthPoints(depth: depth, weight: lineWeight.factor) * s)
            : .classic
        // Drawn as large as it paints (drags cap the radius in canvas units).
        let brush = brushPoint.map { point in
            let radius = min(Self.brushRadius, CGFloat(PaintingSession.maxBrushRadius) * camera.zoom)
            return (center: SIMD2(Float(point.x), Float(point.y)) * s, radius: Float(radius) * s)
        }
        return CanvasUniforms(CanvasFrame(
            origin: SIMD2(Float(camera.origin.x), Float(camera.origin.y)) * s, scale: Float(camera.zoom) * s, pointScale: s,
            targetSize: SIMD2(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height)),
            canvasSize: SIMD2(Float(template.width), Float(template.height)),
            palette: palette, shadowOpacity: palette.shadowOpacity,
            outlineOpacity: palette.outlineOpacity * ClassicLook.strength(depth: depth),
            outlineWidth: widthPt * s, selectedOutlineWidth: (widthPt + 0.55) * s, hatch: 1,
            numbersShown: numbersFade.value(at: time), lines: lines,
            labels: SIMD4(6.5 * s, 8.5 * s, 22 * s, 16 * s),
            numbers: SIMD4(0.5, 0.9, 0.05, reduceMotion ? 1 : 0),
            time: SIMD4(time, selectionTime, pulseStart, bumpStart),
            selection: selected.map { (color: $0, paint: paint) },
            hovered: isReplaying ? -1 : hoverRegion, pulsing: pulseRegion, bumped: bumpRegion,
            brush: brush, shine: (start: shineStart, color: shineColor),
            photoOpacity: photoFade.value(at: time), tiles: tiles))
    }

    private func numbersChanged() {
        let t = now()
        numbersFade.retarget(to: showsNumbers && !isReplaying ? 1 : 0, at: t)
        activeUntil = max(activeUntil, t + 0.3)
        requestRender()
    }

    // MARK: Source photo

    /// Opacity of the photo overlay now (tests and demos).
    var photoOpacity: Float { photoFade.value(at: now()) }

    private func photoChanged() {
        accessibilityValue = showsPhoto ? String(localized: "Showing the photo") : nil
        if showsPhoto && photoTexture == nil {
            loadPhoto()
        } else {
            fadePhoto(to: showsPhoto ? 1 : 0)
        }
    }

    /// Loads the photo once for the life of the view, at no more pixels than the canvas has
    /// units. Releasing before it arrives fades nothing in.
    private func loadPhoto() {
        guard photoTask == nil else { return }
        guard let loader = photoLoader, let context = renderer?.context else {
            // Never synchronously: this runs from `showsPhoto`'s didSet inside a SwiftUI update.
            Task { [weak self] in self?.onPhotoUnavailable?() }
            return
        }
        let size = max(template.width, template.height)
        photoTask = Task { [weak self] in
            let image = await loader(maxPixelSize: size)
            let texture = await Self.makePhotoTexture(from: image, context: context)
            guard let self else { return }
            photoTask = nil
            guard let texture else {
                Log.canvas.error("canvas: source photo unavailable")
                onPhotoUnavailable?()
                return
            }
            photoTexture = texture.value
            if showsPhoto { fadePhoto(to: 1) }
        }
    }

    @concurrent
    private static func makePhotoTexture(from image: CGImage?, context: RenderContext) async -> UncheckedSendable<any MTLTexture>? {
        guard let image, let texture = context.makePhotoTexture(image) else { return nil }
        return UncheckedSendable(texture)
    }

    /// Makes a mosaic's painted bed once, off the main thread; until it arrives the ground is the
    /// grout's colour.
    private func loadBed() {
        guard let wall, let context = renderer?.context, bedTask == nil else { return }
        bedTask = Task { [weak self] in
            let texture = await Self.makeBedTexture(wall, context: context)
            guard let self, let texture else { return }
            bedTexture = texture.value
            requestRender()
        }
    }

    @concurrent
    private static func makeBedTexture(_ wall: TileWall, context: RenderContext) async -> UncheckedSendable<any MTLTexture>? {
        guard let image = TileScene.bed(of: wall), let texture = context.makePhotoTexture(image) else { return nil }
        return UncheckedSendable(texture)
    }

    private func fadePhoto(to target: Float) {
        let t = now()
        photoFade.retarget(to: target, at: t)
        activeUntil = max(activeUntil, t + photoFade.duration + 0.05)
        requestRender()
    }

    // MARK: Replay

    /// How often the replay tells the session how much of the painting it shows
    /// (`PaintingSession.replayed`).
    private static let replayTick: Duration = .milliseconds(50)

    /// Replays the painting: the paint lifts off, then every region fills again in the order
    /// it was painted, all scheduled at once so the GPU animates it without per-frame work. The
    /// session hears how many areas are on screen meanwhile (`ReplayProgress`), so the progress
    /// badge follows the canvas.
    func replay() {
        guard let renderer, !session.progress.log.isEmpty else { return }
        replayTask?.cancel()
        // The replay ends with a finish of its own.
        cancelFinish()
        #if UNRELEASED
        endNightfall()
        #endif
        // A mosaic's grout is the ground, there before the first tile.
        let painted = session.progress.log.map { Int($0.region) }.filter { wall?.isTile($0) ?? true }
        guard !painted.isEmpty else { return }
        isReplaying = true
        // Undo and the bar's Stop follow at once, not at the replay's first tick.
        session.showReplayed(painted.count)
        numbersChanged()
        zoomToFit()
        let reduceMotion = self.reduceMotion
        let lift: Float = reduceMotion ? 0 : 0.45
        let time = now()
        for r in painted {
            renderer.update(r, .unpainting(start: time, duration: lift))
        }
        activeUntil = max(activeUntil, time + lift)
        requestRender()
        replayTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            while now() - time < lift {
                session.showReplayed(ReplayProgress.lifting(total: painted.count, elapsed: now() - time, lift: lift))
                try? await Task.sleep(for: Self.replayTick)
                guard !Task.isCancelled else { return }
            }
            session.showReplayed(0)
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            // About 7 s for a typical painting, never a slog for a large one.
            let span = min(10, max(4, Float(painted.count) * 0.02)) * fillDurationScale
            let step = span / Float(painted.count)
            let begin = now()
            for (i, r) in painted.enumerated() {
                let origin = anchors[r]
                if wall != nil {
                    renderer.update(r, Self.setting(at: begin + Float(i) * step, pace: fillDurationScale))
                    continue
                }
                renderer.update(r, RegionState(
                    origin: origin, start: begin + Float(i) * step, duration: reduceMotion ? 0 : 0.5,
                    radius: reduceMotion ? 0 : template.regions[r].bounds.farthestCorner(from: origin), painted: 1,
                    seed: RegionState.frontSeed(forRegion: r)))
            }
            if wall != nil { liftUntil = max(liftUntil, begin + span + Float(Motion.press + Motion.settle) * fillDurationScale + 0.05) }
            activeUntil = max(activeUntil, begin + span + 1.5)
            requestRender()
            while now() - begin < span + 0.4 {
                session.showReplayed(ReplayProgress.filling(total: painted.count, elapsed: now() - begin, step: step))
                try? await Task.sleep(for: Self.replayTick)
                guard !Task.isCancelled else { return }
            }
            session.showReplayed(nil)
            isReplaying = false
            numbersChanged()
            celebrate(.artworkCompleted)
        }
    }

    /// The painting screen went (`PaintCanvas.dismantleUIView`): a replay, a finish or a night
    /// still to come stops, so none plays on over the next screen (a replay ends in a finish, and
    /// night falls with a VoiceOver announcement), and their tasks let the canvas go.
    func tearDown() {
        replayTask?.cancel()
        replayTask = nil
        bedTask?.cancel()
        if isReplaying {
            isReplaying = false
            session.showReplayed(nil)
        }
        cancelFinish()
        #if UNRELEASED
        endNightfall()
        #endif
    }

    /// Stop: the replay ends where it is and the painting shows whole.
    func stopReplay() {
        if isReplaying { endReplay() }
    }

    /// Ends a replay that was stopped or that the session changed under (a fill, a restart): the
    /// canvas shows what the session holds, not the log the replay was started from.
    private func endReplay() {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        session.showReplayed(nil)
        numbersChanged()
        guard let renderer else { return }
        for (r, state) in Self.settledStates(template: template, progress: session.progress).enumerated() {
            renderer.update(r, state)
        }
        requestRender()
    }

    /// Finishing a color sweeps a gloss over it once its last fill has landed; finishing the
    /// painting flies out to all of it and sweeps the whole canvas (`finish`).
    private func celebrate(_ event: PaintEvent) {
        switch event {
        case let .colorCompleted(color):
            // The fill that finishes the painting finishes a color too: the painting's shine is
            // the one finale.
            guard !session.isComplete else { return }
            shine(color: color, after: 0.35)
        case .artworkCompleted:
            finish()
        case .strokeEnded:
            guard finishAwaitsStroke else { return }
            finishAwaitsStroke = false
            scheduleFinishFlight()
        default:
            return
        }
    }

    /// Sweeps a gloss over `color`'s paint (-1: the whole painting) `delay` seconds from now;
    /// nothing shines under Reduce Motion.
    private func shine(color: Int, after delay: Float) {
        guard !reduceMotion else { return }
        shineColor = color
        shineStart = now() + delay
        // A mosaic's light takes 2.4 s to cross the wall, 1.2 s a paint's tiles (Shaders.metal `rake`).
        let span: Float = wall == nil ? 1.1 : color < 0 ? 2.4 : 1.2
        activeUntil = max(activeUntil, shineStart + span + 0.1)
        requestRender()
    }

    /// The painting is finished (or its replay ended). Once the last fill has landed, and the
    /// stroke that painted it has ended, the camera rests a moment, then eases out to the whole
    /// painting, which shines as the camera lands; already showing about all of it, the camera
    /// stays and the shine sweeps once the fill has landed. Under Reduce Motion the camera cuts
    /// to the whole painting after the pause, so the last area is seen landing, and nothing
    /// shines.
    private func finish() {
        cancelFinish()
        guard abs(camera.zoom - 1) > Self.finishFitSlack else {
            finale(after: max(0.6, fillsLand - now()))
            return
        }
        if session.isStroking {
            finishAwaitsStroke = true
        } else {
            scheduleFinishFlight()
        }
    }

    private func scheduleFinishFlight() {
        finishTask?.cancel()
        let wait = max(0, fillsLand - now()) + Self.finishPause
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(wait)))
            guard let self, !Task.isCancelled else { return }
            finishTask = nil
            flyToFinish()
        }
    }

    /// The finish's flight, unless the painting was undone meanwhile, a replay took over or
    /// feedback's markup canvas leads the camera.
    private func flyToFinish() {
        guard session.isComplete, !isAnnotating, !isReplaying else { return }
        // A stroke begun meanwhile (it paints nothing now): the canvas is the painter's, as
        // after a pan.
        guard !session.isStroking else {
            finale(after: 0)
            return
        }
        // The fill moment's sparkles sit in view space: the flight would leave them behind.
        for sparkle in sparkleLayers { sparkle.removeAnimation(forKey: "sparkle") }
        flyToFit(duration: Self.finishFlight)
        finale(after: Float(Self.finishFlight))
    }

    private func cancelFinish() {
        finishTask?.cancel()
        finishTask = nil
        finishAwaitsStroke = false
    }

    /// A pan or pinch before the finish flew: the camera stays the painter's, and the whole
    /// painting shines at once (not under Reduce Motion).
    private func finishYieldsCamera() {
        guard finishTask != nil || finishAwaitsStroke else { return }
        cancelFinish()
        finale(after: 0)
    }

    /// The finished painting shines `delay` seconds from now; then, in SideStore and Debug builds,
    /// night falls over it (`Nightfall`).
    private func finale(after delay: Float) {
        shine(color: -1, after: delay)
        // A mosaic's finish is the light crossing it, not the night.
        guard wall == nil else { return }
        #if UNRELEASED
        // Once the shine has swept (it takes about a second); without it, a moment after the cut.
        scheduleNightfall(after: Double(delay) + (reduceMotion ? 0.4 : 1.1))
        #endif
    }

    #if UNRELEASED
    private func scheduleNightfall(after delay: Double) {
        nightfallTask?.cancel()
        nightfallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            nightfallTask = nil
            startNightfall()
        }
    }

    private func startNightfall() {
        guard session.isComplete, !isReplaying, !isAnnotating else { return }
        let painting = paintingFrame
        guard painting.width > 40, painting.height > 40 else { return }
        nightfall?.end()
        let night = Nightfall(over: painting, in: layer, sky: Sky.current(), reduceMotion: reduceMotion,
                              pace: Double(fillDurationScale))
        nightfall = night
        nightfallPeak = night.peak
        Announcer.announce(night.announcement)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(night.duration + 0.1))
            guard let self, nightfall === night else { return }
            night.remove()
            nightfall = nil
        }
    }

    /// Lifts a night still falling or about to (an undo, a replay).
    private func endNightfall() {
        nightfallTask?.cancel()
        nightfallTask = nil
        nightfall?.end()
        nightfall = nil
    }

    /// The whole painting's frame in view space.
    private var paintingFrame: CGRect {
        let a = viewPoint(forCanvas: .zero)
        let b = viewPoint(forCanvas: SIMD2(Float(template.width), Float(template.height)))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
    #endif

    private func bump(_ region: Int) {
        bumpRegion = region
        bumpStart = now()
        activeUntil = max(activeUntil, bumpStart + 1.5)
        requestRender()
    }

    // MARK: PaintingCanvas

    func session(_ session: PaintingSession, didPaint regions: [Int], from origin: SIMD2<Float>, animated: Bool) {
        if isReplaying { endReplay() }
        accessibilityChanged()
        guard let renderer else { return }
        if wall != nil {
            setTiles(regions, animated: animated, renderer: renderer)
            return
        }
        FeedbackEngine.shared.tileContacts = []
        let time = now()
        let zoom = Float(scrollView.zoomScale)
        let animate = animated && !reduceMotion
        // The fill that finishes the painting lingers.
        let finishes = session.isComplete
        let pace = (finishes ? Self.lastFillSlowdown : 1) * fillDurationScale
        var longest: Float = 0
        for r in regions {
            guard animate else {
                renderer.update(r, .settled(painted: true))
                continue
            }
            let start = paintOrigin(for: r, near: origin)
            let radius = template.regions[r].bounds.farthestCorner(from: start)
            // Bigger on screen → a little longer, so every fill reads as one smooth stroke.
            let duration = min(0.6, max(0.25, 0.2 + radius * zoom / 700)) * pace
            renderer.update(r, RegionState(
                origin: start, start: time, duration: duration, radius: radius, painted: 1,
                seed: RegionState.frontSeed(forRegion: r)))
            longest = max(longest, duration)
        }
        if animated { FeedbackEngine.shared.fillDuration = TimeInterval(longest) }
        // The finish has a shine of its own, and its flight would leave view-space sparkles behind.
        if animate, regions.count == 1, !finishes { popSparkles(at: regions[0], after: longest) }
        fillsLand = max(fillsLand, time + longest)
        activeUntil = max(activeUntil, time + longest + 0.75)
        if hoverRegion >= 0 && session.isPainted(hoverRegion) { hoverRegion = -1 }
        requestRender()
    }

    /// Tiles going in: each is pressed, settles and catches the light (`Motion`), a stroke's tiles
    /// `Motion.rowGap` apart however fast the finger went; under Reduce Motion each fades in, the
    /// shader's way. The sounds and taps hear when each touches the bed
    /// (`FeedbackEngine.tileContacts`).
    private func setTiles(_ regions: [Int], animated: Bool, renderer: CanvasRenderer) {
        let time = now(), pace = fillDurationScale
        var contacts: [TimeInterval] = []
        for r in regions {
            guard animated else {
                renderer.update(r, .settled(painted: true))
                contacts.append(0)
                continue
            }
            let start = session.isStroking ? max(time, lastSettleStart + Float(Motion.rowGap) * pace) : time
            lastSettleStart = start
            renderer.update(r, Self.setting(at: start, pace: pace))
            contacts.append(Double(start - time) + (reduceMotion ? 0 : Motion.contact * Double(pace)))
        }
        FeedbackEngine.shared.tileContacts = contacts
        let settledAt = lastSettleStart + Float(Motion.press + Motion.settle) * pace + 0.05
        if animated && !reduceMotion { liftUntil = max(liftUntil, settledAt) }
        // The finish waits for the last tile to settle, not for its light to have crossed it.
        fillsLand = max(fillsLand, animated ? settledAt : time)
        activeUntil = max(activeUntil, lastSettleStart + Float(Motion.total) * pace + 0.05)
        if hoverRegion >= 0 && session.isPainted(hoverRegion) { hoverRegion = -1 }
        requestRender()
    }

    /// A tile set at `start` (renderer clock), as the shaders animate it: `painted` with the time it
    /// began; its place's outline fades over its motion.
    private static func setting(at start: Float, pace: Float) -> RegionState {
        RegionState(origin: .zero, start: start, duration: Float(Motion.total) * pace, radius: 0, painted: 1, seed: 0)
    }

    /// Two gold sparkles pop at the region's edge (on its label's free circle, which touches the
    /// outline) as the paint lands, then fade; by Moon they are stars (`Sky`), turning with the
    /// music where its phrase begins. Not during a fast stroke, nor where the region is too small
    /// on screen for them to read.
    private func popSparkles(at region: Int, after delay: Float) {
        guard let label = template.labels(ofRegion: region).max(by: { $0.radius < $1.radius }) else { return }
        let reach = CGFloat(label.radius) * currentCamera().zoom
        let start = CACurrentMediaTime()
        guard reach >= 10, start - lastSparkles > 0.3 else { return }
        lastSparkles = start
        if sparkleLayers.isEmpty {
            sparkleLayers = (0..<4).map { _ in
                let sparkle = CAShapeLayer()
                // `Theme.gold`, spelled out: the theme is SwiftUI, this file isn't.
                sparkle.fillColor = UIColor(red: 0.788, green: 0.635, blue: 0.290, alpha: 1).cgColor
                sparkle.opacity = 0
                sparkle.zPosition = 10
                layer.addSublayer(sparkle)
                return sparkle
            }
        }
        let centre = viewPoint(forCanvas: label.position)
        let size = min(22, max(10, reach * 0.45))
        // The canvas hears of a fill before the sounds do: this is the sky its note will be in.
        let stars = FeedbackEngine.shared.skyOfComingFill() == .moon
        for (k, angle) in [-0.7, 2.3].enumerated() {
            let sparkle = sparkleLayers[nextSparkle]
            nextSparkle = (nextSparkle + 1) % sparkleLayers.count
            let side = size * (k == 0 ? 1 : 0.7)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sparkle.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            sparkle.path = stars ? Sparkle.starPath(in: sparkle.bounds) : Sparkle.cgPath(in: sparkle.bounds)
            sparkle.position = CGPoint(x: centre.x + reach * CGFloat(cos(angle)), y: centre.y + reach * CGFloat(sin(angle)))
            sparkle.opacity = 0
            CATransaction.commit()
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.2, 1.15, 0.85]
            pop.keyTimes = [0, 0.35, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.55, 1]
            let group = CAAnimationGroup()
            group.animations = [pop, fade]
            group.duration = 0.7 * Double(fillDurationScale)
            group.beginTime = start + Double(delay) * 0.8 + Double(k) * 0.08 * Double(fillDurationScale)
            group.fillMode = .backwards
            sparkle.add(group, forKey: "sparkle")
        }
    }

    func session(_ session: PaintingSession, didUnpaint regions: [Int]) {
        if isReplaying { endReplay() }
        #if UNRELEASED
        endNightfall()
        #endif
        accessibilityChanged()
        guard let renderer else { return }
        let time = now()
        for r in regions {
            renderer.update(r, reduceMotion ? .settled(painted: false) : .unpainting(start: time, duration: 0.25))
        }
        activeUntil = max(activeUntil, time + 0.3)
        requestRender()
    }

    func sessionDidChangeSelection(_ session: PaintingSession) {
        let time = now()
        hoverRegion = -1
        tourKey = nil
        if reduceMotion {
            // The hatch of the new color starts at rest instead of gliding in.
            selectionTime = time - 10
        } else {
            selectionTime = time
            activeUntil = max(activeUntil, time + 2)
        }
        if isAccessibilityPainting, let color = session.selectedColor {
            Announcer.announce(PaintSpeech.nextColor(number: color + 1, name: session.colorNames[color], nickname: session.nickname(of: color)))
        }
        accessibilityChanged()
        requestRender()
    }

    func session(_ session: PaintingSession, focusOn region: Int) {
        // Zen Mode's flight comes a moment after the fill: the painter may have taken the camera since.
        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating, !scrollView.isZooming else { return }
        // VoiceOver (and Switch Control) follow the hint to the revealed area.
        pendingFocus = .region(region)
        reveal(region: region)
    }

    /// Paint spreads from the touch; when the touch is outside the region (tolerance, drag
    /// brush), start from the region's nearest point instead.
    private func paintOrigin(for region: Int, near p: SIMD2<Float>) -> SIMD2<Float> {
        // `Int(_:)` traps on a non-finite touch.
        guard p.x.isFinite, p.y.isFinite else { return anchors[region] }
        if template.region(at: p) == region { return p }
        let map = template.regionMap
        let b = template.regions[region].bounds
        let reach = 48
        let cx = Int(p.x), cy = Int(p.y)
        let x0 = max(Int(b.minX), cx - reach), x1 = min(Int(b.maxX) - 1, cx + reach)
        let y0 = max(Int(b.minY), cy - reach), y1 = min(Int(b.maxY) - 1, cy + reach)
        var best: SIMD2<Float>?
        var bestDistance = Float.infinity
        if x0 <= x1 && y0 <= y1 {
            let target = UInt32(region)
            for y in y0...y1 {
                for x in x0...x1 where map[x, y] == target {
                    let q = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                    let d = simd_distance_squared(q, p)
                    if d < bestDistance { bestDistance = d; best = q }
                }
            }
        }
        return best ?? anchors[region]
    }

    // MARK: Gestures

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, !tapBeganWhileMoving else { return }
        let view = g.location(in: self)
        let p = canvasPoint(g.location(in: zoomView))
        let t = CACurrentMediaTime()
        if showsPhoto {
            lastTap = nil
            onDismissPhoto?()
            return
        }
        if let last = lastTap, t - last.time < 0.3, hypot(last.point.x - view.x, last.point.y - view.y) < 40, !last.painted {
            lastTap = nil
            zoomStep(at: view)
            onZoomStep?()
            return
        }
        // "Only Draw with Apple Pencil": fingers navigate (double-tap still zooms), pointers paint.
        if tapWasFinger && UIPencilInteraction.prefersPencilOnlyDrawing {
            lastTap = (t, view, false)
            return
        }
        let event = session.tap(at: p, tolerance: Float(Self.tapTolerance / scrollView.zoomScale))
        var painted = false
        switch event {
        case .painted?: painted = true
        case let .rejected(region, _)?: bump(region)
        default: break
        }
        lastTap = (t, view, painted)
    }

    @objc private func handleDragPaint(_ g: UILongPressGestureRecognizer) {
        guard !UIPencilInteraction.prefersPencilOnlyDrawing else { return }
        let p = canvasPoint(g.location(in: zoomView))
        let radius = Float(Self.brushRadius / scrollView.zoomScale)
        switch g.state {
        case .began:
            // A long press returns to painting exactly like a tap.
            if showsPhoto {
                onDismissPhoto?()
                return
            }
            // No paint on the brush (a finished painting): no brush.
            guard session.selectedColor != nil else { return }
            FeedbackEngine.shared.selectionChanged()
            brushPoint = g.location(in: self)
            dragLast = p
            session.beginStroke()
            session.drag(from: p, to: p, radius: radius)
        case .changed:
            guard let last = dragLast else { return }
            brushPoint = g.location(in: self)
            session.drag(from: last, to: p, radius: radius)
            dragLast = p
        default:
            brushPoint = nil
            dragLast = nil
            session.endStroke()
        }
        requestRender()
    }

    /// `OneFinger.lays`: one finger laying a row from where it first touched.
    @objc private func handleLay(_ g: UIPanGestureRecognizer) {
        let location = g.location(in: zoomView)
        let p = canvasPoint(location)
        let radius = Float(Self.brushRadius / scrollView.zoomScale)
        switch g.state {
        case .began:
            if showsPhoto {
                onDismissPhoto?()
                return
            }
            guard session.selectedColor != nil else { return }
            let moved = g.translation(in: zoomView)
            let first = canvasPoint(CGPoint(x: location.x - moved.x, y: location.y - moved.y))
            dragLast = p
            session.beginStroke()
            session.drag(from: first, to: p, radius: radius)
        case .changed:
            guard let last = dragLast else { return }
            session.drag(from: last, to: p, radius: radius)
            dragLast = p
        default:
            guard dragLast != nil else { return }
            dragLast = nil
            session.endStroke()
        }
    }

    @objc private func handlePencil(_ g: UILongPressGestureRecognizer) {
        let p = canvasPoint(g.location(in: zoomView))
        switch g.state {
        case .began:
            if showsPhoto {
                onDismissPhoto?()
                return
            }
            dragLast = p
            session.beginStroke()
            if case let .rejected(region, _)? = session.tap(at: p, tolerance: Float(6 / scrollView.zoomScale)) {
                bump(region)
            }
        case .changed:
            guard let last = dragLast else { return }
            session.drag(from: last, to: p, radius: Float(4 / scrollView.zoomScale))
            dragLast = p
        default:
            // At the stroke's end, so nothing it triggers (a tip) lands mid-stroke.
            if dragLast != nil { onPencilAction?(.lifted) }
            dragLast = nil
            session.endStroke()
        }
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        var region = -1
        if g.state == .began || g.state == .changed {
            let p = canvasPoint(g.location(in: zoomView))
            if let r = template.region(at: p), !session.isPainted(r), session.colorOf(r) == session.selectedColor {
                region = r
            }
        }
        if region != hoverRegion {
            hoverRegion = region
            requestRender()
        }
    }

    // MARK: Accessibility

    /// UIKit reads the whole array at once, so a rebuild between reads can't mismatch a count
    /// and an element lookup.
    override var accessibilityElements: [Any]? {
        get { accessibleElements() }
        set {}
    }

    private func accessibleElements() -> [NSObject] {
        #if DEBUG
        // Read live: the camera and animation clock can change without a session event.
        if ProcessInfo.processInfo.arguments.contains("-playHarness") { return playHarnessElements() }
        #endif
        if let accessibleItems { return accessibleItems }
        let items = buildAccessibleElements()
        accessibleItems = items
        return items
    }

    #if DEBUG
    /// Wire-only elements for `PlayTests`: region IDs are one-based, paint numbers are the
    /// palette index + 1. Frames use the same primary label anchor as the renderer.
    private func playHarnessElements() -> [NSObject] {
        func element(_ identifier: String, value: String, frame: CGRect) -> UIAccessibilityElement {
            let item = playElements[identifier] ?? UIAccessibilityElement(accessibilityContainer: self)
            playElements[identifier] = item
            item.accessibilityIdentifier = identifier
            item.accessibilityLabel = identifier
            item.accessibilityValue = value
            item.accessibilityFrameInContainerSpace = frame
            return item
        }
        let state: [String: Any] = [
            "screen": isAnnotating ? "feedback" : "painting",
            "selected_paint": session.selectedColor.map { $0 + 1 } as Any? ?? NSNull(),
            "filled_areas": template.regions.indices.filter { session.isPainted($0) }.map { $0 + 1 },
            "area_count": template.regions.count,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys)) ?? Data()
        let settled = laidOutSize != .zero && !needsRender && now() >= activeUntil
            && cameraAnimation == nil && finishTask == nil && !finishAwaitsStroke
            && !scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating
            && !scrollView.isZooming && !scrollView.isZoomBouncing
            && (zoomView.layer.animationKeys()?.isEmpty ?? true)
            && (scrollView.layer.animationKeys()?.isEmpty ?? true)
            && !session.isStroking && !isReplaying && photoTask == nil
        var items: [NSObject] = [
            element("play-state", value: String(decoding: json, as: UTF8.self), frame: bounds),
            element("play-settled", value: settled ? "1" : "0", frame: bounds),
            element("play-screen-scale", value: String(Double(contentScaleFactor)), frame: bounds),
        ]
        if !isAnnotating {
            items += template.regions.indices.map { region in
                let point = viewPoint(forCanvas: anchors[region])
                let item = element(
                    "area-\(region + 1)", value: String(session.colorOf(region) + 1),
                    frame: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                item.accessibilityTraits = .button
                return item
            }
        }
        return items
    }
    #endif

    /// The unpainted areas of the selected color whose numbers are in view (at most
    /// `CanvasAccessibility.limit`, nearest the middle, in reading order), or one placeholder
    /// that says why there are none and carries the actions.
    private func buildAccessibleElements() -> [NSObject] {
        let area = bounds.inset(by: chromeInsets)
        guard let color = session.selectedColor, area.width >= 44, area.height >= 44 else {
            areaElements = [:]
            return [configuredPlaceholder(frame: area.isEmpty ? bounds : area)]
        }
        let camera = currentCamera()
        // Numbers at least half a touch target inside the area, so every frame stays whole.
        let inner = area.insetBy(dx: 22, dy: 22)
        let a = canvasPoint(forView: inner.origin)
        let b = canvasPoint(forView: CGPoint(x: inner.maxX, y: inner.maxY))
        let visible = CGRect(x: CGFloat(a.x), y: CGFloat(a.y), width: CGFloat(b.x - a.x), height: CGFloat(b.y - a.y))
        let regions = CanvasAccessibility.visibleAreas(
            unpaintedOfSelectedColor(), anchors: anchors, visible: visible, center: visibleCenter, rowHeight: Float(44 / camera.zoom))
        guard !regions.isEmpty else {
            areaElements = [:]
            return [configuredPlaceholder(frame: area)]
        }
        let number = color + 1
        let hint = PaintSpeech.areaHint(number: number, name: session.colorNames[color], nickname: session.nickname(of: color))
        var elements: [Int: CanvasAreaElement] = [:]
        let items = regions.map { r -> CanvasAreaElement in
            let element = areaElements[r] ?? CanvasAreaElement(region: r, container: self)
            element.accessibilityLabel = PaintSpeech.areaLabel(number: number)
            element.accessibilityValue = PaintSpeech.areaValue(
                CanvasPosition(anchors[r], width: template.width, height: template.height))
            element.accessibilityHint = hint
            element.accessibilityTraits = .button
            element.accessibilityIdentifier = "canvas-area-\(r)"
            element.accessibilityFrameInContainerSpace = areaFrame(r, zoom: camera.zoom, in: area)
            element.accessibilityCustomActions = accessibilityActionList
            element.accessibilityCustomRotors = [areasRotor]
            elements[r] = element
            return element
        }
        areaElements = elements
        return items
    }

    /// A square around the area's number, as big as the number's free space (44–160 pt), cut
    /// symmetrically to the chrome-free area so it stays centred on the number: a tap at its
    /// centre paints the area.
    private func areaFrame(_ region: Int, zoom: CGFloat, in area: CGRect) -> CGRect {
        let c = viewPoint(forCanvas: anchors[region])
        let half = min(max(CGFloat(labelRadii[region]) * zoom, 22), 80)
        let hx = min(half, c.x - area.minX, area.maxX - c.x)
        let hy = min(half, c.y - area.minY, area.maxY - c.y)
        return CGRect(x: c.x - hx, y: c.y - hy, width: 2 * hx, height: 2 * hy)
    }

    private func configuredPlaceholder(frame: CGRect) -> UIAccessibilityElement {
        let element = placeholder
        element.accessibilityLabel = PaintSpeech.canvasLabel
        if session.isComplete {
            element.accessibilityValue = PaintSpeech.finished
        } else if let color = session.selectedColor {
            element.accessibilityValue = PaintSpeech.noAreasInView(number: color + 1, name: session.colorNames[color], nickname: session.nickname(of: color))
        } else {
            element.accessibilityValue = ""
        }
        element.accessibilityHint = session.isComplete ? nil : PaintSpeech.canvasHint
        element.accessibilityIdentifier = "canvas-placeholder"
        element.accessibilityFrameInContainerSpace = frame
        element.accessibilityCustomActions = accessibilityActionList
        element.accessibilityCustomRotors = [areasRotor]
        return element
    }

    /// Marks the elements stale and, unless VoiceOver is painting (that path focuses itself),
    /// tells VoiceOver or Switch Control that the layout changed.
    private func accessibilityChanged(post: Bool = true) {
        accessibleItems = nil
        guard post, !isAccessibilityPainting else { return }
        postLayoutChanged(nil)
    }

    private func postLayoutChanged(_ focus: Any?) {
        guard UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning else { return }
        UIAccessibility.post(notification: .layoutChanged, argument: focus)
    }

    /// The camera came to rest: rebuild, and focus what a hint or an action asked for.
    private func cameraDidSettle() {
        accessibleItems = nil
        let focus: NSObject?
        switch pendingFocus {
        case let .region(region)?:
            let items = accessibleElements()
            focus = areaElements[region] ?? items.first
        case .first?:
            focus = accessibleElements().first
        case nil:
            focus = nil
        }
        pendingFocus = nil
        postLayoutChanged(focus)
    }

    private func unpaintedOfSelectedColor() -> [Int] {
        guard let color = session.selectedColor else { return [] }
        return regionsByColor[color].filter { !session.isPainted($0) }
    }

    /// Whether a region's number is where VoiceOver would offer it (inside the chrome-free area).
    private func isInView(_ region: Int) -> Bool {
        let area = bounds.inset(by: chromeInsets).insetBy(dx: 22, dy: 22)
        return !area.isEmpty && area.contains(viewPoint(forCanvas: anchors[region]))
    }

    /// Paints an area for VoiceOver or Switch Control the way a tap on its number would, then
    /// moves focus to the area that took its place in the list.
    func paintForAccessibility(_ region: Int) -> Bool {
        guard let color = session.selectedColor, session.colorOf(region) == color, !session.isPainted(region) else {
            return false
        }
        let before = accessibleElements()
        let index = before.firstIndex { ($0 as? CanvasAreaElement)?.region == region }
        isAccessibilityPainting = true
        defer { isAccessibilityPainting = false }
        let anchor = anchors[region]
        // A region without a label is anchored at its bounds centre, which may lie in a
        // neighbour; paint it directly then rather than letting the tap pick the neighbour.
        if template.region(at: anchor) == region {
            session.tap(at: anchor, tolerance: Float(Self.tapTolerance / scrollView.zoomScale))
        }
        if !session.isPainted(region) {
            session.paint([region], from: anchor, animated: true)
        }
        guard session.isPainted(region) else { return false }
        // A camera flight in progress (Paint next area) focuses once it lands.
        if cameraAnimation == nil {
            let items = accessibleElements()
            let next = items.isEmpty ? nil : items[min(index ?? 0, items.count - 1)]
            postLayoutChanged(next)
        }
        let remaining = session.remainingByColor[color]
        if remaining > 0 { Announcer.announce(PaintSpeech.painted(remaining: remaining)) }
        return true
    }

    /// VoiceOver's three-finger swipes page through the painting (the container hides the
    /// scroll view that would otherwise take them). A page is the band in which areas are
    /// offered, so numbers just past its edge are offered on the next one; focus lands on the
    /// first area there. False at the edges, so VoiceOver plays its boundary sound.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let area = bounds.inset(by: chromeInsets)
        let inner = area.insetBy(dx: 22, dy: 22)
        guard !inner.isEmpty, let step = CanvasAccessibility.pageStep(direction, page: inner.size) else { return false }
        // From where a camera flight is heading, so quick swipes add up.
        let zoom = cameraAnimation?.toZoom ?? scrollView.zoomScale
        let from = cameraAnimation?.toOffset ?? scrollView.contentOffset
        let to = clampedOffset(CGPoint(x: from.x + step.dx, y: from.y + step.dy), zoom: zoom)
        guard hypot(to.x - from.x, to.y - from.y) >= 1 else { return false }
        // View point = zoomed canvas point − content offset.
        let middle = SIMD2(Float((to.x + area.midX) / zoom), Float((to.y + area.midY) / zoom))
        UIAccessibility.post(
            notification: .pageScrolled,
            argument: PaintSpeech.pageScrolled(CanvasPosition(middle, width: template.width, height: template.height)))
        pendingFocus = .first
        animateCamera(zoom: zoom, offset: to, duration: 0.3)
        return true
    }

    private lazy var accessibilityActionList: [UIAccessibilityCustomAction] = [
        UIAccessibilityCustomAction(
            name: String(localized: "paint.action.paintNext", defaultValue: "Paint next area",
                         comment: "VoiceOver action: paint the unpainted area nearest the middle of the view")
        ) { [weak self] _ in
            guard let self, let target = CanvasAccessibility.nearest(
                self.unpaintedOfSelectedColor(), anchors: self.anchors, to: self.visibleCenter) else { return false }
            if !isInView(target) {
                pendingFocus = .first
                reveal(region: target)
            }
            return paintForAccessibility(target)
        },
        UIAccessibilityCustomAction(
            name: String(localized: "paint.action.zoomNext", defaultValue: "Zoom to next area",
                         comment: "VoiceOver action: move the view to the next unpainted area, in reading order")
        ) { [weak self] _ in
            guard let self else { return false }
            let rowHeight = Float(template.height) / 12
            guard let next = CanvasAccessibility.next(
                after: tourKey, in: unpaintedOfSelectedColor(), anchors: anchors, rowHeight: rowHeight) else { return false }
            tourKey = CanvasAccessibility.key(next, anchor: anchors[next], rowHeight: rowHeight)
            pendingFocus = .region(next)
            reveal(region: next)
            return true
        },
        UIAccessibilityCustomAction(
            name: String(localized: "paint.action.hint", defaultValue: "Hint",
                         comment: "VoiceOver action: show an unpainted area of the selected color near the view")
        ) { [weak self] _ in
            guard let self, !self.unpaintedOfSelectedColor().isEmpty else { return false }
            showHint()
            return true
        },
        UIAccessibilityCustomAction(
            name: String(localized: "paint.action.zoomToFit", defaultValue: "Zoom to fit",
                         comment: "VoiceOver action: show the whole painting")
        ) { [weak self] _ in
            guard let self else { return false }
            pendingFocus = .first
            zoomToFit()
            return true
        },
    ]

    private lazy var areasRotor: UIAccessibilityCustomRotor = UIAccessibilityCustomRotor(
        name: String(localized: "paint.rotor.unpaintedAreas", defaultValue: "Unpainted areas",
                     comment: "VoiceOver rotor that moves between the unpainted areas in view")
    ) { [weak self] predicate in
        guard let self else { return nil }
        let items = accessibleElements().compactMap { $0 as? CanvasAreaElement }
        let current = predicate.currentItem.targetElement as? CanvasAreaElement
        let i = items.firstIndex { $0 === current }
        let j = predicate.searchDirection == .next ? (i.map { $0 + 1 } ?? 0) : (i.map { $0 - 1 } ?? items.count - 1)
        guard items.indices.contains(j) else { return nil }
        return UIAccessibilityCustomRotorItemResult(targetElement: items[j], targetRange: nil)
    }
}

// MARK: - Delegates

extension CanvasView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        accessibilityChanged(post: false)
        requestRender()
        #if UNRELEASED
        nightfall?.follow(paintingFrame)
        #endif
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if !isApplyingCamera { scrollView.contentInset = insets(forZoom: scrollView.zoomScale) }
        accessibilityChanged(post: false)
        requestRender()
        #if UNRELEASED
        nightfall?.follow(paintingFrame)
        #endif
        onZoomChange?(relativeZoom)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cameraAnimation = nil
        pendingFocus = nil
        finishYieldsCamera()
        onHandChange?(true)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        cameraAnimation = nil
        pendingFocus = nil
        finishYieldsCamera()
        onHandChange?(true)
        onZoomStep?()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            cameraDidSettle()
            onHandChange?(false)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        cameraDidSettle()
        onHandChange?(false)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        cameraDidSettle()
        onHandChange?(false)
    }
}

extension CanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === tapRecognizer {
            // A tap that stops a fling only stops it. One during a camera flight (the hint's, Zen
            // Mode's) lands the flight where it is and paints: the painter is reaching for the
            // area it flies to, and the flight would otherwise eat taps for half a second.
            tapBeganWhileMoving = scrollView.isDecelerating
            tapWasFinger = touch.type == .direct
            cameraAnimation = nil
        }
        return true
    }
}

extension CanvasView: UIPencilInteractionDelegate {
    // Honour the Apple Pencil settings: either gesture may be turned off there.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilAction?(.tap)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        onPencilAction?(.squeeze)
    }
}

/// Breaks the display link → view retain cycle.
private final class DisplayLinkTarget: NSObject {
    weak var view: CanvasView?

    init(_ view: CanvasView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}
