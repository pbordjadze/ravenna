import PaintCore
import SwiftUI

/// Refine's Looks (`RefineTool.looks`): the looks, in a row; a look lays itself on every paint,
/// and a Strength slider softens it once one is chosen. And Edit Paint (`RefineTool.editPaint`):
/// the current paint (picked in the palette, `RefinePaletteBar`, or by a tap on its area) takes a
/// new color from the system color picker, its family moving with it while Similar Colors Too is
/// on. Shapes, lines and numbers never change.
/// The Lamplit Table decided the details (October 18, 2026: `factory/pieces/recolor` on
/// `claude/vibe-factory`): the row always shown, Moonlit first and the row turning from night to
/// day, the slider, the family on, the painters' names; then Paul (October 18): five looks, not
/// eight, the rest kept for later (`offered`).
struct RefineColorsPanel: View {
    /// The looks the row offers, after Photo: night to day, then a painter's. Sepia, Water Lilies
    /// and Great Wave stay in PaintCore, kept for later (Paul: "save the other 3 in case we want
    /// them later"); adding one here brings it back.
    nonisolated static let offered: [TemplateEditor.Look] = [.moonlit, .goldenHour, .pastel, .garden, .starryNight]

    /// What the panel shows.
    enum Mode { case looks, paint }

    /// The template on screen.
    let template: Template
    /// The paints before any edit, which the looks' chips show themselves on.
    let paintsBefore: [PaletteColor]
    /// The edits the template on screen has: the look it shows, and whether any color changed.
    let edits: [TemplateEditor.Edit]
    let mode: Mode
    /// The paint picked (an index of `template.palette`).
    @Binding var paint: Int?
    @Binding var family: Bool
    let change: (RefineColors) -> Void

    @Environment(\.self) private var environment
    @State private var strength: Float = 1
    /// The picked paint's color when it was picked: a repaint's `from` while the picker moves.
    @State private var from: SIMD3<Float>?
    /// The picker's last color, laid once it has rested a moment.
    @State private var pending: Task<Void, Never>?

    /// The look the painting has, nil for none.
    private var look: (look: TemplateEditor.Look, strength: Float)? { RefineColors.look(in: edits) }

    /// Whether the painting is in the photo's own colors: no look, no repaint.
    private var inPhotoColors: Bool { RefineColors.withoutColors(edits).count == edits.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .looks { looks } else { picker }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .frame(maxWidth: 720)
        .onAppear {
            strength = look?.strength ?? 1
            pick(paint)
        }
        .onChange(of: look?.strength) { _, new in strength = new ?? 1 }
        .onChange(of: paint) { _, new in pick(new) }
        // A look or Photo changed the paints: the next repaint starts from the color shown. Only
        // this picker's own repaint, still moving, keeps the color it started from.
        .onChange(of: template.palette) { _, _ in
            if case .repaint(let started, _, _)? = edits.last, started == from { return }
            pick(paint)
        }
        .onDisappear { pending?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("refine-colors")
    }

    @ViewBuilder
    private var looks: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                chip(nil)
                ForEach(Self.offered, id: \.self) { chip($0) }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Looks"))
        if look != nil {
            HStack(spacing: 12) {
                Text("Strength")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Slider(value: $strength, in: 0...1, onEditingChanged: { editing in
                    if !editing, let look { change(.look(look.look, strength: strength)) }
                })
                .tint(Theme.signature)
                .accessibilityLabel(Text("Strength"))
                .accessibilityValue(Text(Double(strength).formatted(.percent.precision(.fractionLength(0)))))
                .accessibilityIdentifier("refine-colors-strength")
            }
        }
    }

    /// The current paint's color, and its family's.
    @ViewBuilder
    private var picker: some View {
        if let paint, paint < template.palette.count {
            HStack(spacing: 12) {
                Text(Self.paintTitle(paint))
                    .font(.footnote.weight(.semibold))
                ColorPicker(selection: color(of: paint), supportsOpacity: false) { Text("Color") }
                    .labelsHidden()
                    .accessibilityIdentifier("refine-colors-picker")
                Spacer(minLength: 8)
                Toggle(isOn: $family) { Text("Similar colors too") }
                    .font(.footnote)
                    .fixedSize()
                    .tint(Theme.signature)
                    .accessibilityIdentifier("refine-colors-family")
            }
        } else {
            Text("Pick a paint in the palette, or tap an area.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Looks

    /// A look's chip (nil: the photo's colors): four of the painting's paints in it, darkest to
    /// lightest, and its name.
    private func chip(_ kind: TemplateEditor.Look?) -> some View {
        let selected = kind == nil ? inPhotoColors : look?.look == kind
        let colors = Self.preview(of: kind, on: paintsBefore)
        return Button {
            guard !selected else { return }
            FeedbackEngine.shared.selectionChanged()
            strength = 1
            change(kind.map { .look($0, strength: 1) } ?? .photo)
        } label: {
            VStack(spacing: 6) {
                Self.quarters(colors)
                    .frame(width: 44, height: 44)
                    .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                    .padding(3)
                    .overlay { Circle().stroke(selected ? Theme.signature : .clear, lineWidth: 2.5) }
                Self.name(of: kind)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(of: kind))
        .accessibilityHint(Text(kind == nil
            ? String(localized: "refine.colors.photo.hint", defaultValue: "Puts the photo’s own colors back.",
                     comment: "Refine screen, Colors: VoiceOver hint of the Photo chip, which takes every look and new color out")
            : String(localized: "refine.colors.look.hint", defaultValue: "Lays this look on every paint.",
                     comment: "Refine screen, Colors: VoiceOver hint of a look's chip (Moonlit, Starry Night, …)")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-look-\(kind?.rawValue ?? "photo")")
        .accessibilityShowsLargeContentViewer { Self.name(of: kind) }
    }

    /// Four of `palette`'s paints, darkest to lightest, in `look` (nil: as they are).
    nonisolated static func preview(of look: TemplateEditor.Look?, on palette: [PaletteColor]) -> [Color] {
        let sorted = palette.sorted { $0.oklab.x < $1.oklab.x }
        guard !sorted.isEmpty else { return [] }
        let edit = look.map { TemplateEditor.look($0, strength: 1, paints: palette) }
        return (0..<4).map { i in
            let paint = sorted[i * (sorted.count - 1) / 3]
            let lab = edit.map { TemplateEditor.recolor(paint.oklab, by: $0) } ?? paint.oklab
            let rgb = ColorScience.okLabToEncoded(lab, space: .sRGB)
            return Color(.sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
        }
    }

    private static func quarters(_ colors: [Color]) -> some View {
        ZStack {
            ForEach(colors.indices, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(i) / 4, to: CGFloat(i + 1) / 4)
                    .stroke(colors[i], lineWidth: 22)
                    .padding(11)
            }
        }
        .rotationEffect(.degrees(-90))
        .clipShape(Circle())
    }

    static func name(of look: TemplateEditor.Look?) -> Text {
        switch look {
        case nil: Text("Photo")
        case .moonlit: Text("Moonlit")
        case .goldenHour: Text("Golden Hour")
        case .pastel: Text("Pastel")
        case .sepia: Text("Sepia")
        case .garden: Text("Garden")
        case .starryNight: Text("Starry Night")
        case .waterLilies: Text("Water Lilies")
        case .greatWave: Text("Great Wave")
        }
    }

    // MARK: Paints

    static func paintTitle(_ index: Int) -> String {
        String(localized: "refine.colors.paint", defaultValue: "Paint \(index + 1)",
               comment: "Refine screen, Colors: the paint picked to take a new color, by its number; the argument is the number")
    }

    /// The picked paint's color as the picker shows it; a color picked is laid once the picker
    /// rests a moment, so a drag across the spectrum doesn't queue an edit per step.
    private func color(of index: Int) -> Binding<Color> {
        Binding(
            get: { PaletteBar.paint(template, index) },
            set: { color in
                guard let from else { return }
                let resolved = color.resolve(in: environment)
                let to = ColorScience.linearSRGBToOKLab(SIMD3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue))
                let family = family
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    change(.repaint(from: from, to: to, family: family))
                }
            })
    }

    private func pick(_ index: Int?) {
        pending?.cancel()
        from = index.flatMap { $0 < template.palette.count ? template.palette[$0].oklab : nil }
    }
}
