import CoreGraphics
import Foundation
import PaintCore

/// Writes a piece of feedback as the bundle `FeedbackReport` describes, in its own export
/// folder (`ArtworkExporter`), zipped, beside the painting-with-marks picture (which goes with
/// the zip, so a message shows it without unzipping) and the report as text (`feedback.md`
/// again, for `FeedbackUploader`, which sends the three). Rendering and writing run off the
/// main actor; the ink comes in drawn (PencilKit draws it, `FeedbackInk`) over the frames of
/// the same `Layout`.
nonisolated enum FeedbackPackage {
    /// The part of the canvas a picture shows (canvas units) and its pixels per canvas unit.
    nonisolated struct Frame: Sendable, Equatable {
        var rect: CGRect
        var scale: CGFloat

        var pixelSize: CGSize {
            CGSize(width: max(1, (rect.width * scale).rounded()), height: max(1, (rect.height * scale).rounded()))
        }
    }

    /// Where the bundle's pictures look: the whole painting, what was on screen, and each
    /// mark close up.
    nonisolated struct Layout: Sendable, Equatable {
        var overview: Frame
        var view: Frame
        var marks: [Frame]

        static let overviewLongSide: CGFloat = 2560
        static let viewLongSide: CGFloat = 2752
        static let closeUpLongSide: ClosedRange<CGFloat> = 480...1600

        init(capture: FeedbackCapture, marks: [FeedbackMark], strokes: [FeedbackStroke]) {
            let canvas = capture.canvasRect
            overview = Frame(rect: canvas, scale: Self.overviewLongSide / max(canvas.width, canvas.height, 1))
            let seen = capture.visibleRect.isEmpty ? canvas : capture.visibleRect
            view = Frame(
                rect: seen,
                scale: min(capture.pointsPerUnit * capture.displayScale, Self.viewLongSide / max(seen.width, seen.height, 1)))
            self.marks = marks.map { Self.closeUp(of: $0, strokes: strokes) }
        }

        /// A mark with room around it (a fifth of its size, and at least 48 points on screen at
        /// the zoom it was drawn at), about as large as the painter saw it on a 2× screen.
        static func closeUp(of mark: FeedbackMark, strokes: [FeedbackStroke]) -> Frame {
            let zoom = max(CGFloat(mark.strokes.map { strokes[$0].zoom }.max() ?? 1), 0.01)
            let pad = max(0.2 * max(mark.bounds.width, mark.bounds.height), 48 / zoom)
            let rect = mark.bounds.insetBy(dx: -pad, dy: -pad)
            let long = max(rect.width, rect.height, 1)
            let scale = min(max(2 * zoom, closeUpLongSide.lowerBound / long), closeUpLongSide.upperBound / long)
            return Frame(rect: rect, scale: scale)
        }
    }

    /// The ink over each frame of a `Layout`, transparent elsewhere.
    nonisolated struct Ink: Sendable {
        var overview: CGImage?
        var view: CGImage?
        var marks: [CGImage?]
    }

    /// Everything a bundle is made of.
    nonisolated struct Contents: Sendable {
        var capture: FeedbackCapture
        var note: String
        var strokes: [FeedbackStroke]
        var marks: [FeedbackMark]
        /// By mark (`FeedbackMark.id`).
        var comments: [Date: String]
        /// The painter's photo as JPEG, when they chose to include it.
        var photo: Data?
        var layout: Layout
        var ink: Ink
    }

    /// What `write` leaves in one export folder, so `ArtworkExporter.removeExport` on any of
    /// them removes all.
    nonisolated struct Files: Sendable, Equatable {
        /// The painting with its marks (PNG).
        var picture: URL
        /// The bundle (zip).
        var bundle: URL
        /// The report as text (`feedback.md`, which the bundle holds too).
        var report: URL

        /// What the share sheet gets: the picture and the bundle.
        var shared: [URL] { [picture, bundle] }
    }

    /// Writes the bundle and returns its files.
    @concurrent
    static func write(_ contents: Contents) async throws -> Files {
        let name = bundleName(title: contents.capture.title, date: contents.capture.date)
        let picture = try ArtworkExporter.temporaryURL(name: name, pathExtension: "png")
        let directory = picture.deletingLastPathComponent()
        let folder = directory.appending(path: ArtworkExporter.fileName(name), directoryHint: .isDirectory)
        let zip = directory.appending(path: "\(ArtworkExporter.fileName(name)).zip")
        let report = directory.appending(path: FeedbackReport.File.markdown)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeFiles(contents, into: folder, picture: picture, report: report)
            try archive(folder, to: zip)
            try? FileManager.default.removeItem(at: folder)
        } catch {
            ArtworkExporter.removeExport(at: picture)
            throw error
        }
        return Files(picture: picture, bundle: zip, report: report)
    }

    /// "Red Fox Feedback 2026-10-05 14.32": the name the picture and the zip are shared under,
    /// told apart by when the feedback was given (local time).
    static func bundleName(title: String, date: Date) -> String {
        let painting = title.isEmpty ? String(localized: "Painting") : title
        let t = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d %02d.%02d", t.year ?? 0, t.month ?? 0, t.day ?? 0, t.hour ?? 0, t.minute ?? 0)
        return String(localized: "feedback.bundleName", defaultValue: "\(painting) Feedback \(stamp)",
                      comment: "Name of the files a painting's feedback is shared as (a picture and a zip archive); the arguments are the painting's title and when the feedback was given, e.g. 2026-10-05 14.32")
    }

    /// The bundle's files go into `folder`; the picture and the report are written beside it too.
    private static func writeFiles(_ contents: Contents, into folder: URL, picture: URL, report reportFile: URL) throws {
        let capture = contents.capture, layout = contents.layout
        guard let context = RenderContext.shared, let scene = CanvasScene(template: capture.template, context: context) else {
            throw ArtworkExporter.ExportError.renderFailed
        }
        let painted = (0..<capture.template.regions.count).map { capture.progress.isPainted($0) }
        var options = CanvasSnapshot.Options(outlines: true, numbers: capture.showsNumbers)
        options.palette = capture.palette
        options.lineWeight = capture.lineWeight
        // The painting as it was shown, with `ink` over it.
        func shown(_ frame: Frame, ink: CGImage?, highlight: Int? = nil) -> CGImage? {
            var look = options
            look.highlight = highlight
            guard let painting = CanvasSnapshot.render(
                scene: scene, painted: painted, size: frame.pixelSize, options: look, context: context, rect: frame.rect)
            else { return nil }
            return composite(painting, ink: ink, backdrop: capture.palette.background)
        }
        func save(_ image: CGImage?, as file: String) throws {
            guard let image, let png = ImageCodec.pngData(image) else { throw ArtworkExporter.ExportError.renderFailed }
            try png.write(to: folder.appending(path: file))
        }

        guard let marked = shown(layout.overview, ink: contents.ink.overview), let markedPNG = ImageCodec.pngData(marked) else {
            throw ArtworkExporter.ExportError.renderFailed
        }
        try markedPNG.write(to: picture, options: .atomic)
        try markedPNG.write(to: folder.appending(path: FeedbackReport.File.marked))
        if let ink = contents.ink.overview { try save(ink, as: FeedbackReport.File.markup) }
        try save(shown(layout.view, ink: contents.ink.view, highlight: capture.selectedColor), as: FeedbackReport.File.view)
        for (index, frame) in layout.marks.enumerated() {
            let ink = contents.ink.marks.indices.contains(index) ? contents.ink.marks[index] : nil
            try save(shown(frame, ink: ink), as: FeedbackReport.File.mark(index + 1))
        }
        let regions = contents.marks.map { FeedbackMarks.regions(of: $0, strokes: contents.strokes, in: capture.template) }
        let report = FeedbackReport(contents, regions: regions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: folder.appending(path: FeedbackReport.File.json))
        let markdown = Data(report.markdown.utf8)
        try markdown.write(to: folder.appending(path: FeedbackReport.File.markdown))
        try markdown.write(to: reportFile)
        try capture.template.encoded().write(to: folder.appending(path: FeedbackReport.File.template))
        if let photo = contents.photo { try photo.write(to: folder.appending(path: FeedbackReport.File.photo)) }
    }

    /// `painting` on the backdrop the canvas showed around the sheet, with `ink` over it.
    static func composite(_ painting: CGImage, ink: CGImage?, backdrop: SIMD3<Float>) -> CGImage? {
        let w = painting.width, h = painting.height
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let ctx = CGContext(
                  data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        // Linear Display P3 → its encoded components.
        let components = [backdrop.x, backdrop.y, backdrop.z].map { CGFloat(ColorScience.encodeSRGB($0)) } + [1]
        ctx.setFillColor(CGColor(colorSpace: space, components: components) ?? CGColor(gray: 0.5, alpha: 1))
        ctx.fill(rect)
        ctx.draw(painting, in: rect)
        if let ink { ctx.draw(ink, in: rect) }
        return ctx.makeImage()
    }

    /// Zips `folder` into `destination` with the system's own archiver (a coordinated read for
    /// uploading hands a directory over as a zip).
    static func archive(_ folder: URL, to destination: URL) throws {
        var coordination: NSError?
        var copying: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: folder, options: .forUploading, error: &coordination) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: destination)
            } catch {
                copying = error
            }
        }
        if let coordination { throw coordination }
        if let copying { throw copying }
    }
}
