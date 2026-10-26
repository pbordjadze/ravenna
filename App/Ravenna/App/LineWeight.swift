import Foundation

/// Settings › Line Weight: how heavy a coloring book's drawing is (a factor on
/// `ColoringBookLook`'s line), on the canvas, in pictures and on paper; classic paintings ignore
/// it. Drawing only: changing it never changes a template, so it reaches every painting at once.
nonisolated enum LineWeight: String, CaseIterable, Identifiable, Sendable {
    case fine, regular, bold

    static let `default` = LineWeight.regular

    var id: String { rawValue }

    /// The factor on the book's line: Fine and Bold are a step of about √2 lighter and heavier.
    var factor: Float {
        switch self {
        case .fine: 0.7
        case .regular: 1
        case .bold: 1.4
        }
    }

    var name: String {
        switch self {
        case .fine: String(localized: "lineWeight.fine", defaultValue: "Fine",
                           comment: "Choice of the Line Weight setting: a painting's drawn lines lighter than designed")
        case .regular: String(localized: "lineWeight.regular", defaultValue: "Regular",
                              comment: "Choice of the Line Weight setting: a painting's drawn lines as designed")
        case .bold: String(localized: "lineWeight.bold", defaultValue: "Bold",
                           comment: "Choice of the Line Weight setting: a painting's drawn lines heavier than designed")
        }
    }

    /// The stored setting (`SettingsKey.lineWeight`), or the default. Safe off the main actor:
    /// pictures and the time-lapse are drawn with it in the background.
    static func stored(in defaults: UserDefaults = .standard) -> LineWeight {
        defaults.string(forKey: SettingsKey.lineWeight).flatMap(LineWeight.init(rawValue:)) ?? .default
    }

    /// The weight nearest `factor` on a log scale: how Settings › Advanced's Line Weight slider
    /// (0.5–2×) carries over (`Preferences.removeRetiredSettings`).
    static func nearest(to factor: Float) -> LineWeight {
        guard factor.isFinite, factor > 0 else { return .default }
        return allCases.min { abs(log2($0.factor / factor)) < abs(log2($1.factor / factor)) } ?? .default
    }
}
