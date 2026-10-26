import Foundation
import PaintCore

/// How many lines the palette wraps into (the painting screen's More › Palette): rows at the
/// bottom, columns along the trailing edge of a landscape iPad.
nonisolated enum PaletteRows: Int, CaseIterable, Identifiable, Sendable {
    /// A few lines on roomy screens (three at the bottom, two beside), one on compact ones.
    case auto = 0
    case one = 1, two, three, four, five, six
    /// As many as every color needs to show at once.
    case all = 99

    static let `default` = PaletteRows.auto

    var id: Int { rawValue }

    /// The most lines this choice wraps into, where `automatic` is what Auto allows here.
    /// A fixed count is used as given (capped by the colors left and the room on screen).
    func maxLines(automatic: Int) -> Int {
        switch self {
        case .auto: automatic
        case .all: .max
        default: rawValue
        }
    }

    /// Whether the palette uses all of `maxLines` (a fixed count) rather than the fewest that fit.
    var isFixed: Bool { self != .auto && self != .all }
}

/// The order of the palette's swatches (the painting screen's More › Palette).
nonisolated enum PaletteOrder: String, CaseIterable, Identifiable, Sendable {
    case number, rainbow, lightToDark, darkToLight, nearlyDone, mostLeft

    static let `default` = PaletteOrder.number

    var id: String { rawValue }

    /// Sorted by the areas left, so the order changes as the painting goes: finishing a color
    /// selects its first swatch, not the next one along (`PaintingSession.advancesToFirstLeft`).
    var followsProgress: Bool { self == .nearlyDone || self == .mostLeft }

    /// Below this OKLab chroma a paint reads as a gray: the rainbow puts grays after the hues.
    static let grayChroma: Float = 0.03

    /// `colors` (palette indices) in this order. `remaining` is each color's areas left to
    /// paint, read only by the orders that follow it: a view whose body arranges the palette
    /// then re-renders on every fill only under those. Ties keep number order, so the result
    /// depends only on its inputs.
    func arrange(_ colors: [Int], palette: [PaletteColor], remaining: @autoclosure () -> [Int]) -> [Int] {
        func by<T: Comparable>(_ key: (Int) -> T) -> [Int] {
            colors.sorted { key($0) != key($1) ? key($0) < key($1) : $0 < $1 }
        }
        switch self {
        case .number:
            return colors.sorted()
        case .rainbow:
            return colors.sorted { a, b in
                let ka = Self.rainbowKey(palette[a].oklab), kb = Self.rainbowKey(palette[b].oklab)
                return ka != kb ? ka < kb : a < b
            }
        case .lightToDark:
            return by { -palette[$0].oklab.x }
        case .darkToLight:
            return by { palette[$0].oklab.x }
        case .nearlyDone:
            let left = remaining()
            return by { left[$0] }
        case .mostLeft:
            let left = remaining()
            return by { -left[$0] }
        }
    }

    /// Hues around the wheel from red (OKLab hue angle 0 sits at pink-red), then grays from
    /// light to dark.
    private static func rainbowKey(_ lab: SIMD3<Float>) -> RainbowKey {
        let lch = ColorScience.lch(lab)
        guard lch.y >= grayChroma else { return RainbowKey(isGray: true, value: -lch.x) }
        let turn = 2 * Float.pi
        return RainbowKey(isGray: false, value: (lch.z.truncatingRemainder(dividingBy: turn) + turn).truncatingRemainder(dividingBy: turn))
    }

    private struct RainbowKey: Comparable {
        var isGray: Bool
        var value: Float

        static func < (a: Self, b: Self) -> Bool {
            a.isGray != b.isGray ? !a.isGray : a.value < b.value
        }
    }
}

// MARK: Names

extension PaletteRows {
    var name: String {
        switch self {
        case .auto:
            String(localized: "palette.rows.auto", defaultValue: "Auto",
                   comment: "Palette Rows choice: as many rows as fit the screen (three on iPad, one on iPhone)")
        case .all:
            String(localized: "palette.rows.all", defaultValue: "All at Once",
                   comment: "Palette Rows choice: as many rows as it takes to show every color without scrolling")
        default:
            String(localized: "palette.rows.count", defaultValue: "\(rawValue) Rows",
                   comment: "Palette Rows choice: a fixed number of rows of swatches (columns beside a landscape iPad); the argument is the count")
        }
    }
}

extension PaletteOrder {
    var name: String {
        switch self {
        case .number:
            String(localized: "palette.order.number", defaultValue: "By Number",
                   comment: "Palette Order choice: swatches in the order of their numbers")
        case .rainbow:
            String(localized: "palette.order.rainbow", defaultValue: "Rainbow",
                   comment: "Palette Order choice: swatches by hue, red through violet, then grays")
        case .lightToDark:
            String(localized: "palette.order.lightToDark", defaultValue: "Light to Dark",
                   comment: "Palette Order choice: lightest paint first")
        case .darkToLight:
            String(localized: "palette.order.darkToLight", defaultValue: "Dark to Light",
                   comment: "Palette Order choice: darkest paint first")
        case .nearlyDone:
            String(localized: "palette.order.nearlyDone", defaultValue: "Nearly Done First",
                   comment: "Palette Order choice: colors with the fewest areas left to paint first")
        case .mostLeft:
            String(localized: "palette.order.mostLeft", defaultValue: "Most Left First",
                   comment: "Palette Order choice: colors with the most areas left to paint first")
        }
    }
}
