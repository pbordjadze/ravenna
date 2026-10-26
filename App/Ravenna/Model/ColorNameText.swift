import Foundation
import PaintCore

/// The app's localizable rendering of `ColorName` ("dark grayish green"). PaintCore's `english`
/// serves the CLI; in English both read the same. Word order lives in the format strings, so a
/// translation can put the family first.
nonisolated enum ColorNameText {
    static func string(_ name: ColorName) -> String {
        let family = word(name.family)
        let lightness = name.spokenLightness.flatMap { word($0) }
        let chroma = name.spokenChroma.flatMap { word($0) }
        switch (lightness, chroma) {
        case let (lightness?, chroma?):
            return String(localized: "colorName.format.lightness-chroma-family",
                          defaultValue: "\(lightness) \(chroma) \(family)",
                          comment: "Color name: lightness, chroma and hue family words, e.g. “dark grayish green”")
        case let (lightness?, nil):
            return String(localized: "colorName.format.lightness-family",
                          defaultValue: "\(lightness) \(family)",
                          comment: "Color name: lightness and hue family words, e.g. “dark green”")
        case let (nil, chroma?):
            return String(localized: "colorName.format.chroma-family",
                          defaultValue: "\(chroma) \(family)",
                          comment: "Color name: chroma and hue family words, e.g. “vivid green”")
        case (nil, nil):
            return family
        }
    }

    /// The name capitalized for display on its own ("Dark grayish green").
    static func title(_ name: ColorName) -> String {
        let text = string(name)
        guard let first = text.first else { return text }
        return String(first).localizedUppercase + text.dropFirst()
    }

    /// "12 · Dark green": the number printed on the canvas, then the name, for text on screen.
    /// A `nickname` ("Harbor Fog") takes the name's place.
    static func numbered(number: Int, name: ColorName, nickname: String? = nil) -> String {
        let title = nickname ?? Self.title(name)
        return String(localized: "colorName.format.numbered", defaultValue: "\(number) · \(title)",
                      comment: "A palette color as shown on screen: its number, then its capitalized name, e.g. “12 · Dark green”")
    }

    /// Whether playful nicknames may be shown while the app runs in `languageCode` (the bundle's
    /// preferred localization). The vocabulary is English data: in any other language the
    /// localized structured name is shown instead, until a translated vocabulary exists.
    static func nicknamesAvailable(languageCode: String? = Bundle.main.preferredLocalizations.first) -> Bool {
        guard let languageCode else { return true }
        return Locale.Language(identifier: languageCode).languageCode == .english
    }

    /// The palette's nicknames, index-aligned (using the artwork's recorded `version`): nil for a color
    /// with no vocabulary name (it keeps its structured one) and for every color when
    /// `languageCode` isn't English.
    static func nicknames(
        for palette: [PaletteColor], seed: UInt64, version: Int,
        languageCode: String? = Bundle.main.preferredLocalizations.first
    ) -> [String?] {
        guard nicknamesAvailable(languageCode: languageCode) else { return palette.map { _ in nil } }
        let names = Set(ColorNickname.Vocabulary(version: version).entries.map(\.name))
        return ColorNickname.assign(palette, seed: seed, version: version).map { names.contains($0) ? $0 : nil }
    }

    private static func word(_ lightness: ColorName.Lightness) -> String? {
        switch lightness {
        case .veryDark:
            return String(localized: "colorName.lightness.veryDark", defaultValue: "very dark",
                          comment: "Color name lightness modifier")
        case .dark:
            return String(localized: "colorName.lightness.dark", defaultValue: "dark",
                          comment: "Color name lightness modifier")
        case .medium:
            return nil
        case .light:
            return String(localized: "colorName.lightness.light", defaultValue: "light",
                          comment: "Color name lightness modifier")
        case .pale:
            return String(localized: "colorName.lightness.pale", defaultValue: "pale",
                          comment: "Color name lightness modifier")
        }
    }

    private static func word(_ chroma: ColorName.Chroma) -> String? {
        switch chroma {
        case .grayish:
            return String(localized: "colorName.chroma.grayish", defaultValue: "grayish",
                          comment: "Color name chroma modifier (a dull, desaturated color)")
        case .muted:
            return nil
        case .vivid:
            return String(localized: "colorName.chroma.vivid", defaultValue: "vivid",
                          comment: "Color name chroma modifier (a strongly saturated color)")
        }
    }

    private static func word(_ family: ColorName.Family) -> String {
        switch family {
        case .black: String(localized: "colorName.family.black", defaultValue: "black", comment: "Color name hue family")
        case .white: String(localized: "colorName.family.white", defaultValue: "white", comment: "Color name hue family")
        case .gray: String(localized: "colorName.family.gray", defaultValue: "gray", comment: "Color name hue family")
        case .red: String(localized: "colorName.family.red", defaultValue: "red", comment: "Color name hue family")
        case .orange: String(localized: "colorName.family.orange", defaultValue: "orange", comment: "Color name hue family")
        case .brown: String(localized: "colorName.family.brown", defaultValue: "brown", comment: "Color name hue family")
        case .beige: String(localized: "colorName.family.beige", defaultValue: "beige", comment: "Color name hue family")
        case .yellow: String(localized: "colorName.family.yellow", defaultValue: "yellow", comment: "Color name hue family")
        case .olive: String(localized: "colorName.family.olive", defaultValue: "olive", comment: "Color name hue family")
        case .green: String(localized: "colorName.family.green", defaultValue: "green", comment: "Color name hue family")
        case .teal: String(localized: "colorName.family.teal", defaultValue: "teal", comment: "Color name hue family")
        case .blue: String(localized: "colorName.family.blue", defaultValue: "blue", comment: "Color name hue family")
        case .navy: String(localized: "colorName.family.navy", defaultValue: "navy", comment: "Color name hue family")
        case .purple: String(localized: "colorName.family.purple", defaultValue: "purple", comment: "Color name hue family")
        case .magenta: String(localized: "colorName.family.magenta", defaultValue: "magenta", comment: "Color name hue family")
        case .pink: String(localized: "colorName.family.pink", defaultValue: "pink", comment: "Color name hue family")
        }
    }
}

nonisolated extension PaletteColor {
    /// "#AA5E59": how the swatch details and the PDF key write a paint.
    var hexCode: String { "#" + hexDigits.uppercased() }
}

