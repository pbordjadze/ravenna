import Foundation
import PaintCore
import UIKit

/// What VoiceOver says on the painting screen. Pure, so the palette, the canvas, the chrome
/// and the tests share one wording.
nonisolated enum PaintSpeech {
    /// "12, dark green": the number people see on the canvas, then the color's name. With a
    /// nickname it reads "12, Harbor Fog, dark grayish blue", so the structured name isn't lost.
    static func colorLabel(number: Int, name: ColorName, nickname: String? = nil) -> String {
        let color = ColorNameText.string(name)
        guard let nickname else {
            return String(localized: "paint.speech.colorLabel", defaultValue: "\(number), \(color)",
                          comment: "VoiceOver label of a palette color: its number, then its name (e.g. “12, dark green”)")
        }
        return String(localized: "paint.speech.colorLabel.nickname", defaultValue: "\(number), \(nickname), \(color)",
                      comment: "VoiceOver label of a palette color that has a playful nickname: its number, the nickname, then its plain color name (e.g. “12, Harbor Fog, dark grayish blue”)")
    }

    /// Whole percent painted, rounded down; 0 only when nothing is painted and 100 only when
    /// everything is, so the first fill and the last always change it. The one rule for every
    /// percentage of a painting the painter sees or hears (the badge, the gallery, VoiceOver):
    /// rounded down alone, the first fills of a large painting showed 0%.
    static func percent(painted: Int, total: Int) -> Int {
        guard total > 0, painted > 0 else { return 0 }
        guard painted < total else { return 100 }
        return min(max(painted * 100 / total, 1), 99)
    }

    /// "finished" or "30 percent painted".
    static func colorProgress(painted: Int, total: Int) -> String {
        if total > 0 && painted >= total { return finished }
        return percentPainted(Self.percent(painted: painted, total: total))
    }

    /// "30 percent painted": a palette color's value, and the painting's progress.
    static func percentPainted(_ percent: Int) -> String {
        String(localized: "paint.speech.percentPainted", defaultValue: "\(percent) percent painted",
               comment: "VoiceOver value of a palette color or of the painting: how much of it is painted, as a whole percentage")
    }

    /// "Irises, 30 percent painted": the painting screen's progress badge when it shows the title.
    static func paintingProgress(title: String, percent: Int) -> String {
        let progress = percentPainted(percent)
        return String(localized: "paint.speech.titleProgress", defaultValue: "\(title), \(progress)",
                      comment: "VoiceOver label of the painting screen's progress badge: the painting's title, then how much of it is painted (the percentPainted text)")
    }

    /// The value of a finished color or painting.
    static var finished: String {
        String(localized: "paint.speech.finished", defaultValue: "finished",
               comment: "VoiceOver value of a palette color, or of the painting, whose areas are all painted")
    }

    static func swatchHint(selected: Bool) -> String {
        selected
            ? String(localized: "paint.speech.swatchHint.selected", defaultValue: "Shows where to paint next",
                     comment: "VoiceOver hint of the selected palette color (activating it shows a hint)")
            : String(localized: "paint.speech.swatchHint", defaultValue: "Selects this color",
                     comment: "VoiceOver hint of a palette color")
    }

    /// "Area 12": areas are named by the number printed in them.
    static func areaLabel(number: Int) -> String {
        String(localized: "paint.speech.areaLabel", defaultValue: "Area \(number)",
               comment: "VoiceOver label of an unpainted area on the canvas: the number printed in it")
    }

    /// "not painted, top left".
    static func areaValue(_ position: CanvasPosition) -> String {
        let place = position.spoken
        return String(localized: "paint.speech.areaValue", defaultValue: "not painted, \(place)",
                      comment: "VoiceOver value of an unpainted area: its state, then where it sits on the painting")
    }

    /// "Paints this area with 12, dark green."
    static func areaHint(number: Int, name: ColorName, nickname: String? = nil) -> String {
        let color = colorLabel(number: number, name: name, nickname: nickname)
        return String(localized: "paint.speech.areaHint", defaultValue: "Paints this area with \(color).",
                      comment: "VoiceOver hint of an unpainted area; the argument is the color label")
    }

    /// "No areas of 12, dark green in view".
    static func noAreasInView(number: Int, name: ColorName, nickname: String? = nil) -> String {
        let color = colorLabel(number: number, name: name, nickname: nickname)
        return String(localized: "paint.speech.noAreasInView", defaultValue: "No areas of \(color) in view",
                      comment: "VoiceOver value of the canvas when no area of the selected color is visible")
    }

    /// "Painting, top left": which part of the painting a VoiceOver page scroll brought into view.
    static func pageScrolled(_ position: CanvasPosition) -> String {
        let place = position.spoken
        return String(localized: "paint.speech.pageScrolled", defaultValue: "Painting, \(place)",
                      comment: "VoiceOver announcement after scrolling the canvas by a page: the part of the painting now in the middle of the view")
    }

    /// "Painted, 7 left".
    static func painted(remaining: Int) -> String {
        String(localized: "paint.speech.painted", defaultValue: "Painted, \(remaining) left",
               comment: "VoiceOver announcement after painting an area: how many areas of the color remain")
    }

    /// "Color 12, dark green, finished".
    static func colorFinished(number: Int, name: ColorName, nickname: String? = nil) -> String {
        let color = colorLabel(number: number, name: name, nickname: nickname)
        return String(localized: "paint.speech.colorFinished", defaultValue: "Color \(color), finished",
                      comment: "VoiceOver announcement when every area of a color is painted")
    }

    /// "Next color: 13, light blue".
    static func nextColor(number: Int, name: ColorName, nickname: String? = nil) -> String {
        let color = colorLabel(number: number, name: name, nickname: nickname)
        return String(localized: "paint.speech.nextColor", defaultValue: "Next color: \(color)",
                      comment: "VoiceOver announcement when the brush moves on to the next color")
    }

    static var paintingFinished: String {
        String(localized: "paint.speech.paintingFinished", defaultValue: "Painting finished",
               comment: "VoiceOver announcement when the whole painting is done")
    }

    static var canvasLabel: String {
        String(localized: "paint.canvas.label", defaultValue: "Painting", comment: "VoiceOver name of the canvas")
    }

    static var canvasHint: String {
        String(localized: "paint.canvas.hint", defaultValue: "Use the actions to zoom to the next area.",
               comment: "VoiceOver hint of the canvas when no area to paint is in view")
    }
}

/// Speaks after whatever VoiceOver is saying, so announcements don't cut each other off.
enum Announcer {
    static func announce(_ text: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true]))
    }
}
