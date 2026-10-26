#if DEBUG
import CoreGraphics
import PaintCore
import PencilKit
import QuartzCore
import SwiftUI
import os
import simd

/// Demo scenarios for the painting screen, deterministic for CI screenshots. The template is
/// generated from a library picture, which the canvas's photo loader also gets, so the top bar
/// is the one users see. Classic lines, from Delicate Arch:
///
/// - `paint`: fresh canvas, fit to screen
/// - `paint-progress`: ~55 % painted color by color, the color in progress selected
/// - `paint-zoom`: zoomed ~4× into the canvas, numbers and highlight visible
/// - `paint-complete`: finished painting (line art dissolved)
/// - `paint-finish`: everything but one area painted, zoomed ~3× onto it; after 1.5 s it is painted,
///   and the camera eases out to the whole painting (ready once it lands)
/// - `paint-nightfall`: `paint-finish` by Moon (Settings › Music), ready once night has fallen
///   over the finished painting, the crescent inked and both stars out (`Nightfall`, SideStore and
///   Debug builds); `-introSlowdown <factor>` stretches the finish and the night for UI tests
/// - `paint-nightfall-dark`: `paint-nightfall` in dark appearance
/// - `paint-dark`: `paint-progress` for dark appearance
/// - `paint-dark-paper`: `paint-progress` on dark paper (the Paper setting at Dark)
/// - `paint-fill`: fills frozen mid-animation to inspect the paint front
/// - `paint-hint`: the hint flies the camera to a region of the selected color
/// - `paint-replay`: a finished painting mid-replay
/// - `paint-photo`: the source photo shown over a painting in progress
/// - `paint-quiet`, `paint-quiet-dark`: `paint-progress`, then an area of the selected color is
///   painted and the top bar fades to Back, the progress ring and Hint (`QuietPainting`; Debug
///   and SideStore builds)
/// - `paint-tip`: a fresh canvas with the first tip ("Tap to Paint") at the selected swatch;
///   with the gallery's, the create flow's and Settings' tip scenarios the only ones that show
///   tips (`PaintTips.configure`)
/// - `paint-tip-fill`: `paint-tip`, then once the tip is up an area is filled for the painter
///   (a UI test checks the tip goes with the fill)
/// - `paint-ax`: `paint-progress`, showing the selected color's name
/// - `paint-ax-large`: `paint-ax` at the largest accessibility text size
/// - `paint-palette`: ~30 % painted, the palette in four rows in rainbow order (More › Palette)
/// - `paint-palette-number`: ~30 % painted, the palette in three rows by number, filled down each
///   column (`PaletteLayoutTests`)
/// - `paint-long-text`, `paint-complete-long-text`: `paint-progress` and `paint-complete` with a long
///   title and every localized string twice as long (`ci/screenshots.sh` adds
///   `-NSDoubleLocalizedStrings YES` to scenarios named `*-long-text`): the progress badge, palette
///   caption and completion bar as translations would stress them
/// - `paint-feedback`: ~45 % painted, in feedback mode with two marks drawn (a red circle and
///   arrow round the busiest part, a highlighter stroke across another) and the tools
/// - `paint-feedback-dark`: `paint-feedback` for dark appearance (the ink keeps its colors)
/// - `paint-feedback-review`: the review and send sheet over it, with a note, the first mark's
///   comment, both close-ups and the Original Photo switch (a painting from the painter's photo)
/// - `paint-feedback-long-text`: `paint-feedback-review` with doubled strings and a long title
///
/// A coloring book of the red fox from the real pipeline, with the real edge detector (the
/// stand-in map when the model is unavailable):
/// - `paint-book`: fresh canvas, fit to screen (the drawing in thick ink, nothing else)
/// - `paint-book-progress`: ~45 % painted, the color in progress selected (the drawing stays
///   over the paint; the selected color's cells are hatched, not outlined)
/// - `paint-book-zoomed`: zoomed 4× into the busiest part, a color selected
/// - `paint-book-dark-paper`: `paint-book-progress` on dark paper
/// - `paint-book-night-paper`: the same in light appearance (no "dark" in its name), where dark
///   paper makes the bars dark too (`PaintView.chromeScheme`)
/// - `paint-book-moon-dark`: `paint-book-dark-paper` in dark appearance by Moon (Settings › Music),
///   zoomed 2.5× onto the unpainted area with the most room, which is painted and its two stars
///   held at their fullest (fills and sparkles slowed)
struct PaintDemoView: View {
    let scenario: String
    @State private var demo: Demo?
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    var body: some View {
        ZStack {
            if let demo {
                PaintView(
                    session: demo.session, title: demo.title, onClose: {},
                    initialCamera: demo.camera, fillDurationScale: demo.fillDurationScale, showsPhoto: demo.showsPhoto)
                    .environment(\.sourcePhotoLoader, demo.photo.map { name in
                        SourcePhotoLoader(load: { size in await Self.photo(name, maxPixelSize: size) })
                    })
                    .environment(\.dynamicTypeSize, demo.dynamicTypeSize ?? systemTypeSize)
                    .environment(\.feedbackSource, demo.feedbackSource)
                    .environment(\.feedbackDemo, demo.feedback)
                    .task {
                        await demo.run()
                        DemoMode.markReady()
                    }
            } else {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ProgressView()
            }
        }
        .task {
            let book = scenario.hasPrefix("paint-book")
            let photo = book ? "young-woman-in-red-photo" : "william-photo"
            let template: Template?
            if book {
                template = await Self.bookTemplate(photo: photo)
            } else {
                template = await Self.template(photo: photo)
            }
            // The canvas needs it, made off the main thread (`ArtworkPaintingView` waits too).
            _ = await RenderContext.ready()
            // Titles are the person's own words, which pseudo-localization doesn't lengthen.
            let title = scenario.hasSuffix("-long-text")
                ? "Delicate Arch on Our Spring Trip Through Utah"
                : (template == nil ? "Mosaic" : (book ? "Red Fox" : "Delicate Arch"))
            demo = await Demo(
                scenario: scenario, template: template ?? SyntheticTemplate.make(), title: title,
                photo: template == nil ? nil : photo)
        }
    }

    /// The photo the demo template is generated from, so the overlay lines up for real.
    @concurrent
    private static func photo(_ name: String, maxPixelSize: Int?) async -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return ImageCodec.image(at: url, maxPixelSize: maxPixelSize)
    }

    /// The photo's classic template: the classic demos show the original look.
    @concurrent
    private static func template(photo: String) async -> Template? {
        let settings = GenerationSettings(lineArt: LineArtSettings(style: .classic))
        guard let url = Bundle.main.url(forResource: photo, withExtension: "jpg"),
              let image = try? PhotoLoader.load(url: url, maxPixelSize: 2048),
              let output = try? TemplateGenerator(settings: settings).generate(from: image)
        else { return nil }
        return output.template.mesh.indices.isEmpty ? nil : output.template
    }

    /// The photo's coloring book from the real pipeline: from the real detector
    /// (`LineArtInputs.compute`), or the stand-in map (`SyntheticTemplate.edgeMap`) when the model
    /// is unavailable.
    @concurrent
    private static func bookTemplate(photo: String) async -> Template? {
        guard let url = Bundle.main.url(forResource: photo, withExtension: "jpg"),
              let image = try? PhotoLoader.load(url: url, maxPixelSize: 2048),
              let small = try? PhotoLoader.load(url: url, maxPixelSize: 640)
        else { return nil }
        var input: LineArtInput?
        if let cgImage = PhotoLoader.cgImage(from: image) {
            input = try? await LineArtInputs.compute(for: cgImage)
            Log.demo.notice("demo \(photo, privacy: .public): edge detector \(input == nil ? "unavailable, using the stand-in map" : "ran", privacy: .public)")
        }
        guard let output = try? TemplateGenerator()
            .generate(from: image, lineArt: input ?? LineArtInput(edges: SyntheticTemplate.edgeMap(for: small)))
        else { return nil }
        return output.template.lineArt == nil || output.template.mesh.indices.isEmpty ? nil : output.template
    }
}

@MainActor
private final class Demo {
    let session: PaintingSession
    let title: String
    /// The bundled photo the template was made from; nil for the synthetic mosaic that stands
    /// in when generating from it failed.
    let photo: String?
    var camera: CanvasCamera?
    var fillDurationScale: Float = 1
    var showsPhoto = false
    /// Overrides the system text size (accessibility scenarios).
    var dynamicTypeSize: DynamicTypeSize?
    /// Feedback scenarios: what feedback starts with, and where the painting came from.
    var feedback: FeedbackDemo?
    var feedbackSource: FeedbackSource?
    /// `paint-finish`: the area left to paint; `paint-book-moon-dark`: the area its stars pop on.
    private var lastArea: Int?
    private let scenario: String

    init(scenario: String, template t: Template, title: String, photo: String?) async {
        self.scenario = scenario
        self.title = title
        self.photo = photo
        session = await PaintingSession.make(template: t)

        // Paint colors in palette order (how people tend to work), each color top to bottom.
        let order = t.regions.indices.sorted {
            let a = t.regions[$0], b = t.regions[$1]
            if a.colorIndex != b.colorIndex { return a.colorIndex < b.colorIndex }
            return (a.bounds.minY, a.bounds.minX) < (b.bounds.minY, b.bounds.minX)
        }
        func paint(fraction: Double) {
            let count = Int(Double(order.count) * fraction)
            let regions = Array(order.prefix(count))
            if !regions.isEmpty { session.paint(regions, from: .zero, animated: false) }
            if let next = order.dropFirst(count).first { session.select(color: session.colorOf(next)) }
        }

        switch scenario {
        case "paint-progress", "paint-dark", "paint-ax", "paint-long-text", "paint-quiet", "paint-quiet-dark":
            paint(fraction: 0.55)
        case "paint-dark-paper":
            paint(fraction: 0.55)
            // Registered, not stored: it lasts for this launch, so the next scenario on the same
            // simulator keeps the default light paper.
            UserDefaults.standard.register(defaults: [SettingsKey.paperAppearance: PaperAppearance.dark.rawValue])
        case "paint-palette":
            paint(fraction: 0.3)
            // Registered, not stored, like the paper above.
            UserDefaults.standard.register(defaults: [
                SettingsKey.paletteRows: PaletteRows.four.rawValue, SettingsKey.paletteOrder: PaletteOrder.rainbow.rawValue,
            ])
        case "paint-palette-number":
            paint(fraction: 0.3)
            UserDefaults.standard.register(defaults: [
                SettingsKey.paletteRows: PaletteRows.three.rawValue, SettingsKey.paletteOrder: PaletteOrder.number.rawValue,
            ])
        case "paint-ax-large":
            paint(fraction: 0.55)
            dynamicTypeSize = .accessibility5
        case "paint-zoom":
            paint(fraction: 0.3)
            // Centre on a mid-sized unpainted region of the selected color near the middle.
            let middle = SIMD2(Float(t.width), Float(t.height)) * 0.5
            let color = session.selectedColor ?? 0
            let candidates = t.regions.indices.filter {
                session.colorOf($0) == color && !session.isPainted($0) && t.regions[$0].inscribedRadius > 6
            }
            let target = candidates.min { simd_distance(Self.center(t, $0), middle) < simd_distance(Self.center(t, $1), middle) }
            camera = CanvasCamera(zoom: 4, center: target.map { Self.center(t, $0) } ?? middle)
        case "paint-complete", "paint-complete-long-text":
            paint(fraction: 1)
        case "paint-finish", "paint-nightfall", "paint-nightfall-dark":
            if scenario.hasPrefix("paint-nightfall") {
                UserDefaults.standard.register(defaults: [SettingsKey.sky: SkySetting.moon.rawValue])
                let slowdown = UserDefaults.standard.double(forKey: "introSlowdown")
                if slowdown > 0 { fillDurationScale = Float(slowdown) }
            }
            // Everything but a mid-sized area near the middle, zoomed in on it.
            let middle = SIMD2(Float(t.width), Float(t.height)) * 0.5
            let last = t.regions.indices.filter { t.regions[$0].inscribedRadius > 6 }
                .min { simd_distance(Self.center(t, $0), middle) < simd_distance(Self.center(t, $1), middle) }
            if let last {
                session.paint(order.filter { $0 != last }, from: .zero, animated: false)
                session.select(color: session.colorOf(last))
                camera = CanvasCamera(zoom: 3, center: Self.center(t, last))
                lastArea = last
            }
        case "paint-replay":
            paint(fraction: 1)
            // Slowed so the CI screenshot lands mid-replay.
            fillDurationScale = 4
        case "paint-fill":
            paint(fraction: 0.2)
            // Big fills take 0.6 s; stretched so the CI screenshot (~10 s later) lands mid-spread.
            fillDurationScale = 128
        case "paint-hint":
            paint(fraction: 0.4)
        case "paint-photo":
            paint(fraction: 0.4)
            showsPhoto = true
        case "paint-book-progress":
            paint(fraction: 0.45)
        case "paint-book-dark-paper", "paint-book-night-paper":
            paint(fraction: 0.45)
            UserDefaults.standard.register(defaults: [SettingsKey.paperAppearance: PaperAppearance.dark.rawValue])
        case "paint-book-moon-dark":
            paint(fraction: 0.45)
            UserDefaults.standard.register(defaults: [
                SettingsKey.paperAppearance: PaperAppearance.dark.rawValue, SettingsKey.sky: SkySetting.moon.rawValue,
            ])
            fillDurationScale = 30
            // Sparkles pop only where an area's label has 10 points of room on screen
            // (`CanvasView.popSparkles`): zoom onto the unpainted area with the most, on the fox
            // rather than the paper around it (one area, numbered all over).
            func room(_ r: Int) -> Float { t.labels(ofRegion: r).map(\.radius).max() ?? 0 }
            let page = Float(t.width * t.height)
            if let target = t.regions.indices
                .filter({ !session.isPainted($0) && t.regions[$0].area < page * 0.05 })
                .max(by: { room($0) < room($1) }) {
                session.select(color: session.colorOf(target))
                camera = CanvasCamera(zoom: 2.5, center: Self.center(t, target))
                lastArea = target
            }
        case "paint-book-zoomed":
            paint(fraction: 0.2)
            camera = CanvasCamera(zoom: 4, center: Self.busiest(t))
        case "paint-feedback", "paint-feedback-dark", "paint-feedback-review", "paint-feedback-long-text":
            paint(fraction: 0.45)
            let reviews = scenario.hasSuffix("-review") || scenario.hasSuffix("-long-text")
            let busiest = Self.busiest(t)
            feedback = FeedbackDemo(
                ink: { pointsPerUnit in Self.feedbackInk(t, around: busiest, pointsPerUnit: pointsPerUnit) },
                note: "The sky reads beautifully, but the rocks under the arch are too fiddly to paint.",
                comment: "Too many tiny areas in here, and two of them are the same brown.", reviews: reviews)
            // The review shows the photo switch: a painting made from the painter's own photo.
            var source = FeedbackSource(settings: GenerationSettings(lineArt: LineArtSettings(style: .classic)))
            if let name = photo {
                if reviews {
                    source.photo = { await Self.photoData(name) }
                } else {
                    source.sampleName = name
                }
            }
            feedbackSource = source
        default:
            break
        }
    }

    /// Feedback's demo ink in canvas units, as large as drawn at `pointsPerUnit`: a red circle
    /// round `center` with an arrow pointing at it, and a highlighter stroke across the other
    /// half of the painting (two marks).
    private static func feedbackInk(_ t: Template, around center: SIMD2<Float>, pointsPerUnit: CGFloat) -> PKDrawing {
        let unit = 1 / max(pointsPerUnit, 0.01)
        let c = CGPoint(x: CGFloat(center.x), y: CGFloat(center.y))
        let r = CGFloat(min(t.width, t.height)) * 0.09
        var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func stroke(_ points: [CGPoint], _ ink: PKInk, width: CGFloat) -> PKStroke {
            date += 1
            let controls = points.enumerated().map { i, p in
                PKStrokePoint(
                    location: p, timeOffset: Double(i) * 0.02, size: CGSize(width: width * unit, height: width * unit),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: date), transform: .identity, mask: nil)
        }
        let pen = PKInk(.pen, color: .systemRed)
        let circle = (0...48).map { i -> CGPoint in
            let a = CGFloat(i) / 46 * 2 * .pi - 0.7
            return CGPoint(x: c.x + r * 1.2 * cos(a), y: c.y + r * 0.95 * sin(a))
        }
        let tip = CGPoint(x: c.x + r * 0.95, y: c.y - r * 0.85)
        let tail = CGPoint(x: c.x + r * 2.1, y: c.y - r * 1.9)
        let shaft = (0...8).map { i in CGPoint(x: tail.x + (tip.x - tail.x) * CGFloat(i) / 8, y: tail.y + (tip.y - tail.y) * CGFloat(i) / 8) }
        let head = [CGPoint(x: tip.x + r * 0.4, y: tip.y + r * 0.02), tip, CGPoint(x: tip.x - r * 0.02, y: tip.y - r * 0.4)]
        // Across the half of the painting the circle isn't in.
        let w = CGFloat(t.width), h = CGFloat(t.height)
        let y = c.y < h / 2 ? h * 0.8 : h * 0.2
        let from = CGPoint(x: w * 0.25, y: y), to = CGPoint(x: w * 0.6, y: y + h * 0.02)
        let line = (0...12).map { i in CGPoint(x: from.x + (to.x - from.x) * CGFloat(i) / 12, y: from.y + (to.y - from.y) * CGFloat(i) / 12) }
        return PKDrawing(strokes: [
            stroke(circle, pen, width: 4), stroke(shaft, pen, width: 4), stroke(head, pen, width: 4),
            stroke(line, PKInk(.marker, color: .systemYellow), width: 24),
        ])
    }

    @concurrent
    private static func photoData(_ name: String) async -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The middle of the busiest of 8 × 8 tiles (most line points, strokes included), where
    /// zooming in shows the layers.
    private static func busiest(_ t: Template) -> SIMD2<Float> {
        let n = 8
        var counts = [Int](repeating: 0, count: n * n)
        func add(_ p: SIMD2<Float>) {
            let i = min(n - 1, max(0, Int(p.x / Float(t.width) * Float(n))))
            let j = min(n - 1, max(0, Int(p.y / Float(t.height) * Float(n))))
            counts[j * n + i] += 1
        }
        t.points.forEach(add)
        t.lineArt?.strokePoints.forEach(add)
        let best = counts.indices.max { counts[$0] < counts[$1] } ?? 0
        return SIMD2((Float(best % n) + 0.5) * Float(t.width), (Float(best / n) + 0.5) * Float(t.height)) / Float(n)
    }

    /// Scenario actions that need the canvas on screen.
    func run() async {
        if let feedback {
            // Ready once the ink is down and, for the review, the sheet's pictures are drawn.
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(30)
            var commented = false
            while clock.now < deadline {
                if let draft = feedback.draft {
                    if !feedback.reviews { break }
                    if !commented, let first = draft.marks.first {
                        draft.comments[first.id] = feedback.comment
                        commented = true
                    }
                    if commented, draft.overview != nil, draft.closeUps.count == draft.marks.count { break }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            let marks = feedback.draft?.marks.count ?? -1
            Log.demo.notice("demo \(self.scenario, privacy: .public): \(marks, privacy: .public) marks")
            try? await Task.sleep(for: .seconds(1))
            return
        }
        if scenario.hasPrefix("paint-quiet") {
            // A tap's fill, as a painter's would land; ready once it has and the bar has faded.
            try? await Task.sleep(for: .seconds(1))
            if let color = session.selectedColor,
               let area = session.template.regions.indices.first(where: { session.colorOf($0) == color && !session.isPainted($0) }) {
                session.paint([area], from: Self.center(session.template, area), animated: true)
            }
            try? await Task.sleep(for: .seconds(1.5))
            return
        }
        if scenario == "paint-hint" {
            try? await Task.sleep(for: .seconds(1.5))
            session.showHint(near: SIMD2(Float(session.template.width), Float(session.template.height)) * 0.5)
            let attached = session.canvas != nil
            Log.demo.notice("demo paint-hint: requested (canvas attached: \(attached, privacy: .public))")
            return
        }
        if scenario == "paint-photo" {
            // Ready once the photo has loaded and faded in.
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(5)
            var opacity: Float = 0
            while clock.now < deadline {
                opacity = (session.canvas as? CanvasView)?.photoOpacity ?? 0
                if opacity >= 0.999 { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            Log.demo.notice("demo paint-photo: photo opacity \(opacity, privacy: .public)")
            return
        }
        if scenario == "paint-tip" || scenario == "paint-tip-fill" {
            // The desk gives the tip its turn once TipKit finds it eligible, and TipKit presents it.
            await PaintTips.awaitDemoTip()
            if scenario == "paint-tip-fill" {
                // Long enough for a UI test, slow on CI, to have found the tip.
                try? await Task.sleep(for: .seconds(12))
                let color = session.selectedColor ?? 0
                if let area = session.template.regions.indices.first(where: { session.colorOf($0) == color && !session.isPainted($0) }) {
                    session.paint([area], from: Self.center(session.template, area), animated: true)
                }
            }
            return
        }
        if scenario == "paint-finish" || scenario.hasPrefix("paint-nightfall"), let last = lastArea {
            try? await Task.sleep(for: .seconds(1.5))
            session.paint([last], from: Self.center(session.template, last), animated: true)
            // Ready once the camera has landed on the whole painting.
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(10)
            var zoom = 0.0
            while clock.now < deadline {
                if let canvas = session.canvas as? CanvasView {
                    zoom = Double(canvas.relativeZoom)
                    if !canvas.isCameraFlying && abs(zoom - 1) < 0.01 { break }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            Log.demo.notice("demo paint-finish: relative zoom \(zoom, privacy: .public)")
            #if UNRELEASED
            if scenario.hasPrefix("paint-nightfall") {
                // Ready at the night's fullest: it falls once the shine has swept.
                while clock.now < deadline + .seconds(20) {
                    if let canvas = session.canvas as? CanvasView, let peak = canvas.nightfallPeak {
                        let wait = peak - CACurrentMediaTime()
                        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                Log.demo.notice("demo paint-nightfall: night at its fullest")
            }
            #endif
            return
        }
        if scenario == "paint-replay" {
            try? await Task.sleep(for: .seconds(1.5))
            (session.canvas as? CanvasView)?.replay()
            // Readiness is signalled on return; the screenshot follows ~2 s later, mid-replay.
            try? await Task.sleep(for: .seconds(1.5))
            return
        }
        if scenario == "paint-book-moon-dark", let target = lastArea {
            try? await Task.sleep(for: .seconds(1.5))
            session.paint([target], from: Self.center(session.template, target), animated: true)
            // Ready at the stars' fullest: they pop as the paint lands, and grow for a third of
            // their time (`CanvasView.popSparkles`), the fill's length known once it is painted.
            let longest = FeedbackEngine.shared.fillDuration
            try? await Task.sleep(for: .seconds(0.8 * longest + 0.35 * 0.7 * Double(fillDurationScale)))
            Log.demo.notice("demo paint-book-moon-dark: painted \(target, privacy: .public), fill \(longest, privacy: .public) s")
            return
        }
        guard scenario == "paint-fill" else { return }
        try? await Task.sleep(for: .seconds(1.5))
        let t = session.template
        // Large regions whose paint reads clearly against the paper, so the front is visible.
        func luminance(_ r: Int) -> Float {
            ColorScience.relativeLuminance(encoded: t.palette[Int(t.regions[r].colorIndex)].rgb, space: t.colorSpace)
        }
        guard let first = t.regions.indices
            .filter({ !session.isPainted($0) && luminance($0) < 0.3 })
            .max(by: { t.regions[$0].area < t.regions[$1].area })
        else { return }
        let color = session.colorOf(first)
        session.select(color: color)
        let targets = t.regions.indices
            .filter { session.colorOf($0) == color && !session.isPainted($0) }
            .sorted { t.regions[$0].area > t.regions[$1].area }
            .prefix(3)
        for r in targets {
            session.paint([r], from: Self.center(t, r), animated: true)
        }
        let canvas = session.canvas as? CanvasView
        Log.demo.notice(
            "demo paint-fill: painted \(Array(targets), privacy: .public) of color \(color, privacy: .public); frames \(canvas?.framesRendered ?? -1, privacy: .public)")
    }

    private static func center(_ t: Template, _ region: Int) -> SIMD2<Float> {
        t.labels(ofRegion: region).first?.position ?? .zero
    }
}

/// A feedback scenario (`paint-feedback*`): the ink feedback starts with (drawn as large as
/// at the zoom it is given), the note, the first mark's comment and whether the review sheet
/// opens. `PaintView` starts it and hands over the draft, which `Demo.run` watches.
@MainActor
final class FeedbackDemo {
    let ink: (_ pointsPerUnit: CGFloat) -> PKDrawing
    let note: String
    let comment: String
    let reviews: Bool
    var draft: FeedbackDraft?

    init(ink: @escaping (_ pointsPerUnit: CGFloat) -> PKDrawing, note: String, comment: String, reviews: Bool) {
        self.ink = ink
        self.note = note
        self.comment = comment
        self.reviews = reviews
    }
}

private nonisolated struct FeedbackDemoKey: EnvironmentKey {
    static let defaultValue: FeedbackDemo? = nil
}

extension EnvironmentValues {
    var feedbackDemo: FeedbackDemo? {
        get { self[FeedbackDemoKey.self] }
        set { self[FeedbackDemoKey.self] = newValue }
    }
}
#endif
