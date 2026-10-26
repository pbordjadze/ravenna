import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// What feedback says about where a painting came from, which the painting screen doesn't
/// know: `ArtworkPaintingView` puts it in the environment for `PaintView`, demos make their
/// own. Nil fields are unknown.
nonisolated struct FeedbackSource: Sendable {
    var artworkID: UUID?
    var settings: GenerationSettings?
    /// `Artwork.settingsOrigin` and `Artwork.paintingLength` as stored.
    var settingsOrigin: String?
    var paintingLength: String?
    /// The library picture the painting was made from (`Sample.id`); its photo is in the
    /// repository, so feedback names it instead of attaching it.
    var sampleName: String?
    var createdAt: Date?
    /// The painter's own photo as JPEG, read only when they choose to include it; nil when the
    /// painting has none (a library picture, or a photo that wasn't kept).
    var photo: (@Sendable () async -> Data?)?
}

private nonisolated struct FeedbackSourceKey: EnvironmentKey {
    static let defaultValue: FeedbackSource? = nil
}

extension EnvironmentValues {
    var feedbackSource: FeedbackSource? {
        get { self[FeedbackSourceKey.self] }
        set { self[FeedbackSourceKey.self] = newValue }
    }
}

/// The painting as it was when the painter asked to give feedback: what feedback's pictures
/// show and its report records. Painting is off while feedback is given, so the paint stays
/// as captured; the camera moves on (marks are drawn wherever the painter zooms).
nonisolated struct FeedbackCapture: Sendable {
    var date: Date
    var title: String
    var template: Template
    var progress: PaintProgress
    /// The palette index the brush held (the canvas hatched its unpainted areas).
    var selectedColor: Int?
    /// The colors' nicknames as the painting named them (nil under plain names), and the seed
    /// and vocabulary that pick them (`pbn names --seed … --vocabulary …` prints the same).
    var nicknames: [String?]
    var nicknameSeed: UInt64
    var nicknameVersion: Int
    var showsNumbers: Bool
    var paper: PaperAppearance
    var darkInterface: Bool
    var lineWeight: LineWeight
    /// What was on screen (canvas units, clear of the chrome), at how many points per canvas
    /// unit, on a screen of `displayScale` pixels per point; `relativeZoom` is 1 when the whole
    /// painting fitted.
    var visibleRect: CGRect
    var pointsPerUnit: CGFloat
    var displayScale: CGFloat
    var relativeZoom: CGFloat
    /// "1.0.42 (42)", the device's model identifier ("iPad16,6") and its system ("iPadOS 26.1").
    var app: String
    var device: String
    var system: String
    var source: FeedbackSource?

    /// The paper and ink the painting showed.
    var palette: CanvasPalette { .resolve(paper, interfaceIsDark: darkInterface) }

    var canvasRect: CGRect { CGRect(x: 0, y: 0, width: template.width, height: template.height) }
}

extension FeedbackCapture {
    /// The painting on `session` as the canvas behind `controller` shows it now.
    init(
        session: PaintingSession, title: String, controller: CanvasController, showsNumbers: Bool, paper: PaperAppearance,
        darkInterface: Bool, lineWeight: LineWeight, displayScale: CGFloat, source: FeedbackSource?, date: Date = .now
    ) {
        let template = session.template
        self.init(
            date: date, title: title, template: template, progress: session.progress, selectedColor: session.selectedColor,
            nicknames: (0..<session.paletteCount).map { session.nickname(of: $0) }, nicknameSeed: session.nicknameSeed,
            nicknameVersion: session.nicknameVersion, showsNumbers: showsNumbers,
            paper: paper, darkInterface: darkInterface, lineWeight: lineWeight,
            visibleRect: controller.visibleCanvasRect ?? CGRect(x: 0, y: 0, width: template.width, height: template.height),
            pointsPerUnit: controller.pointsPerUnit ?? 1, displayScale: displayScale,
            relativeZoom: controller.relativeZoom ?? 1, app: "Ravenna \(AppInfo().summary)", device: Self.deviceModel,
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)", source: source)
    }

    /// The hardware model identifier ("iPhone18,1"); the simulated one in the simulator.
    private static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
