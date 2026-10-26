import SwiftUI

/// A 44 pt circular Liquid Glass button with an SF Symbol. Uses the system glass button style:
/// interactive glass on a plain button's label swallows the tap, so the action never ran.
struct GlassIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            GlassIconLabel(systemImage: systemImage)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemImage) }
    }
}

/// The symbol inside a circular glass button; the style's 7 pt padding brings it to
/// `glassButtonDiameter`.
struct GlassIconLabel: View {
    let systemImage: String
    @Environment(\.glassButtonDiameter) private var diameter

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .imageScale(diameter > 44 ? .large : .medium)
            .foregroundStyle(Color.primary)
            .frame(width: diameter - 14, height: diameter - 14)
    }
}

private nonisolated struct GlassButtonDiameterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 44
}

extension EnvironmentValues {
    /// The size of the painting screen's round glass buttons: 44 pt, a quarter more on regular
    /// widths' top bar (`QuietPainting.scale`).
    var glassButtonDiameter: CGFloat {
        get { self[GlassButtonDiameterKey.self] }
        set { self[GlassButtonDiameterKey.self] = newValue }
    }
}
