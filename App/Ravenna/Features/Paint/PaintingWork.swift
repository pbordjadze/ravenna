import Foundation
import SwiftUI
import UIKit

/// What the painting screen's More menu tells of the open mosaic, as v0's did: its making-of, to
/// watch again (More › The Making-of), and a library work's record (More › About This Work, as
/// `library.json` has it). Set by `ArtworkPaintingView`, read by `PaintView`
/// (`@Environment(\.paintingWork)`). Ravenna's seam: Paint by Moonlight's menu has neither.
nonisolated struct PaintingWork: Sendable {
    /// The library work the painting was laid from; nil for the painter's own photo.
    let sample: Sample?
    /// Makes the show (its mosaic, photo, finish and card); nil for a painting without a mosaic, or
    /// without a photo to show (its stored one, else a library work's own).
    let makingOf: (@Sendable () async -> MakingOfSource?)?
}

private nonisolated struct PaintingWorkKey: EnvironmentKey {
    static let defaultValue: PaintingWork? = nil
}

extension EnvironmentValues {
    var paintingWork: PaintingWork? {
        get { self[PaintingWorkKey.self] }
        set { self[PaintingWorkKey.self] = newValue }
    }
}

/// A library work as its record has it: the picture, its title, who made it and when, where and
/// of what, the collection's credit and license, and its page there. v0's About this work.
struct SampleAboutView: View {
    let sample: Sample
    @Environment(\.dismiss) private var dismiss
    @State private var picture: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let picture {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: sample.title)
                        .font(.display(.title2))
                        .accessibilityAddTraits(.isHeader)
                    if let provenance = sample.provenance {
                        Text(verbatim: "\(provenance.creator), \(provenance.year)").font(.body)
                    }
                    if let place = sample.place { Text(verbatim: place).foregroundStyle(.secondary) }
                    if let medium = sample.medium { Text(verbatim: medium).foregroundStyle(.secondary) }
                    if let provenance = sample.provenance {
                        Text(verbatim: provenance.credit).font(.footnote).foregroundStyle(.secondary)
                        Text(verbatim: provenance.license).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let source = sample.source {
                        Link(destination: source) {
                            Label(Self.linkTitle(source), systemImage: "building.columns")
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(String(localized: "sampleAbout.title", defaultValue: "About This Work",
                                    comment: "Title of the sheet, from the mosaic's More menu, about the ancient work a library mosaic was laid from"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .tint(Theme.signature)
                }
            }
        }
        .pageSizedOnPad()
        .task {
            guard let url = sample.url else { return }
            let image = await Task.detached(priority: .userInitiated) { ImageCodec.image(at: url, maxPixelSize: 1200) }.value
            picture = image.map { UIImage(cgImage: $0) }
        }
    }

    /// The link's words: the Met's, which holds every work the library has now, or any other's.
    private static func linkTitle(_ source: URL) -> String {
        if source.host()?.hasSuffix("metmuseum.org") == true {
            String(localized: "sampleAbout.source.met", defaultValue: "See It at The Met",
                   comment: "More › About This Work: the link to the work's page at The Metropolitan Museum of Art (a proper name)")
        } else {
            String(localized: "sampleAbout.source", defaultValue: "See Its Source",
                   comment: "More › About This Work: the link to the work's page at the collection it comes from")
        }
    }
}
