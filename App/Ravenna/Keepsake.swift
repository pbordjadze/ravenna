import SwiftUI
import UIKit

/// The wall as a picture to keep or send: every tile set so far, in the painter's finish, about
/// 3,000 pixels on its long side. A finished wall has no outlines left; one in progress shows
/// where its tiles still go.
struct Keepsake: Identifiable {
    let id = UUID()
    let image: UIImage

    static func make(_ m: Mosaic, _ finish: Finish, setting: Setting, bed: UIImage?) async -> Keepsake? {
        let ground = Unchecked(bed?.cgImage), set = setting.set
        let made = await Task.detached(priority: .userInitiated) {
            Unchecked(WallImage.make(m, finish, bed: ground.value, set: set, longest: 3000, outlines: set.count < m.tiles.count)?.current)
        }.value
        return made.value.map { Keepsake(image: UIImage(cgImage: $0)) }
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
