import CoreGraphics
import SwiftUI

/// The create flow's draft, at the top of the gallery: the photo, its name, how much was
/// refined, and the way back into Refine or out of the draft (`Drafts`). Narrow windows and
/// large text stack the buttons under the text. Discard asks first, and the row asks (a dialog is
/// a popover on the view that carries it: this one points at the button).
struct DraftRow: View {
    let draft: CreateDraft
    /// The draft's photo file, decoded at the thumbnail's size.
    let photo: URL
    let isCompact: Bool
    /// The draft is being read to open the create flow on it.
    let isOpening: Bool
    var onContinue: () -> Void
    /// The painter confirmed Discard Draft.
    var onDiscard: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var image: CGImage?
    @State private var confirmsDiscard = false

    private static let thumbnailSize: CGFloat = 64

    var body: some View {
        let stacked = isCompact || typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // The photo and the name open the draft too; VoiceOver has the button.
                HStack(spacing: 14) {
                    thumbnail
                    caption
                }
                .contentShape(.rect)
                .onTapGesture(perform: onContinue)
                if !stacked { continueButton(fillsWidth: false) }
                // Discard keeps its distance from Continue: set apart after it, or above it when stacked.
                discardButton
            }
            if stacked { continueButton(fillsWidth: true) }
        }
        .padding(14)
        // The whole row, its edges the grid's: a card of its own width left half of a wide row empty.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.09), radius: 16, x: 0, y: 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("draft-row")
        .task(id: draft.photoID) {
            let url = photo, pixels = Int((Self.thumbnailSize * displayScale).rounded(.up))
            let loaded = await Background.run { ImageCodec.image(at: url, maxPixelSize: pixels) }
            withAnimation(.easeInOut(duration: 0.3)) { image = loaded }
        }
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.paper)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(draft.resolvedTitle)
                .font(.display(.headline, weight: .semibold))
                .lineLimit(2)
            Text(String(localized: "gallery.draft.caption", defaultValue: "Draft · \(RefineView.changes(draft.refinements.changeCount))",
                        comment: "Caption of the gallery's draft row: a new painting refined and not started yet; the argument is how many changes the painter made in Refine, e.g. 3 changes"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func continueButton(fillsWidth: Bool) -> some View {
        Button(action: onContinue) {
            Text("Continue Refining")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.signature)
        .controlSize(.large)
        .disabled(isOpening)
        .accessibilityIdentifier("draft-continue")
    }

    private var discardButton: some View {
        // Glass draws its label in the tint, whatever the role.
        Button("Discard Draft", systemImage: "trash", role: .destructive) { confirmsDiscard = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .tint(.red)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(isOpening)
            .accessibilityIdentifier("draft-discard")
            .confirmationDialog("Discard this draft?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button(String(localized: "gallery.draft.discard.confirm", defaultValue: "Discard “\(draft.resolvedTitle)”",
                              comment: "Destructive button of the draft's discard confirmation; the argument is the draft's title"),
                       role: .destructive, action: onDiscard)
            } message: {
                Text("Its photo and everything you changed in Refine will be lost.")
            }
            .padding(.leading, 20)
    }
}
