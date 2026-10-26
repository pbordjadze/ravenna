import SwiftUI
import UIKit

/// How much of the photo goes on the wall: the whole of it, or a panel of a chosen shape the
/// painter slides over it, as a setter squares off the part of a cartoon they'll lay.
nonisolated enum Panel: String, CaseIterable, Identifiable, Sendable {
    case whole, square, upright, wide
    var id: Self { self }

    var name: String {
        switch self {
        case .whole: "Whole"
        case .square: "Square"
        case .upright: "Upright"
        case .wide: "Wide"
        }
    }

    /// Width over height, or nil for the photo's own.
    var aspect: CGFloat? {
        switch self {
        case .whole: nil
        case .square: 1
        case .upright: 4 / 5
        case .wide: 3 / 2
        }
    }

    /// The panel in the photo's unit square (width `size.width` by `size.height`, any units), as
    /// large as fits, its centre at `centre` as far as the photo allows.
    func rect(in size: CGSize, centre: CGPoint) -> CGRect {
        guard let aspect, size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let photo = size.width / size.height
        let w = aspect < photo ? aspect / photo : 1, h = aspect < photo ? 1 : photo / aspect
        let x = min(max(centre.x - w / 2, 0), 1 - w), y = min(max(centre.y - h / 2, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The photo cut to `unit` (in its upright unit square), re-encoded, at most `longSide` px: the
    /// most the Pieces slider's top asks for, twice over.
    static func cut(_ data: Data, to unit: CGRect, longSide: Int = 2896) -> Data? {
        if unit == CGRect(x: 0, y: 0, width: 1, height: 1) { return data }
        let k = 1 / max(unit.width, unit.height)
        guard let image = Maker.oriented(data, longSide: Int(CGFloat(longSide) * k)) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let r = CGRect(x: unit.minX * w, y: unit.minY * h, width: unit.width * w, height: unit.height * h).integral
        guard let cut = image.cropping(to: r) else { return nil }
        return Maker.jpeg(cut)
    }
}

/// The photo with the panel over it: drag to move the panel; outside it, the photo dims.
struct FramingView: View {
    let image: UIImage
    let panel: Panel
    @Binding var centre: CGPoint
    @State private var start: CGPoint?

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .overlay {
                GeometryReader { g in
                    let unit = panel.rect(in: image.size, centre: centre)
                    let r = CGRect(x: unit.minX * g.size.width, y: unit.minY * g.size.height,
                                   width: unit.width * g.size.width, height: unit.height * g.size.height)
                    if panel != .whole {
                        Path { p in p.addRect(CGRect(origin: .zero, size: g.size)); p.addRect(r) }
                            .fill(Theme.ground.opacity(0.62), style: FillStyle(eoFill: true))
                        Rectangle().stroke(Theme.tint, lineWidth: 1.5).frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let from = start ?? CGPoint(x: unit.midX, y: unit.midY)
                            start = from
                            centre = clamped(CGPoint(x: from.x + v.translation.width / g.size.width,
                                                     y: from.y + v.translation.height / g.size.height))
                        }.onEnded { _ in start = nil })
                        .allowsHitTesting(panel != .whole)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Your photo")
            .accessibilityValue(panel == .whole ? "All of it" : "\(panel.name) panel, \(place)")
            .accessibilityActions {
                if panel != .whole {
                    Button("Move left") { nudge(-0.1, 0) }
                    Button("Move right") { nudge(0.1, 0) }
                    Button("Move up") { nudge(0, -0.1) }
                    Button("Move down") { nudge(0, 0.1) }
                }
            }
    }

    /// Where the panel sits, in words.
    private var place: String {
        let unit = panel.rect(in: image.size, centre: centre)
        let across = unit.width >= 0.999 ? "" : unit.midX < 0.4 ? "left" : unit.midX > 0.6 ? "right" : "centre"
        let down = unit.height >= 0.999 ? "" : unit.midY < 0.4 ? "top" : unit.midY > 0.6 ? "bottom" : "middle"
        return [down, across].filter { !$0.isEmpty }.joined(separator: " ").ifEmpty("all across")
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        let unit = panel.rect(in: image.size, centre: centre)
        centre = clamped(CGPoint(x: unit.midX + dx, y: unit.midY + dy))
    }

    /// The centre, kept where the panel stays on the photo.
    private func clamped(_ c: CGPoint) -> CGPoint {
        let unit = panel.rect(in: image.size, centre: c)
        return CGPoint(x: unit.midX, y: unit.midY)
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
