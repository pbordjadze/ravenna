import Foundation
import SwiftUI

/// A gallery card: the painting as it stands, its title and progress.
struct ArtworkCard: View {
    let artwork: Artwork
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardFrame {
                ArtworkThumbnail(artwork: artwork)
            }
            // A finished painting has no badge: its caption says so, with the time it took.
            .overlay(alignment: .topTrailing) {
                if artwork.needsNewerApp { NeedsUpdateBadge().padding(10) }
            }
            .overlay(alignment: .topLeading) {
                if artwork.isFavorite { FavoriteBadge().padding(10) }
            }
            // The pointer lifts the picture, not its caption.
            .contentShape(.hoverEffect, .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .hoverEffect(.lift)
            .matchedTransitionSource(id: artwork.id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(artwork.title)
                    .font(.display(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                    // Two lines, so a long title on a phone's narrow card reads whole.
                    .lineLimit(2)
                ProgressCaption(artwork: artwork)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artwork.title)
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(.isButton)
    }

    /// The label stays the title (what people and UI tests look a card up by); the value carries
    /// the favorite mark ahead of the progress.
    private var spokenValue: String {
        let progress = ProgressCaption.spoken(artwork)
        guard artwork.isFavorite else { return progress }
        return String(localized: "gallery.card.spoken.favorite", defaultValue: "Favorite, \(progress)",
                      comment: "VoiceOver value of a favorite painting's card; the argument is its progress, e.g. 42 percent painted")
    }
}

/// Square, rounded, softly shadowed frame shared by cards and placeholders.
struct CardFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.09), radius: 16, x: 0, y: 8)
    }
}

/// The artwork's stored thumbnail, decoded at the size it is shown and reloaded (with a
/// crossfade) when it changes.
struct ArtworkThumbnail: View {
    let artwork: Artwork
    var contentMode: ContentMode = .fill
    @Environment(Library.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var size: CGSize = .zero

    private struct Load: Equatable {
        let key: String
        let pixelSize: Int
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: Load(key: ThumbnailCache.key(artwork), pixelSize: pixelSize)) {
            let pixelSize = pixelSize
            guard pixelSize > 0 else { return }
            let cache = ThumbnailCache.shared
            if image == nil { image = cache.cached(artwork, maxPixelSize: pixelSize) ?? cache.bestCached(artwork) }
            let loaded = await cache.load(artwork, maxPixelSize: pixelSize, from: library.store)
            if let loaded, loaded !== image {
                withAnimation(.easeInOut(duration: 0.3)) { image = loaded }
            }
        }
    }

    private var pixelSize: Int {
        ThumbnailCache.pixelSize(
            frame: size, displayScale: displayScale, aspectRatio: artwork.aspectRatio, fills: contentMode == .fill)
    }
}

/// Marks a favorite. Hidden from VoiceOver: the card's value says it.
private struct FavoriteBadge: View {
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 30, height: 30)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }
}

/// Marks an artwork made by a newer version of the app, which this one can't open.
private struct NeedsUpdateBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(width: 30, height: 30)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }
}

/// "42%", "Ready to paint", "Finished", "Needs app update".
struct ProgressCaption: View {
    let artwork: Artwork

    var body: some View {
        HStack(spacing: 6) {
            if artwork.needsNewerApp {
                Image(systemName: "arrow.up.circle").foregroundStyle(.orange)
                Text("Needs app update")
            } else if artwork.isComplete {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                if artwork.activeSeconds >= 60 {
                    let spent = PaintingTimeText.spent(artwork.activeSeconds)
                    Text(String(localized: "gallery.card.finishedAfter", defaultValue: "Finished · \(spent)",
                                comment: "Caption of a finished painting's card; the argument is the time spent painting, e.g. 2 h 14 min"))
                } else {
                    Text("Finished")
                }
            } else if artwork.isStarted {
                ProgressRing(fraction: artwork.fractionComplete, lineWidth: 2.4)
                    .frame(width: 14, height: 14)
                let percent = Self.percentText(artwork)
                Text(String(localized: "gallery.card.percentPainted", defaultValue: "\(percent) painted",
                            comment: "Caption of a painting card in progress; the argument is the formatted percentage painted, e.g. 42%"))
                    .monospacedDigit()
            } else {
                Image(systemName: "square.grid.3x3.fill").foregroundStyle(.tint)  // Ravenna: tiles, not a brush
                Text("Ready to paint")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        // Wraps rather than clips at large text sizes on narrow cards.
        .lineLimit(2)
    }

    static func percent(_ artwork: Artwork) -> Int {
        PaintSpeech.percent(painted: artwork.paintedAreas, total: artwork.areaCount)
    }

    /// "42%": `percent` as the locale writes it.
    static func percentText(_ artwork: Artwork) -> String {
        (Double(percent(artwork)) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func spoken(_ artwork: Artwork) -> String {
        if artwork.needsNewerApp {
            return String(localized: "gallery.card.spoken.needsUpdate", defaultValue: "Needs a newer version of the app",
                          comment: "VoiceOver value of a painting made by a newer version of the app")
        }
        if artwork.isComplete {
            return String(localized: "gallery.card.spoken.finished", defaultValue: "Finished",
                          comment: "VoiceOver value of a finished painting's card")
        }
        if !artwork.isStarted {
            let colorCount = artwork.colorCount
            return String(localized: "gallery.card.spoken.notStarted", defaultValue: "Not started, \(colorCount) colors",
                          comment: "VoiceOver value of a painting nobody has painted on; the argument is its number of colors")
        }
        return PaintSpeech.percentPainted(percent(artwork))
    }
}

/// Stands in for an artwork that is still being prepared.
struct PlaceholderCard: View {
    let placeholder: Library.Placeholder
    @State private var image: CGImage?

    /// The long side its picture is decoded at.
    static let pictureSize = 400

    /// The picture shows sharp, in its colors, so the first launch's wait has the page's picture to
    /// look at rather than a grey blur (the first-five-minutes walk, October 23; Paul: "let's build
    /// them all"), the brush pulsing on glass over it. SideStore and Debug builds only for now
    /// (`UNRELEASED`, root `CLAUDE.md` › App rules).
    #if UNRELEASED
    private static let showsPicture = true
    #else
    private static let showsPicture = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardFrame {
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .saturation(Self.showsPicture ? 1 : 0.15)
                            .opacity(Self.showsPicture ? 1 : 0.4)
                            .blur(radius: Self.showsPicture ? 0 : 8)
                    }
                    if Self.showsPicture {
                        brush
                            .frame(width: 56, height: 56)
                            .glassEffect(.regular, in: .circle)
                    } else {
                        brush
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(placeholder.sample.title)
                    .font(.display(.headline, weight: .semibold))
                    .lineLimit(2)
                Text("Preparing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .task { image = await SampleImages.shared.load(placeholder.sample, maxPixelSize: Self.pictureSize) }
        .accessibilityElement(children: .combine)
    }

    private var brush: some View {
        Image(systemName: "square.grid.3x3.fill")  // Ravenna: tiles, not a brush
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.tint)
            .symbolEffect(.pulse, options: .repeating)
            .accessibilityHidden(true)
    }
}
