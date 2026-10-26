import Foundation
import PaintCore

/// UserDefaults keys of user preferences (views bind them with `@AppStorage`).
enum SettingsKey {
    static let haptics = "hapticsEnabled"
    static let sounds = "soundsEnabled"
    /// Settings › Music's Sun, Moon or Auto (`SkySetting`): which sounds play, and whether the
    /// fill's sparkles are stars.
    nonisolated static let sky = "sky"
    static let autoAdvance = "autoAdvanceColors"
    /// Zen Mode: fly on to the next area after each fill (the painting screen's More menu).
    static let zenMode = "zenMode"
    static let paintingLength = "paintingLength"
    static let paperAppearance = "paperAppearance"
    /// The palette's lines (`PaletteRows`) and order (`PaletteOrder`), set from the painting
    /// screen's More › Palette.
    static let paletteRows = "paletteRows"
    static let paletteOrder = "paletteOrder"
    /// How heavy a coloring book's drawing is (`LineWeight`).
    nonisolated static let lineWeight = "lineWeight"
    /// What the create flow's preview shows beside the photo (`PreviewStyle`).
    nonisolated static let previewStyle = "previewStyle"
    /// Start Painting first plays the making-of show (`MakingOfView`): the painter's photo becoming
    /// its painting, step by step (Settings › The Making-of; off by default).
    static let playsMakingOf = "playsMakingOf"
    /// Whether the app gives small tips as the painter goes (Settings › Tips). On for everyone
    /// until they switch it off there: unset means on (`TipPreference`).
    nonisolated static let tipsEnabled = "tipsEnabled"
    /// The create flow's preview shows its settings: its Adjust was opened, and stays so (SideStore
    /// and Debug builds, `TemplatePreviewView.foldsSettings`).
    static let previewShowsSettings = "previewShowsSettings"
    /// Refine's Snap: a drawn line's ends join the lines their ink touches (on unless switched off).
    static let refineSnaps = "refineSnaps"
    /// Refine's Color from Photo: a drawn line gives the areas it divides the photo's colors (off).
    static let refinePenColors = "refinePenColors"
    /// Refine's Paint Brush's Size: its radius on screen, in points (`RefineGestures.brushSize` unless set).
    static let refineBrushSize = "refineBrushSize"
}

/// What each switch of `SettingsKey` is until the painter sets it, written once: the `@AppStorage`
/// declarations and the code reading `UserDefaults` itself start from these. The keys whose
/// values are a type of their own keep their default on it (`PaintingLength.default`,
/// `SkySetting.default`, `PaperAppearance.default`, `LineWeight.default`, `PreviewStyle.default`,
/// `PaletteRows.default`, `PaletteOrder.default`).
nonisolated enum SettingsDefault {
    static let haptics = true
    static let sounds = true
    static let autoAdvance = true
    static let zenMode = false
    static let playsMakingOf = false
    static let tipsEnabled = true
    static let previewShowsSettings = false
    static let refineSnaps = true
    static let refinePenColors = false
    static let refineBrushSize = Double(RefineGestures.brushSize)
}

/// The preferences that code outside views reads (the create flow), with their defaults; views
/// bind the other keys with `@AppStorage` (a painting's session takes its settings from
/// `PaintView`, whoever presents it).
struct Preferences {
    /// How long a painting Suggested settings aim for in the create flow.
    var paintingLength: PaintingLength
    /// What the create flow's preview shows beside the photo.
    var previewStyle: PreviewStyle
    /// Start Painting plays the making-of show first.
    var playsMakingOf: Bool

    init(defaults: UserDefaults = .standard) {
        paintingLength = defaults.string(forKey: SettingsKey.paintingLength).flatMap(PaintingLength.init(rawValue:))
            ?? .default
        previewStyle = PreviewStyle.stored(in: defaults)
        // `bool(forKey:)` reads a launch argument's `YES` too.
        playsMakingOf = defaults.object(forKey: SettingsKey.playsMakingOf) == nil
            ? SettingsDefault.playsMakingOf : defaults.bool(forKey: SettingsKey.playsMakingOf)
    }

    /// Keys of settings the app no longer has: Settings › Advanced's line art, pipeline tuning,
    /// line appearance and preview picture, and its switch for each sound, haptic and flourish;
    /// Settings' paper size for printing and Color Names; the time-lapse's pace; Settings › Detail
    /// Brushes (later Text Corrections: Refine's Text tool is always there now); Settings › The
    /// Marginarium. Left in place, the first two would still shape new paintings, unseen.
    static let retiredKeys = [
        "advancedLineArt", "advancedPipelineTuning", "advancedLineAppearance", "advancedPreviewPicture",
        "printPaperSize", "colorNameStyle", "timelapsePace", "refineDetailBrushes", "showsMarginarium",
    ] + [
        "paintNotes", "colorJingle", "finishFanfare", "wrongColorSound", "fillHaptics", "wrongColorHaptics",
        "finishHaptics", "fillSparkles", "finishShine",
    ].map { "paintingEffect." + $0 }

    /// Where the retired Custom palette order kept each painting's arrangement, by its nickname
    /// seed.
    static let retiredCustomOrderPrefix = "paletteOrder.custom."

    /// Removes the retired settings (at launch; nothing is left to do once they are gone), first
    /// carrying Advanced's Line Weight over to Settings › Line Weight; the palette order Custom
    /// goes with the arrangements it read.
    static func removeRetiredSettings(in defaults: UserDefaults = .standard) {
        if defaults.object(forKey: SettingsKey.lineWeight) == nil,
           let data = defaults.data(forKey: "advancedLineAppearance"),
           let appearance = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weight = appearance["coloringBookWeight"] as? Double {
            let carried = LineWeight.nearest(to: Float(weight))
            if carried != .default { defaults.set(carried.rawValue, forKey: SettingsKey.lineWeight) }
        }
        for key in retiredKeys { defaults.removeObject(forKey: key) }
        if defaults.string(forKey: SettingsKey.paletteOrder) == "custom" {
            defaults.removeObject(forKey: SettingsKey.paletteOrder)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(retiredCustomOrderPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Settings › Painting Length: what Suggested settings aim for.
nonisolated extension PaintingLength {
    static let `default` = PaintingLength.relaxed

    var name: String {
        switch self {
        case .quick: String(localized: "paintingLength.quick", defaultValue: "Quick",
                            comment: "Choice of the Painting Length setting: suggested settings aim for a short painting")
        case .relaxed: String(localized: "paintingLength.relaxed", defaultValue: "Relaxed",
                              comment: "Choice of the Painting Length setting: suggested settings aim for about half an hour of painting")
        case .detailed: String(localized: "paintingLength.detailed", defaultValue: "Detailed",
                               comment: "Choice of the Painting Length setting: suggested settings aim for a long, detailed painting")
        }
    }

    /// The Settings footer under the picker: what the choice typically gives (`timeBand`: Quick
    /// 8–25 min, Relaxed 20–50, Detailed 40–120). Medians of large corpus photos under a Vision
    /// stand-in map: 16, 26 and 42 minutes (`docs/auto-tuning.md`, round two). A photo
    /// too small or too plain to fill Relaxed's or Detailed's band ends below it, at any setting.
    var footer: String {
        switch self {
        case .quick: String(localized: "settings.paintingLength.footer.quick",
                            defaultValue: "Suggested settings aim for about 15 minutes of painting.",
                            comment: "Footer under the Painting Length setting when Quick is chosen")
        case .relaxed: String(localized: "settings.paintingLength.footer.relaxed",
                              defaultValue: "Suggested settings aim for about half an hour of painting. Small or simple photos make shorter paintings.",
                              comment: "Footer under the Painting Length setting when Relaxed is chosen")
        case .detailed: String(localized: "settings.paintingLength.footer.detailed",
                               defaultValue: "Suggested settings aim for 45 minutes or more of painting. Small or simple photos make shorter paintings.",
                               comment: "Footer under the Painting Length setting when Detailed is chosen")
        }
    }
}
