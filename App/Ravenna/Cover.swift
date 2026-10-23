import SwiftUI
import UIKit

/// A work's cover in the gallery: its painted bed with the painter's tiles set on it, so each card
/// shows how far it has come in its own tiles. A work not begun shows its bed alone.
struct Cover: View {
    @Environment(Library.self) private var library
    let work: Work
    @State private var image: UIImage?
    @AppStorage(Keys.ground) private var ground = GroundChoice.picture

    var body: some View {
        let progress = library.progress(work)
        let set = library.setting(work, library.detail).set
        let key = "\(work.id)-\(library.detail.rawValue)-\(library.finish.rawValue)-\(ground.rawValue)-\(set.count)"
        Group {
            if let shown = progress > 0 ? image ?? library.image(work, "bed") : library.image(work, "bed") {
                Image(uiImage: shown).resizable().scaledToFill()
            } else {
                Theme.panel
            }
        }
        .accessibilityHidden(true)
        .task(id: key) {
            guard !set.isEmpty else { image = nil; return }
            if let cached = Covers.shared.images[key] { image = cached; return }
            guard let m = try? await library.mosaic(work, library.detail) else { return }
            let finish = library.finish, bed = Unchecked(library.image(work, "bed")?.cgImage), ground = self.ground
            let made = await Task.detached(priority: .utility) {
                Unchecked(WallImage.make(ground.applied(to: m), finish, bed: bed.value, set: set, longest: 720, outlines: false)?.current)
            }.value
            guard let cg = made.value else { return }
            let cover = UIImage(cgImage: cg)
            Covers.shared.keep(key, cover)
            image = cover
        }
    }
}

/// Covers already drawn, the latest few.
final class Covers {
    static let shared = Covers()
    private(set) var images: [String: UIImage] = [:]
    private var order: [String] = []

    func keep(_ key: String, _ image: UIImage) {
        images[key] = image
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > 24 { images[order.removeFirst()] = nil }
    }
}
