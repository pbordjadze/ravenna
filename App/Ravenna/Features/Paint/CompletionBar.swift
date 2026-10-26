import Foundation
import Observation
import PaintCore
import SwiftUI
import UIKit

/// Replaces the palette once the painting is finished.
struct CompletionBar: View {
    /// As tall as a one-line palette, so the canvas keeps its place when the painting finishes.
    static let height = PaletteMetrics.standard.thickness(lines: 1, caption: false)

    let session: PaintingSession
    let title: String
    /// False while the top bar's progress badge names the painting: the caption says it's all
    /// painted instead.
    var showsTitle = true
    let share: CompletionShare
    /// The seal bounces each time this grows (`PaintView` bumps it once the bar is up: a bar
    /// inserted with the painting's completion never sees that change).
    let sealBounces: Int
    let onReplay: () -> Void
    /// Replay's slot holds Stop while the painting plays back.
    let onStopReplay: () -> Void
    let onShareTimelapse: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: sealBounces)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Finished!").font(.headline)
                Group {
                    if title.isEmpty || !showsTitle {
                        Text("Every region is painted.")
                    } else {
                        Text(title)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            // The buttons keep their size on a phone; the caption shrinks, then truncates.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if session.isReplaying {
                GlassIconButton(systemImage: "stop.fill", label: "Stop", action: onStopReplay)
            } else {
                GlassIconButton(systemImage: "play.fill", label: "Replay", action: onReplay)
                    // The only hint after a finish: over the bar, which sits at the bottom.
                    .gentleTip(.benchReplay, arrowEdge: .bottom)
            }
            if let picture = share.picture {
                let name = title.isEmpty ? String(localized: "Painting") : title
                // UIImage keeps the picture's Display P3 colors.
                let shareImage = Image(uiImage: UIImage(cgImage: picture))
                Menu {
                    ShareLink(item: shareImage, preview: SharePreview(name, image: shareImage)) {
                        Label("Share Picture", systemImage: "photo")
                    }
                    Button { onShareTimelapse() } label: {
                        Label("Share Time-lapse", systemImage: "timelapse")
                    }
                } label: {
                    GlassIconLabel(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Share"))
                .accessibilityShowsLargeContentViewer { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if let onClose {
                Button(action: onClose) {
                    Text("Done").lineLimit(1).fixedSize()
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .fixedSize()
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: Self.height)
        .frame(maxWidth: 560)
        // One compact row even at the largest text sizes: the canvas insets assume its height,
        // and the Large Content Viewer shows its buttons enlarged.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glassEffect(.regular, in: .capsule)
        .task(id: session.revision) { await share.prepare(for: session) }
    }
}

/// The finished painting as a picture to share, rendered once per completion (the bar
/// showing it is rebuilt far more often: layout changes, the palette moving aside).
@Observable
final class CompletionShare {
    private(set) var picture: CGImage?
    /// The session revision `picture` shows (or is being rendered for).
    @ObservationIgnored private var revision: Int?

    func prepare(for session: PaintingSession) async {
        guard session.isComplete, revision != session.revision else { return }
        let target = session.revision
        revision = target
        picture = nil
        let image = await Self.render(template: session.template, progress: session.progress)
        // Undone and finished again meanwhile: that completion renders its own.
        guard revision == target else { return }
        picture = image
        // A failed render may succeed next time the bar appears.
        if image == nil { revision = nil }
    }

    @concurrent
    private static func render(template: Template, progress: PaintProgress) async -> CGImage? {
        let size = CanvasSnapshot.fittedSize(for: template, longSide: 2048)
        return CanvasSnapshot.render(template: template, progress: progress, size: size, options: .painting)
    }
}
