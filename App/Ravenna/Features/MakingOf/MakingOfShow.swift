import CoreGraphics
import Foundation
import MakingOf
import PaintCore

/// What a painting's making-of show is made from: the photo and the generator inputs its base
/// template was made with (`CreateModel.makingOfSource`), and the painting's own template.
nonisolated struct MakingOfSource: Sendable {
    var image: RGBAImage
    var importance: PaintCore.Grid<Float>?
    var lineArt: LineArtInput?
    /// The painter's refinements: their generator inputs make the base as the create flow made it.
    var refinements: TemplateRefinements
    var settings: GenerationSettings
    /// The painting's template as Start saved it (the base with the painter's edits laid on it);
    /// nil shows the base the pictures come from.
    var template: Template?
    /// The photo as the create flow holds it: what shows while the show is being made, which is
    /// how the show begins.
    var photo: CGImage
    var seed: UInt64
}

/// A making-of show ready to play (`MakingOfPlayer`): MakingOf's `FieldShow`, the show with no crew
/// (each step grows from seeds over the picture itself), and what the view draws beside its
/// pictures (`ShowFrame`'s doc comment): the numbers' digits, each step's card, and the real
/// template the finished drawing hands over to.
///
/// `build` generates the base template once more with a `PipelineSnapshot` observer for the stage
/// pictures (observing never changes the template: PaintCore's `PipelineSnapshotTests`), then
/// builds the show from them, the painting's own template, the bundled `making-of.json` and the
/// artwork's seed. On a device that is a generation and about a second more; the show keeps about
/// 35 MB.
nonisolated struct MakingOfShow: Sendable {
    let show: FieldShow
    let spec: ShowSpec
    /// Where each number of the template goes, in `ShowFrame.numbers`' order, and its paint number.
    let numbers: [ShowTemplate.Number]
    let digits: [Int]
    /// One per step, in order.
    let cards: [MakingOfCard]
    /// The painting's template on the show's paper, its lines without its numbers (the view keeps
    /// drawing those over it): the real template the finished drawing hands over to
    /// (`PictureRecipe.handoff`), and what the show ends on.
    let handoff: CGImage?
    /// The space the pictures' bytes are in: the photo's.
    let colorSpace: RGBColorSpace

    /// The long side the real template is drawn at: about the screen's, so it stays sharp.
    static let handoffSize = 2048

    @concurrent
    static func build(_ source: MakingOfSource) async throws -> MakingOfShow {
        // A task's cancellation shows only on the thread running it; the flag reaches the
        // generator's and the show's worker threads too.
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try make(source, cancel: CancellationCheck { flag.isSet })
        } onCancel: {
            flag.set()
        }
    }

    static func make(_ source: MakingOfSource, cancel: CancellationCheck) throws -> MakingOfShow {
        let spec = try ShowSpec(json: resource("making-of"))
        let (pictures, base) = try observe(source, cancel: cancel)
        let template = source.template ?? base
        let shown = ShowTemplate(template, width: pictures.width, height: pictures.height)
        let show = try FieldShow(pictures: pictures, template: shown, spec: spec, seed: source.seed, cancel: cancel)
        try cancel.throwIfCancelled()
        return MakingOfShow(
            show: show, spec: spec, numbers: shown.numbers,
            digits: template.labels.map { Int(template.regions[Int($0.region)].colorIndex) + 1 },
            cards: spec.steps.enumerated().map { MakingOfCard(step: $1, index: $0) },
            handoff: TemplateRasterizer.image(template, style: handoffStyle, maxPixelSize: handoffSize),
            colorSpace: template.colorSpace)
    }

    /// The base template made again from `source`, and the stage pictures its making showed.
    static func observe(_ source: MakingOfSource, cancel: CancellationCheck) throws -> (ShowPictures, Template) {
        let aspect = Float(source.image.width) / Float(max(source.image.height, 1))
        let inputs = source.refinements.refining(importance: source.importance, lineArt: source.lineArt, aspect: aspect)
        let recorder = SnapshotRecorder()
        let base = try TemplateGenerator(settings: source.settings)
            .generate(
                from: source.image, importance: inputs.importance, lineArt: inputs.lineArt, cancel: cancel,
                observer: { recorder.receive($0) })
            .template
        return (try ShowPictures(snapshots: recorder.snapshots), base)
    }

    /// Reduce Motion's stills (`MakingOfPlayer`): the picture as each step leaves it, then the
    /// real template once the steps are over.
    static func stillTimes(_ timing: ScheduleTiming) -> [Double] {
        (0..<ScheduleTiming.steps).map { timing.start($0 + 1) - 0.05 } + [timing.end + 1]
    }

    /// The picture of `frame` (`FieldShow.composite`: the layers, the lines and the fronts' tide
    /// lines) as an image, drawn in `pixels`, a plane of the pictures' size kept from frame to frame.
    func picture(_ frame: ShowFrame, into pixels: inout Plane<SIMD4<UInt8>>) -> CGImage? {
        show.composite(frame, into: &pixels)
        return Self.image(pixels, space: colorSpace)
    }

    /// A plane of opaque RGBA bytes as an image, copied.
    static func image(_ pixels: Plane<SIMD4<UInt8>>, space: RGBColorSpace) -> CGImage? {
        guard pixels.width > 0, pixels.height > 0 else { return nil }
        let data = pixels.data.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.width * 4, space: space.cgColorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The real template as the show hands over to it: its drawing in the show's ink on the show's
    /// paper (`RevealStyle`), so only the lines change as it comes in.
    static let handoffStyle: TemplateRasterizer.Style = {
        let style = RevealStyle.standard
        var drawn = TemplateRasterizer.Style()
        drawn.paper = SIMD3<Float>(style.paper / 255)
        let ink = SIMD3<Float>(style.ink / 255)
        drawn.outlineColor = SIMD4(ink, 1)
        return drawn
    }()

    private static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }
}

/// Keeps the stage pictures a show is made from, as the generator's thread hands them over: the
/// line art and vectorized pictures are not among them.
private nonisolated final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [PipelineSnapshot] = []

    var snapshots: [PipelineSnapshot] { lock.withLock { kept } }

    func receive(_ snapshot: PipelineSnapshot) {
        guard snapshot.stage != .lineArt, snapshot.stage != .vectorized else { return }
        lock.withLock { kept.append(snapshot) }
    }
}
