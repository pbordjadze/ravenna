import CoreGraphics
import SwiftUI

/// Loads the photo the open painting was made from, for the painting screen's photo peek:
/// read by `PaintView` (`@Environment(\.sourcePhotoLoader)`) and called by `CanvasView`.
nonisolated struct SourcePhotoLoader: Sendable {
    let load: @Sendable (_ maxPixelSize: Int?) async -> CGImage?

    func callAsFunction(maxPixelSize: Int? = nil) async -> CGImage? { await load(maxPixelSize) }
}

private nonisolated struct SourcePhotoLoaderKey: EnvironmentKey {
    static let defaultValue: SourcePhotoLoader? = nil
}

extension EnvironmentValues {
    var sourcePhotoLoader: SourcePhotoLoader? {
        get { self[SourcePhotoLoaderKey.self] }
        set { self[SourcePhotoLoaderKey.self] = newValue }
    }
}
