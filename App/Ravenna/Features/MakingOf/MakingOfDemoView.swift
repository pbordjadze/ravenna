#if DEBUG
import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI

/// Demo scenarios of the making-of show (`MakingOfView`), made as Start makes it from a portrait
/// photograph, South Manitou Island Lighthouse (the factory's checks found their bugs on a
/// portrait), at the default settings with its line art, and held still for the screenshot:
///
/// - `making-of`: the paints step at 7 s: the paints running through their areas, the seed rings
///   and the step's card.
/// - `making-of-ink`: the ink step at 11.6 s, the lines burning with a spark at each hot tip.
/// - `making-of-stars`: the template step at 14.7 s, the numbers coming out each in a faint
///   ring (a star).
/// - `making-of-dark`, `making-of-long-text`: the ink step at 12 s, its card crediting two
///   methods; in dark appearance, and with every localized string twice as long.
/// - `making-of-end`: the real template after the hand-off, at the end of the hold.
/// - `making-of-reduce-motion`: Reduce Motion's still of the paints step, with its card.
struct MakingOfDemoView: View {
    let scenario: String
    @State private var source: MakingOfSource?

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let source {
                MakingOfView(demo: source, heldAt: heldAt, reduceMotion: reducesMotion, onReady: { DemoMode.markReady() })
            }
        }
        .task {
            source = await Self.source()
            if source == nil { Log.demo.error("Making-of demo: no photo") }
        }
    }

    private var reducesMotion: Bool { scenario.contains("reduce-motion") }

    /// The show's time (Reduce Motion: the still) the scenario holds.
    private var heldAt: Double {
        switch scenario {
        case "making-of-reduce-motion": 2
        case "making-of-ink": 11.6
        case "making-of-stars": 14.7
        case "making-of-dark", "making-of-long-text": 12
        case "making-of-end": 17.2
        default: 7
        }
    }

    /// What Start would make the show from, for the demo's photo: its line art from the maps
    /// demo launches keep (`LineArtMapsCache`), no subject importance, no refinements.
    private static func source() async -> MakingOfSource? {
        guard let sample = Sample.named("south-manitou-lighthouse") ?? Sample.all.first, let url = sample.url,
              let photo = await Background.run({ try? PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }),
              let preview = PhotoLoader.cgImage(from: photo)
        else { return nil }
        let settings = GenerationSettings()
        let lineArt = try? await LineArtInputs.forGeneration(of: preview, settings: settings.lineArt, cached: true)
        return MakingOfSource(
            image: photo, importance: nil, lineArt: lineArt, refinements: TemplateRefinements(), settings: settings,
            template: nil, photo: preview, seed: 7)
    }
}
#endif
