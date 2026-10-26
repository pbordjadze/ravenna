import Accessibility
import Foundation
import PaintCore
import SwiftUI

/// What one finger (or the Pencil) does on the Refine screen.
nonisolated enum RefineTool: Hashable {
    /// Draws lines as they are drawn.
    case pen
    /// Draws the shape picked (`RefineShape`) across a drag.
    case shape
    /// Rubs out what it touches; a tap takes out a dab.
    case eraser
    /// Rubs lines out, or takes out the one tapped, junction to junction (`LineChains`).
    case smartEraser
    /// A tap makes the closed shape under it an area of its own in the photo's color there, or
    /// clears that again (`EditFills`).
    case fill
    /// The text the app found corrected: a tap turns a found line off or on again, a drag marks
    /// one it missed.
    case text
    /// The Toolbox's Select: a tap picks the cell under it, which shows its outline and a bar
    /// with its paint (`RefineSelectionBar`); a tap on it again lets it go.
    case select
    /// The Toolbox's Cell Edge: a stroke divides a cell where it goes and draws no line, both
    /// sides keeping the paint (`TemplateEditor.Edit.cellEdge`).
    case cellEdge
    /// The Toolbox's Merge: a drag across cells joins them into the first, boundaries and all
    /// (`TemplateEditor.Edit.merge`).
    case merge
    /// The Toolbox's Paint Brush: the stroke's footprint takes the current paint, joining the
    /// cells of that paint it meets (`TemplateEditor.Edit.brush`); a tap is a dab.
    case brush
    /// The Toolbox's Bucket: a tap gives the cell under it the current paint
    /// (`TemplateEditor.Edit.paintArea`).
    case bucket
    /// The Toolbox's Eyedropper: a tap makes the cell's paint the current paint, or over the
    /// photo the photo's color there.
    case eyedropper
    /// The Toolbox's Edit Paint: the current paint takes a new color everywhere it's used
    /// (`RefineColorsPanel`'s picker); a tap on a cell makes its paint the current one.
    case editPaint
    /// The Toolbox's Looks over every paint (`RefineColorsPanel`'s row).
    case looks
    /// The Toolbox's Bend Line: a drag moves the line under it, bending it near where it was
    /// grabbed (`TemplateEditor.Edit.reshape`).
    case bendLine
    /// The Toolbox's Move Edge: a drag moves a cell's boundary, inked or not, so the cell and its
    /// neighbour change shape (`TemplateEditor.Edit.reshape`, as Bend Line's).
    case moveEdge
    /// The Toolbox's Move Number: a drag moves a number within its cell
    /// (`TemplateEditor.Edit.moveLabel`).
    case moveNumber
    /// The Toolbox's Try Painting: the painting screen on the template as it stands, saving
    /// nothing. An action, never the finger's tool.
    case tryPainting

    /// The tool the Pencil's double tap switches to: a drawing tool's eraser, an eraser's pen.
    var pencilPartner: RefineTool? {
        switch self {
        case .pen, .shape: .eraser
        case .eraser, .smartEraser: .pen
        case .fill, .text, .select, .cellEdge, .merge, .brush, .bucket, .eyedropper, .editPaint, .looks, .bendLine,
             .moveEdge, .moveNumber, .tryPainting:
            nil
        }
    }

    /// What the tool does shows in the painting (paints, and a cell edge, which draws no line), so
    /// the painting shows beneath it.
    /// The tool drags something already there (a line, an edge, a number), drawing no ink.
    var drags: Bool { self == .bendLine || self == .moveEdge || self == .moveNumber }

    var paints: Bool {
        self == .cellEdge || self == .brush || self == .bucket || self == .editPaint || self == .looks
    }

    var erases: Bool { self == .eraser || self == .smartEraser }
}

/// What shows beneath the drawing on the Refine screen.
nonisolated enum RefineBackdrop: Hashable {
    /// The drawing's paper.
    case paper
    /// The photo.
    case photo
    /// The template painted, every area in its paint: the picture once it's finished.
    case painting
    /// The photo, with the painting over it as faint as the Toolbox's slider makes it, for
    /// tracing (`RefineView.photoShows`).
    case photoBehind
}

/// The create flow's optional Refine step (`TemplateRefinements`): the drawing large, on its
/// paper, over the photo or over the painting finished (every area in its paint), where one
/// finger draws lines and takes them out, and two fingers zoom and move; a tap of two fingers
/// undoes. What the painter does is made by hand to the template (PaintCore's `TemplateEditor`,
/// `CreateModel.edit(_:)`): no image processing, no new template. A line is the line drawn, as the
/// outline of the areas it closes too, and nothing the painter didn't touch changes:
/// - the Pen draws a line as drawn (smoothed as it showed); only an end whose ink touches a
///   line's moves onto it, by no more than the ink's width, so the cell closes as it looks
///   (`PenAssist`); the sides of the areas it cuts that the photo tells apart take their own
///   paints;
/// - Shapes draws a straight line, a rectangle, an oval or a curve across a drag
///   (`RefineShape`, `ShapePath`), shown as it will be while the finger is down; a line's or a
///   curve's ends move onto a line their ink touches, as the Pen's do;
/// - the Eraser rubs out what it touches (ink within its reach is cut at the edge of it), and a
///   tap takes out a dab;
/// - the Line Eraser rubs too, and a tap takes the line out from junction to junction;
/// - Fill: a tap inside a closed shape makes it an area of its own, painted the photo's color
///   where it was tapped (`LineEdit.photoColor`), kept however small, its number allowed down to
///   about half the usual size and read zoomed in (a detail area, `Template.detailRegions`); a
///   tap in a filled area clears it (`EditFills`). A shape left open fills the area around it,
///   which shows at once, and Undo takes it back. Refine zooms in far
///   (`RefineSurfaceView.maximumZoom`), so a Pencil outlines a star of a few pixels comfortably.
/// An edit the template can't take (a line that doubles back on itself) changes nothing and says
/// so, in a toast VoiceOver announces; so does a shape a line closed that has no room for a
/// number (the line stays).
/// Once an Apple Pencil touches the canvas (or with Only Draw with Apple Pencil on), the Pencil
/// draws and taps and one finger moves the picture, so a palm leaves no mark; its double tap
/// switches between drawing and the Eraser. Photo and Painting show the photo, or the template
/// painted (every area in its paint, `TemplateRasterizer.Style.paintedAreas`), beneath the
/// drawing: the painting the changes make, once the template has them. Text corrects the text the
/// app found (a tap turns a found line off or on again, a drag across a line marks it).
///
/// An edit lands in a few hundredths of a second, off the main actor, and the screen then shows
/// the new template with no crossfade; until it does, the edit shows over the last template in the
/// drawing's own ink (`RefineInkLayer`), so a line is there the moment it is drawn and gone the
/// moment it is erased, and a fill shows as a swatch of its color where it was tapped
/// (`RefineFillLayer`, which then tints the areas fills made in their paint, under the drawing).
/// The text corrections still make the template again, as the sliders do, and the edits are laid
/// on the new one. Undo and Redo (⌘Z, ⇧⌘Z) step through the changes
/// (`CreateModel.history`; an edit taken back or put back comes at once from the templates kept),
/// Cancel puts back what the screen opened with, Done keeps them.
///
/// The tools are laid out as the Toolbox, a drawing app's:
/// Ink, Cells, Paint, Numbers and See, every tool in a rail on iPad and in group tabs on iPhone; a
/// Pen of ink alone with Snap and Color from Photo, Bend Line, Select, Cell Edge, Merge, Move Edge,
/// a palette with a current paint, the Bucket, the Paint Brush, the Eyedropper, Edit Paint and
/// Looks, Move Number, Try Painting; Start From until the first edit
/// (the generator's template, or the photo as one area to draw and paint everything on); an area's
/// card on a long press, sparkles where a line closes off an area and a badge for numbers near their
/// floor (`RefineStudio.swift`, `RefineToolbox.swift`, App/CLAUDE.md › Create flow › The Toolbox).
struct RefineView: View {
    let model: CreateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @State private var tool: RefineTool
    @State private var shape = RefineShape.line
    @State private var backdrop = RefineBackdrop.paper
    /// The template on screen painted, for `RefineBackdrop.painting`, with its preview's id.
    @State private var painting: (preview: UUID, image: CGImage)?
    /// The template the screen draws over: the newest at full resolution.
    @State private var base: CreateModel.Preview?
    /// The edits sent that `base` doesn't show yet, which the screen draws over it.
    @State private var submitted: [Submitted] = []
    /// The pen's line or the eraser's pass under the finger, until it lifts; for Shapes, where
    /// the drag began and where the finger is.
    @State private var trace: [SIMD2<Float>]?
    /// The lines a pen's ends may join, as its stroke began.
    @State private var snapLines: SnapLines?
    /// A curve's ends, drawn and waiting for the drag that bends it.
    @State private var curve: (from: SIMD2<Float>, to: SIMD2<Float>)?
    /// The line of text being dragged out: where the drag began and where it is.
    @State private var marking: (SIMD2<Float>, SIMD2<Float>)?
    /// The line the eraser was last tapped on, which flashes as it goes.
    @State private var tapped: [SIMD2<Float>]?
    @State private var flashes = false
    /// Where the picture is in the canvas, and its zoom (the touch surface's).
    @State private var picture: CGRect = .zero
    @State private var zoom: CGFloat = 1
    @State private var canvasSize: CGSize = .zero
    /// The tallest the tools along the bottom have been, the least room they keep: picking a tool
    /// with a shorter bar no longer grows the canvas, nor a taller one (once seen) shrinks it, so
    /// the picture neither moves under the finger nor loses its zoom (the exploratory QA of
    /// October 21 tapped where it had been).
    @State private var toolsHeight: CGFloat = 0
    /// Edit Paint's family follows the current paint while it is on.
    @State private var colorFamily = true
    /// A part of the picture the touch surface is to bring up close.
    @State private var focus: RefineFocus?
    #if DEBUG
    /// The demo's paint, cell or card is picked once its edits have landed.
    @State private var didPickDemoPaint = false
    #endif
    /// The screen has begun refining (`CreateModel.beginRefining`), once.
    @State private var opened = false
    /// How plainly the photo shows through the painting in Photo Behind: 0 the painting, 1 the photo.
    @State private var photoShows = 0.5
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Whether a line's ends join the lines their ink touches (`PenAssist`): the Toolbox's Snap.
    @AppStorage(SettingsKey.refineSnaps) private var snaps = SettingsDefault.refineSnaps
    /// Whether a drawn line gives the pieces it cuts the photo's colors (`TemplateEditor.painted`):
    /// the Toolbox's Color from Photo, off, so the Pen draws ink alone.
    @AppStorage(SettingsKey.refinePenColors) private var penColors = SettingsDefault.refinePenColors
    /// The Paint Brush's Size: its radius on screen, in points.
    @AppStorage(SettingsKey.refineBrushSize) private var brushSize = SettingsDefault.refineBrushSize
    /// The current paint (OKLab, as on screen): the Bucket gives it, the palette, the Eyedropper
    /// and Edit Paint pick it. A color no paint has yet becomes one with the first Bucket tap.
    @State private var currentPaint: SIMD3<Float>?
    /// The cell Select picked, by a point in it (canvas units), so it follows its region through
    /// edits.
    @State private var selection: SIMD2<Float>?
    /// The undrawn edges of the template on screen, made once per template (`RefineCellEdges`).
    @State private var cellEdges: (id: UUID, path: Path)?
    /// Try Painting's painting, while it is open.
    @State private var trial: RefineTrial?
    /// The Studio's group on screen (`RefineGroup`), and the tool last picked in each.
    @State private var group = RefineGroup.ink
    @State private var lastTool: [RefineGroup: RefineTool] = [:]
    /// The area a long press opened the card of (`RefineAreaCard`).
    @State private var card: RefineAreaPick?
    /// The sparkles where a line closed off an area last: the line's number, where its ends met
    /// on screen, and the shape's smaller side on screen.
    @State private var sparkles: (id: Int, point: CGPoint, extent: CGFloat)?
    /// What a Merge drag joins, lit while the finger is down: the probe of the template on screen
    /// (with its preview's id), the areas found for the drag so far, and the drag waiting for
    /// the probe while it works on an earlier one.
    @State private var mergeProbe: (preview: UUID, probe: TemplateEditor.MergeProbe)?
    @State private var mergeAreas: [Int] = []
    @State private var mergeWanted: [SIMD2<Float>]?
    @State private var mergeProbing = false
    /// The Merge drag the lit areas are for: one found for an earlier drag never lights this one.
    @State private var mergeStroke = 0
    /// The areas whose numbers are near the smallest (`RefineTinyAreas`), and the one shown last.
    @State private var tiny: [(region: Int, label: PaintCore.Label)] = []
    @State private var tinyShown = -1
    /// A Tool Guide page's practice canvas (`RefineGuideView`): the tool it teaches over the
    /// practice picture, with Undo, Redo, the views and Reset above it in place of the screen's
    /// bars, and none of the other tools.
    private let practice: RefinePracticeSetup?
    /// Reset on a practice canvas: the page makes the canvas again, from the picture.
    private let onReset: (() -> Void)?
    /// The Tool Guide, open at a page.
    @State private var guide: RefineGuideTopic?

    init(model: CreateModel) {
        self.init(model: model, practice: nil)
    }

    /// Refine, or with `practice` a Tool Guide page's practice canvas on `model`'s practice picture
    /// (`CreateModel.practice(_:scene:)`).
    init(model: CreateModel, practice: RefinePracticeSetup?, onReset: (() -> Void)? = nil) {
        self.model = model
        self.practice = practice
        self.onReset = onReset
        // Never a draft: its canvas is smaller than the one the edits will be laid on.
        _base = State(initialValue: model.preview.flatMap { $0.isDraft ? nil : $0 })
        _tool = State(initialValue: .pen)
        // The Studio opens on the painting in its paints (the Lamplit Table, 6 to 0).
        _backdrop = State(initialValue: .painting)
        if let practice {
            // A practice's switches are its own, from the painter's: the Pen's page turning Color
            // from Photo on leaves Refine's Pen as it was.
            let store = RefinePracticeSetup.settings
            _snaps = AppStorage(wrappedValue: SettingsDefault.refineSnaps, SettingsKey.refineSnaps, store: store)
            _penColors = AppStorage(wrappedValue: SettingsDefault.refinePenColors, SettingsKey.refinePenColors, store: store)
            _brushSize = AppStorage(wrappedValue: SettingsDefault.refineBrushSize, SettingsKey.refineBrushSize, store: store)
            _tool = State(initialValue: practice.tool)
            _group = State(initialValue: RefineGroup.of(practice.tool))
            _backdrop = State(initialValue: practice.backdrop)
            if let shape = practice.shape { _shape = State(initialValue: shape) }
            return
        }
        #if DEBUG
        if let demo = ShellDemo.current {
            let opens: RefineTool? = demo.picksColorPaint ? .editPaint : demo.opensColors ? .looks : demo.selectsCell ? .select : nil
            if let opens {
                _tool = State(initialValue: opens)
                _group = State(initialValue: RefineGroup.of(opens))
            }
            if let topic = demo.opensGuide { _guide = State(initialValue: topic) }
        }
        #endif
    }

    var body: some View {
        stage
        .onAppear {
            if !isPractice { PaintTips.desk.enter(.refine) }
            // Once: Try Painting's cover makes it disappear and appear again, and the history and
            // what Cancel puts back are the screen's, not the cover's.
            guard !opened else { return }
            opened = true
            model.beginRefining()
            // A draft refined before (Continue Refining) has found how to draw already.
            if model.refinements.isEmpty, !isPractice { PaintTips.refineShown() }
        }
        .onDisappear {
            model.dismissNote()
            if !isPractice { PaintTips.desk.leave(.refine) }
        }
        .onChange(of: model.closedShape) { _, shape in
            if let shape { closed(shape) }
        }
        .fullScreenCover(item: $trial) { trial in
            PaintView(session: trial.session, title: String(localized: "Try Painting"), onClose: { self.trial = nil })
        }
        .task(id: Landing(preview: model.preview?.id, settled: model.settledEdits, showsPainting: showsPainting)) {
            await land()
        }
    }

    /// Whether this is a Tool Guide page's practice canvas.
    private var isPractice: Bool {
        practice != nil
    }

    /// Refine's screen, or a practice canvas.
    @ViewBuilder
    private var stage: some View {
        if practice != nil {
            practiceScreen
        } else {
            refineScreen
        }
    }

    private var refineScreen: some View {
        NavigationStack {
            canvas
                .safeAreaInset(edge: .bottom, spacing: 0) { reservedTools }
                .safeAreaInset(edge: .leading, alignment: .top, spacing: 0) {
                    if usesRail { toolRail }
                }
                .background(Theme.paper)
                .navigationTitle("Refine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .fullScreenCover(item: $guide) { topic in RefineGuideView(opening: topic) }
    }

    /// An edit sent to the model, which draws it until the template on screen has it.
    private struct Submitted: Identifiable {
        /// Its number (`CreateModel.edit(_:)`).
        let id: Int
        let edit: TemplateEditor.Edit
        /// A line tapped away, as the tap found it, normalized.
        var chain: [SIMD2<Float>]?
        /// A line Bend Line moved, as it was and as it goes, normalized, which shows until the
        /// template has it.
        var bent: (original: [SIMD2<Float>], moved: [SIMD2<Float>])?
        /// A swatch of the photo's color shows where a fill was tapped, until the template has it.
        var showsSwatch = false
    }

    /// What the screen draws over: when any of it changes, `land` brings `base` up to date.
    private struct Landing: Hashable {
        var preview: UUID?
        var settled: Int
        var showsPainting: Bool
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            if let photo = model.source?.preview {
                // A card, as the preview's comparison is; zoomed in, its corners leave the screen.
                Self.card
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
                    .frame(width: picture.width, height: picture.height)
                    .position(x: picture.midX, y: picture.midY)
                let showsPhoto = backdrop == .photo || backdrop == .photoBehind || base == nil
                let painted = showsPainting && base != nil && painting?.preview == base?.id ? painting?.image : nil
                ZStack {
                    if showsPhoto {
                        Image(decorative: photo, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                    }
                    if let painted {
                        Image(decorative: painted, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                            .opacity(backdrop == .photoBehind ? 1 - photoShows : 1)
                            // New colors cross-fade in (`land`).
                            .id(painting?.preview)
                            .transition(.opacity)
                    }
                    // The brush's strokes until they land, in their paint under the drawing's ink,
                    // which a brush never covers.
                    RefineInkLayer(
                        lines: [], trace: nil, traceIsDrawn: false, erasing: false, brushes: brushes,
                        eraserRadius: eraserRadius, rect: picture, lineWidth: lineWidth, beneath: nil, halo: false)
                    if let base {
                        LineArtLayer(
                            drawing: base.drawing, picture: picture, scale: zoom, overPhoto: showsPhoto,
                            overPaint: painted != nil && !showsPhoto)
                            .equatable()
                    }
                    RefineFillLayer(
                        base: base, fills: filledPoints, swatches: swatches, space: model.source?.image.colorSpace, rect: picture,
                        showsAreas: painted == nil)
                        .equatable()
                    if group == .cells, let cellEdges {
                        RefineCellEdges(id: cellEdges.id, size: templateSize, path: cellEdges.path, rect: picture)
                            .equatable()
                    }
                    if !glowAreas.isEmpty {
                        RefinePaintGlow(base: base, areas: glowAreas, rect: picture, reduceMotion: reduceMotion)
                            .equatable()
                    }
                    let figure = shapeTrace
                    RefineInkLayer(
                        lines: pending, trace: tool == .shape ? figure : tool.drags || tool == .brush ? nil : trace, traceIsDrawn: tool == .shape, erasing: tool.erases,
                        dashed: tool == .cellEdge, merging: tool == .merge,
                        eraserRadius: eraserRadius, rect: picture, lineWidth: lineWidth,
                        beneath: showsPhoto ? photo : painted, halo: showsPhoto)
                    if let bend {
                        RefineBendPreview(original: bend.original, moved: bend.moved, size: templateSize, rect: picture, lineWidth: lineWidth)
                    }
                    if group == .numbers, let base {
                        RefineNumbers(base: base, rect: picture)
                            .equatable()
                    }
                    if let held = heldNumber, let template = base?.template {
                        RefineHeldNumber(template: template, paint: held.paint, at: held.at, rect: picture)
                    }
                    if let tapped {
                        RefineTappedLine(points: tapped, rect: picture, lineWidth: lineWidth)
                            .opacity(flashes ? 1 : 0)
                    }
                    RefineMarks(
                        refinements: model.refinements, found: model.foundText, marking: marking, rect: picture,
                        emphasizesText: tool == .text)
                }
                // Drawing past the picture's edge stays on the picture.
                .mask {
                    Self.card
                        .frame(width: picture.width, height: picture.height)
                        .position(x: picture.midX, y: picture.midY)
                }
            }
            RefineTouchSurface(
                aspectRatio: aspectRatio,
                onLayout: { rect, zoom in
                    picture = rect
                    self.zoom = zoom
                },
                onDraw: draw, onTap: tap, onUndo: undo, onPencilTap: pencilTap, onLongPress: openCard, focus: focus)
            if let sparkles {
                RefineSparkles(point: sparkles.point, extent: sparkles.extent, stars: Sky.current() == .moon)
                    .id(sparkles.id)
            }
        }
        .clipped()
        .overlay(alignment: .bottom) { status.padding(12) }
        .overlay(alignment: .top) { RefineNoteToast(note: model.note).padding(.top, 12) }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(reduceMotion ? nil : .snappy, value: model.note)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "refine.canvas", defaultValue: "Painting to refine",
            comment: "VoiceOver label of the Refine screen's picture, where lines are drawn and erased; its value counts the changes")))
        .accessibilityValue(Self.changes(model.refinements.changeCount))
        .accessibilityIdentifier("refine-canvas")
        // After the picture's own accessibility, which ignores its children: Start From and the
        // badge are controls of their own.
        .overlay(alignment: .top) {
            if !isPractice { topControls.padding(12) }
        }
        // A draft that couldn't be saved, with its Retry, under the note (a practice canvas keeps
        // no draft).
        .overlay(alignment: .top) {
            if !isPractice {
                VStack(spacing: 8) {
                    RefineNoteToast(note: model.note).hidden()
                    DraftSaveToast(photoID: model.photoID)
                }
                .padding(.top, 12)
                .animation(reduceMotion ? nil : .snappy, value: model.note)
            }
        }
        .popover(item: $card, attachmentAnchor: .rect(.rect(cardAnchor))) { pick in areaCard(pick) }
    }

    private static let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

    /// Whether the painting shows beneath the drawing: on its own, or over the photo.
    private var showsPainting: Bool { backdrop == .painting || backdrop == .photoBehind }

    /// The template's canvas, in canvas units (zero before there is a template).
    private var templateSize: CGSize { base?.drawing.size ?? .zero }

    /// A picture point (0…1) in the template's canvas units.
    private func canvasPoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let size = templateSize
        return SIMD2(p.x * Float(size.width), p.y * Float(size.height))
    }

    /// The edits sent that the template on screen doesn't show yet, as the lines the ink layer
    /// draws (normalized to the picture). Fills change no line (`RefineFillLayer` shows them).
    private var pending: [TemplateRefinements.Line] {
        let size = templateSize
        guard size.width > 0, size.height > 0 else { return [] }
        let long = Float(max(size.width, size.height))
        func normalized(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x / Float(size.width), p.y / Float(size.height)) }
        var lines: [TemplateRefinements.Line] = []
        for item in submitted {
            switch item.edit {
            case .draw(let points, let closed, _):
                lines.append(.init(kind: .draw, radius: 0, points: (closed ? points + points.prefix(1) : points).map(normalized)))
            case .erase(let path, let radius):
                lines.append(.init(kind: .erase, radius: radius / long, points: path.map(normalized)))
            case .eraseLine:
                if let chain = item.chain { lines.append(.init(kind: .eraseLine, radius: 0, points: chain)) }
            case .reshape:
                // A line Bend Line moved: gone from where it was, drawn where it goes.
                if let bent = item.bent {
                    lines.append(.init(kind: .eraseLine, radius: 0, points: bent.original))
                    lines.append(.init(kind: .draw, radius: 0, points: bent.moved))
                }
            case .fill, .split, .cellEdge, .merge, .brush, .look, .repaint, .paintArea, .moveLabel:
                // `RefineFillLayer` shows fills, `brushes` the brush's strokes; a split, a cell
                // edge, a merge and paint draw nothing.
                break
            }
        }
        return lines
    }

    /// Where the fills the template on screen has were tapped (normalized to the picture): its
    /// edits', and the lines builds before them filled through the generator.
    private var filledPoints: [SIMD2<Float>] {
        guard let base else { return [] }
        let size = SIMD2(Float(base.template.width), Float(base.template.height))
        var points = base.refinements.lines.filter { $0.kind == .fill }.compactMap(\.points.first)
        for case .fill(let at, _) in base.refinements.edits { points.append(at / size) }
        return points
    }

    /// The fills sent that the template on screen doesn't show yet, normalized to the picture.
    private var swatches: [RefineFillLayer.Swatch] {
        let size = SIMD2(Float(templateSize.width), Float(templateSize.height))
        guard size.x > 0, size.y > 0 else { return [] }
        return submitted.compactMap { item in
            guard item.showsSwatch, case .fill(let at, let color) = item.edit else { return nil }
            return RefineFillLayer.Swatch(point: at / size, color: color)
        }
    }

    private var aspectRatio: CGFloat {
        guard let image = model.source?.image, image.width > 0, image.height > 0 else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    /// The drawing's line on screen, as the preview and the canvas draw it at this size.
    private var lineWidth: CGFloat {
        (base?.drawing ?? model.preview?.drawing)?.lineWidth(scale: zoom, weight: lineWeight) ?? 1.5
    }

    /// The eraser keeps its size on screen, so zoomed in it erases finer (`RefineScreen.eraserRadius`).
    private var eraserRadius: Float { screen.eraserRadius }

    /// The screen as the gestures see it (`RefineGestures`, which `pbn refine` replays too).
    private var screen: RefineScreen {
        RefineScreen(canvas: templateSize, picture: picture.size, view: canvasSize, lineWidth: lineWidth)
    }

    @ViewBuilder
    private var status: some View {
        if model.phase == .generating {
            HStack(spacing: 10) {
                ProgressView(value: model.progress)
                    .frame(width: 64)
                Text("Updating…")
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .transition(.opacity)
        }
    }

    // MARK: Touches

    private func draw(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch tool {
        case .pen, .cellEdge, .merge, .brush, .eraser, .smartEraser: follow(touch, at: point)
        case .shape: drawShape(touch, at: point)
        case .text: mark(touch, at: point)
        // A fill is a tap, and so are selecting, painting a cell and picking a paint: a drag
        // does nothing.
        case .bendLine, .moveEdge, .moveNumber: drag(touch, at: point)
        case .fill, .select, .bucket, .eyedropper, .editPaint, .looks, .tryPainting: break
        }
    }

    /// The pen's line or the eraser's pass follows the finger; when it lifts, it is laid on the
    /// template, the pen's as it showed.
    private func follow(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point]
            snapLines = tool.erases || tool == .merge || tool == .brush || !snapsOn ? nil : currentSnapLines()
            if tool == .merge { probeMerge() }
        case .moved:
            // Samples closer than a point add nothing the line shows.
            guard var current = trace, let last = current.last, screen.onScreenLength(point - last) >= 1 else { return }
            current.append(point)
            trace = current
            if tool == .merge { light(current) }
        case .ended:
            guard var current = trace else { return }
            current.append(point)
            let edit = tool.erases ? eraserEdit(current)
                : tool == .cellEdge ? RefineGestures.cellEdge(current, on: screen, snapping: snapLines)
                : tool == .merge ? RefineGestures.merge(current, on: screen)
                : tool == .brush ? brushEdit(current)
                : penEdit(current)
            endStroke()
            if let edit { submit(edit) }
        case .cancelled:
            endStroke()
        }
    }

    /// Sends an edit to the template (`CreateModel.edit(_:)`), which draws it in a moment; until
    /// then it shows over the template (`pending`).
    private func submit(
        _ edit: TemplateEditor.Edit, chain: [SIMD2<Float>]? = nil, bent: (original: [SIMD2<Float>], moved: [SIMD2<Float>])? = nil
    ) {
        let edit = inked(edit)
        submitted.append(Submitted(id: model.edit(edit), edit: edit, chain: chain, bent: bent))
        if !isPractice {
            PaintTips.refineEdited()
            if case .draw = edit { PaintTips.refineLineDrawn() }
        }
    }

    private func endStroke() {
        trace = nil
        snapLines = nil
        mergeAreas = []
        mergeWanted = nil
    }

    /// Whether a line's ends join the lines their ink touches: the Toolbox's Snap.
    private var snapsOn: Bool { snaps }

    /// A drawn line as the Studio lays it: ink alone (a draw with no paints to give, which lays
    /// nudged through junctions as any line now does) unless Color from Photo is on, when the
    /// model reads the photo's colors for the pieces it cuts (`TemplateEditor.painted`).
    private func inked(_ edit: TemplateEditor.Edit) -> TemplateEditor.Edit {
        Self.inked(edit, colorsFromPhoto: penColors)
    }

    /// `edit`, a drawn line with no paints to give unless `colorsFromPhoto`.
    nonisolated static func inked(_ edit: TemplateEditor.Edit, colorsFromPhoto: Bool) -> TemplateEditor.Edit {
        guard !colorsFromPhoto, case .draw(let points, let closed, nil) = edit else { return edit }
        return .draw(points: points, closed: closed, paints: [])
    }

    /// A pen's line from its samples (`RefineGestures.pen`).
    private func penEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.pen(points, on: screen, snapping: snapLines)
    }

    /// The eraser's pass as an edit (`RefineGestures.eraser`).
    private func eraserEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.eraser(points, on: screen)
    }

    /// Bend Line, Move Edge and Move Number follow the drag from where it began to the finger
    /// (`trace`, the two points), the line or number shown moving, and lay it when it lifts.
    private func drag(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point, point]
        case .moved:
            guard let start = trace?.first else { return }
            trace = [start, point]
        case .ended:
            guard let start = trace?.first else { return }
            trace = [start, point]
            // Bend Line's line shows where it goes until the template has it; a cell edge has no ink.
            let shown = tool == .bendLine ? bend.map { (normalized($0.original), normalized($0.moved)) } : nil
            // What the drag holds, by the edit's own rule, on the template on screen: one that holds
            // nothing says where to start, unless edits are still on their way (it may hold what
            // they move: the queue lays it on the template they make, and says if it can't).
            let holds = tool == .moveNumber ? heldNumber != nil : bend != nil
            trace = nil
            guard holds || !submitted.isEmpty else {
                if screen.onScreenLength(point - start) >= 4 {
                    model.tell(tool == .moveNumber ? .grabNumber : tool == .bendLine ? .grabLine : .grabEdge)
                }
                return
            }
            let edit = tool == .moveNumber
                ? RefineGestures.moveLabel(from: start, to: point, on: screen)
                : RefineGestures.reshape(from: start, to: point, on: screen, target: tool == .bendLine ? .ink : .edge)
            if let edit { submit(edit, bent: shown) }
        case .cancelled:
            trace = nil
        }
    }

    /// How near a drag must begin to a line or a number to take it: a finger's reach on screen, in
    /// canvas units (`RefineGestures.fingerReach`, as the edits it sends).
    private var fingerReach: Float {
        picture.width > 0 ? Float(RefineGestures.fingerReach * templateSize.width / picture.width) : TemplateEditor.tapReach
    }

    /// Canvas points normalized to the picture.
    private func normalized(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let size = SIMD2(Float(max(templateSize.width, 1)), Float(max(templateSize.height, 1)))
        return points.map { $0 / size }
    }

    /// The line Bend Line (ink) or Move Edge (a cell's edge) holds, as it was and moved to the
    /// finger (canvas units), the same moved points the edit will lay (`TemplateEditor.reshapedChain`).
    private var bend: (original: [SIMD2<Float>], moved: [SIMD2<Float>])? {
        guard tool == .bendLine || tool == .moveEdge, let trace, trace.count == 2, let template = base?.template,
              picture.width > 0, screen.onScreenLength(trace[1] - trace[0]) >= 1
        else { return nil }
        return TemplateEditor.reshapedChain(
            on: template, from: canvasPoint(trace[0]), to: canvasPoint(trace[1]), reach: fingerReach,
            target: tool == .bendLine ? .ink : .edge)
    }

    /// The number Move Number holds (its paint's index), the one the edit will move
    /// (`TemplateEditor.labelNear`), and where the finger has it, normalized.
    private var heldNumber: (paint: Int, at: SIMD2<Float>)? {
        guard tool == .moveNumber, let trace, trace.count == 2, let template = base?.template,
              let held = TemplateEditor.labelNear(on: template, at: canvasPoint(trace[0]), reach: fingerReach)
        else { return nil }
        return (Int(template.regions[held.region].colorIndex), trace[1])
    }

    /// The Paint Brush's stroke as an edit, in the current paint at the brush's Size
    /// (`RefineGestures.brush`).
    private func brushEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        guard let color = currentPaint else { return nil }
        return RefineGestures.brush(points, on: screen, color: color, size: CGFloat(brushSize))
    }

    /// The brush's strokes sent that the template on screen doesn't show yet, and the one under
    /// the finger, as `RefineInkLayer` lays them.
    private var brushes: [RefineInkLayer.Brush] {
        let size = templateSize
        guard size.width > 0, size.height > 0, let space = base?.template.colorSpace else { return [] }
        let long = Float(max(size.width, size.height))
        var strokes: [RefineInkLayer.Brush] = submitted.compactMap { item in
            guard case .brush(let path, let radius, let color) = item.edit else { return nil }
            return .init(
                points: path.map { SIMD2($0.x / Float(size.width), $0.y / Float(size.height)) }, radius: radius / long,
                color: RefinePalette.color(color, space: space))
        }
        if tool == .brush, let trace, let color = currentPaint {
            strokes.append(.init(points: trace, radius: screen.brushRadius(size: CGFloat(brushSize)), color: RefinePalette.color(color, space: space)))
        }
        return strokes
    }

    // MARK: Shapes

    /// Shapes follows the drag: the shape spans from where it began to the finger, and is laid on
    /// the template when it lifts. A curve takes two drags: its ends, then its bend.
    private func drawShape(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            if curve == nil { snapLines = snapsOn ? currentSnapLines() : nil }
            trace = [point, point]
        case .moved:
            guard let start = trace?.first else { return }
            trace = [start, point]
        case .ended:
            guard let start = trace?.first else { return }
            trace = [start, point]
            let figure = shapeFigure()
            trace = nil
            if shape == .curve && curve == nil {
                // The ends are down; the next drag bends the curve between them.
                if let figure, figure.count == 2 {
                    curve = (screen.picturePoint(figure[0]), screen.picturePoint(figure[1]))
                }
            } else {
                curve = nil
                snapLines = nil
                if let figure, let edit = RefineGestures.drawEdit(figure, closed: shape.isClosed, on: screen) { submit(edit) }
            }
        case .cancelled:
            trace = nil
        }
    }

    /// The shape as it will be drawn (points on screen), from the drag under way (`trace`) and,
    /// for a curve, its ends; nil while it is too small to draw.
    private func shapeFigure() -> [CGPoint]? {
        guard picture.width > 0, picture.height > 0 else { return nil }
        if let curve {
            guard let bend = trace?.last else { return [screen.onScreen(curve.from), screen.onScreen(curve.to)] }
            return RefineGestures.figure(shape, from: bend, to: bend, curve: curve, on: screen, snapping: snapLines)
        }
        guard let trace, let first = trace.first, let last = trace.last else { return nil }
        return RefineGestures.figure(shape, from: first, to: last, on: screen, snapping: snapLines)
    }

    /// The shape under the finger, or a curve waiting to be bent, as `RefineInkLayer` draws it.
    private var shapeTrace: [SIMD2<Float>]? {
        guard tool == .shape, trace != nil || curve != nil else { return nil }
        return shapeFigure()?.map(screen.picturePoint)
    }

    /// A curve whose ends are down and that wasn't bent is laid straight.
    private func finishCurve() {
        guard let pending = curve else { return }
        curve = nil
        snapLines = nil
        if let edit = RefineGestures.straightCurve(from: pending.from, to: pending.to, on: screen) { submit(edit) }
    }

    /// The lines on screen, in the template's canvas units: its drawing, the lines drawn since,
    /// less what was erased since (the edits sent that it doesn't show yet).
    private func currentSnapLines() -> SnapLines? {
        guard let drawing = base?.drawing else { return nil }
        return RefineGestures.snapLines(
            drawing: drawing.lines.map(\.points), canvas: drawing.size, pending: submitted.map { ($0.edit, $0.chain) })
    }

    // MARK: Landing

    /// Brings `base` up to date with the model's template, and with it the painting beneath the
    /// drawing (every area in its paint, with no line, at up to twice the canvas's resolution),
    /// then takes the edits the template shows off the ones still drawn over it. They change
    /// together, so an edit's ink never goes before the template that has it comes, and the
    /// painting never lags the drawing.
    private func land() async {
        let preview = model.preview, settled = model.settledEdits
        if let preview, !preview.isDraft {
            var image = painting
            if showsPainting, painting?.preview != preview.id {
                let template = preview.template
                let long = min(2 * max(template.width, template.height), Self.paintingPixels)
                let made = await Background.run { TemplateRasterizer.image(template, style: .paintedAreas, maxPixelSize: long) }
                guard !Task.isCancelled else { return }
                if let made { image = (preview.id, made) }
            }
            // Changes of paint cross-fade in, the Lamplit Table's gentler landing (the Child at
            // Bedtime); every other edit is there the moment it lands.
            let fades = tool.paints && !reduceMotion && painting != nil && image?.preview != painting?.preview
            let before = base?.template.palette
            withAnimation(fades ? .easeInOut(duration: 0.35) : nil) {
                base = preview
                // Only a painting of this template: an older one would show lines that are gone.
                painting = image?.preview == preview.id ? image : nil
            }
            tiny = RefineTinyAreas.find(in: preview.template)
            if tinyShown >= tiny.count { tinyShown = -1 }
            currentPaint = RefinePalette.following(currentPaint, from: before, to: preview.template.palette)
            if cellEdges?.id != preview.id { cellEdges = (preview.id, RefineCellEdges.path(of: preview.template)) }
            #if DEBUG
            if isPractice, !didPickDemoPaint, ShellDemo.current?.opensGuide != nil {
                didPickDemoPaint = true
                DemoMode.markReady()
            }
            // Pick from the refined template once its edits have landed, as a painter would.
            if !isPractice, !didPickDemoPaint, preview.refinements == model.refinements, let demo = ShellDemo.current {
                let template = preview.template
                let largest = template.regions.indices.max(by: { template.regions[$0].area < template.regions[$1].area })
                let at = largest.flatMap { template.labels(ofRegion: $0).max(by: { $0.radius < $1.radius })?.position }
                if demo.picksColorPaint {
                    let counts = template.regionCountsByColor
                    currentPaint = counts.indices.max { counts[$0] < counts[$1] }.map { template.palette[$0].oklab }
                }
                if demo.selectsCell { selection = at }
                if demo.opensCard, let at {
                    card = RefineAreaPick(point: SIMD2(at.x / Float(template.width), at.y / Float(template.height)), at: at)
                }
                didPickDemoPaint = true
            }
            #endif
        }
        submitted.removeAll { $0.id <= settled }
    }

    /// The painting's long side, in pixels, at most.
    static let paintingPixels = 3200

    private func mark(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            marking = (point, point)
        case .moved:
            if let start = marking?.0 { marking = (start, point) }
        case .ended:
            if let start = marking?.0 { mark(from: start, to: point) }
            marking = nil
        case .cancelled:
            marking = nil
        }
    }

    private func tap(at point: SIMD2<Float>) {
        switch tool {
        case .pen, .cellEdge, .merge, .looks, .bendLine, .moveEdge, .moveNumber, .tryPainting:
            break
        case .brush:
            // A dab, of the brush's own reach.
            if let edit = brushEdit([point]) { submit(edit) }
        case .shape:
            finishCurve()
        case .eraser:
            // A dab, of the eraser's own reach.
            if let edit = eraserEdit([point]) { submit(edit) }
        case .smartEraser:
            eraseLine(at: point)
        case .fill:
            fill(at: point)
        case .text:
            toggleText(at: point)
        case .select, .bucket, .eyedropper, .editPaint:
            cellTapped(at: point)
        }
    }

    /// Takes out the drawn line under a tap from junction to junction (`LineChains` finds it for
    /// the flash and the ink laid over it; the template's editor decides what goes): the lines it
    /// meets stay whole. The line glows as it goes.
    private func eraseLine(at point: SIMD2<Float>) {
        guard let drawing = base?.drawing,
              let erased = RefineGestures.lineEraser(at: point, on: screen, chains: LineChains(drawing))
        else { return }
        let normalized = erased.chain
        submit(erased.edit, chain: normalized)
        FeedbackEngine.shared.selectionChanged()
        guard !reduceMotion else { return }
        tapped = normalized
        flashes = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 0.45)) { flashes = false }
        }
    }

    /// Fills the shape under a tap, or clears a fill made there (`EditFills`; the model decides, in
    /// its turn, on the template as the edits before it left it). A swatch of the photo's color
    /// shows where a fill will be, unless the tap clears one.
    private func fill(at point: SIMD2<Float>) {
        guard picture.width > 0, templateSize.width > 0, let photo = model.source?.image else { return }
        let color = LineEdit.photoColor(at: point, in: photo)
        let at = canvasPoint(point)
        let clears = base.map { !EditFills.cleared(by: at, edits: $0.refinements.edits, on: $0.template).isEmpty } ?? false
        submitted.append(Submitted(id: model.fill(at: at, color: color), edit: .fill(at: at, color: color), showsSwatch: !clears))
        FeedbackEngine.shared.selectionChanged()
        if !isPractice {
            PaintTips.refineEdited()
            PaintTips.refineFilled()
        }
    }

    /// A marked line is unmarked; a found line is turned off, or on again.
    private func toggleText(at point: SIMD2<Float>) {
        if let marked = model.refinements.addedText.last(where: { Self.line($0, contains: point) }) {
            model.change(.unmarkText(marked))
            if !isPractice { PaintTips.refineEdited() }
        } else if let line = model.foundText.first(where: { Self.line($0, contains: point) }) {
            model.change(.toggleFound(line))
            if !isPractice { PaintTips.refineEdited() }
        }
    }

    /// Marks the line dragged out from `a` to `b`, unless the drag was too small to hold one.
    private func mark(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        guard abs(a.x - b.x) * Float(picture.width) >= 12, abs(a.y - b.y) * Float(picture.height) >= 6 else { return }
        model.change(.markText(TemplateRefinements.textLine(from: a, to: b)))
        if !isPractice { PaintTips.refineEdited() }
    }

    /// Whether a tap at `point` falls on `line`, give or take a little for the finger.
    private static func line(_ line: [SIMD2<Float>], contains point: SIMD2<Float>) -> Bool {
        guard let bounds = TemplateRefinements.bounds(line) else { return false }
        return bounds.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }

    // MARK: Changes

    private func undo() {
        trace = nil
        // Undo while a curve waits to be bent takes the curve back, not the change before.
        if curve != nil {
            curve = nil
            snapLines = nil
            return
        }
        model.undo()
    }

    private func cancel() {
        model.cancelRefining()
        dismiss()
    }

    /// Keeps the changes, a curve waiting to be bent among them (as switching tools keeps it).
    private func done() {
        finishCurve()
        dismiss()
    }

    /// The number of changes, for VoiceOver.
    static func changes(_ count: Int) -> String {
        guard count > 0 else {
            return String(
                localized: "refine.changes.none", defaultValue: "No changes",
                comment: "VoiceOver value of the Refine button and the Refine screen's picture before anything was refined")
        }
        return String(
            localized: "refine.changes", defaultValue: "\(count) changes",
            comment: "VoiceOver value of the Refine button and the Refine screen's picture: how many lines were drawn or erased, areas brushed and text lines changed")
    }

    // MARK: Bars

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark", action: cancel)
                .accessibilityIdentifier("refine-cancel")
        }
        ToolbarItem(placement: .topBarLeading) {
            Button("Tool Guide", systemImage: "questionmark.circle") {
                FeedbackEngine.shared.selectionChanged()
                guide = RefineGuideTopic.opening(at: tool)
            }
            .accessibilityHint(Text(String(
                localized: "refine.guide.open.hint", defaultValue: "What each tool does, with a picture to try it on.",
                comment: "Refine screen: VoiceOver hint of the Tool Guide button, which opens a page per tool with a description and a practice canvas")))
            .accessibilityIdentifier("refine-guide")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .disabled(!model.canUndo)
                .keyboardShortcut("z")
                .accessibilityIdentifier("refine-undo")
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityIdentifier("refine-redo")
        }
        ToolbarItem(placement: .principal) { backdropPicker }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark", action: done)
                .tint(Theme.signature)
                .accessibilityIdentifier("refine-done")
        }
    }

    /// The tools, keeping the room of the tallest they have been (`toolsHeight`).
    private var reservedTools: some View {
        tools
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > toolsHeight { toolsHeight = height }
            }
            .frame(minHeight: toolsHeight, alignment: .bottom)
            // Another width (a rotation, a resized window) lays the tools out anew: measured again.
            .onChange(of: canvasSize.width) { toolsHeight = 0 }
    }

    /// What the finger does, along the bottom (`studioBar`): the picked tool's options and, on
    /// iPhone, the groups and the group's tools. How each tool works is its button's VoiceOver
    /// hint, and how to draw at all a tip said once (`RefineDrawTip`); only a curve waiting to be
    /// bent says what comes next.
    private var tools: some View {
        VStack(spacing: 12) {
            if tool == .shape, shape == .curve, curve != nil {
                Text(hint(for: .shape))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
                    .accessibilityIdentifier("refine-hint")
            }
            studioBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        // Like the painting's bars: larger text sizes reach the buttons through the Large
        // Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// How `tool` works: its button's VoiceOver hint (a curve waiting to be bent also shows it).
    private func hint(for tool: RefineTool) -> String {
        switch tool {
        case .pen:
            String(localized: "refine.hint.pen",
                   defaultValue: "Draw lines exactly as you draw them. Two fingers zoom and move, and a two‑finger tap undoes.",
                   comment: "Refine screen: how the Pen works (it draws lines into the painting's drawing just where they are drawn), read by VoiceOver as the hint of its button")
        case .shape:
            switch shape {
            case .line:
                String(localized: "refine.hint.line",
                       defaultValue: "Drag to draw a straight line. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Line works (a drag draws a straight line from where it starts to where it ends), read by VoiceOver as the hint of its button")
            case .rectangle:
                String(localized: "refine.hint.rectangle",
                       defaultValue: "Drag from corner to corner to draw a rectangle. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Rectangle works (a drag spans the rectangle from one corner to the opposite one), read by VoiceOver as the hint of its button")
            case .oval:
                String(localized: "refine.hint.oval",
                       defaultValue: "Drag across to draw an oval. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Oval works (a drag spans the box the oval fills), read by VoiceOver as the hint of its button")
            case .curve:
                curve == nil
                    ? String(localized: "refine.hint.curve",
                             defaultValue: "Drag from one end of the curve to the other, then drag to bend it. Two fingers zoom and move.",
                             comment: "Refine screen: how the Shapes tool's Curve works (a first drag places the curve's ends, a second bends it through the finger), read by VoiceOver as the hint of its button")
                    : String(localized: "refine.hint.curve.bend",
                             defaultValue: "Drag to bend the curve, or tap to keep it straight.",
                             comment: "Refine screen: the Shapes tool's Curve once its ends are placed: a drag bends it through the finger, a tap keeps it a straight line")
            case .polygon:
                String(localized: "refine.hint.polygon",
                       defaultValue: "Drag across to draw a hexagon. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Hexagon works (a drag spans the box the hexagon fills), read by VoiceOver as the hint of its button")
            case .star:
                String(localized: "refine.hint.star",
                       defaultValue: "Drag across to draw a star. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Star works (a drag spans the box the five-pointed star fills), read by VoiceOver as the hint of its button")
            }
        case .eraser:
            String(localized: "refine.hint.eraser",
                   defaultValue: "Rub out just what you touch, or tap to erase a spot. Two fingers zoom and move.",
                   comment: "Refine screen: how the Eraser works (it takes out exactly the parts of lines it touches), read by VoiceOver as the hint of its button")
        case .smartEraser:
            String(localized: "refine.hint.smartEraser",
                   defaultValue: "Rub lines out, or tap a line to erase all of it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Smart Eraser works (it takes lines out of the painting's drawing; a tap takes a whole line), read by VoiceOver as the hint of its button")
        case .fill:
            String(localized: "refine.hint.fill",
                   defaultValue: "Tap inside a closed shape to make it an area of its own, in the photo’s color there. Tap it again to clear it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Fill tool works (a tap makes the closed shape of the drawing under it an area of its own, painted the photo's color where it was tapped; a tap in a filled area clears it), read by VoiceOver as the hint of its button")
        case .select:
            String(localized: "refine.hint.select",
                   defaultValue: "Tap an area to select it and see its paint. Tap it again to let it go.",
                   comment: "Refine screen: how Select works (a tap selects the area under it, outlined, with its paint shown in a bar), read by VoiceOver as the hint of its button")
        case .cellEdge:
            String(localized: "refine.hint.cellEdge",
                   defaultValue: "Draw across an area to divide it in two with no line. Both parts keep the paint.",
                   comment: "Refine screen: how Cell Edge works (a stroke divides an area where it goes, drawing no line; both parts keep their paint until painted), read by VoiceOver as the hint of its button")
        case .bendLine:
            String(localized: "refine.hint.bendLine",
                   defaultValue: "Drag a line to move it. It bends near where you hold it.",
                   comment: "Refine screen: how Bend Line works (a drag on a drawn line moves the part of it near the finger, the rest bending smoothly into place), read by VoiceOver as the hint of its button")
        case .moveEdge:
            String(localized: "refine.hint.moveEdge",
                   defaultValue: "Drag the edge between two areas to change their shapes.",
                   comment: "Refine screen: how Move Edge works (a drag on the boundary between two areas moves it, one area growing as the other shrinks), read by VoiceOver as the hint of its button")
        case .moveNumber:
            String(localized: "refine.hint.moveNumber",
                   defaultValue: "Drag a number to where you want it in its area.",
                   comment: "Refine screen: how Move Number works (a drag moves an area's number to another spot inside the same area, where it fits), read by VoiceOver as the hint of its button")
        case .tryPainting:
            String(localized: "refine.hint.tryPainting",
                   defaultValue: "Paints the template as it is now, to try it. Nothing is saved.",
                   comment: "Refine screen: what Try Painting does (opens the painting screen on the template as refined so far; fills made there are not kept), read by VoiceOver as the hint of its button")
        case .merge:
            String(localized: "refine.hint.merge",
                   defaultValue: "Drag across areas to join them into one, in the first one’s paint.",
                   comment: "Refine screen: how Merge works (a drag across areas joins them into one, taking the paint of the area the drag began in; the lines between them go), read by VoiceOver as the hint of its button")
        case .brush:
            String(localized: "refine.hint.brush",
                   defaultValue: "Paint the current paint where you brush, or tap to paint a spot. It joins the areas of that paint it touches.",
                   comment: "Refine screen: how the Paint Brush works (where it is dragged becomes the paint picked in the palette, joining areas of that paint it meets; a tap paints a spot), read by VoiceOver as the hint of its button")
        case .bucket:
            String(localized: "refine.hint.bucket",
                   defaultValue: "Tap an area to give it the current paint.",
                   comment: "Refine screen: how the Bucket works (a tap gives the area under it the paint picked in the palette), read by VoiceOver as the hint of its button")
        case .eyedropper:
            String(localized: "refine.hint.eyedropper",
                   defaultValue: "Tap an area to make its paint the current paint. Over the photo, tap to pick the photo’s color.",
                   comment: "Refine screen: how the Eyedropper works (a tap picks the paint of the area under it, or the photo's color there when the photo shows), read by VoiceOver as the hint of its button")
        case .editPaint:
            String(localized: "refine.hint.editPaint",
                   defaultValue: "Give the current paint a new color everywhere it’s used. Tap an area to pick its paint.",
                   comment: "Refine screen: how Edit Paint works (the current paint takes a new color from the color picker in every area that uses it; a tap on an area picks its paint), read by VoiceOver as the hint of its button")
        case .looks:
            String(localized: "refine.hint.looks",
                   defaultValue: "Pick a look for every paint.",
                   comment: "Refine screen: how Looks works (a look changes every paint of the painting at once), read by VoiceOver as the hint of its button")
        case .text:
            String(localized: "refine.hint.text",
                   defaultValue: "Tap a line of text to keep or ignore it, or drag across a line the app missed.",
                   comment: "Refine screen: how the Text tool works (lines of text in the photo are drawn as writing), read by VoiceOver as the hint of its button")
        }
    }

    /// A tool, prominent while it's the finger's.
    @ViewBuilder
    private func toolButton(_ tool: RefineTool, systemImage: String, label: Text, id: String) -> some View {
        let selected = self.tool == tool
        let button = Button { toolTapped(tool) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityHint(Text(hint(for: tool)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(id)")
        .accessibilityShowsLargeContentViewer { Label { label } icon: { Image(systemName: systemImage) } }
        if selected {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func shapeName(_ kind: RefineShape) -> Text {
        switch kind {
        case .line: Text("Line")
        case .rectangle: Text("Rectangle")
        case .oval: Text("Oval")
        case .curve: Text("Curve")
        case .polygon: Text("Hexagon")
        case .star: Text("Star")
        }
    }

    private func pickShape(_ kind: RefineShape) {
        if kind != shape { finishCurve() }
        shape = kind
        pick(.shape)
    }

    private func pick(_ tool: RefineTool) {
        guard tool != self.tool else { return }
        // A practice canvas keeps the tool its page teaches (the card's link, the Pencil's double tap).
        if let practice, tool != practice.tool { return }
        FeedbackEngine.shared.selectionChanged()
        // A stroke under way was the other tool's, and a curve waiting to be bent stays straight.
        endStroke()
        finishCurve()
        self.tool = tool
        if tool != .select { selection = nil }
        group = RefineGroup.of(tool)
        // A cell edge and the paint tools show only in the painting: it shows beneath them.
        if tool.paints, base != nil, !showsPainting { backdrop = .painting }
    }

    /// A tool's button: picks it; Try Painting opens the painting screen instead.
    private func toolTapped(_ tool: RefineTool) {
        if tool == .tryPainting {
            tryPainting()
            return
        }
        pick(tool)
    }

    /// A long press on an area opens its card.
    private func openCard(at point: SIMD2<Float>) {
        guard let template = base?.template, model.hasLineArtInput, template.region(at: canvasPoint(point)) != nil else { return }
        endStroke()
        FeedbackEngine.shared.selectionChanged()
        card = RefineAreaPick(point: point, at: canvasPoint(point))
    }

    /// The Pencil's double tap: a pen's eraser, or an eraser's pen, of the same kind.
    private func pencilTap() {
        guard model.hasLineArtInput, let partner = tool.pencilPartner else { return }
        pick(partner)
    }
}

// MARK: The Studio

extension RefineView {
    /// Whether every tool stands in a rail along the leading edge (iPad), rather than in group tabs
    /// over a row of the group's tools (iPhone).
    private var usesRail: Bool { sizeClass == .regular }

    /// The Studio's bottom: Photo Behind's slider, the picked tool's options, the cell Select
    /// picked, the palette (in Cells and Paint), and on iPhone the groups and the group's tools.
    @ViewBuilder
    private var studioBar: some View {
        photoSlider
        toolOptions
        if tool == .select, let template = base?.template, let region = selectedRegion {
            RefineSelectionBar(template: template, region: region) {
                guard let selection else { return }
                FeedbackEngine.shared.selectionChanged()
                card = RefineAreaPick(point: picturePoint(selection), at: selection)
            }
            .transition(.opacity)
        }
        if group == .cells || group == .paint, let template = base?.template {
            RefinePaletteBar(template: template, current: $currentPaint, merge: paletteMerge)
                .disabled(!model.hasLineArtInput)
        }
        if practice?.teaches == .tryPainting {
            Button("Try Painting", systemImage: "paintbrush", action: tryPainting)
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .disabled(base == nil)
                .accessibilityIdentifier("refine-practice-try")
        }
        if !usesRail, practice == nil {
            Picker("Tools", selection: Binding(get: { group }, set: { choose($0) })) {
                ForEach(RefineGroup.allCases, id: \.self) { kind in
                    Self.groupName(kind).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .disabled(!model.hasLineArtInput)
            .accessibilityIdentifier("refine-groups")
            // Centred where the row fits (a group holds at most five), scrolling where it doesn't
            // (larger text).
            ViewThatFits(in: .horizontal) {
                groupRow
                ScrollView(.horizontal) { groupRow }
                    .scrollIndicators(.hidden)
            }
        }
    }

    /// The group's tools, each a round button.
    private var groupRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(group.tools, id: \.self) { kind in
                    studioButton(kind)
                        .disabled(!model.hasLineArtInput)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Every tool, in its group's labelled section, a name beside each (iPad); it scrolls where
    /// the screen is too short for all of them.
    private var toolRail: some View {
        ViewThatFits(in: .vertical) {
            railTools
            ScrollView { railTools }
                .scrollIndicators(.hidden)
        }
        .frame(width: 184)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(!model.hasLineArtInput)
    }

    private var railTools: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(RefineGroup.allCases, id: \.self) { kind in
                Self.groupName(kind)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, kind == RefineGroup.allCases.first ? 4 : 14)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(kind.tools, id: \.self) { railRow($0) }
            }
        }
        .padding(8)
    }

    /// A tool in the rail: its symbol and name, filled in the signature color while it's the
    /// finger's.
    @ViewBuilder
    private func railRow(_ kind: RefineTool) -> some View {
        let selected = tool == kind
        let row = Button { toolTapped(kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(kind))
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                Self.toolName(kind)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if selected { Capsule().fill(Theme.signature) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.toolName(kind))
        .accessibilityHint(Text(hint(for: kind)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(Self.toolID(kind))")
        .accessibilityShowsLargeContentViewer { Label { Self.toolName(kind) } icon: { Image(systemName: symbol(kind)) } }
        switch kind {
        case .pen: row.gentleTip(.refineDraw, arrowEdge: .leading)
        case .fill: row.gentleTip(.refineFill, arrowEdge: .leading)
        case .shape: row.accessibilityValue(shapeName(shape))
        default: row
        }
    }

    /// A tool's round button (iPhone's row).
    @ViewBuilder
    private func studioButton(_ kind: RefineTool) -> some View {
        let button = toolButton(kind, systemImage: symbol(kind), label: Self.toolName(kind), id: Self.toolID(kind))
        switch kind {
        case .pen: button.gentleTip(.refineDraw, arrowEdge: .bottom)
        case .fill: button.gentleTip(.refineFill, arrowEdge: .bottom)
        case .shape: button.accessibilityValue(shapeName(shape))
        default: button
        }
    }

    static func groupName(_ kind: RefineGroup) -> Text {
        switch kind {
        case .ink: Text("Ink")
        case .cells: Text("Cells")
        case .paint: Text("Paint")
        case .numbers: Text("Numbers")
        case .see: Text("See")
        }
    }

    static func toolName(_ kind: RefineTool) -> Text {
        switch kind {
        case .pen: Text("Pen")
        case .shape: Text("Shapes")
        case .eraser: Text("Eraser")
        case .smartEraser: Text("Line Eraser")
        case .text: Text("Writing")
        case .select: Text("Select")
        case .cellEdge: Text("Cell Edge")
        case .merge: Text("Merge")
        case .fill: Text("Fill Shape")
        case .brush: Text("Paint Brush")
        case .bucket: Text("Bucket")
        case .eyedropper: Text("Eyedropper")
        case .editPaint: Text("Edit Paint")
        case .looks: Text("Looks")
        case .bendLine: Text("Bend Line")
        case .moveEdge: Text("Move Edge")
        case .moveNumber: Text("Move Number")
        case .tryPainting: Text("Try Painting")
        }
    }

    private func symbol(_ kind: RefineTool) -> String { Self.symbol(kind, shape: shape) }

    /// A tool's symbol; Shapes' is its figure's.
    static func symbol(_ kind: RefineTool, shape: RefineShape) -> String {
        switch kind {
        case .pen: "pencil.tip"
        case .shape: shape.systemImage
        case .eraser: "eraser"
        case .smartEraser: "eraser.line.dashed"
        case .text: "text.viewfinder"
        case .select: "cursorarrow"
        case .cellEdge: "square.split.diagonal"
        case .merge: "arrow.triangle.merge"
        case .fill: "circle.inset.filled"
        case .brush: "paintbrush.pointed"
        case .bucket: "drop.fill"
        case .eyedropper: "eyedropper"
        case .editPaint: "swatchpalette"
        case .looks: "camera.filters"
        case .bendLine: "scribble"
        case .moveEdge: "arrow.left.and.right.square"
        case .moveNumber: "number.circle"
        case .tryPainting: "paintbrush"
        }
    }

    /// The tool's accessibility identifier, after `refine-tool-` (the UI tests' names).
    nonisolated static func toolID(_ kind: RefineTool) -> String {
        switch kind {
        case .shape: "shapes"
        default: "\(kind)"
        }
    }

    // MARK: Options

    /// What the picked tool offers above the tools: Shapes' figures, Snap where lines join, the
    /// Pen's Color from Photo, the looks, and the current paint's color.
    @ViewBuilder
    private var toolOptions: some View {
        switch tool {
        case .pen:
            optionBar {
                snapToggle
                Toggle(isOn: $penColors) { Text("Color from Photo") }
                    .accessibilityHint(Text(String(
                        localized: "refine.penColors.hint", defaultValue: "Gives the areas a line divides the photo’s colors there.",
                        comment: "Refine screen, the Pen's options: VoiceOver hint of Color from Photo, which makes each part of an area a drawn line divides take the photo's color there")))
                    .accessibilityIdentifier("refine-pen-colors")
            }
        case .shape:
            optionBar {
                HStack(spacing: 6) {
                    ForEach(RefineShape.allCases, id: \.self) { shapeOption($0) }
                }
                snapToggle
            }
        case .cellEdge:
            optionBar { snapToggle }
        case .brush:
            optionBar {
                Text("Size")
                Slider(value: $brushSize, in: 4...48)
                    .frame(width: 160)
                    .accessibilityLabel(Text("Size"))
                    .accessibilityValue(Text(String(
                        localized: "refine.brush.size", defaultValue: "\(Int(brushSize.rounded())) points",
                        comment: "Refine screen, the Paint Brush's options: VoiceOver value of its Size slider, the brush's radius on screen in points; the argument is the number")))
                    .accessibilityIdentifier("refine-brush-size")
            }
        case .looks, .editPaint:
            if let base {
                RefineColorsPanel(
                    template: base.template, paintsBefore: model.paintsBeforeEdits, edits: base.refinements.edits,
                    mode: tool == .looks ? .looks : .paint, paint: currentIndexBinding, family: $colorFamily,
                    change: model.recolor)
                    .disabled(model.phase == .generating || !model.hasLineArtInput)
                    .transition(.opacity)
            }
        default:
            EmptyView()
        }
    }

    private func optionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 16) { content() }
            .font(.footnote)
            .toggleStyle(.switch)
            .tint(Theme.signature)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .disabled(!model.hasLineArtInput)
    }

    private var snapToggle: some View {
        Toggle(isOn: $snaps) { Text("Snap") }
            .accessibilityHint(Text(String(
                localized: "refine.snap.hint", defaultValue: "Joins the end of a line to a line it touches.",
                comment: "Refine screen, a drawing tool's options: VoiceOver hint of Snap, which moves a drawn line's end onto a line its ink touches")))
            .accessibilityIdentifier("refine-snap")
    }

    /// One of Shapes' figures: picks it.
    private func shapeOption(_ kind: RefineShape) -> some View {
        let selected = shape == kind
        let button = Button {
            FeedbackEngine.shared.selectionChanged()
            pickShape(kind)
        } label: {
            Label { shapeName(kind) } icon: { Image(systemName: kind.systemImage) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
        }
        .buttonBorderShape(.circle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-shape-\(kind)")
        return Group {
            if selected {
                button.buttonStyle(.glassProminent).tint(Theme.signature)
            } else {
                button.buttonStyle(.glass)
            }
        }
    }

    /// Another group on screen, with the tool last picked there.
    private func choose(_ next: RefineGroup) {
        guard next != group else { return }
        lastTool[group] = tool
        pick(lastTool[next] ?? next.tools[0])
        group = next
    }

    /// What shows beneath the drawing: a segmented control in the bar where there is room, else a
    /// menu; Photo Behind adds its slider.
    @ViewBuilder
    private var backdropPicker: some View {
        if sizeClass == .regular {
            backdropChoice.pickerStyle(.segmented).fixedSize()
        } else {
            backdropChoice.pickerStyle(.menu)
        }
    }

    private var backdropChoice: some View {
        Picker("Show", selection: $backdrop) {
            Text("Painting").tag(RefineBackdrop.painting)
            Text("Paper").tag(RefineBackdrop.paper)
            Text("Photo").tag(RefineBackdrop.photo)
            Text("Photo Behind").tag(RefineBackdrop.photoBehind)
        }
        .accessibilityIdentifier("refine-backdrop")
    }

    /// Photo Behind's slider: how plainly the photo shows through the painting.
    @ViewBuilder
    private var photoSlider: some View {
        if backdrop == .photoBehind {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .accessibilityHidden(true)
                Slider(value: $photoShows, in: 0...1)
                    .frame(width: 180)
                    .tint(Theme.signature)
                    .accessibilityLabel(Text("Photo"))
                    .accessibilityValue(Text(photoShows.formatted(.percent.precision(.fractionLength(0)))))
                    .accessibilityIdentifier("refine-photo-behind")
                Image(systemName: "photo")
                    .accessibilityHidden(true)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .transition(.opacity)
        }
    }

    // MARK: Cells and paint

    /// The region Select picked, on the template on screen.
    private var selectedRegion: Int? {
        guard let selection else { return nil }
        return base?.template.region(at: selection)
    }

    /// The current paint's number less one, when the painting has it.
    private var currentIndex: Int? {
        RefinePalette.index(of: currentPaint, in: base?.template.palette ?? [])
    }

    /// What a swatch dropped on another does: in Edit Paint, `mergePaints`; elsewhere nothing.
    private var paletteMerge: ((Int, Int) -> Void)? {
        guard tool == .editPaint else { return nil }
        return { from, into in mergePaints(from, into: into) }
    }

    /// Edit Paint's swatch dropped on another: paint `from` takes the color of `into`, so the two
    /// become one (`TemplateEditor.Edit.repaint`, whose paints made alike merge), which a note
    /// says; the current paint follows.
    private func mergePaints(_ from: Int, into: Int) {
        guard let palette = base?.template.palette, palette.indices.contains(from), palette.indices.contains(into) else { return }
        FeedbackEngine.shared.selectionChanged()
        if currentPaint == palette[from].oklab { currentPaint = palette[into].oklab }
        model.recolor(.repaint(from: palette[from].oklab, to: palette[into].oklab, family: false))
    }

    /// Edit Paint's paint, as the colors panel picks it: the current paint.
    private var currentIndexBinding: Binding<Int?> {
        Binding(
            get: { currentIndex },
            set: { index in
                guard let index, let palette = base?.template.palette, index < palette.count else { return }
                currentPaint = palette[index].oklab
            })
    }

    /// The areas that glow: those a Merge drag joins, a card's paint's, the cell Select picked,
    /// or Edit Paint's paint's.
    private var glowAreas: [Int] {
        guard let template = base?.template else { return [] }
        if tool == .merge, trace != nil, let probe = mergeProbe, probe.preview == base?.id { return mergeAreas }
        if let card, let region = template.region(at: card.at) {
            return RefinePaintGlow.areas(of: Int(template.regions[region].colorIndex), in: template)
        }
        if tool == .select, let region = selectedRegion { return [region] }
        if tool == .editPaint, let index = currentIndex { return RefinePaintGlow.areas(of: index, in: template) }
        return []
    }

    /// A Merge drag begins: the template on screen gets its probe, unless it has one.
    private func probeMerge() {
        mergeStroke += 1
        mergeAreas = []
        guard let base, mergeProbe?.preview != base.id else { return }
        mergeProbe = (try? TemplateEditor.MergeProbe(base.template)).map { (base.id, $0) }
    }

    /// The areas the Merge drag so far joins, found off the main actor; a drag that moves on while
    /// they are being found waits for that, and only its newest points are looked at.
    private func light(_ points: [SIMD2<Float>]) {
        mergeWanted = points
        guard !mergeProbing else { return }
        lightNext()
    }

    private func lightNext() {
        guard let points = mergeWanted, let probe = mergeProbe,
              case .merge(let path)? = RefineGestures.merge(points, on: screen)
        else { return }
        mergeWanted = nil
        mergeProbing = true
        let stroke = mergeStroke
        Task {
            let areas = await Self.areas(of: probe.probe, along: path)
            mergeProbing = false
            // The finger may have lifted, another drag begun or the template changed meanwhile.
            if trace != nil, stroke == mergeStroke, probe.preview == mergeProbe?.preview { mergeAreas = areas }
            if mergeWanted != nil { lightNext() }
        }
    }

    @concurrent
    private static func areas(of probe: TemplateEditor.MergeProbe, along path: [SIMD2<Float>]) async -> [Int] {
        probe.areas(along: path)
    }

    /// A tap of Select, the Bucket, the Eyedropper or Edit Paint on the cell under it.
    private func cellTapped(at point: SIMD2<Float>) {
        guard let template = base?.template, model.hasLineArtInput else { return }
        let at = canvasPoint(point)
        let region = template.region(at: at)
        switch tool {
        case .select:
            FeedbackEngine.shared.selectionChanged()
            selection = region != nil && region != selectedRegion ? at : nil
        case .bucket:
            guard region != nil, let color = currentPaint else { return }
            FeedbackEngine.shared.selectionChanged()
            submitted.append(Submitted(id: model.paintArea(at: at, color: color), edit: .paintArea(at: at, color: color)))
            if !isPractice { PaintTips.refineEdited() }
        case .eyedropper:
            // The photo where it is what shows: on its own, or more than the painting over it.
            if backdrop == .photo || (backdrop == .photoBehind && photoShows > 0.5), let photo = model.source?.image {
                currentPaint = RefinePalette.snapped(LineEdit.photoColor(at: point, in: photo), to: template.palette)
            } else if let region {
                currentPaint = template.palette[Int(template.regions[region].colorIndex)].oklab
            } else {
                return
            }
            FeedbackEngine.shared.selectionChanged()
            announceCurrentPaint(in: template)
        case .editPaint:
            guard let region else { return }
            FeedbackEngine.shared.selectionChanged()
            currentPaint = template.palette[Int(template.regions[region].colorIndex)].oklab
            announceCurrentPaint(in: template)
        default:
            break
        }
    }

    /// VoiceOver hears the paint a tap picked: its number and how many areas use it, or that it is
    /// a new one.
    private func announceCurrentPaint(in template: Template) {
        let announcement: String
        if let paint = RefinePalette.index(of: currentPaint, in: template.palette) {
            let number = (paint + 1).formatted()
            let areas = TemplateCounts.areas(RefinePaintGlow.areas(of: paint, in: template).count)
            announcement = String(
                localized: "refine.colors.areas", defaultValue: "Paint \(number): \(areas)",
                comment: "VoiceOver announcement when picking a paint in Refine: the formatted paint number, then how many areas use it (\"3 areas\")")
        } else {
            announcement = String(localized: "New Paint")
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// Where the card points: the pressed spot, on screen.
    private var cardAnchor: CGRect {
        guard let card else { return .zero }
        let p = onScreen(card.point)
        return CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)
    }

    /// A point of the picture (0…1) on screen.
    private func onScreen(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: picture.minX + CGFloat(p.x) * picture.width, y: picture.minY + CGFloat(p.y) * picture.height)
    }

    /// A point in canvas units as a point of the picture (0…1).
    private func picturePoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let size = templateSize
        guard size.width > 0, size.height > 0 else { return .zero }
        return SIMD2(p.x / Float(size.width), p.y / Float(size.height))
    }

    @ViewBuilder
    private func areaCard(_ pick: RefineAreaPick) -> some View {
        if let template = base?.template {
            RefineAreaCard(
                template: template, at: pick.at,
                paintArea: { model.paintArea(at: pick.at, color: $0) },
                repaint: { from, to in model.recolor(.repaint(from: from, to: to, family: false)) },
                showPaint: { paint in
                    card = nil
                    currentPaint = template.palette[paint].oklab
                    self.pick(.editPaint)
                })
        }
    }

    /// Start From at the top's leading end and the tiny-numbers badge at its trailing one, clear of
    /// each other; where they don't fit side by side (larger text) the badge goes under the chooser.
    private var topControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                startChooser
                Spacer(minLength: 0)
                tinyBadge
            }
            VStack(alignment: .leading, spacing: 8) {
                startChooser
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    tinyBadge
                }
            }
        }
    }

    /// Where the template starts from, asked until the first edit: what the generator made (the
    /// default), or the photo as one area (Blank), which the painter's lines and paint then make
    /// into the picture. Out of the way while a note shows at the top.
    @ViewBuilder
    private var startChooser: some View {
        if model.refinements.edits.isEmpty, submitted.isEmpty, model.hasLineArtInput, model.note == nil {
            Picker("Start From", selection: Binding(get: { model.refinements.start }, set: { model.start(from: $0) })) {
                Text("Generated").tag(TemplateRefinements.Start.generated)
                Text("Blank").tag(TemplateRefinements.Start.blank)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(6)
            .glassEffect(.regular, in: .capsule)
            .disabled(model.phase == .generating)
            .accessibilityIdentifier("refine-start")
            .transition(.opacity)
        }
    }

    /// How many numbers are near the smallest: a tap brings the next of them up close.
    @ViewBuilder
    private var tinyBadge: some View {
        if !tiny.isEmpty, let template = base?.template {
            Button {
                tinyShown = (tinyShown + 1) % tiny.count
                let label = tiny[tinyShown].label
                focus = RefineFocus(
                    id: (focus?.id ?? 0) + 1, rect: RefineTinyAreas.focus(on: label, in: template), animated: !reduceMotion)
                FeedbackEngine.shared.selectionChanged()
            } label: {
                Label { Text(Self.tinyText(tiny.count)) } icon: { Image(systemName: "magnifyingglass") }
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            .accessibilityHint(Text(String(
                localized: "refine.tiny.hint", defaultValue: "Shows the next one up close.",
                comment: "Refine screen: VoiceOver hint of the badge that counts the areas whose numbers are near the smallest size; a tap zooms in on the next one")))
            .accessibilityIdentifier("refine-tiny")
            .transition(.opacity)
        }
    }

    /// "12 tiny numbers".
    nonisolated static func tinyText(_ count: Int) -> String {
        String(
            localized: "refine.tiny", defaultValue: "\(count) tiny numbers",
            comment: "Refine screen: a badge counting the areas whose numbers are near the smallest a painter can read; a tap zooms in on the next one. The argument is the count")
    }

    /// A line or a cell edge closed off an area of its own: a soft tap, VoiceOver hears of it, and
    /// the sparkles pop where its ends met (none under Reduce Motion).
    private func closed(_ shape: CreateModel.ClosedShape) {
        FeedbackEngine.shared.areaMade()
        AccessibilityNotification.Announcement(String(
            localized: "refine.areaMade", defaultValue: "New area",
            comment: "VoiceOver announcement on the Refine screen when a line the painter drew closed off an area of its own")).post()
        let size = templateSize
        guard !reduceMotion, size.width > 0, size.height > 0 else { return }
        let point = onScreen(SIMD2(shape.at.x / Float(size.width), shape.at.y / Float(size.height)))
        sparkles = (shape.serial, point, CGFloat(shape.extent) * picture.width / size.width)
    }
}

// MARK: Practice

extension RefineView {
    /// A Tool Guide page's practice canvas: the canvas, the tool's options (and the palette, in
    /// Cells and Paint) below it, and above it Undo, Redo, the views and Reset.
    fileprivate var practiceScreen: some View {
        canvas
            .safeAreaInset(edge: .top, spacing: 0) { practiceBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { reservedTools }
            .background(Theme.paper)
    }

    /// Undo and Redo, the views (a segmented control where it fits, else a menu) and Reset.
    private var practiceBar: some View {
        ViewThatFits(in: .horizontal) {
            practiceBarRow { backdropChoice.pickerStyle(.segmented).fixedSize() }
            practiceBarRow { backdropChoice.pickerStyle(.menu) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func practiceBarRow<Views: View>(@ViewBuilder views: () -> Views) -> some View {
        HStack(spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                        .disabled(!model.canUndo)
                        .keyboardShortcut("z")
                        .accessibilityIdentifier("refine-undo")
                    Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                        .disabled(!model.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .accessibilityIdentifier("refine-redo")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            Spacer(minLength: 0)
            views()
            Spacer(minLength: 0)
            Button("Reset", systemImage: "arrow.counterclockwise", action: resetPractice)
                .buttonStyle(.glass)
                .disabled(!model.canUndo && model.refinements.edits.isEmpty)
                .accessibilityHint(Text(String(
                    localized: "refine.practice.reset.hint", defaultValue: "Puts the practice picture back as it was.",
                    comment: "Tool Guide: VoiceOver hint of Reset above a tool's practice canvas, which undoes everything tried on it")))
                .accessibilityIdentifier("refine-practice-reset")
        }
    }

    /// Reset: the practice picture as the page opened it, with the canvas made again (its tool's
    /// options and current paint too).
    private func resetPractice() {
        FeedbackEngine.shared.selectionChanged()
        model.cancelRefining()
        onReset?()
    }
}

/// Try Painting's painting: a session on the template as it stood, which nothing saves.
struct RefineTrial: Identifiable {
    let id = UUID()
    let session: PaintingSession
}

extension RefineView {
    /// Try Painting: the painting screen on the template on screen, once the canvas's renderer is
    /// made (`ArtworkPaintingView` waits for it too). Its fills go when it closes.
    fileprivate func tryPainting() {
        guard let template = base?.template else { return }
        FeedbackEngine.shared.selectionChanged()
        Task {
            _ = await RenderContext.ready()
            trial = RefineTrial(session: PaintingSession(template: template, nicknameVersion: ColorNickname.currentVersion))
        }
    }
}
