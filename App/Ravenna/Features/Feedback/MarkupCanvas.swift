import PencilKit
import SwiftUI
import UIKit

/// Feedback mode's drawing surface: a transparent PencilKit canvas over the painting that
/// takes every touch. A finger or the Pencil draws with the tool `FeedbackTools` picked (only
/// the Pencil under "Only Draw with Apple Pencil", as when painting); two fingers pan and
/// pinch. Its scroll view leads the camera, set up with the painting canvas's zoom limits and
/// insets, and the Metal canvas under it follows (`CanvasController.follow`), so the ink is
/// drawn in canvas units over a painting that stays sharp at every zoom. Ink keeps the colors
/// picked in either appearance, and marks have an undo history of their own: the bar's Undo
/// takes back marks, never paint. The canvas never becomes first responder (see
/// `FeedbackTools`).
struct MarkupCanvas: UIViewRepresentable {
    let draft: FeedbackDraft
    let controller: CanvasController
    /// The painting's size in canvas units.
    let canvasSize: CGSize
    var isMarking = true
    var tool = FeedbackTool.pen
    var penColor = FeedbackInkColor.red

    func makeUIView(context: Context) -> MarkupCanvasView {
        MarkupCanvasView(draft: draft, controller: controller, canvasSize: canvasSize)
    }

    func updateUIView(_ view: MarkupCanvasView, context: Context) {
        view.isMarking = isMarking
        view.use(tool, penColor: penColor)
    }
}

final class MarkupCanvasView: PKCanvasView {
    var isMarking = true {
        didSet { if isMarking != oldValue { markingChanged() } }
    }

    private let draft: FeedbackDraft
    private let controller: CanvasController
    private let canvasSize: CGSize
    private let marks: UndoManager
    /// The canvas's delegate: a separate object, so no method here stands in for one of
    /// PencilKit's own scroll view callbacks.
    private let events: Events
    private var laidOutSize: CGSize = .zero
    /// True while this canvas takes the painting canvas's camera (no echo back to it).
    private var isTakingCamera = false
    private var inUse: (FeedbackTool, FeedbackInkColor)?

    init(draft: FeedbackDraft, controller: CanvasController, canvasSize: CGSize) {
        self.draft = draft
        self.controller = controller
        self.canvasSize = canvasSize
        marks = UndoManager()
        events = Events()
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        // PencilKit lightens dark ink in dark mode; marks keep the colors picked.
        overrideUserInterfaceStyle = .light
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = true
        // The painting canvas clamps its zoom, so a bounce past the limits would part the two.
        bouncesZoom = false
        scrollsToTop = false
        drawing = draft.drawing
        events.view = self
        delegate = events
        draft.undoManager = marks
        use(draft.tool, penColor: draft.penColor)
        markingChanged()
        isAccessibilityElement = true
        // Without it VoiceOver takes the touches, and the hint's promise to draw couldn't be kept.
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = String(localized: "feedback.canvas.label", defaultValue: "Painting",
                                    comment: "VoiceOver label of the painting while feedback is being drawn on it")
        accessibilityHint = String(localized: "feedback.canvas.hint",
                                   defaultValue: "Draw on the painting to show what your feedback is about. Two fingers move and zoom.",
                                   comment: "VoiceOver hint of the painting while feedback is being drawn on it")
        accessibilityIdentifier = "feedback-canvas"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Marks undo apart from the window's history, which holds the painting's fills.
    override var undoManager: UndoManager? { marks }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1, bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        // After the painting canvas has laid itself out for this size (it keeps looking at
        // the same place across rotation).
        Task { self.takeCanvasCamera() }
    }

    /// Draws with `tool` from now on: the pen in `penColor`, the yellow highlighter, or the
    /// eraser that takes whole strokes.
    func use(_ tool: FeedbackTool, penColor: FeedbackInkColor) {
        if let inUse, inUse == (tool, penColor) { return }
        inUse = (tool, penColor)
        switch tool {
        case .pen: self.tool = PKInkingTool(.pen, color: penColor.uiColor)
        case .highlighter: self.tool = PKInkingTool(.marker, color: .systemYellow)
        case .eraser: self.tool = PKEraserTool(.vector)
        }
    }

    private func markingChanged() {
        // Under the review sheet, out of the accessibility tree. It keeps taking touches, which
        // would otherwise reach the painting under it.
        accessibilityElementsHidden = !isMarking
        // A finger draws unless the painter draws only with the Pencil, as when painting.
        if isMarking { drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing ? .pencilOnly : .anyInput }
    }

    // MARK: Camera

    /// Starts from where the painting canvas looks, with its zoom limits and insets.
    private func takeCanvasCamera() {
        guard let camera = controller.scrollCamera else { return }
        isTakingCamera = true
        defer { isTakingCamera = false }
        minimumZoomScale = camera.zoomRange.lowerBound
        maximumZoomScale = camera.zoomRange.upperBound
        zoomScale = camera.zoom
        contentSize = zoomedCanvasSize
        contentInset = controller.contentInsets(forZoom: camera.zoom)
        contentOffset = camera.offset
    }

    private var zoomedCanvasSize: CGSize {
        CGSize(width: canvasSize.width * zoomScale, height: canvasSize.height * zoomScale)
    }

    fileprivate func zoomed() {
        guard !isTakingCamera else { return }
        let size = zoomedCanvasSize
        if abs(contentSize.width - size.width) > 0.5 || abs(contentSize.height - size.height) > 0.5 { contentSize = size }
        contentInset = controller.contentInsets(forZoom: zoomScale)
        leadCanvas()
    }

    fileprivate func leadCanvas() {
        guard !isTakingCamera else { return }
        controller.follow(zoom: zoomScale, offset: contentOffset)
    }

    // MARK: Drawing

    fileprivate func drawingChanged() {
        draft.drawingChanged(drawing, zoom: zoomScale, undoManager: marks)
    }

    private final class Events: NSObject, PKCanvasViewDelegate {
        weak var view: MarkupCanvasView?

        func scrollViewDidScroll(_ scrollView: UIScrollView) { view?.leadCanvas() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { view?.zoomed() }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { view?.drawingChanged() }
    }
}
