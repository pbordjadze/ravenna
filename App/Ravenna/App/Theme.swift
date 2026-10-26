import CoreText
import SwiftUI
import UIKit

/// Shared visual language. Ravenna's seam: Paint by Moonlight's design system (native iOS, its
/// tokens in the asset catalog) dressed in Ravenna's design language
/// (https://claude.ai/artifact/8F7FXLE2aSLQ2Vb5XArJR6, v0's `Theme`): the dark of an apse,
/// lime-plaster white for words and the tint, lapis under prominent labels, Alegreya for titles
/// and numerals, and gold only where a tile is setting. Dark only, as v0 (`UIUserInterfaceStyle`).
enum Theme {
    /// `surface-base`: screen background. Apse, #15130F.
    static let paper = Color("Paper")
    /// `surface-elevated`: cards, sheets, grouped rows. Bench, #1E1B16.
    static let surface = Color("Surface")
    /// `radius-lg`: media cards.
    static let cardRadius: CGFloat = 20
    static let hairline = Color.primary.opacity(0.08)
    /// `tint`: lime-plaster white, #E9E2D3: buttons, the held paint's ring, progress. Not gold.
    static let accent = Color("AccentColor")
    /// Lapis, #1F2A52, the signature: under the labels of primary buttons and tinted badges.
    static let signature = Color(red: 0.122, green: 0.165, blue: 0.322)
    /// Smalti gold, #C9A24A: a tile settling and catching the light, and a work that is set (and
    /// Paint by Moonlight's stars, sparkles and crescent, where they still show).
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)
    /// `outline`: rules and hairlines. Joint, #3A342A.
    static let outline = Color("Outline")

    /// Navigation titles in Alegreya SC (`Typeface`), like the identity's headings.
    static func styleNavigationTitles() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: displayFont(.largeTitle, size: 34, weight: .bold)]
        bar.titleTextAttributes = [.font: displayFont(.headline, size: 17, weight: .semibold)]
    }

    /// `size` is the style's size at the default text size; the font scales from it.
    private static func displayFont(_ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let face: UIFont
        if Typeface.stored() == .alegreya, let alegreya = UIFont(name: Typeface.smallCaps(heavy: weight.rawValue >= UIFont.Weight.semibold.rawValue), size: size) {
            face = alegreya
        } else {
            face = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: face)
    }

    /// A text style's size at the default text size, which a custom font scales from.
    static func defaultSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

/// The face of titles and numerals, an option until Paul chooses (the design page): Alegreya
/// (Juan Pablo del Peral, Huerta Tipográfica; SIL Open Font License, bundled) or the system serif,
/// New York, as Paint by Moonlight and v0 had. Read as each title is drawn; navigation titles take
/// a change at the next launch.
nonisolated enum Typeface: String, CaseIterable, Sendable {
    case alegreya, systemSerif

    static let key = "typeface"

    static func stored(in defaults: UserDefaults = .standard) -> Typeface {
        defaults.string(forKey: key).flatMap(Typeface.init(rawValue:)) ?? .alegreya
    }

    /// Alegreya SC's PostScript name, bold or medium.
    static func smallCaps(heavy: Bool) -> String { heavy ? "AlegreyaSC-Bold" : "AlegreyaSC-Medium" }
}

extension Font {
    /// Alegreya SC at a Dynamic Type style (New York under `Typeface.systemSerif`): titles and
    /// numerals. Ravenna's seam; New York in Paint by Moonlight.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        guard Typeface.stored() == .alegreya else { return .system(style, design: .serif, weight: weight) }
        return .custom(Typeface.smallCaps(heavy: Self.isHeavy(weight)), size: Theme.defaultSize(of: style), relativeTo: style)
    }

    /// A numeral of `size` points (a swatch's) in the display face, its figures lining rather than
    /// Alegreya's old-style ones, so every number stands the same height in its swatch.
    static func numeral(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        guard Typeface.stored() == .alegreya,
              let face = UIFont(name: Typeface.smallCaps(heavy: Self.isHeavy(weight)), size: size)
        else { return .system(size: size, weight: weight, design: .serif) }
        let lining = face.fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberCaseType, UIFontDescriptor.FeatureKey.selector: kUpperCaseNumbersSelector,
        ]]])
        return Font(UIFont(descriptor: lining, size: size) as CTFont)
    }

    private static func isHeavy(_ weight: Font.Weight) -> Bool {
        [.semibold, .bold, .heavy, .black].contains(weight)
    }
}

/// The design system's four-point sparkle (Motifs/sparkle.svg). `pinch` is how far the
/// control points sit off the centre, as a fraction of the half-size: 0 gives needle-thin arms.
nonisolated struct Sparkle: Shape {
    var pinch: CGFloat = 0.133

    func path(in rect: CGRect) -> Path { Path(Self.cgPath(in: rect, pinch: pinch)) }

    static func cgPath(in rect: CGRect, pinch: CGFloat = 0.133) -> CGPath {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let kx = rect.width / 2 * pinch, ky = rect.height / 2 * pinch
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: CGPoint(x: c.x + kx, y: c.y - ky))
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: CGPoint(x: c.x + kx, y: c.y + ky))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: CGPoint(x: c.x - kx, y: c.y + ky))
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: CGPoint(x: c.x - kx, y: c.y - ky))
        p.closeSubpath()
        return p
    }

    /// The Moon's star (`Sky`): the sparkle with shorter rays on its diagonals, like a star on an
    /// old sky chart, their tips rounded so they never read as thorns and their lengths a touch
    /// uneven, as if inked by hand (the Lamplit Table, October 17, 2026). Each ray winds the way
    /// the sparkle does, so their overlap stays filled under the non-zero rule.
    static func starPath(in rect: CGRect, pinch: CGFloat = 0.133) -> CGPath {
        let p = CGMutablePath()
        p.addPath(cgPath(in: rect, pinch: pinch))
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let half = min(rect.width, rect.height) / 2
        // Up-right, down-right, down-left, up-left, as fractions of the long arms (the sparkle's
        // own sides reach about 0.45 along a diagonal).
        let reach: [CGFloat] = [0.68, 0.60, 0.65, 0.58]
        let base = half * 0.30, tip = half * 0.045
        for (k, fraction) in reach.enumerated() {
            let angle = -CGFloat.pi / 4 + CGFloat.pi / 2 * CGFloat(k)
            let length = half * fraction
            // A point `x` along the ray and `y` across it.
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: c.x + x * cos(angle) - y * sin(angle), y: c.y + x * sin(angle) + y * cos(angle))
            }
            let middle = (length - tip) / 2, side = (base + tip) / 2
            p.move(to: point(0, -base))
            p.addQuadCurve(to: point(length - tip, -tip), control: point(middle, -side))
            p.addQuadCurve(to: point(length - tip, tip), control: point(length + tip * 0.35, 0))
            p.addQuadCurve(to: point(0, base), control: point(middle, side))
            p.closeSubpath()
        }
        return p
    }
}

/// The design system's crescent, as the empty gallery's sketch draws it: the outer arc of one
/// circle and the inner arc of a smaller one set off up and to the right, an outline to stroke.
/// `rect` is the outer circle's square.
nonisolated enum Crescent {
    static func cgPath(in rect: CGRect) -> CGPath {
        // The sketch's moon: an outer circle of radius 26 and an inner one of 23, 6.41 right of
        // and 2.89 above its centre.
        let s = rect.width / 52
        let outer = CGPoint(x: rect.midX, y: rect.midY)
        let inner = CGPoint(x: outer.x + 6.41 * s, y: outer.y - 2.89 * s)
        let p = CGMutablePath()
        func arc(center: CGPoint, radius: CGFloat, from a0: Double, to a1: Double) {
            let steps = 40
            for k in 0...steps {
                let a = (a0 + (a1 - a0) * Double(k) / Double(steps)) * .pi / 180
                let point = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
                if p.isEmpty { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
        arc(center: outer, radius: 26 * s, from: -81.75, to: -326.7)
        arc(center: inner, radius: 23 * s, from: 48.24, to: 263.31)
        p.closeSubpath()
        return p
    }
}

/// A gentle press response for tappable cards.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// A description under a title (a `ContentUnavailableView`'s) that wraps at a readable width:
    /// on a wide screen it would run on for most of the screen's width.
    func readableDescription() -> some View {
        frame(maxWidth: 480)
            .multilineTextAlignment(.center)
    }
}

/// Small circular progress indicator in the tint color.
struct ProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat = 2.5
    @Environment(\.colorScheme) private var colorScheme

    /// How much of the tint the unfilled part of the ring shows. At night the tint is antique
    /// gold on a near-black surface, where the day's share all but vanishes.
    static func trackOpacity(for scheme: ColorScheme) -> Double { scheme == .dark ? 0.4 : 0.22 }

    var body: some View {
        ZStack {
            Circle().stroke(.tint.opacity(Self.trackOpacity(for: colorScheme)), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}
