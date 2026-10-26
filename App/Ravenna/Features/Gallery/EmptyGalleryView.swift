import SwiftUI

/// Shown when the gallery is empty: an invitation to make the first painting.
struct EmptyGalleryView: View {
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            sketch
                .frame(width: 270, height: 198)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Every painting starts with a photo")
                    .font(.display(.title))
                Text("Turn any photo into a numbered canvas, then bring it to life one color at a time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .containerRelativeFrame(.horizontal) { length, _ in max(0, min(length - 64, 400)) }

            Button(action: onCreate) {
                Label("New Painting", systemImage: "plus")
                    .font(.headline)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .controlSize(.large)
        }
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var sketch: some View {
        #if UNRELEASED
        SelfPaintingSketch()
        #else
        NightSketch()
        #endif
    }
}

/// An unpainted night landscape, outlines and numbers only: moon, stars, mountains, a lake.
/// `paint` paints its three areas (a sketch painting itself, `SelfPaintingSketch`).
private struct NightSketch: View {
    var paint = SketchPaint.none

    /// The drawing's own coordinate space.
    private static let size = CGSize(width: 300, height: 220)

    var body: some View {
        let outline = Theme.outline, gold = Theme.gold, paint = paint
        let moon = Self.moon, mountains = Self.mountains, shore = Self.shore
        Canvas { context, size in
            let s = min(size.width / Self.size.width, size.height / Self.size.height)
            context.scaleBy(x: s, y: s)
            let line = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            let frame = Path(roundedRect: CGRect(x: 1, y: 1, width: 298, height: 218), cornerRadius: 14)

            if paint.isPainting {
                context.drawLayer { layer in
                    layer.clip(to: frame)
                    for area in Area.allCases {
                        let amount = paint.amount(area)
                        guard amount > 0 else { continue }
                        if paint.spreads {
                            // The paint spreads from the area's number, as a fill does on the canvas.
                            let reach = 230 * amount
                            let from = area.number
                            layer.drawLayer { spread in
                                spread.clip(to: Path(ellipseIn: CGRect(x: from.x - reach, y: from.y - reach,
                                                                       width: reach * 2, height: reach * 2)))
                                spread.fill(area.shape, with: .color(area.paint))
                            }
                        } else {
                            layer.fill(area.shape, with: .color(area.paint.opacity(amount)))
                        }
                    }
                }
            }

            context.stroke(frame, with: .color(outline), style: line)
            context.stroke(moon, with: .color(gold), style: line)
            for star in [CGRect(x: 50, y: 30, width: 20, height: 20), CGRect(x: 144, y: 56, width: 12, height: 12)] {
                let shape = Sparkle(pinch: 0).path(in: star)
                context.stroke(shape, with: .color(outline), style: line)
                // The stars come out once the sky is painted.
                if paint.stars > 0 { context.stroke(shape, with: .color(gold.opacity(paint.stars)), style: line) }
            }
            context.stroke(mountains, with: .color(outline), style: line)
            context.stroke(shore, with: .color(outline), style: line)

            for area in Area.allCases {
                // A painted area's number goes, as on the canvas.
                let shows = 1 - paint.amount(area)
                guard shows > 0 else { continue }
                let text = Text(verbatim: "\(area.rawValue)")
                    .font(.system(size: 20, weight: .heavy, design: .serif))
                    .foregroundStyle(.secondary)
                context.drawLayer { label in
                    label.opacity = shows
                    label.draw(text, at: area.number, anchor: .bottom)
                }
            }
        }
    }

    private static let moon = Path(Crescent.cgPath(in: CGRect(x: 206.27, y: 33.73, width: 52, height: 52)))

    private static let ridge = [CGPoint(x: 2, y: 140), CGPoint(x: 70, y: 70), CGPoint(x: 118, y: 118),
                                CGPoint(x: 170, y: 58), CGPoint(x: 240, y: 128), CGPoint(x: 298, y: 98)]

    private static let mountains: Path = {
        var p = Path()
        p.addLines(NightSketch.ridge)
        return p
    }()

    private static let shore: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 2, y: 172))
        p.addCurve(to: CGPoint(x: 298, y: 168), control1: CGPoint(x: 80, y: 158), control2: CGPoint(x: 200, y: 162))
        return p
    }()

    /// The sketch's three areas, by their numbers: the sky (1), the mountains (4) and the lake (2).
    enum Area: Int, CaseIterable {
        case sky = 1, mountains = 4, lake = 2

        /// Where its number stands (the bottom of the digit).
        var number: CGPoint {
            switch self {
            case .sky: CGPoint(x: 110, y: 40)
            case .mountains: CGPoint(x: 168, y: 130)
            case .lake: CGPoint(x: 150, y: 202)
            }
        }

        /// Its paint: a night sky, hills by moonlight and a lake, dark enough for the gold to read
        /// on them in either appearance.
        var paint: Color {
            switch self {
            case .sky: Color(red: 0.24, green: 0.18, blue: 0.36)
            case .mountains: Color(red: 0.43, green: 0.37, blue: 0.55)
            case .lake: Color(red: 0.31, green: 0.40, blue: 0.57)
            }
        }

        /// The area up to its outlines; the sketch's frame clips it.
        var shape: Path {
            var p = Path()
            switch self {
            case .sky:
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: 140))
                for point in NightSketch.ridge { p.addLine(to: point) }
                p.addLine(to: CGPoint(x: 300, y: 98))
                p.addLine(to: CGPoint(x: 300, y: 0))
            case .mountains:
                p.move(to: CGPoint(x: 0, y: 140))
                for point in NightSketch.ridge { p.addLine(to: point) }
                p.addLine(to: CGPoint(x: 300, y: 98))
                p.addLine(to: CGPoint(x: 300, y: 168))
                p.addLine(to: CGPoint(x: 298, y: 168))
                p.addCurve(to: CGPoint(x: 2, y: 172), control1: CGPoint(x: 200, y: 162), control2: CGPoint(x: 80, y: 158))
                p.addLine(to: CGPoint(x: 0, y: 172))
            case .lake:
                p.move(to: CGPoint(x: 0, y: 172))
                p.addLine(to: CGPoint(x: 2, y: 172))
                p.addCurve(to: CGPoint(x: 298, y: 168), control1: CGPoint(x: 80, y: 158), control2: CGPoint(x: 200, y: 162))
                p.addLine(to: CGPoint(x: 300, y: 168))
                p.addLine(to: CGPoint(x: 300, y: 220))
                p.addLine(to: CGPoint(x: 0, y: 220))
            }
            p.closeSubpath()
            return p
        }
    }
}

/// How far the sketch has painted itself: each area's paint from 0 to 1, and the stars' gold.
private struct SketchPaint {
    var sky = 0.0, mountains = 0.0, lake = 0.0, stars = 0.0
    /// Paint spreads from each number (false: it fades in where it lies, under Reduce Motion).
    var spreads = true

    static let none = SketchPaint()
    static let painted = SketchPaint(sky: 1, mountains: 1, lake: 1, stars: 1)

    var isPainting: Bool { sky > 0 || mountains > 0 || lake > 0 }

    func amount(_ area: NightSketch.Area) -> Double {
        switch area {
        case .sky: sky
        case .mountains: mountains
        case .lake: lake
        }
    }
}

#if UNRELEASED
/// The empty gallery's sketch paints itself once a launch, about two seconds, the first time the
/// empty gallery appears (Paul, October 18, 2026: "Build both please, then let me see"; the Lamplit Table's
/// round `pieces/intro-animation`): the sky, the mountains and the lake in turn, each spreading
/// from its number as a fill does, then the two stars come out in gold. It ends painted and stays
/// so. Reduce Motion fades the paint in where it lies, all at once. In SideStore and Debug
/// builds only for now (`UNRELEASED`).
private struct SelfPaintingSketch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var isDone = false
    #if DEBUG
    /// `-introWaitsForTap YES` holds the sketch unpainted until a tap on it: the painting runs by
    /// the clock from when the sketch appears, and a slow simulator can let it finish before a UI
    /// test's first frame (`NightfallUITests`).
    @State private var isHeld = UserDefaults.standard.bool(forKey: "introWaitsForTap")
    #endif

    /// It painted itself already this launch: it shows painted.
    private static var hasPainted = false

    /// When each area starts and ends (seconds after the sketch appears), and the stars.
    private static let sky = (0.35, 0.95), mountains = (0.8, 1.4), lake = (1.25, 1.85), stars = (1.7, 2.2)
    private static let still = (0.3, 0.9)
    private var duration: Double { (reduceMotion ? Self.still.1 : Self.stars.1) * Self.slowdown }

    var body: some View {
        let painted = isDone || Self.hasPainted
        TimelineView(.animation(paused: start == nil || painted)) { timeline in
            NightSketch(paint: painted ? .painted : paint(at: start.map { timeline.date.timeIntervalSince($0) / Self.slowdown } ?? 0))
        }
        #if DEBUG
        .onTapGesture { isHeld = false }
        #endif
        .task(id: waits) {
            guard !waits, !isDone, !Self.hasPainted else { return }
            start = .now
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            isDone = true
            Self.hasPainted = true
            #if DEBUG
            // `gallery-empty`'s screenshot shows the sketch painted.
            if ShellDemo.current == .galleryEmpty { DemoMode.markReady() }
            #endif
        }
    }

    /// Held by a UI test (Debug only): it waits for the tap.
    private var waits: Bool {
        #if DEBUG
        return isHeld
        #else
        return false
        #endif
    }

    private func paint(at t: Double) -> SketchPaint {
        func eased(_ span: (Double, Double)) -> Double {
            let x = min(1, max(0, (t - span.0) / (span.1 - span.0)))
            return x * x * (3 - 2 * x)
        }
        if reduceMotion {
            let all = eased(Self.still)
            return SketchPaint(sky: all, mountains: all, lake: all, stars: all, spreads: false)
        }
        return SketchPaint(sky: eased(Self.sky), mountains: eased(Self.mountains), lake: eased(Self.lake),
                           stars: eased(Self.stars))
    }

    /// Debug launches stretch it with `-introSlowdown <factor>`, for UI tests that take frames.
    private static let slowdown: Double = {
        #if DEBUG
        let factor = UserDefaults.standard.double(forKey: "introSlowdown")
        return factor > 0 ? factor : 1
        #else
        1
        #endif
    }()
}
#endif
