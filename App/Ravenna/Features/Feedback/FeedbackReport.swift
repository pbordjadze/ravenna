import CoreGraphics
import Foundation
import PaintCore

/// What a feedback bundle says (`<title> Feedback.zip`, written by `FeedbackPackage`), for the
/// developers. The bundle holds:
///
/// - `feedback.md`: this report for people: the note, each mark's comment and the regions it
///   touches, the painting's facts and these files. English, like pbn's output.
/// - `feedback.json`: the same for scripts (`format` 2; format 1 had the retired Line Appearance
///   setting where 2 has `lineWeight`): app, device and system; where the
///   painting came from and its generation settings; what was on screen; each mark's comment,
///   regions (under the ink, or inside a loop it closes) and strokes as polylines in canvas
///   units (the template's, y down), with the zoom each was drawn at.
/// - `marked.png`: the painting as captured with the marks; `markup.png`: the marks alone at the
///   same size; `view.png`: what was on screen (the selected color hatched as the canvas showed
///   it); `mark-N.png`: each mark close up, about as large as the painter saw it (anything
///   written on the painting reads there).
/// - `template.pbnt`: the template (`pbn check` and
///   `pbn names --seed <nicknameSeed> --vocabulary <nicknameVersion>` read it; absent version = 1).
/// - `photo.jpg`: the painter's photo, only when they chose to include it. A library picture is
///   named instead (`painting.sample`, `App/PaintByNumber/Resources/Samples/<sample>.jpg`).
///
/// Regions are template region indices; paints are numbered as the painting numbers them
/// (palette index + 1) except in `FeedbackRegionHit.color`, a palette index. Fields are only
/// ever added: scripts read them by name.
nonisolated struct FeedbackReport: Codable, Sendable {
    static let currentFormat = 2

    var format: Int
    var app: String
    var device: String
    var system: String
    var date: Date
    var title: String
    var note: String
    var painting: Painting
    var view: OnScreen
    var marks: [Mark]
    var files: [String]

    nonisolated struct Painting: Codable, Sendable {
        var artworkID: String?
        /// The library picture it was made from (`Sample.id`), if any.
        var sample: String?
        /// `photo.jpg` when the painter's photo is included.
        var photo: String?
        var createdAt: Date?
        var settings: GenerationSettings?
        var settingsOrigin: String?
        var paintingLength: String?
        var pipelineVersion: Int
        /// "classic", "layered" or "coloringBook", as the template records it (a layered one, of
        /// the retired style, draws as a coloring book).
        var lineStyle: String
        var width: Int
        var height: Int
        var regions: Int
        var paints: [Paint]
        var paintedRegions: [Int]
        var activeSeconds: Double
        /// The number of the paint on the brush.
        var selectedNumber: Int?
        var showsNumbers: Bool
        /// The Paper setting ("light", "dark", "automatic") and whether the paper was dark.
        var paper: String
        var darkPaper: Bool
        /// The Line Weight setting ("fine", "regular", "bold").
        var lineWeight: String
        var nicknameSeed: UInt64
        /// The recorded version, not the resolved one; nil in bundles made before versioning (= 1).
        var nicknameVersion: Int?
    }

    nonisolated struct Paint: Codable, Sendable {
        var number: Int
        var hex: String
        var name: String
        var nickname: String?
    }

    nonisolated struct OnScreen: Codable, Sendable {
        /// x, y, width, height in canvas units.
        var rect: [Double]
        var relativeZoom: Double
        var pointsPerUnit: Double
        var displayScale: Double
        var image: String
    }

    nonisolated struct Mark: Codable, Sendable {
        var number: Int
        /// x, y, width, height in canvas units, ink included.
        var bounds: [Double]
        var comment: String
        var image: String
        var regions: [FeedbackRegionHit]
        var strokes: [Stroke]
    }

    nonisolated struct Stroke: Codable, Sendable {
        var ink: String
        var color: String
        var width: Double
        var zoom: Double
        /// [x, y] in canvas units.
        var points: [[Double]]
    }

    /// The bundle's file names.
    nonisolated enum File {
        static let markdown = "feedback.md"
        static let json = "feedback.json"
        static let marked = "marked.png"
        static let markup = "markup.png"
        static let view = "view.png"
        static let template = "template.pbnt"
        static let photo = "photo.jpg"
        static func mark(_ number: Int) -> String { "mark-\(number).png" }
    }
}

nonisolated extension FeedbackReport {
    /// The report of `contents`, with each mark's regions (`FeedbackMarks.regions`).
    init(_ contents: FeedbackPackage.Contents, regions: [[FeedbackRegionHit]]) {
        let capture = contents.capture, template = capture.template
        let lineStyle = switch template.lineArt?.style {
        case .layered?: "layered"
        case .coloringBook?: "coloringBook"
        case nil: "classic"
        }
        let paints = template.palette.indices.map { i in
            Paint(
                number: i + 1, hex: "#" + template.palette[i].hexDigits.uppercased(),
                name: ColorNameText.string(template.palette[i].colorName),
                nickname: capture.nicknames.indices.contains(i) ? capture.nicknames[i] : nil)
        }
        let source = capture.source
        let marks = contents.marks.enumerated().map { index, mark in
            Mark(
                number: index + 1, bounds: Self.numbers(mark.bounds),
                comment: (contents.comments[mark.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                image: File.mark(index + 1),
                regions: regions.indices.contains(index) ? regions[index] : [],
                strokes: mark.strokes.map { Self.stroke(contents.strokes[$0]) })
        }
        var files = [File.markdown, File.json, File.marked, File.markup, File.view]
        files += marks.map(\.image)
        files.append(File.template)
        if contents.photo != nil { files.append(File.photo) }
        self.init(
            format: Self.currentFormat, app: capture.app, device: capture.device, system: capture.system, date: capture.date,
            title: capture.title, note: contents.note.trimmingCharacters(in: .whitespacesAndNewlines),
            painting: Painting(
                artworkID: source?.artworkID?.uuidString, sample: source?.sampleName,
                photo: contents.photo == nil ? nil : File.photo, createdAt: source?.createdAt, settings: source?.settings,
                settingsOrigin: source?.settingsOrigin, paintingLength: source?.paintingLength,
                pipelineVersion: Int(template.pipelineVersion), lineStyle: lineStyle, width: template.width,
                height: template.height, regions: template.regions.count, paints: paints,
                paintedRegions: template.regions.indices.filter { capture.progress.isPainted($0) },
                activeSeconds: capture.progress.activeSeconds, selectedNumber: capture.selectedColor.map { $0 + 1 },
                showsNumbers: capture.showsNumbers, paper: capture.paper.rawValue,
                darkPaper: capture.paper.usesDarkPaper(interfaceIsDark: capture.darkInterface),
                lineWeight: capture.lineWeight.rawValue, nicknameSeed: capture.nicknameSeed,
                nicknameVersion: capture.nicknameVersion),
            view: OnScreen(
                rect: Self.numbers(contents.layout.view.rect), relativeZoom: Self.rounded(capture.relativeZoom),
                pointsPerUnit: Self.rounded(capture.pointsPerUnit), displayScale: Double(capture.displayScale),
                image: File.view),
            marks: marks, files: files)
    }

    private static func rounded(_ value: CGFloat) -> Double { (Double(value) * 100).rounded() / 100 }
    private static func numbers(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map { rounded($0) }
    }

    private static func stroke(_ stroke: FeedbackStroke) -> Stroke {
        Stroke(
            ink: stroke.ink, color: stroke.color, width: rounded(CGFloat(stroke.width)), zoom: rounded(CGFloat(stroke.zoom)),
            points: stroke.points.map { [rounded(CGFloat($0.x)), rounded(CGFloat($0.y))] })
    }

    /// `feedback.md`.
    var markdown: String {
        var lines = ["# \(title.isEmpty ? "Untitled mosaic" : title): feedback", ""]
        // Ravenna's seam: `app` names the app itself ("Ravenna …", `FeedbackCapture`).
        lines.append("\(app) on \(device), \(system), \(date.formatted(.iso8601))")
        lines += ["", "## Note", "", note.isEmpty ? "(none)" : note, "", "## Marks", ""]
        if marks.isEmpty { lines.append("(none)") }
        for mark in marks {
            lines.append("\(mark.number). \(mark.comment.isEmpty ? "(no comment)" : mark.comment)")
            let inked = mark.regions.filter { $0.inked > 0 }.map(Self.describe)
            let circled = mark.regions.filter { $0.inked == 0 && $0.enclosed > 0 }.map(Self.describe)
            if !inked.isEmpty { lines.append("   - Under the ink: \(inked.joined(separator: ", "))") }
            if !circled.isEmpty { lines.append("   - Circled: \(circled.joined(separator: ", "))") }
            lines.append("   - Close-up: \(mark.image)")
        }
        let p = painting
        let origin: String
        if let sample = p.sample {
            origin = "Library picture \(sample) (App/PaintByNumber/Resources/Samples/\(sample).jpg)"
        } else if let photo = p.photo {
            origin = "The painter's photo, included as \(photo)"
        } else {
            origin = "The painter's photo, not included"
        }
        let percent = p.regions == 0 ? 0 : p.paintedRegions.count * 100 / p.regions
        lines += [
            "", "## Painting", "",
            "- \(origin)",
            "- \(p.width) × \(p.height), \(p.paints.count) paints, \(p.regions) regions, \(p.paintedRegions.count) painted (\(percent) %)",
            "- \(p.lineStyle) lines, pipeline \(p.pipelineVersion), \(p.settingsOrigin ?? "unknown") settings; all of them in \(File.json)",
            "- On screen: \(view.rect.map { "\($0)" }.joined(separator: ", ")) (x, y, width, height) at \(view.relativeZoom)× (\(view.image))",
            "", "## Files", "",
        ]
        lines += files.map { "- \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func describe(_ hit: FeedbackRegionHit) -> String {
        "region \(hit.region) (paint \(hit.color + 1))"
    }
}
