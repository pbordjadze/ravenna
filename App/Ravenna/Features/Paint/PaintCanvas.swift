import PaintCore
import SwiftUI
import UIKit

/// Lets SwiftUI chrome and commands drive the live canvas (hints, zoom), and feedback's
/// markup canvas take over its camera.
final class CanvasController {
    fileprivate weak var view: CanvasView?

    func showHint() { view?.showHint() }
    func zoomToFit() { view?.zoomToFit() }
    func zoom(by factor: CGFloat) { view?.zoom(by: factor) }
    func replay() { view?.replay() }
    /// The painting shows whole again at once.
    func stopReplay() { view?.stopReplay() }
    /// Where the template is in the canvas (the canvas's own coordinates), and whether the first
    /// frame has been on screen (`PaintCanvas.watchesFirstFrame`): the start of a painting is handed
    /// over to the canvas (`StartHandoff`).
    var templateFrame: CGRect? { view?.templateFrame }
    var isShowingFirstFrame: Bool { view?.hasShownFirstFrame ?? false }
    /// Makes the canvas first responder again (the window's undo history of fills, ⌘Z).
    func focus() { _ = view?.becomeFirstResponder() }
    /// Lets go of first responder, so ⌘Z and three-finger undo take back no fills meanwhile.
    func releaseFocus() { _ = view?.resignFirstResponder() }

    // Feedback (see `CanvasView`'s camera of another scroll view).
    var scrollCamera: CanvasView.ScrollCamera? { view?.scrollCamera }
    func contentInsets(forZoom zoom: CGFloat) -> UIEdgeInsets { view?.contentInsets(forZoom: zoom) ?? .zero }
    func follow(zoom: CGFloat, offset: CGPoint) { view?.follow(zoom: zoom, offset: offset) }
    var visibleCanvasRect: CGRect? { view?.visibleCanvasRect }
    var pointsPerUnit: CGFloat? { view?.pointsPerUnit }
    var relativeZoom: CGFloat? { view?.relativeZoom }
}

/// SwiftUI host of the Metal canvas.
struct PaintCanvas: UIViewRepresentable {
    let session: PaintingSession
    let controller: CanvasController
    /// Space taken by floating chrome, in the canvas's own (full-screen) coordinates.
    var chromeInsets = EdgeInsets()
    var showsNumbers = true
    var paperAppearance = PaperAppearance.default
    /// How heavy a coloring book's drawing is (Settings › Line Weight); classic templates ignore it.
    var lineWeight = LineWeight.default
    var initialCamera: CanvasCamera?
    var fillDurationScale: Float = 1
    var onPencilAction: ((PencilAction) -> Void)?
    /// Called (after this update) when the device can't draw the canvas.
    var onUnavailable: (() -> Void)?
    var photoLoader: SourcePhotoLoader?
    var showsPhoto = false
    var onPhotoUnavailable: (() -> Void)?
    var onDismissPhoto: (() -> Void)?
    var onZoomStep: (() -> Void)?
    /// A finger took hold of the page to move or zoom it (true), or let go (false).
    var onHandChange: ((Bool) -> Void)?
    /// Feedback mode: the markup canvas over this one has the touches and the camera.
    var isAnnotating = false
    /// The canvas notes when its first frame is on screen (`CanvasController.isShowingFirstFrame`).
    /// Read when the view is made.
    var watchesFirstFrame = false

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(session: session)
        view.watchesFirstFrame = watchesFirstFrame
        view.initialCamera = initialCamera
        view.fillDurationScale = fillDurationScale
        view.photoLoader = photoLoader
        view.reduceMotion = context.environment.accessibilityReduceMotion
        view.paperAppearance = paperAppearance
        view.lineWeight = lineWeight
        controller.view = view
        // Deferred: state mustn't change while SwiftUI is making views.
        if !view.isRenderable, let onUnavailable { Task { onUnavailable() } }
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        let rtl = context.environment.layoutDirection == .rightToLeft
        view.chromeInsets = UIEdgeInsets(
            top: chromeInsets.top, left: rtl ? chromeInsets.trailing : chromeInsets.leading,
            bottom: chromeInsets.bottom, right: rtl ? chromeInsets.leading : chromeInsets.trailing)
        view.showsNumbers = showsNumbers
        view.reduceMotion = context.environment.accessibilityReduceMotion
        view.paperAppearance = paperAppearance
        view.lineWeight = lineWeight
        view.onPencilAction = onPencilAction
        // Loader and callbacks first: showing the photo may start loading it.
        view.photoLoader = photoLoader
        view.onPhotoUnavailable = onPhotoUnavailable
        view.onDismissPhoto = onDismissPhoto
        view.onZoomStep = onZoomStep
        view.onHandChange = onHandChange
        view.showsPhoto = showsPhoto
        view.isAnnotating = isAnnotating
        controller.view = view
    }

    static func dismantleUIView(_ view: CanvasView, coordinator: Coordinator) {
        view.tearDown()
    }
}

/// Stands in for the canvas when the device can't draw it (Metal unavailable), instead of a
/// blank screen.
struct CanvasUnavailableView: View {
    var onClose: (() -> Void)?

    var body: some View {
        // `SwiftUI.Label`: PaintCore has a `Label` too.
        ContentUnavailableView {
            SwiftUI.Label("Can’t Show the Canvas", systemImage: "exclamationmark.triangle")
        } description: {
            Text("This device can’t draw the painting right now. Your progress is saved.")
                .readableDescription()
        } actions: {
            if let onClose {
                Button("Back to Gallery", action: onClose)
                    .buttonStyle(.glass)
            }
        }
    }
}
