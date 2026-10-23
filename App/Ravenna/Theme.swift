import SwiftUI

/// Ravenna's look, provisional (the design page: https://claude.ai/artifact/8F7FXLE2aSLQ2Vb5XArJR6):
/// the dark of an apse, lime-plaster white for words and the tint, and gold kept for where a tile is
/// being set (the guardians' caution: no gold spread over every screen).
enum Theme {
    static let ground = Color(red: 0.082, green: 0.075, blue: 0.059)
    static let panel = Color(red: 0.118, green: 0.106, blue: 0.086)
    static let rule = Color(red: 0.227, green: 0.204, blue: 0.165)
    static let plaster = Color(red: 0.914, green: 0.886, blue: 0.827)
    static let muted = Color(red: 0.651, green: 0.612, blue: 0.537)
    /// Smalti gold: a tile settling and catching the light, and a work that is set. Nowhere else.
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)
    static let lapis = Color(red: 0.122, green: 0.165, blue: 0.322)
    /// Buttons, the held paint's ring, progress: lime white, not gold.
    static let tint = plaster

    /// Alegreya SC (Juan Pablo del Peral, Huerta Tipográfica; SIL Open Font License), bundled. Every
    /// size grows with Dynamic Type, tied to the text style nearest it.
    static func title(_ size: CGFloat) -> Font {
        .custom(size >= 22 ? "AlegreyaSC-Bold" : "AlegreyaSC-Medium", size: size, relativeTo: style(size))
    }

    /// Alegreya, the same hand for words.
    static func body(_ size: CGFloat = 16) -> Font { .custom("Alegreya-Regular", size: size, relativeTo: style(size)) }

    private static func style(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case 34...: .largeTitle
        case 26..<34: .title
        case 21..<26: .title2
        case 19..<21: .title3
        case 16.5..<19: .body
        case 15..<16.5: .callout
        case 14..<15: .subheadline
        case 12.5..<14: .footnote
        default: .caption
        }
    }
}

extension Color {
    init(_ rgb: SIMD3<Float>, opacity: Double = 1) {
        self.init(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z), opacity: opacity)
    }
}
