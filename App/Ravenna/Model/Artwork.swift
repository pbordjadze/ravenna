import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import PaintCore

/// Metadata of one artwork in the library (its `meta.json`). Holds everything the gallery
/// shows, so listing the library never touches the much larger template.
nonisolated struct Artwork: Identifiable, Hashable, Codable, Sendable {
    /// Bump when older apps must not open or rewrite an artwork folder: a template
    /// `formatVersion` bump or a new *required* template chunk. Such apps list the artwork
    /// read-only (`needsNewerApp`) instead of misreading it. Set whenever the folder's
    /// template is written; opening or painting keeps the recorded format.
    /// 1: format-1 templates. 2: templates are written in `Template.formatVersion` 2.
    static let currentFormat = 2

    var id: UUID
    var title: String
    var createdAt: Date
    /// Last change to the painting; the gallery sorts by it.
    var modifiedAt: Date
    var completedAt: Date?
    var settings: GenerationSettings
    /// Canvas size in template units.
    var width: Int
    var height: Int
    var colorCount: Int
    var regionCount: Int
    var paintedCount: Int
    var activeSeconds: Double
    /// Bumped whenever `thumbnail.png` is rewritten; part of the image cache key.
    var thumbnailVersion: Int
    /// The library picture the artwork was made from (`Sample.id`), if any. It may name one the
    /// app no longer has, which `Sample.named` doesn't resolve.
    var sampleName: String?
    var format: Int
    /// `Template.pipelineVersion` of the current template (0 = unknown).
    var pipelineVersion: Int
    /// Marked by the painter: favorites sort first in the gallery and have their own filter.
    /// Absent from older `meta.json` files, which decode as not favorite (no format bump).
    var isFavorite = false
    /// Where `settings` came from: `SettingsOrigin` raw values ("suggested", "custom"); nil for
    /// artworks made before Suggested settings, and kept as written so a value a newer app
    /// adds survives an older one rewriting the file. The suggestion itself is not stored: it
    /// is reproducible from the photo and the painting length.
    var settingsOrigin: String?
    /// The `PaintingLength` raw value the create flow aimed for; nil before Suggested settings.
    var paintingLength: String?
    /// Frozen vocabulary used for this painting's derived nicknames. Missing or unreadable
    /// metadata means v1; keep unknown future versions as written, even if this build uses
    /// its newest known vocabulary to display them.
    var nicknameVersion: Int
    /// What Ravenna's engine made the mosaic with (`MosaicEngine.Recipe`): what regeneration
    /// makes it with again. Nil for an artwork without one (none is written by this app), which
    /// regenerates with the recipe's defaults. Ravenna's seam: Paint by Moonlight's `settings` stay
    /// written as they were, unread by the engine.
    var recipe: MosaicEngine.Recipe?

    init(
        id: UUID = UUID(), title: String, createdAt: Date = .now, modifiedAt: Date? = nil,
        template: Template, settings: GenerationSettings, settingsOrigin: SettingsOrigin? = nil,
        paintingLength: PaintingLength? = nil, progress: PaintProgress? = nil, sampleName: String? = nil,
        recipe: MosaicEngine.Recipe? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.settings = settings
        self.settingsOrigin = settingsOrigin?.rawValue
        self.paintingLength = paintingLength?.rawValue
        nicknameVersion = ColorNickname.currentVersion
        width = template.width
        height = template.height
        colorCount = template.palette.count
        regionCount = template.regions.count
        pipelineVersion = Int(template.pipelineVersion)
        paintedCount = progress?.paintedCount ?? 0
        activeSeconds = progress?.activeSeconds ?? 0
        completedAt = progress?.isComplete == true ? self.modifiedAt : nil
        thumbnailVersion = 1
        self.sampleName = sampleName
        self.recipe = recipe
        format = Self.currentFormat
    }

    var fractionComplete: Double {
        regionCount == 0 ? 0 : min(1, Double(paintedCount) / Double(regionCount))
    }

    var isComplete: Bool { regionCount > 0 && paintedCount >= regionCount }
    var isStarted: Bool { paintedCount > 0 }
    var aspectRatio: CGFloat { height == 0 ? 1 : CGFloat(width) / CGFloat(height) }
    /// Written by a newer app: listed and deletable, but never opened or rewritten here.
    var needsNewerApp: Bool { format > Self.currentFormat }

    /// Mirrors the artwork's template and the settings that made it into the metadata.
    mutating func adopt(_ template: Template, settings: GenerationSettings) {
        width = template.width
        height = template.height
        colorCount = template.palette.count
        regionCount = template.regions.count
        pipelineVersion = Int(template.pipelineVersion)
        self.settings = settings
    }

    /// Mirrors a progress snapshot into the metadata.
    mutating func record(_ progress: PaintProgress, at date: Date = .now) {
        paintedCount = progress.paintedCount
        activeSeconds = progress.activeSeconds
        modifiedAt = date
        if progress.isComplete {
            if completedAt == nil { completedAt = date }
        } else {
            completedAt = nil
        }
    }

    // Decoding tolerates missing optional fields so older or hand-edited files still load.
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, completedAt, settings, width, height
        case colorCount, regionCount, paintedCount, activeSeconds, thumbnailVersion, sampleName, format
        case pipelineVersion, isFavorite, settingsOrigin, paintingLength, nicknameVersion, recipe
    }

    /// What an artwork saved without settings was made with: classic lines, the only kind
    /// there was, so regeneration keeps its look whatever the default style is now.
    static let settingsBeforeLineArt = GenerationSettings(lineArt: LineArtSettings(style: .classic))

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nicknameVersion = (try? c.decodeIfPresent(Int.self, forKey: .nicknameVersion)) ?? 1
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        guard format <= Self.currentFormat else {
            // A newer app may have changed any field; take what still reads so the gallery can
            // show the artwork (and offer to delete it) instead of hiding it.
            func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
                (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
            }
            id = field(.id, UUID())  // the folder name overrides it
            title = field(.title, "")
            createdAt = field(.createdAt, .distantPast)
            modifiedAt = field(.modifiedAt, createdAt)
            completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
            settings = field(.settings, Self.settingsBeforeLineArt)
            width = max(1, field(.width, 1))
            height = max(1, field(.height, 1))
            colorCount = max(0, field(.colorCount, 0))
            regionCount = max(0, field(.regionCount, 0))
            paintedCount = max(0, field(.paintedCount, 0))
            activeSeconds = PaintProgress.sanitized(field(.activeSeconds, 0))
            thumbnailVersion = field(.thumbnailVersion, 0)
            sampleName = try? c.decodeIfPresent(String.self, forKey: .sampleName)
            pipelineVersion = field(.pipelineVersion, 0)
            isFavorite = field(.isFavorite, false)
            settingsOrigin = try? c.decodeIfPresent(String.self, forKey: .settingsOrigin)
            paintingLength = try? c.decodeIfPresent(String.self, forKey: .paintingLength)
            recipe = try? c.decodeIfPresent(MosaicEngine.Recipe.self, forKey: .recipe)
            return
        }
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        settings = try c.decodeIfPresent(GenerationSettings.self, forKey: .settings) ?? Self.settingsBeforeLineArt
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        colorCount = try c.decodeIfPresent(Int.self, forKey: .colorCount) ?? 0
        regionCount = try c.decode(Int.self, forKey: .regionCount)
        paintedCount = try c.decodeIfPresent(Int.self, forKey: .paintedCount) ?? 0
        activeSeconds = PaintProgress.sanitized(try c.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0)
        thumbnailVersion = try c.decodeIfPresent(Int.self, forKey: .thumbnailVersion) ?? 0
        sampleName = try c.decodeIfPresent(String.self, forKey: .sampleName)
        pipelineVersion = try c.decodeIfPresent(Int.self, forKey: .pipelineVersion) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        settingsOrigin = try? c.decodeIfPresent(String.self, forKey: .settingsOrigin)
        paintingLength = try? c.decodeIfPresent(String.self, forKey: .paintingLength)
        recipe = try? c.decodeIfPresent(MosaicEngine.Recipe.self, forKey: .recipe)
        guard width > 0, height > 0, regionCount >= 0, paintedCount >= 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid artwork dimensions"))
        }
    }
}

/// Whether a painting's generation settings are the create flow's suggestion for its photo or
/// the painter's own (a slider moved).
nonisolated enum SettingsOrigin: String, Sendable {
    case suggested, custom
}

/// Everything needed to add a new artwork to the library.
nonisolated struct ArtworkDraft: Sendable {
    var title: String
    var template: Template
    var settings: GenerationSettings
    /// Nil when nothing was suggested (first-launch samples, demos).
    var settingsOrigin: SettingsOrigin?
    /// The painting length the suggestion aimed for.
    var paintingLength: PaintingLength?
    /// The source photo, stored downscaled for comparison and regeneration.
    var photo: CGImage?
    var sampleName: String?
    var progress: PaintProgress?
    var date: Date = .now
    /// The mosaic the template is of, kept beside it (`mosaic.json`), and what made it.
    var mosaic: Mosaic?
    var recipe: MosaicEngine.Recipe?
}
