import CoreGraphics
import MosaicEngine
import MosaicKit
import SwiftUI

/// Ravenna's Refine, opened from the new mosaic's preview before it is set: the painter draws on
/// the mosaic with one finger, and it is laid again as they go. Two tools: Lines (a line the
/// tiles' rows follow; Erase rubs the photo's own lines out) and Gold (the gold ground brushed
/// on; Erase takes it off). What is drawn is the recipe's (`MosaicEngine.Mark`, `Recipe.marks`),
/// so the mosaic is made again as it was. Undo takes the last mark back; Cancel, every one drawn
/// since it opened.
///
/// Ravenna's seam: Paint by Moonlight's Refine (`Features/Refine`, a line-art editor) is gone with
/// its line art (issue #13); this is its place in the preview's bar, for a mosaic.
struct MosaicRefineView: View {
    let model: CreateModel
    @Environment(\.dismiss) private var dismiss

    enum Tool: Hashable { case lines, gold }

    @State private var tool: Tool = .lines
    @State private var erasing = false
    @State private var showsPhoto = false
    /// The stroke under the finger, in the panel's unit square.
    @State private var stroke: [SIMD2<Double>] = []
    /// The marks there were when Refine opened: what Cancel goes back to.
    @State private var original: [MosaicEngine.Mark]?

    /// A drawn line's width, as a share of the panel's long side: about an outline the photo's
    /// contours make at the standard count.
    static let lineWidth = 0.004
    /// The eraser's and the gold brush's width on the screen.
    static let brushPoints: CGFloat = 28
    /// Points closer than this (in the panel's unit square) add nothing to a stroke.
    static let pointSpacing = 0.002

    var body: some View {
        NavigationStack {
            wall
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
                .safeAreaInset(edge: .bottom) { controls }
                .navigationTitle("Refine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear { if original == nil { original = model.recipe.marks } }
        .interactiveDismissDisabled()
    }

    // MARK: The wall

    private var mosaicImage: CGImage? {
        guard case .painting(let image)? = model.preview?.picture else { return nil }
        return image
    }

    /// The mosaic (or the photo it is laid from) as large as fits, the marks over it.
    @ViewBuilder
    private var wall: some View {
        if let image = mosaicImage, let mosaic = model.preview?.mosaic, mosaic.width > 0, mosaic.height > 0 {
            let aspect = CGFloat(mosaic.width / mosaic.height)
            GeometryReader { proxy in
                let size = fitted(aspect, in: proxy.size)
                ZStack {
                    picture(image)
                    marks(in: size)
                }
                .frame(width: size.width, height: size.height)
                .contentShape(.rect)
                .gesture(drawing(in: size))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .accessibilityElement()
                .accessibilityLabel(showsPhoto ? Text("The photo") : Text("The mosaic"))
                .accessibilityHint(hint)
                .accessibilityIdentifier("refine-wall")
            }
            .overlay(alignment: .top) { status }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func picture(_ mosaic: CGImage) -> some View {
        if showsPhoto, let photo = model.framed {
            Image(decorative: photo, scale: 1).resizable().interpolation(.high)
        } else {
            Image(decorative: mosaic, scale: 1).resizable().interpolation(.high)
        }
    }

    private func fitted(_ aspect: CGFloat, in room: CGSize) -> CGSize {
        guard room.width > 0, room.height > 0, aspect > 0 else { return .zero }
        return room.width / room.height > aspect
            ? CGSize(width: room.height * aspect, height: room.height)
            : CGSize(width: room.width, height: room.width / aspect)
    }

    /// The lines drawn, which the tiles follow, and the stroke under the finger. Rub-outs and gold
    /// show in the mosaic itself.
    private func marks(in size: CGSize) -> some View {
        let lines = model.recipe.marks.filter { $0.kind == .line }
        let current = stroke, kind = self.kind, brush = brushWidth(in: size)
        return Canvas { context, _ in
            func path(_ points: [SIMD2<Double>]) -> Path {
                var p = Path()
                guard let first = points.first else { return p }
                let at = { (q: SIMD2<Double>) in CGPoint(x: q.x * size.width, y: q.y * size.height) }
                p.move(to: at(first))
                if points.count == 1 { p.addLine(to: at(first)) }
                for q in points.dropFirst() { p.addLine(to: at(q)) }
                return p
            }
            // Faint, so the row of tiles laid along it shows through.
            let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            for mark in lines {
                context.stroke(path(mark.points), with: .color(.white.opacity(0.5)), style: line)
            }
            guard !current.isEmpty else { return }
            let width: CGFloat = kind == .line ? 2 : CGFloat(brush) * max(size.width, size.height)
            let colour: Color = switch kind {
            case .line: .white.opacity(0.9)
            case .gold: Theme.gold.opacity(0.55)
            case .unline, .ungold: .white.opacity(0.3)
            }
            context.stroke(path(current), with: .color(colour),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }

    /// While the mosaic is laid again: a small note at the top, so the wall stays to draw on.
    @ViewBuilder
    private var status: some View {
        if isLaying {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Laying the tiles…")
                    .font(.footnote)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .padding(.top, 8)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private var isLaying: Bool {
        guard let preview = model.preview else { return true }
        return preview.isDraft || preview.recipe != model.recipe || model.phase == .generating
    }

    // MARK: Drawing

    private var kind: MosaicEngine.Mark.Kind {
        switch (tool, erasing) {
        case (.lines, false): .line
        case (.lines, true): .unline
        case (.gold, false): .gold
        case (.gold, true): .ungold
        }
    }

    /// The brush's width as a share of the wall's long side on the screen.
    private func brushWidth(in size: CGSize) -> Double {
        Double(Self.brushPoints / max(max(size.width, size.height), 1))
    }

    private func drawing(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let p = SIMD2(min(max(Double(value.location.x / size.width), 0), 1),
                              min(max(Double(value.location.y / size.height), 0), 1))
                if let last = stroke.last {
                    let d = p - last
                    guard (d * d).sum() >= Self.pointSpacing * Self.pointSpacing else { return }
                }
                stroke.append(p)
            }
            .onEnded { _ in
                let points = stroke
                stroke = []
                guard !points.isEmpty else { return }
                let width = kind == .line ? Self.lineWidth : brushWidth(in: size)
                model.recipe.marks.append(MosaicEngine.Mark(kind: kind, width: width, points: points))
                model.recipeChanged()
            }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                    .labelStyle(.iconOnly)
                    .disabled(model.recipe.marks.isEmpty)
                    .accessibilityIdentifier("refine-undo")
                Picker("Tool", selection: $tool) {
                    Text("Lines").tag(Tool.lines)
                    Text("Gold").tag(Tool.gold)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .accessibilityIdentifier("refine-tool")
                Toggle(isOn: $erasing) {
                    Label("Erase", systemImage: "eraser")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("refine-erase")
                Toggle(isOn: $showsPhoto) {
                    Label("Show the Photo", systemImage: "photo")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .disabled(model.framed == nil)
                .accessibilityIdentifier("refine-photo")
            }
            .font(.title3)
            hint
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var hint: Text {
        switch (tool, erasing) {
        case (.lines, false): Text("Draw a line, and the rows of tiles follow it.")
        case (.lines, true): Text("Rub out the photo’s lines where no outline should be.")
        case (.gold, false): Text("Brush the gold ground where it should be.")
        case (.gold, true): Text("Take the gold ground off where it shouldn’t be.")
        }
    }

    private func undo() {
        guard !model.recipe.marks.isEmpty else { return }
        model.recipe.marks.removeLast()
        model.recipeChanged()
    }

    private func cancel() {
        if let original, original != model.recipe.marks {
            model.recipe.marks = original
            model.recipeChanged()
        }
        dismiss()
    }
}
