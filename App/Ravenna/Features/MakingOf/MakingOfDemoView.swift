#if DEBUG
import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import os
import SwiftUI

/// Demo scenarios of the making-of show (`MakingOfView`), made as Start makes it for the first
/// starter (Young Woman in Red, its bundled mosaic at the recipe's defaults), held still for the
/// screenshot:
///
/// - `making-of`: the face being set, at 20 s, its card crediting Dioskourides.
/// - `making-of-smalti`: the glass cooling and cut into tesserae, at 6 s.
/// - `making-of-andamento`: the rows and the field, at 33 s.
/// - `making-of-dark`, `making-of-long-text`: the outlines at 25 s; in dark appearance, and with
///   every localized string twice as long.
/// - `making-of-end`: the finished mosaic with the closing card, at the end of the hold.
/// - `making-of-reduce-motion`: Reduce Motion's still of the drawing on the bed, with its card.
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
            if source == nil { Log.demo.error("Making-of demo: no mosaic") }
        }
    }

    private var reducesMotion: Bool { scenario.contains("reduce-motion") }

    /// The show's time the scenario holds (Reduce Motion: the scene's still).
    private var heldAt: Double {
        switch scenario {
        case "making-of-smalti": 6
        case "making-of-andamento": 33
        case "making-of-dark", "making-of-long-text": 25
        case "making-of-end": 1000
        case "making-of-reduce-motion": 10
        default: 20
        }
    }

    /// What Start makes the show from for the first starter: its bundled mosaic and photo.
    private static func source() async -> MakingOfSource? {
        guard let sample = Sample.starters.first ?? Sample.all.first, let url = sample.url else { return nil }
        return await Background.run {
            guard let photo = try? PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize),
                  let image = PhotoLoader.cgImage(from: photo),
                  let mosaic = MosaicMaker.bundled(sample.id, recipe: MosaicEngine.Recipe())
            else { return nil }
            return MakingOfSource(mosaic: mosaic, photo: image, finish: .material, title: sample.title,
                                  credit: MakingOfSource.credit(of: sample))
        }
    }
}
#endif
