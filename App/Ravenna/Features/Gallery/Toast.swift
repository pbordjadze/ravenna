import SwiftUI

/// A floating glass capsule message with an optional action.
struct Toast<Trailing: View>: View {
    let text: String
    let systemImage: String
    /// The screen edge it slides in from.
    var edge: Edge = .bottom
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Accessibility sizes leave a phone-wide capsule too little beside the icon and the action
        // for a painting's title: the message gets the full width, with the action under it.
        let large = dynamicTypeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // The action keeps its label however long the message is: the message gets what is left.
            Text(text)
                .lineLimit(large ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            trailing
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        // The stacked toast is too tall for a capsule's ends: they would cut into the text.
        .glassEffect(.regular, in: large ? AnyShape(.rect(cornerRadius: 28, style: .continuous)) : AnyShape(.capsule))
        .transition(reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

extension Toast where Trailing == EmptyView {
    init(text: String, systemImage: String, edge: Edge = .bottom) {
        self.init(text: text, systemImage: systemImage, edge: edge) { EmptyView() }
    }
}
