import Foundation
import SwiftUI

/// Before/after: the photo on the leading side of a draggable divider, the template's picture
/// (Ravenna's seam: the mosaic, its tiles set; Paint by Moonlight's line art is left out) on the
/// trailing side. New pictures
/// crossfade in, a photo's first with the divider sweeping in from the trailing edge
/// (`sweepIn`). Pinch or double-tap zooms both layers alike (up to `maxZoom`) to check an eye or
/// a line of writing, and the zoom holds while the sliders change the template; zoomed in, a drag
/// pans and the divider moves by its handle. The comparison takes the photo's shape, or fills
/// the space it is given (`fillsSpace`, the enlarged preview) with the picture fitted inside it,
/// where zooming in lets the picture grow to the whole space.
struct CompareView: View {
    let photo: CGImage
    let after: CreateModel.Picture?
    /// Identity of `after`; a change crossfades.
    let afterID: String
    /// Names the template layer on the trailing side (already localized).
    let afterLabel: String
    let aspectRatio: CGFloat
    /// The space the painting screen fits a painting into (the window): line art is drawn as
    /// heavy as the canvas would draw it at the picture's size relative to that.
    var canvasSize: CGSize = .zero
    var fillsSpace = false
    /// Fraction of the picture's width showing the photo; purely presentational, so owned here.
    @State private var split: CGFloat = 0.5
    /// The layers' zoom (1 fits the picture in the frame) and offset from the frame's centre, as
    /// committed and as a gesture in progress shows them.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var liveZoom: CGFloat?
    @State private var liveOffset: CGSize?
    @State private var frameSize: CGSize = .zero
    /// The divider has swept in for this photo's first picture (`sweepIn`).
    @State private var hasSwept = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maxZoom: CGFloat = 4
    /// Where a double tap zooms to.
    static let tapZoom: CGFloat = 2.5

    var body: some View {
        CompareFrame(aspectRatio: aspectRatio, fills: fillsSpace) {
            GeometryReader { geo in
                let size = geo.size
                let picture = pictureRect(in: size)
                let visible = Self.visible(picture, in: size)
                let x = after == nil ? visible.maxX : visible.minX + visible.width * split
                ZStack(alignment: .topLeading) {
                    card(visible)

                    ZStack(alignment: .topLeading) {
                        ZStack {
                            if let after {
                                afterLayer(after, picture: picture, size: size)
                                    .id(afterID)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: afterID)

                        imageLayer(photo, size: size)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: max(0, x))
                            }

                        if after != nil {
                            divider(at: x, in: visible, size: size)
                        }

                        labels(split: after == nil ? 1 : split)
                            .frame(width: visible.width)
                            .offset(x: visible.minX, y: visible.minY)
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .mask(alignment: .topLeading) { placed(Self.cardShape, in: visible) }

                    placed(Self.cardShape.strokeBorder(Theme.hairline, lineWidth: 0.5), in: visible)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height)
                .coordinateSpace(.named(Self.space))
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            // A pinch's first finger isn't a drag.
                            guard liveZoom == nil else { return }
                            if shownZoom > 1 {
                                liveOffset = clamped(
                                    CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                                    zoom: shownZoom, in: size)
                            } else {
                                moveDivider(to: value.location.x, in: size)
                            }
                        }
                        .onEnded { _ in
                            if let liveOffset { offset = liveOffset }
                            liveOffset = nil
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let z = min(max(zoom * value.magnification, 1), Self.maxZoom)
                            liveZoom = z
                            liveOffset = clamped(zoomedOffset(about: value.startLocation, to: z, in: size), zoom: z, in: size)
                        }
                        .onEnded { _ in
                            if let liveZoom { zoom = liveZoom }
                            if let liveOffset { offset = liveOffset }
                            liveZoom = nil
                            liveOffset = nil
                        }
                )
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    withAnimation(reduceMotion ? nil : .snappy) {
                        if zoom > 1 {
                            zoom = 1
                            offset = .zero
                        } else {
                            offset = clamped(zoomedOffset(about: location, to: Self.tapZoom, in: size), zoom: Self.tapZoom, in: size)
                            zoom = Self.tapZoom
                        }
                    }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            frameSize = size
            // A resized frame (the enlarged preview, a rotation) keeps the zoomed picture over it.
            offset = clamped(offset, zoom: zoom, in: size)
        }
        // Another photo starts fitted, its divider waiting at the trailing edge for the picture.
        .onChange(of: ObjectIdentifier(photo)) {
            zoom = 1
            offset = .zero
            hasSwept = false
            if after == nil { split = 1 }
        }
        // Without a picture the divider stands at the trailing edge whatever `split` is: setting
        // it there before one arrives gives the sweep its start without a frame of its own.
        .onAppear { if after == nil { split = 1 } }
        .onChange(of: after == nil) { _, isNil in
            if !isNil { sweepIn() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comparison of photo and painting")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(1, split + 0.1)
            case .decrement: split = max(0, split - 0.1)
            @unknown default: break
            }
        }
        .accessibilityZoomAction { action in
            let z = action.direction == .zoomIn ? min(zoom * 1.5, Self.maxZoom) : max(zoom / 1.5, 1)
            offset = clamped(CGSize(width: offset.width * z / zoom, height: offset.height * z / zoom), zoom: z, in: frameSize)
            zoom = z
        }
        .accessibilityIdentifier("compare")
    }

    private var shownZoom: CGFloat { liveZoom ?? zoom }
    private var shownOffset: CGSize { liveOffset ?? offset }

    private var accessibilityValue: String {
        guard zoom > 1 else {
            return String(
                localized: "create.compare.value", defaultValue: "\(Int((split * 100).rounded())) percent photo",
                comment: "VoiceOver value of the before/after comparison: the whole percentage of the width showing the photo")
        }
        let photo = Double(split).formatted(.percent.precision(.fractionLength(0)))
        let zoomed = Double(zoom).formatted(.percent.precision(.fractionLength(0)))
        return String(
            localized: "create.compare.zoomedValue", defaultValue: "\(photo) photo, zoomed to \(zoomed)",
            comment: "VoiceOver value of the before/after comparison while zoomed in: the share of the width showing the photo and the zoom, both as percentages, e.g. 50% photo, zoomed to 250%")
    }

    // MARK: Geometry

    /// `aspect` (width over height) fitted inside `size`.
    nonisolated static func fitted(_ aspect: CGFloat, in size: CGSize) -> CGSize {
        guard aspect > 0, aspect.isFinite, size.width > 0, size.height > 0 else { return size }
        return size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
    }

    /// The picture in a frame of `size`: fitted and centred, then zoomed and moved as shown. In a
    /// frame of the photo's shape it fills the frame until zoomed in.
    private func pictureRect(in size: CGSize) -> CGRect {
        let fitted = Self.fitted(aspectRatio, in: size)
        let width = fitted.width * shownZoom, height = fitted.height * shownZoom
        return CGRect(
            x: (size.width - width) / 2 + shownOffset.width, y: (size.height - height) / 2 + shownOffset.height,
            width: width, height: height)
    }

    /// The part of `picture` inside the frame: the card the comparison shows.
    private static func visible(_ picture: CGRect, in size: CGSize) -> CGRect {
        let visible = picture.intersection(CGRect(origin: .zero, size: size))
        return visible.isNull ? .zero : visible
    }

    private func moveDivider(to x: CGFloat, in size: CGSize) {
        let visible = Self.visible(pictureRect(in: size), in: size)
        guard after != nil, visible.width > 0 else { return }
        PaintTips.dividerMoved()
        split = min(max((x - visible.minX) / visible.width, 0), 1)
    }

    /// The offset that keeps the content under `location` (in the frame) where it is while the
    /// zoom goes to `z`.
    private func zoomedOffset(about location: CGPoint, to z: CGFloat, in size: CGSize) -> CGSize {
        let p = CGPoint(x: location.x - size.width / 2, y: location.y - size.height / 2)
        let ratio = z / max(zoom, 1)
        return CGSize(width: p.x - (p.x - offset.width) * ratio, height: p.y - (p.y - offset.height) * ratio)
    }

    /// `offset` limited so the zoomed picture still covers the frame where it is larger than
    /// the frame, and stays centred where it is not.
    private func clamped(_ offset: CGSize, zoom z: CGFloat, in size: CGSize) -> CGSize {
        let fitted = Self.fitted(aspectRatio, in: size)
        let x = max(0, (fitted.width * z - size.width) / 2), y = max(0, (fitted.height * z - size.height) / 2)
        return CGSize(width: min(max(offset.width, -x), x), height: min(max(offset.height, -y), y))
    }

    // MARK: Layers

    /// An image fitted in a frame of `size` (cropped to the photo's shape), zoomed and moved as
    /// shown, so masks line up with the frame.
    private func imageLayer(_ image: CGImage, size: CGSize) -> some View {
        let fitted = Self.fitted(aspectRatio, in: size)
        return Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: fitted.width, height: fitted.height)
            .clipped()
            .scaleEffect(shownZoom)
            .offset(shownOffset)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    @ViewBuilder
    private func afterLayer(_ after: CreateModel.Picture, picture: CGRect, size: CGSize) -> some View {
        switch after {
        case .painting(let image):
            imageLayer(image, size: size)
        }
    }

    private static let cardShape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

    /// `content` sized and placed as `rect` in the frame's top-leading coordinates.
    private func placed(_ content: some View, in rect: CGRect) -> some View {
        content
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// The card under the picture, and its shadow.
    private func card(_ rect: CGRect) -> some View {
        placed(Self.cardShape.fill(Theme.surface).shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10), in: rect)
    }

    /// The divider's handle drags it whatever the zoom.
    private func divider(at x: CGFloat, in visible: CGRect, size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2.5, height: visible.height)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .allowsHitTesting(false)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { value in moveDivider(to: value.location.x, in: size) }
                )
                // Compare Photo and Page: hung below the handle.
                .gentleTip(.newPaintingDivider, arrowEdge: .top)
        }
        .position(x: x, y: visible.midY)
    }

    private static let space = "compare"

    /// The photo's first picture arrives from the trailing edge, the divider sweeping from there
    /// to the middle: before and after, shown rather than said. Once per photo, when the view
    /// saw it arrive; Reduce Motion or a zoom puts the divider in the middle at once, and a
    /// divider the painter moved while waiting stays where it is.
    private func sweepIn() {
        guard !hasSwept else { return }
        hasSwept = true
        guard split == 1 else { return }
        if reduceMotion || zoom != 1 || liveZoom != nil || liveOffset != nil {
            split = 0.5
        } else {
            withAnimation(.smooth(duration: 0.9).delay(0.15)) { split = 0.5 }
        }
    }

    private func labels(split: CGFloat) -> some View {
        // Tight enough for both words on a tall photo's narrow preview on a phone.
        HStack(spacing: 6) {
            caption(String(localized: "Photo")).opacity(split > 0.16 ? 1 : 0)
            Spacer(minLength: 0)
            caption(afterLabel).opacity(split < 0.84 ? 1 : 0)
        }
        .padding(10)
        .animation(.easeOut(duration: 0.15), value: split > 0.16)
        .animation(.easeOut(duration: 0.15), value: split < 0.84)
        .allowsHitTesting(false)
    }

    // Not named `tag`: that would resolve `tag("Photo")` to `View.tag(_:)` on `self` and nest
    // the whole comparison inside its own overlay, recursing until the stack overflows.
    /// White on a dark scrim: legible over any photo, light or dark.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: .capsule)
    }
}

/// The comparison's size: the photo's shape fitted into the space offered (a card), or all of
/// that space (`fills`). One layout for both, so the comparison keeps its zoom and divider while
/// the preview is enlarged, and its frame animates between the two.
private struct CompareFrame: Layout {
    var aspectRatio: CGFloat
    var fills: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let aspect = aspectRatio > 0 && aspectRatio.isFinite ? aspectRatio : 1
        switch (proposal.width, proposal.height) {
        case let (width?, height?) where width.isFinite && height.isFinite:
            let space = CGSize(width: width, height: height)
            return fills ? space : CompareView.fitted(aspect, in: space)
        case let (width?, _) where width.isFinite:
            return CGSize(width: width, height: width / aspect)
        case let (_, height?) where height.isFinite:
            return CGSize(width: height * aspect, height: height)
        default:
            return CGSize(width: 320, height: 320 / aspect)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}
