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
    static let paperAppearance = "paperAppearance"
    /// The palette's lines (`PaletteRows`) and order (`PaletteOrder`), set from the painting
    /// screen's More › Palette.
    static let paletteRows = "paletteRows"
    static let paletteOrder = "paletteOrder"
    /// How heavy a coloring book's drawing is (`LineWeight`).
    nonisolated static let lineWeight = "lineWeight"
    /// Start Painting first plays the making-of show (`MakingOfView`): the mosaic set step by step,
    /// each technique named (Settings › The Making-of; on by default in Ravenna).
    static let playsMakingOf = "playsMakingOf"
    /// The create flow's preview shows its settings: its Adjust was opened, and stays so
    /// (`TemplatePreviewView.foldsSettings`).
    static let previewShowsSettings = "previewShowsSettings"
    /// Whether the app gives small tips as the painter goes (Settings › Tips). On for everyone
    /// until they switch it off there: unset means on (`TipPreference`).
    nonisolated static let tipsEnabled = "tipsEnabled"
}

/// What each switch of `SettingsKey` is until the painter sets it, written once: the `@AppStorage`
/// declarations and the code reading `UserDefaults` itself start from these. The keys whose
/// values are a type of their own keep their default on it (`SkySetting.default`,
/// `PaperAppearance.default`, `LineWeight.default`, `PaletteRows.default`, `PaletteOrder.default`).
nonisolated enum SettingsDefault {
    static let haptics = true
    static let sounds = true
    static let autoAdvance = true
    static let zenMode = false
    /// Ravenna's seam: Paul's decision (issue #13), the making-of is on by default.
    static let playsMakingOf = true
    static let previewShowsSettings = false
    static let tipsEnabled = true
}

/// The preferences that code outside views reads (the create flow), with their defaults; views
/// bind the other keys with `@AppStorage` (a painting's session takes its settings from
/// `PaintView`, whoever presents it).
struct Preferences {
    /// Start Painting plays the making-of show first.
    var playsMakingOf: Bool

    init(defaults: UserDefaults = .standard) {
        // `bool(forKey:)` reads a launch argument's `YES` too.
        playsMakingOf = defaults.object(forKey: SettingsKey.playsMakingOf) == nil
            ? SettingsDefault.playsMakingOf : defaults.bool(forKey: SettingsKey.playsMakingOf)
    }

    /// Keys of settings the app no longer has: Settings › Advanced's line art, pipeline tuning,
    /// line appearance and preview picture, and its switch for each sound, haptic and flourish;
    /// Settings' paper size for printing and Color Names; the time-lapse's pace; Settings › Detail
    /// Brushes (later Text Corrections: Refine's Text tool is always there now); Settings › The
    /// Marginarium. Left in place, the first two would still shape new paintings, unseen. Ravenna's
    /// seam: Settings › Preview and Painting Length and Refine's own, which it has none of; and
    /// its own Finish, One Finger, Row Sound, Border (v0's keys) and Typeface, fixed since
    /// October 28 (`TileOptions`, issue #14).
    static let retiredKeys = [
        "advancedLineArt", "advancedPipelineTuning", "advancedLineAppearance", "advancedPreviewPicture",
        "printPaperSize", "colorNameStyle", "timelapsePace", "refineDetailBrushes", "showsMarginarium",
        "previewStyle", "paintingLength", "refineSnaps", "refinePenColors", "refineBrushSize",
        "finish", "oneFinger", "rowSound", "border", "typeface",
    ] + [
        "paintNotes", "colorJingle", "finishFanfare", "wrongColorSound", "fillHaptics", "wrongColorHaptics",
        "finishHaptics", "fillSparkles", "finishShine",
    ].map { "paintingEffect." + $0 }

    /// v0's settings v1 carries to its own (`carryV0Settings`) and then retires: its Sound, Touch
    /// and Tune, its first lesson's step (the tips teach the same: Tap to Set, Lay a Row) and its
    /// Detail (each mosaic keeps its own pieces now, `MosaicEngine.Recipe`). v0's `ground` goes
    /// once `V0CarryOver` has recorded it with each carried work. Ravenna's seam.
    static let retiredV0Keys = ["sound", "touch", "tune", "lesson", "detail"]

    /// Carries v0's Sound, Touch and Tune to Settings' Sounds, Haptics and Music, where the painter
    /// hasn't set those yet, then removes v0's keys that nothing reads (`retiredV0Keys`, and
    /// `ground` once v0's works are carried over).
    static func carryV0Settings(in defaults: UserDefaults = .standard) {
        if defaults.object(forKey: SettingsKey.sounds) == nil, let sound = defaults.object(forKey: "sound") as? Bool {
            defaults.set(sound, forKey: SettingsKey.sounds)
        }
        if defaults.object(forKey: SettingsKey.haptics) == nil, let touch = defaults.object(forKey: "touch") as? Bool {
            defaults.set(touch, forKey: SettingsKey.haptics)
        }
        // v0's tune was major or minor at every hour: the Sun's and the Moon's.
        if defaults.object(forKey: SettingsKey.sky) == nil, let tune = defaults.string(forKey: "tune") {
            switch tune {
            case "major": defaults.set(SkySetting.sun.rawValue, forKey: SettingsKey.sky)
            case "minor": defaults.set(SkySetting.moon.rawValue, forKey: SettingsKey.sky)
            default: break
            }
        }
        for key in retiredV0Keys { defaults.removeObject(forKey: key) }
        if defaults.bool(forKey: V0CarryOver.doneKey) { defaults.removeObject(forKey: "ground") }
    }

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
        carryV0Settings(in: defaults)
    }
}
