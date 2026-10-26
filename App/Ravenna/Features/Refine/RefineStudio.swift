import Foundation
import PaintCore
import SwiftUI

/// The Refine Toolbox's groups of tools (the design:
/// claude.ai/artifact/1RuRF7GYbjagg8AJHrVhUH, Paul, October 21, 2026: "a drawing app with the
/// tools to make a paint by number"). Ink is the lines the painter sees, Cells the shapes of the
/// color areas, Paint what color each is, Numbers where they sit, and See what shows: each tool
/// does one visible thing.
/// On iPad every tool stands in a rail, a section per group; on iPhone the groups are tabs over a
/// row of the group's tools (at most five, so a phone's width holds them).
nonisolated enum RefineGroup: Hashable, CaseIterable {
    case ink, cells, paint, numbers, see

    /// The group's tools, in their order on screen.
    var tools: [RefineTool] {
        switch self {
        case .ink: [.pen, .shape, .bendLine, .eraser, .smartEraser]
        case .cells: [.select, .cellEdge, .merge, .moveEdge, .fill]
        case .paint: [.bucket, .brush, .eyedropper, .editPaint, .looks]
        case .numbers: [.moveNumber]
        case .see: [.text, .tryPainting]
        }
    }

    /// The group `tool` is in.
    static func of(_ tool: RefineTool) -> RefineGroup {
        allCases.first { $0.tools.contains(tool) } ?? .ink
    }
}

/// An area a long press picked, for its card (`RefineAreaCard`).
nonisolated struct RefineAreaPick: Identifiable, Equatable {
    let id = UUID()
    /// Where the press was, normalized to the picture (0…1).
    let point: SIMD2<Float>
    /// The same point in the template's canvas units.
    let at: SIMD2<Float>
}

/// An area's card, from a long press on it with any tool: its paint, how many areas share it, a
/// new color for this area alone (Only This Area: the eyes the generator gave the sky's blue, in a
/// blue of their own while the sky stays), or another of the painting's paints for it, and the
/// other areas of its paint, glowing (`RefinePaintGlow`). A popover beside the area on iPad, a
/// sheet on iPhone, as the Lamplit Table read its split vote (`factory/pieces/refine-studio`).
struct RefineAreaCard: View {
    /// The template on screen.
    let template: Template
    /// The press, in canvas units.
    let at: SIMD2<Float>
    /// The area's own new color (OKLab): a paint of its own (`TemplateEditor.Edit.paintArea`).
    let paintArea: (SIMD3<Float>) -> Void
    /// The paint's new color (OKLab), from `from`, when the area is its paint's only one.
    let repaint: (_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> Void
    /// Shows every area of a paint (Edit Paint, with it the current paint).
    let showPaint: (Int) -> Void

    @Environment(\.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Whether the area shared its paint when the card opened: the picker then gives it a paint of
    /// its own, else it repaints its paint, from `from`.
    @State private var isolates: Bool?
    @State private var from: SIMD3<Float>?
    /// The picker's last color, laid once it has rested a moment.
    @State private var pending: Task<Void, Never>?

    private var region: Int? { template.region(at: at) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let region {
                let paint = Int(template.regions[region].colorIndex)
                let count = Self.areaCount(of: paint, in: template)
                header(paint: paint, count: count)
                ColorPicker(selection: color(paint: paint), supportsOpacity: false) {
                    Label {
                        if isolates ?? (count > 1) { Text("Only This Area") } else { Text("Color") }
                    } icon: {
                        Image(systemName: "drop.halffull")
                    }
                }
                .accessibilityHint(Text(isolates ?? (count > 1)
                    ? String(localized: "refine.card.only.hint", defaultValue: "Gives this area a color of its own; the other areas of its paint keep theirs.",
                             comment: "Refine screen, an area's card: VoiceOver hint of Only This Area, a color picker that gives the pressed area a paint of its own")
                    : String(localized: "refine.card.color.hint", defaultValue: "Gives this paint a new color.",
                             comment: "Refine screen, an area's card: VoiceOver hint of Color, a color picker for the paint of an area that is its paint's only area")))
                .accessibilityIdentifier("refine-card-color")
                paints(current: paint)
                if count > 1 {
                    Button {
                        showPaint(paint)
                    } label: {
                        Label { Text("Show Its Other Areas") } icon: { Image(systemName: "sparkle.magnifyingglass") }
                    }
                    .accessibilityHint(Text(String(
                        localized: "refine.card.others.hint", defaultValue: "Shows every area of this paint, glowing, in Paints.",
                        comment: "Refine screen, an area's card: VoiceOver hint of Show Its Other Areas, which opens Paints with the area's paint picked")))
                    .accessibilityIdentifier("refine-card-others")
                }
            }
        }
        .padding(20)
        .frame(minWidth: typeSize.isAccessibilitySize ? nil : 300, maxWidth: 420, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationCompactAdaptation(.sheet)
        .onAppear(perform: begin)
        .onDisappear { pending?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("refine-card")
    }

    private func header(paint: Int, count: Int) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: "\(paint + 1)")
                .font(.display(.title3))
                .monospacedDigit()
                .foregroundStyle(PaletteBar.numeralInk(template, paint))
                .frame(width: 44, height: 44)
                .background(Circle().fill(PaletteBar.paint(template, paint)))
                .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ColorNameText.title(template.palette[paint].colorName))
                    .font(.display(.title3))
                Text(Self.subtitle(paint: paint, count: count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Paint 1 · 3 areas".
    nonisolated static func subtitle(paint: Int, count: Int) -> String {
        let number = (paint + 1).formatted(), areas = TemplateCounts.areas(count)
        return String(
            localized: "refine.card.paint", defaultValue: "Paint \(number) · \(areas)",
            comment: "Refine screen, an area's card: under the paint's color name, its number (formatted), then how many areas have that paint (\"3 areas\")")
    }

    /// The painting's other paints, one of which the area may take instead.
    private func paints(current: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or Use a Paint")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(template.palette.indices.filter { $0 != current }, id: \.self) { index in
                        Button {
                            FeedbackEngine.shared.selectionChanged()
                            pending?.cancel()
                            paintArea(template.palette[index].oklab)
                        } label: {
                            Text(verbatim: "\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .serif))
                                .monospacedDigit()
                                .foregroundStyle(PaletteBar.numeralInk(template, index))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(PaletteBar.paint(template, index)))
                                .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(ColorNameText.numbered(number: index + 1, name: template.palette[index].colorName)))
                        .accessibilityHint(Text(String(
                            localized: "refine.card.use.hint", defaultValue: "Gives this area this paint.",
                            comment: "Refine screen, an area's card: VoiceOver hint of one of the painting's paints, which the pressed area takes")))
                        .accessibilityIdentifier("refine-card-paint-\(index + 1)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The number of areas `paint` has on `template`.
    nonisolated static func areaCount(of paint: Int, in template: Template) -> Int {
        template.regions.reduce(0) { $0 + (Int($1.colorIndex) == paint ? 1 : 0) }
    }

    private func begin() {
        guard isolates == nil, let region else { return }
        let paint = Int(template.regions[region].colorIndex)
        isolates = Self.areaCount(of: paint, in: template) > 1
        from = template.palette[paint].oklab
    }

    /// The area's color as the picker shows it; a color picked is laid once the picker rests a
    /// moment, so a drag across the spectrum doesn't queue an edit per step (Colors' way).
    private func color(paint: Int) -> Binding<Color> {
        Binding(
            get: { PaletteBar.paint(template, paint) },
            set: { color in
                let resolved = color.resolve(in: environment)
                let to = ColorScience.linearSRGBToOKLab(SIMD3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue))
                let isolates = isolates ?? true, from = from
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    if isolates {
                        paintArea(to)
                    } else if let from {
                        repaint(from, to)
                    }
                }
            })
    }
}

/// Two gold sparkles where a line closed off an area of its own, the fill moment's (by Moon its
/// stars): they pop in, rest and fade within about a second, never larger than the shape on
/// screen and never a flash ("a firefly, not a camera", the Child at Bedtime). Not shown under
/// Reduce Motion.
struct RefineSparkles: View {
    /// Where the line's ends met, on screen.
    let point: CGPoint
    /// The shape's smaller side on screen, which the sparkles stay within.
    let extent: CGFloat
    let stars: Bool

    @State private var phase = 0

    var body: some View {
        let size = min(22, max(8, extent * 0.5))
        ZStack {
            sparkle(size).offset(x: size * 0.45, y: -size * 0.6)
            sparkle(size * 0.62).offset(x: -size * 0.55, y: size * 0.45)
        }
        .scaleEffect(phase == 0 ? 0.2 : phase == 1 ? 1 : 0.85)
        .opacity(phase == 1 ? 1 : 0)
        .position(point)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { phase = 1 }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeIn(duration: 0.35)) { phase = 2 }
        }
    }

    private func sparkle(_ side: CGFloat) -> some View {
        RefineSparkleShape(star: stars)
            .fill(Theme.gold)
            .frame(width: side, height: side)
    }
}

/// The design system's sparkle, or by Moon its star (`Sparkle.starPath`).
nonisolated struct RefineSparkleShape: Shape {
    var star: Bool

    func path(in rect: CGRect) -> Path {
        Path(star ? Sparkle.starPath(in: rect) : Sparkle.cgPath(in: rect))
    }
}

/// The areas whose numbers are near the smallest a painter can read: within a quarter of their
/// floor (`LabelSizing.minimumRadius(digits:detail:)`, a detail area's its own). The Studio's
/// badge counts them, and a tap on it brings the next one up close; none, no badge.
nonisolated enum RefineTinyAreas {
    /// How near the floor a number is to count: a quarter above it.
    static let margin: Float = 1.25

    /// The tiny areas of `template`, top to bottom, left to right, each with its number's spot.
    static func find(in template: Template) -> [(region: Int, label: PaintCore.Label)] {
        var found: [(region: Int, label: PaintCore.Label)] = []
        for region in template.regions.indices {
            guard let label = template.labels(ofRegion: region).max(by: { $0.radius < $1.radius }) else { continue }
            let digits = LabelSizing.digitCount(colorIndex: template.regions[region].colorIndex)
            let floor = LabelSizing.minimumRadius(digits: digits, detail: template.isDetailRegion(region))
            if label.radius < floor * margin { found.append((region, label)) }
        }
        return found.sorted {
            ($0.label.position.y, $0.label.position.x) < ($1.label.position.y, $1.label.position.x)
        }
    }

    /// The part of the picture (normalized) to zoom to for `label`: a few numbers' room around
    /// it, at least a twentieth of the picture across.
    static func focus(on label: PaintCore.Label, in template: Template) -> CGRect {
        let width = Float(max(template.width, 1)), height = Float(max(template.height, 1))
        let side = max(label.radius * 16, max(width, height) / 20)
        return CGRect(
            x: CGFloat((label.position.x - side / 2) / width), y: CGFloat((label.position.y - side / 2) / height),
            width: CGFloat(side / width), height: CGFloat(side / height))
    }
}
