import CoreGraphics
import Foundation
import PaintCore
import SwiftUI

/// Swatch geometry at a Dynamic Type size. Numerals grow with text up to 1.4×, so the palette
/// keeps its place on screen at accessibility sizes; the Large Content Viewer covers the rest.
/// At the default size (scale 1) swatches are 40 pt on a 56 pt pitch.
nonisolated struct PaletteMetrics: Equatable, Sendable {
    let scale: CGFloat

    init(scale: CGFloat) { self.scale = scale }

    init(dynamicTypeSize: DynamicTypeSize) {
        let steps: [(DynamicTypeSize, CGFloat)] = [
            (.xLarge, 1.08), (.xxLarge, 1.16), (.xxxLarge, 1.24), (.accessibility1, 1.32), (.accessibility2, 1.4),
        ]
        scale = steps.last(where: { $0.0 <= dynamicTypeSize })?.1 ?? 1
    }

    /// These metrics `factor` times larger, at most 1.6× in all (regular widths' bigger swatches,
    /// `QuietPainting.scale`, on top of the text size's).
    func scaled(by factor: CGFloat) -> PaletteMetrics {
        factor == 1 ? self : PaletteMetrics(scale: min(scale * factor, 1.6))
    }

    static let standard = PaletteMetrics(scale: 1)
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 14
    static let endPadding: CGFloat = 16

    var diameter: CGFloat { 40 * scale }
    /// Distance between neighbouring swatch centres.
    var pitch: CGFloat { diameter + 16 }
    var numeralSize: CGFloat { 16 * scale }
    var checkmarkSize: CGFloat { 15 * scale }
    var captionFontSize: CGFloat { 13 * scale }
    /// Height of the current-color caption row above the swatches (compact widths).
    var captionHeight: CGFloat { (24 * scale).rounded(.up) }

    /// Bar thickness across its axis.
    func thickness(lines: Int, caption: Bool) -> CGFloat {
        CGFloat(lines) * pitch - Self.spacing + 2 * Self.padding + (caption ? captionHeight : 0)
    }

    /// Bar length along its axis for `count` swatches in `lines` lines.
    func length(count: Int, lines: Int) -> CGFloat {
        CGFloat((count + lines - 1) / max(lines, 1)) * pitch - Self.spacing + 2 * Self.endPadding
    }

    /// The fewest lines (up to `maxLines`) that fit `count` swatches in `length` points.
    func lines(count: Int, length: CGFloat, maxLines: Int) -> Int {
        let perLine = max(1, Int((length - 2 * Self.endPadding + Self.spacing) / pitch))
        return min(max(1, maxLines), max(1, (count + perLine - 1) / perLine))
    }
}

/// Where the palette's scroll view stands along the bar, and the offset that brings a lane of
/// swatches into view (`PaletteBar.reveal`). The glass may clip the scroll view: only `shown`
/// points of it, from `hiddenBefore` points in, can be seen, and only they count as in view.
nonisolated struct PaletteWindow: Equatable, Sendable {
    /// The scroll view's content offset, its length and its content's, along the bar.
    var offset: CGFloat
    var viewport: CGFloat
    var content: CGFloat
    var hiddenBefore: CGFloat = 0
    var shown: CGFloat

    /// The offset that shows the swatches of `lane` whole, with `PaletteMetrics.endPadding` to spare
    /// on the side they come in from, moving as little as it can; nil while they show already (or
    /// the bar can't scroll further).
    func offset(revealing lane: Int, metrics: PaletteMetrics) -> CGFloat? {
        let start = PaletteMetrics.endPadding + CGFloat(lane) * metrics.pitch
        let end = start + metrics.pitch - PaletteMetrics.spacing
        let margin = PaletteMetrics.endPadding
        let before = min(max(hiddenBefore, 0), viewport)
        let length = max(0, min(shown, viewport - before))
        let first = offset + before
        let target: CGFloat
        if start - margin < first {
            target = start - margin - before
        } else if end + margin > first + length {
            target = end + margin - length - before
        } else {
            return nil
        }
        let clamped = min(max(target, 0), max(0, content - viewport))
        return abs(clamped - offset) < 0.5 ? nil : clamped
    }
}

/// The paint palette: circular swatches with their number and a progress ring per color;
/// finished colors leave it. Swatches wrap into up to `lines` rows (columns when vertical)
/// in `order`, filling across the bar before along it (`lanes`), so the order reads along the
/// way the bar scrolls; they scroll when they still don't fit, keeping the selected color in view,
/// or the swatch a tap on its color's area just shook.
struct PaletteBar: View {
    let session: PaintingSession
    var axis: Axis = .horizontal
    /// Rows of a horizontal bar, columns of a vertical one.
    var lines = 1
    /// Per color, bumped to shake its swatch (e.g. after tapping a region of that color).
    var shakes: [Int: Int] = [:]
    var metrics: PaletteMetrics = .standard
    /// Shows the selected color's number and name above the swatches, so the color can be
    /// told by name (horizontal bars only; wide layouts show it in the progress badge).
    var showsCurrentColor = false
    /// Every color in its order on screen (`PaintView.colorOrder`), finished ones too.
    let order: [Int]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The color whose details popover is open (long-press on its swatch).
    @State private var detailsColor: Int?
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var scroll = ScrollState()

    /// Where the scroll view and the bar's clipped glass are, and how far it has scrolled. A
    /// reference, so that scrolling renders nothing.
    private final class ScrollState {
        var geometry: ScrollGeometry?
        /// Global frames: the scroll view's, and the bar's as the glass clips it.
        var frame = CGRect.null
        var clip = CGRect.null
        /// A color to bring into view once both frames are known (the bar appearing).
        var pending: Int?
    }

    /// The color whose swatch was just shaken (its count went up), the lowest if several were.
    static func shaken(from old: [Int: Int], to new: [Int: Int]) -> Int? {
        new.filter { $0.value > old[$0.key, default: 0] }.keys.min()
    }

    /// Colors still to paint (plus the selected one): finished colors leave the palette.
    static func visibleColors(_ session: PaintingSession) -> [Int] {
        (0..<session.paletteCount).filter { !session.isColorComplete($0) || session.selectedColor == $0 }
    }

    /// `colors` cut into lanes of `lines` swatches: a bottom bar's columns, read top to bottom
    /// (1 4 7 over 2 5 8 over 3 6 9), a side bar's rows, read leading to trailing.
    static func lanes(_ colors: [Int], lines: Int) -> [[Int]] {
        let size = max(lines, 1)
        return stride(from: 0, to: colors.count, by: size).map { Array(colors[$0..<min($0 + size, colors.count)]) }
    }

    /// The paint of palette color `index` as a SwiftUI color.
    static func paint(_ template: Template, _ index: Int) -> Color {
        let rgb = template.palette[index].rgb
        return Color(template.colorSpace == .displayP3 ? .displayP3 : .sRGB,
                     red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }

    /// The ink of the number on palette color `index`.
    static func numeralInk(_ template: Template, _ index: Int) -> Color {
        ColorScience.relativeLuminance(encoded: template.palette[index].rgb, space: template.colorSpace) > darkInkLuminance
            ? Color.black.opacity(0.75) : Color.white
    }

    /// Paints lighter than this (relative luminance) take dark numerals, the rest white ones.
    private static let darkInkLuminance: Float = 0.36

    var body: some View {
        let visible = Set(Self.visibleColors(session))
        let colors = order.filter(visible.contains)
        let count = max(colors.count, 1)
        let lineCount = max(1, min(lines, count))
        let lanes = Self.lanes(colors, lines: lineCount)
        let horizontal = axis == .horizontal
        // Lanes run along the bar, each one swatch per line across it.
        let along = horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: PaletteMetrics.spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: PaletteMetrics.spacing))
        let across = horizontal
            ? AnyLayout(VStackLayout(spacing: PaletteMetrics.spacing))
            : AnyLayout(HStackLayout(spacing: PaletteMetrics.spacing))
        let caption = showsCurrentColor && axis == .horizontal
        let thickness = metrics.thickness(lines: lineCount, caption: caption)
        let radius = min(thickness / 2, 38)
        // A caption needs room for a long name even when few swatches are left.
        let minLength = caption ? 260 * metrics.scale : 0
        let transition: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
        VStack(spacing: 0) {
            if caption {
                CurrentColorLabel(session: session, font: .system(size: metrics.captionFontSize, weight: .semibold))
                    .frame(height: metrics.captionHeight - 8)
                    .padding(.top, 8)
                    .padding(.horizontal, PaletteMetrics.endPadding)
            }
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                along {
                    ForEach(lanes.indices, id: \.self) { lane in
                        across {
                            ForEach(lanes[lane], id: \.self) { index in
                                swatch(index).id(index)
                                    .transition(transition)
                            }
                        }
                    }
                }
                .padding(axis == .horizontal ? .horizontal : .vertical, PaletteMetrics.endPadding)
                .padding(axis == .horizontal ? .vertical : .horizontal, PaletteMetrics.padding)
                .frame(minWidth: minLength, alignment: .center)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in
                scroll.geometry = geometry
                revealPending()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                scroll.frame = frame
                revealPending()
            }
            // The bar moves only as far as brings the selected swatch into view, and not at all while
            // it shows: centring it pulled the palette to its middle at every change of color.
            .onAppear {
                if let selected = session.selectedColor { reveal(selected, animated: false) }
            }
            .onChange(of: session.selectedColor) { _, selected in
                if let selected { reveal(selected, animated: true) }
            }
            // A tap on another color's area shakes that color's swatch: scrolled out of view, it
            // shook unseen and the tap seemed to do nothing (QA, October 21), so the bar brings it in.
            .onChange(of: shakes) { old, new in
                if let shaken = Self.shaken(from: old, to: new) { reveal(shaken, animated: true) }
            }
        }
        .frame(width: axis == .vertical ? thickness : nil,
               height: axis == .horizontal ? thickness : nil)
        .frame(maxWidth: axis == .horizontal ? max(metrics.length(count: count, lines: lineCount), minLength) : nil,
               maxHeight: axis == .vertical ? metrics.length(count: count, lines: lineCount) : nil)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            scroll.clip = frame
            revealPending()
        }
        .clipShape(.rect(cornerRadius: radius))
        .glassEffect(.regular, in: .rect(cornerRadius: radius))
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: colors)
    }

    /// Scrolls the swatch of `color` whole into view, as little as it can. Not `ScrollViewReader`'s
    /// `scrollTo` without an anchor: on a phone it left the swatch three places past the bar's
    /// leading edge, under the glass (Paul, October 18: "When I tap "10" the palette scrolls but not
    /// such that 10 is visible"); the scroll view counted more of itself in view than the glass shows.
    /// So the offset is worked out here, from the swatches' places and what the glass shows.
    private func reveal(_ color: Int, animated: Bool) {
        let horizontal = axis == .horizontal
        guard !scroll.frame.isNull, !scroll.clip.isNull else {
            scroll.pending = color
            return
        }
        scroll.pending = nil
        let visible = Set(Self.visibleColors(session))
        let colors = order.filter(visible.contains)
        let lineCount = max(1, min(lines, colors.count))
        let lanes = Self.lanes(colors, lines: lineCount)
        guard let lane = lanes.firstIndex(where: { $0.contains(color) }) else { return }
        let frameLength = horizontal ? scroll.frame.width : scroll.frame.height
        // Before the scroll view first reports its geometry it hasn't scrolled: the content sits at
        // its start, as long as the swatches lay it out.
        let geometry = scroll.geometry
        let window = PaletteWindow(
            offset: geometry.map { horizontal ? $0.contentOffset.x : $0.contentOffset.y } ?? 0,
            viewport: geometry.map { horizontal ? $0.containerSize.width : $0.containerSize.height } ?? frameLength,
            content: geometry.map { horizontal ? $0.contentSize.width : $0.contentSize.height }
                ?? metrics.length(count: max(colors.count, 1), lines: lineCount),
            hiddenBefore: horizontal ? scroll.clip.minX - scroll.frame.minX : scroll.clip.minY - scroll.frame.minY,
            shown: horizontal ? scroll.clip.width : scroll.clip.height)
        guard let target = window.offset(revealing: lane, metrics: metrics) else { return }
        withAnimation(animated && !reduceMotion ? .smooth(duration: 0.35) : nil) {
            if horizontal { position.scrollTo(x: target) } else { position.scrollTo(y: target) }
        }
    }

    private func revealPending() {
        if let color = scroll.pending { reveal(color, animated: false) }
    }

    private func swatch(_ index: Int) -> some View {
        let template = session.template
        let total = session.totalByColor[index]
        let painted = total - session.remainingByColor[index]
        let fraction = 1 - Double(session.remainingByColor[index]) / Double(max(total, 1))
        let complete = session.isColorComplete(index)
        let selected = session.selectedColor == index
        let nickname = session.nickname(of: index)
        return Button {
            // A long press that opened the details also ends in a release over the swatch.
            guard detailsColor == nil else { return }
            if selected {
                session.showHint()
            } else {
                session.select(color: index)
                FeedbackEngine.shared.selectionChanged()
            }
        } label: {
            Swatch(
                number: index + 1, color: Self.paint(template, index), ink: Self.numeralInk(template, index), fraction: fraction,
                isComplete: complete, isSelected: selected, metrics: metrics, reduceMotion: reduceMotion)
                .modifier(Shake(amount: CGFloat(shakes[index] ?? 0)))
        }
        .buttonStyle(.plain)
        // Details take precedence over the button's selection gesture. Recognizing both
        // simultaneously let a held swatch select its color instead of opening the popover.
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in detailsColor = index })
        .popover(isPresented: detailsBinding(index), arrowEdge: axis == .horizontal ? .bottom : .trailing) {
            SwatchDetails(
                number: index + 1, nickname: nickname, shade: session.colorTitles[index], hex: template.palette[index].hexCode)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(session.colorLabels[index])
        .accessibilityValue(PaintSpeech.colorProgress(painted: painted, total: total))
        .accessibilityHint(PaintSpeech.swatchHint(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: Text("Show Color Details")) { detailsColor = index }
        // The tips about the selected color (Tap to Paint, Can't Find It?) point at its swatch: over
        // a bottom bar, beside a trailing one, and over it again at the largest text sizes, where
        // beside would leave no room for the words.
        .gentleTip(
            .benchTap, .benchFind, active: selected,
            arrowEdge: axis == .horizontal || dynamicTypeSize.isAccessibilitySize ? .bottom : .trailing)
        .accessibilityIdentifier("swatch-\(index + 1)")
        .accessibilityShowsLargeContentViewer {
            Text(session.numberedColorNames[index])
        }
    }

    private func detailsBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { detailsColor == index }, set: { if !$0 && detailsColor == index { detailsColor = nil } })
    }
}

/// What a long press on a swatch shows: the paint's number, nickname (when it has one), plain
/// color name and hex code.
private struct SwatchDetails: View {
    let number: Int
    let nickname: String?
    let shade: String
    let hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(Text("Number"), "\(number)", id: "number")
            if let nickname { row(Text("Name"), nickname, id: "name") }
            row(Text("Shade"), shade, id: "shade")
            row(Text("Hex"), hex, id: "hex")
        }
        .padding(16)
        .frame(minWidth: 240)
        .fixedSize(horizontal: false, vertical: true)
        // A container of its own: on a plain stack the identifier would replace each row's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swatch-details")
    }

    private func row(_ title: Text, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            title.foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(verbatim: value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swatch-details-\(id)")
    }
}

/// The selected color's number, paint and name ("12 · Harbor Fog", or "12 · Dark green" under
/// Plain names), for people who can't tell the paints apart by eye. Renders nothing when no color is selected.
struct CurrentColorLabel: View {
    let session: PaintingSession
    let font: Font

    var body: some View {
        if let color = session.selectedColor {
            HStack(spacing: 6) {
                Circle()
                    .fill(PaletteBar.paint(session.template, color))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                Text(session.numberedColorNames[color])
                    .font(font)
                    .lineLimit(1)
                    // Translated names can run long; the caption's height is fixed.
                    .minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "paint.currentColor", defaultValue: "Current color",
                                       comment: "VoiceOver label of the selected color's name shown on screen"))
            .accessibilityValue(session.colorLabels[color])
            .accessibilityIdentifier("current-color")
            // Text to read, not a control: no touch target to size.
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

private struct Swatch: View {
    let number: Int
    let color: Color
    let ink: Color
    let fraction: Double
    let isComplete: Bool
    let isSelected: Bool
    let metrics: PaletteMetrics
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: metrics.checkmarkSize, weight: .heavy))
            } else {
                Text(verbatim: "\(number)")
                    .font(.system(size: metrics.numeralSize, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(ink)
        .frame(width: metrics.diameter, height: metrics.diameter)
        .padding(4)
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(isSelected ? 0.16 : 0.08), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.primary.opacity(isSelected ? 0.85 : 0.4), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .opacity(isComplete && !isSelected ? 0.4 : 1)
        .scaleEffect(isSelected ? 1.14 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
        // The touch area is the whole pitch, square: a tap between two swatches or in a corner
        // lands on the nearer one instead of on nothing. The layout keeps the swatch's size.
        .padding(PaletteMetrics.spacing / 2)
        .contentShape(.rect)
        .padding(-PaletteMetrics.spacing / 2)
    }
}

/// A short horizontal shake; animate `amount` by +1 to play it once.
nonisolated private struct Shake: GeometryEffect {
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(amount * .pi * 4), y: 0))
    }
}
