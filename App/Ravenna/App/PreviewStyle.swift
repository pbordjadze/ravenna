import Foundation

/// Settings › Preview: what a new painting's preview shows beside the photo in the create flow.
/// The painting as it will look finished, or its line art: the drawing alone on the canvas
/// sheet's paper, its lines as the canvas draws them, which shows them better while they are
/// tuned (`CompareView`). A way of looking only: it never changes a template.
nonisolated enum PreviewStyle: String, CaseIterable, Identifiable, Sendable {
    case painting, lineArt

    static let `default` = PreviewStyle.painting

    var id: String { rawValue }

    /// The choice in Settings, and the caption of the comparison's layer.
    var name: String {
        switch self {
        case .painting: String(localized: "Painting")
        case .lineArt: String(localized: "Line Art")
        }
    }

    /// The stored setting (`SettingsKey.previewStyle`), or the default.
    static func stored(in defaults: UserDefaults = .standard) -> PreviewStyle {
        defaults.string(forKey: SettingsKey.previewStyle).flatMap(PreviewStyle.init(rawValue:)) ?? .default
    }
}
