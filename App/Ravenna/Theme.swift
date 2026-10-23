import SwiftUI

/// Ravenna's look, provisional: the dark of an apse, lime-plaster white for words, and gold kept
/// for where a tile is being set (the guardians' caution: no gold spread over every screen).
enum Theme {
    static let ground = Color(red: 0.082, green: 0.075, blue: 0.059)
    static let panel = Color(red: 0.118, green: 0.106, blue: 0.086)
    static let rule = Color(red: 0.227, green: 0.204, blue: 0.165)
    static let plaster = Color(red: 0.914, green: 0.886, blue: 0.827)
    static let muted = Color(red: 0.651, green: 0.612, blue: 0.537)
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif).smallCaps() }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, design: .serif) }
}

extension Color {
    init(_ rgb: SIMD3<Float>, opacity: Double = 1) {
        self.init(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z), opacity: opacity)
    }
}
