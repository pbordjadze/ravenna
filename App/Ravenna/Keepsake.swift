import SwiftUI
import UIKit

/// The wall as a picture to keep or send: every tile set so far, in the painter's finish, about
/// 3,000 pixels on its long side. A finished wall has no outlines left; one in progress shows
/// where its tiles still go.
struct Keepsake: Identifiable {
    let id = UUID()
    let image: UIImage

    static func make(_ m: Mosaic, _ finish: Finish, setting: Setting, bed: UIImage?, border: Border = .none) async -> Keepsake? {
        let ground = Unchecked(bed?.cgImage), set = setting.set
        let made = await Task.detached(priority: .userInitiated) {
            let wall = WallImage.make(m, finish, bed: ground.value, set: set, longest: 3000, outlines: set.count < m.tiles.count)?.current
            return Unchecked(wall.flatMap { border.around($0, m, finished: set.count == m.tiles.count) } ?? wall)
        }.value
        return made.value.map { Keepsake(image: UIImage(cgImage: $0)) }
    }
}

/// What goes round the shared picture (an option): nothing, a margin of lime plaster, or a band
/// of square tesserae in the plaster, as a panel's border is laid.
nonisolated enum Border: String, CaseIterable, Identifiable, Sendable {
    case none, plaster, band
    var id: Self { self }

    var name: String {
        switch self {
        case .none: "None"
        case .plaster: "Plaster"
        case .band: "A band of tesserae"
        }
    }

    /// `wall` with the border round it, or nil for none. The band alternates the mosaic's darkest
    /// paint with gold on a finished wall, or with its lightest paint on one in progress.
    func around(_ wall: CGImage, _ m: Mosaic, finished: Bool) -> CGImage? {
        guard self != .none else { return nil }
        let w = CGFloat(wall.width), h = CGFloat(wall.height)
        let tile = max(w, h) / 90, gap = tile * 0.16
        let margin = self == .band ? tile * 3.2 : tile * 1.6
        let size = CGSize(width: w + 2 * margin, height: h + 2 * margin)
        guard let cg = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(red: 0.914, green: 0.886, blue: 0.827, alpha: 1)  // Theme.plaster
        cg.fill(CGRect(origin: .zero, size: size))
        cg.draw(wall, in: CGRect(x: margin, y: margin, width: w, height: h))
        if self == .band {
            let luma = { (c: SIMD3<Float>) in 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
            let dark = m.palette.min { luma($0) < luma($1) } ?? SIMD3(0.1, 0.1, 0.1)
            let light = finished ? SIMD3<Float>(0.788, 0.635, 0.290) /* Theme.gold */ : (m.palette.max { luma($0) < luma($1) } ?? SIMD3(0.9, 0.9, 0.9))
            // The band's centre line, a tile and a bit in from the edge; tiles fitted evenly along each side.
            let inset = tile * 0.9 + tile / 2
            let ring = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            var k = 0
            for (a, b) in [(CGPoint(x: ring.minX, y: ring.minY), CGPoint(x: ring.maxX, y: ring.minY)),
                           (CGPoint(x: ring.maxX, y: ring.minY), CGPoint(x: ring.maxX, y: ring.maxY)),
                           (CGPoint(x: ring.maxX, y: ring.maxY), CGPoint(x: ring.minX, y: ring.maxY)),
                           (CGPoint(x: ring.minX, y: ring.maxY), CGPoint(x: ring.minX, y: ring.minY))] {
                let length = hypot(b.x - a.x, b.y - a.y), n = max(1, Int((length / (tile + gap)).rounded()))
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n)
                    let c = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    let j = { (salt: UInt64) in CGFloat(TileColor.wobble(k, salt: salt)) * tile * 0.05 }
                    let body = k.isMultiple(of: 2) ? dark : light
                    cg.setFillColor(red: CGFloat(body.x), green: CGFloat(body.y), blue: CGFloat(body.z), alpha: 1)
                    let half = (tile - gap) / 2
                    cg.beginPath()
                    cg.move(to: CGPoint(x: c.x - half + j(1), y: c.y - half + j(2)))
                    cg.addLine(to: CGPoint(x: c.x + half + j(3), y: c.y - half + j(4)))
                    cg.addLine(to: CGPoint(x: c.x + half + j(5), y: c.y + half + j(6)))
                    cg.addLine(to: CGPoint(x: c.x - half + j(7), y: c.y + half + j(8)))
                    cg.closePath()
                    cg.fillPath()
                    k += 1
                }
            }
        }
        return cg.makeImage()
    }
}

/// The system's share sheet: Save Image, Messages, AirDrop and the rest.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
