import CoreTransferable
import Foundation
import MosaicKit
import PaintCore
import UniformTypeIdentifiers

/// Renders shareable files of an artwork (off the main actor).
nonisolated enum ArtworkExporter {
    enum ExportError: LocalizedError {
        case renderFailed
        case timelapseFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                String(localized: "export.error.renderFailed", defaultValue: "The picture couldn’t be rendered.",
                       comment: "Error when a painting's picture can't be rendered for sharing")
            case .timelapseFailed:
                String(localized: "export.error.timelapseFailed", defaultValue: "The time-lapse couldn’t be made.",
                       comment: "Error when the time-lapse movie can't be created")
            }
        }
    }

    /// Long side of shared images, in pixels.
    static let imagePixelSize = 4096

    /// The painting as a PNG: finished if it is, otherwise its current state with the
    /// unpainted areas sketched in.
    static func paintingPNG(store: ArtworkStore, artwork: Artwork) throws -> Data {
        let template = try store.readTemplate(artwork.id)
        let progress = try store.readProgress(artwork.id, regionCount: template.regions.count).progress
        // Ravenna's seam: a mosaic is shared as its tiles (`MosaicCard.keepsake`).
        if let mosaic = try store.readMosaic(artwork.id), let wall = MosaicCard.keepsake(mosaic, painted: progress.painted),
           let data = ImageCodec.pngData(wall) {
            return data
        }
        let style: TemplateRasterizer.Style = progress.isComplete ? .finished : .thumbnail
        guard let data = TemplateRasterizer.pngData(template, painted: progress.painted, style: style, maxPixelSize: imagePixelSize) else {
            throw ExportError.renderFailed
        }
        return data
    }

    /// The printable template. Its color key names the colors by their nicknames (the ones the
    /// painting shows).
    static func templatePDF(store: ArtworkStore, artwork: Artwork, paper: PDFExporter.Paper) throws -> Data {
        let template = try store.readTemplate(artwork.id)
        let nicknames = ColorNameText.nicknames(
            for: template.palette, seed: ColorNickname.seed(for: artwork.id), version: artwork.nicknameVersion)
        return PDFExporter.document(for: template, title: artwork.title, paper: paper, nicknames: nicknames)
    }

    /// The painting to send someone else (`SharedPainting`): its template as it is, refinements
    /// and all, with its title and settings, never its progress; with `includesPhoto`, the photo
    /// it was made from (`source.jpg`) and, with it, the library picture it came from.
    static func sharedPainting(store: ArtworkStore, artwork: Artwork, includesPhoto: Bool) throws -> Data {
        let template = try store.readTemplate(artwork.id)
        let photo = includesPhoto ? try? Data(contentsOf: store.url(.source, of: artwork.id)) : nil
        return try SharedPaintingCodec.encode(SharedPainting(
            title: artwork.title, settings: artwork.settings, template: template, photo: photo,
            sampleName: photo == nil ? nil : artwork.sampleName))
    }

    /// Writes `data` to a uniquely placed temporary file named after the artwork.
    static func temporaryFile(_ data: Data, name: String, pathExtension: String) throws -> URL {
        let url = try temporaryURL(name: name, pathExtension: pathExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Every export lives in its own folder here: `tmp/Exports/<uuid>/<name>.<ext>`.
    static var exportsRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
    }

    /// Exports older than this are swept whenever a new one is made.
    static let staleExportAge: TimeInterval = 600

    /// A fresh temporary location, in its own folder so the file keeps a readable name.
    static func temporaryURL(name: String, pathExtension: String, root: URL = exportsRoot) throws -> URL {
        // Picture and template share links can't tell when their share sheet closes, and the
        // app may not relaunch for days, so each new export sweeps the old ones. The share sheet
        // is modal and hands receivers copies, so by the time another export starts the earlier
        // ones are done with; the age only leaves a margin.
        purgeExports(createdBefore: Date.now - staleExportAge, in: root)
        let dir = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(fileName(name)).\(pathExtension)")
    }

    /// Removes the export folders created before `cutoff` (and any whose date is unknown).
    static func purgeExports(createdBefore cutoff: Date, in root: URL = exportsRoot) {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            let created = try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate
            if created.map({ $0 < cutoff }) ?? true { try? fm.removeItem(at: entry) }
        }
    }

    /// Deletes the folder of an export once it has been shared.
    static func removeExport(at file: URL, root: URL = exportsRoot) {
        let folder = file.deletingLastPathComponent()
        // Only ever a folder directly inside the exports root. Compared by resolved path
        // components: tmp may be spelled /var or /private/var, and directory URLs may or may
        // not end in a slash.
        guard folder.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            == root.resolvingSymlinksInPath().pathComponents
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// "Irises Template": the printable PDF's name, in the share sheet and as its file name.
    static func templateName(title: String) -> String {
        String(localized: "export.templateName", defaultValue: "\(title) Template",
               comment: "Name of a painting's printable template PDF; the argument is the painting's title")
    }

    /// "Irises Time-lapse": the movie's file name.
    static func timelapseName(title: String) -> String {
        String(localized: "export.timelapseName", defaultValue: "\(title) Time-lapse",
               comment: "File name of a painting's time-lapse movie; the argument is the painting's title")
    }

    static func fileName(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "Painting") : cleaned
    }
}

/// "Share Painting": a PNG rendered when the share sheet asks for it.
nonisolated struct PaintingImageFile: Transferable, Sendable {
    let store: ArtworkStore
    let artwork: Artwork

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(try await item.export())
        }
    }

    @concurrent
    func export() async throws -> URL {
        let data = try ArtworkExporter.paintingPNG(store: store, artwork: artwork)
        return try ArtworkExporter.temporaryFile(data, name: artwork.title, pathExtension: "png")
    }
}

/// "Printable Template": a PDF (the template, on several sheets when it is detailed, then the
/// color key) rendered when the share sheet asks for it.
nonisolated struct PrintableTemplateFile: Transferable, Sendable {
    let store: ArtworkStore
    let artwork: Artwork
    let paper: PDFExporter.Paper

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            SentTransferredFile(try await item.export())
        }
    }

    @concurrent
    func export() async throws -> URL {
        let data = try ArtworkExporter.templatePDF(store: store, artwork: artwork, paper: paper)
        return try ArtworkExporter.temporaryFile(data, name: ArtworkExporter.templateName(title: artwork.title), pathExtension: "pdf")
    }
}

/// What a time-lapse replays: a saved artwork, or an open painting's live state (its saved
/// copy may lag behind).
nonisolated enum TimelapseSource: Sendable {
    case saved(store: ArtworkStore, artwork: Artwork)
    /// With the mosaic the template is of, when it is one (Ravenna's seam: its tiles are set).
    case live(template: Template, progress: PaintProgress, mosaic: Mosaic?)
}

/// "Share Time-lapse": the painting replayed fill by fill with the canvas shaders, as a short
/// movie (see `TimelapseExportSheet`).
nonisolated struct TimelapseRequest: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let source: TimelapseSource

    /// Renders the movie into its own export folder. On failure or cancellation (checked every
    /// frame) the folder and the partial movie are removed.
    @concurrent
    func render(longSide: Int = 1080, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let template: Template, progress: PaintProgress, mosaic: Mosaic?
        switch source {
        case let .saved(store, artwork):
            template = try store.readTemplate(artwork.id)
            progress = try store.readProgress(artwork.id, regionCount: template.regions.count).progress
            mosaic = try store.readMosaic(artwork.id)
        case let .live(liveTemplate, liveProgress, liveMosaic):
            template = liveTemplate
            progress = liveProgress
            mosaic = liveMosaic
        }
        let url = try ArtworkExporter.temporaryURL(name: ArtworkExporter.timelapseName(title: title), pathExtension: "mp4")
        do {
            try await TimelapseFrameRenderer.export(
                template: template, progress: progress, mosaic: mosaic, to: url, longSide: longSide, onProgress: onProgress)
        } catch {
            ArtworkExporter.removeExport(at: url)
            throw error
        }
        return url
    }
}
