import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import PencilKit
import UIKit

/// Feedback being given on a painting (feedback mode): what was captured, the ink drawn over
/// it, the note, a comment per mark and whether the painter's photo goes along. Lives while
/// the mode lasts; `PaintView` owns it, `MarkupCanvas` feeds it the ink and `FeedbackSheet`
/// sends it.
@Observable
final class FeedbackDraft {
    let capture: FeedbackCapture
    var note = ""
    /// By mark (`FeedbackMark.id`): what the painter wrote about it.
    var comments: [Date: String] = [:]
    /// Whether the painter's own photo goes along: never unless they say so.
    var includesPhoto = false
    /// What the markup canvas draws with (`FeedbackTools`).
    var tool = FeedbackTool.pen
    var penColor = FeedbackInkColor.red
    /// The review and send sheet is up (over the markup canvas).
    var isReviewing = false
    /// Sent or shared: feedback mode is ending.
    var isSent = false
    private(set) var hasInk = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// The ink grouped into marks when the review began, in the order they were begun.
    private(set) var marks: [FeedbackMark] = []
    private(set) var strokes: [FeedbackStroke] = []
    /// The review sheet's pictures: the whole painting with its marks, and each mark close up.
    private(set) var overview: FeedbackPicture?
    private(set) var closeUps: [Date: FeedbackPicture] = [:]

    /// The ink in canvas units (`MarkupCanvas` keeps it current).
    @ObservationIgnored private(set) var drawing = PKDrawing()
    /// The zoom (points per canvas unit) each stroke was drawn at, by its path's creation date.
    @ObservationIgnored private var strokeZooms: [Date: CGFloat] = [:]
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The strokes the review sheet's pictures show.
    @ObservationIgnored private var picturesFor: [FeedbackStroke]?

    init(capture: FeedbackCapture) {
        self.capture = capture
    }

    /// Whether leaving would lose anything.
    var isEmpty: Bool { !hasInk && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The painter's own photo can go along (a library picture is named instead).
    var canIncludePhoto: Bool { capture.source?.photo != nil }

    // MARK: Ink

    /// The ink changed: new strokes were drawn at `zoom` points per canvas unit, and undo
    /// through `undoManager` (when given).
    func drawingChanged(_ drawing: PKDrawing, zoom: CGFloat, undoManager: UndoManager?) {
        self.drawing = drawing
        if let undoManager { self.undoManager = undoManager }
        for stroke in drawing.strokes where strokeZooms[stroke.path.creationDate] == nil {
            strokeZooms[stroke.path.creationDate] = zoom
        }
        let ink = !drawing.strokes.isEmpty
        if hasInk != ink { hasInk = ink }
        undoChanged()
        Log.feedback.info("Ink: \(drawing.strokes.count, privacy: .public) strokes; undo \(self.canUndo, privacy: .public), redo \(self.canRedo, privacy: .public)")
        // PencilKit may register a stroke's undo after telling of it.
        Task { self.undoChanged() }
    }

    func undo() {
        undoManager?.undo()
        undoChanged()
    }

    func redo() {
        undoManager?.redo()
        undoChanged()
    }

    func undoChanged() {
        let undo = undoManager?.canUndo ?? false, redo = undoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }

    // MARK: Review

    /// Groups the ink into marks and draws their pictures in the background (the review sheet
    /// shows them as they come). Comments stay with their marks, which keep the id of the
    /// stroke that began them.
    func prepareReview() {
        strokes = FeedbackInk.strokes(of: drawing, zooms: strokeZooms)
        marks = FeedbackMarks.group(strokes)
        Log.feedback.notice("Review: \(self.strokes.count, privacy: .public) strokes in \(self.marks.count, privacy: .public) marks")
        drawPictures()
    }

    /// The review sheet's pictures, small, drawn in the background: the whole painting and each
    /// mark close up, with the ink over them.
    private func drawPictures() {
        guard picturesFor != strokes || overview == nil else { return }
        picturesFor = strokes
        let shown = strokes
        let canvas = capture.canvasRect
        let overviewFrame = FeedbackPackage.Frame(rect: canvas, scale: 960 / max(canvas.width, canvas.height, 1))
        let frames = marks.map { mark -> FeedbackPackage.Frame in
            var frame = FeedbackPackage.Layout.closeUp(of: mark, strokes: strokes)
            frame.scale = 240 / max(frame.rect.width, frame.rect.height, 1)
            return frame
        }
        let ids = marks.map(\.id)
        let capture = self.capture, drawing = self.drawing
        Task {
            let pictures = await Self.pictures(capture, ink: drawing, frames: [overviewFrame] + frames)
            guard picturesFor == shown else { return }
            overview = pictures.first.flatMap { $0 }
            var byMark: [Date: FeedbackPicture] = [:]
            for (index, id) in ids.enumerated() {
                if let picture = pictures[index + 1] { byMark[id] = picture }
            }
            closeUps = byMark
        }
    }

    /// The painting in each frame with `ink` over it.
    @concurrent
    private static func pictures(
        _ capture: FeedbackCapture, ink: PKDrawing, frames: [FeedbackPackage.Frame]
    ) async -> [FeedbackPicture?] {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: capture.template, context: context) else {
            return frames.map { _ in nil }
        }
        let painted = (0..<capture.template.regions.count).map { capture.progress.isPainted($0) }
        var options = CanvasSnapshot.Options(outlines: true, numbers: capture.showsNumbers)
        options.palette = capture.palette
        options.lineWeight = capture.lineWeight
        return frames.map { frame in
            CanvasSnapshot.render(
                scene: scene, painted: painted, size: frame.pixelSize, options: options, context: context, rect: frame.rect
            ).map { FeedbackPicture(painting: $0, ink: FeedbackInk.image(of: ink, rect: frame.rect, scale: frame.scale)) }
        }
    }

    // MARK: Sending

    /// Writes the bundle (`FeedbackPackage`) and returns its files.
    func package() async throws -> FeedbackPackage.Files {
        if strokes.isEmpty && hasInk { prepareReview() }
        let layout = FeedbackPackage.Layout(capture: capture, marks: marks, strokes: strokes)
        let ink = await Self.ink(drawing, over: layout)
        var photo: Data?
        if includesPhoto, let load = capture.source?.photo {
            photo = await load()
            if photo == nil { Log.feedback.error("The photo couldn't be read: the feedback goes without it") }
        }
        let contents = FeedbackPackage.Contents(
            capture: capture, note: note, strokes: strokes, marks: marks, comments: comments, photo: photo,
            layout: layout, ink: ink)
        return try await FeedbackPackage.write(contents)
    }

    /// `drawing` over each of `layout`'s frames.
    @concurrent
    private static func ink(_ drawing: PKDrawing, over layout: FeedbackPackage.Layout) async -> FeedbackPackage.Ink {
        func image(_ frame: FeedbackPackage.Frame) -> CGImage? {
            FeedbackInk.image(of: drawing, rect: frame.rect, scale: frame.scale)
        }
        return FeedbackPackage.Ink(
            overview: drawing.strokes.isEmpty ? nil : image(layout.overview), view: image(layout.view),
            marks: layout.marks.map(image))
    }
}

/// A painting picture with the ink over it, as two layers (the review sheet stacks them).
nonisolated struct FeedbackPicture: Sendable {
    var painting: CGImage
    var ink: CGImage?
}
