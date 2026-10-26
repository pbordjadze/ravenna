#if DEBUG
import CryptoKit
import Foundation
import os
import PaintCore

/// Demo and test launches only: the templates `ArtworkFactory.draft(sample:…)` generated for the
/// bundled pictures, kept on disk in the app's caches by picture, size, settings, pipeline and
/// maps (`LineArtMapsCache.version`), so the dozens of launches a CI run makes (one per
/// screenshot scenario and UI test, each seeding the same pictures into a fresh library) generate
/// each once instead of once per launch: a Debug build's pipeline took 10 to 19 s a seed on CI's
/// iPad simulator, and the tests waited for it. What a launch gets back is what it would generate
/// (from the maps `LineArtMapsCache` keeps); a file that doesn't decode is generated again.
/// Release builds have none of this.
nonisolated enum DemoTemplateCache {
    private static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appending(path: "DemoTemplates", directoryHint: .isDirectory)
    }

    /// Where the template of `sample` at `photoMaxPixelSize` and `settings` is kept; nil outside
    /// demo and test launches (`LineArtMapsCache.isEnabled`).
    static func url(sample: String, photoMaxPixelSize: Int, settings: GenerationSettings) -> URL? {
        guard LineArtMapsCache.isEnabled, let directory else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let json = try? encoder.encode(settings) else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data("\(sample) \(photoMaxPixelSize) \(TemplateGenerator.pipelineVersion) \(LineArtMapsCache.version) ".utf8))
        hasher.update(data: json)
        return directory.appending(path: hasher.finalize().map { String(format: "%02x", $0) }.joined() + ".pbnt")
    }

    static func template(at url: URL) -> Template? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let template = try? Template(encoded: data) else {
            Log.demo.error("Demo template cache: \(url.lastPathComponent, privacy: .public) unreadable, generating")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return template
    }

    static func store(_ template: Template, at url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try template.encoded().write(to: url, options: .atomic)
        } catch {
            Log.demo.error("Demo template cache: writing failed: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
