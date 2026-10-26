import SwiftUI

/// Ravenna: a picture laid as a Byzantine mosaic, set tile by tile.
@main
struct RavennaApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(Theme.tint)
        }
    }
}
