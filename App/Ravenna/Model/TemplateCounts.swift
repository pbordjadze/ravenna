import Foundation

/// How many colors and areas a template has, worded for the create flow's summary and the
/// printable template's header and color key.
nonisolated enum TemplateCounts {
    static func colors(_ count: Int) -> String {
        String(localized: "template.colors", defaultValue: "\(count) colors",
               comment: "How many colors a template has; the argument is the count")
    }

    static func areas(_ count: Int) -> String {
        String(localized: "template.areas", defaultValue: "\(count) areas",
               comment: "How many areas (regions to paint) a template has; the argument is the count")
    }

    /// "24 colors · 1,284 areas · ~1.5 h": the create flow's summary.
    static func summary(colors: Int, areas: Int, seconds: TimeInterval) -> String {
        let colorsText = Self.colors(colors)
        let areasText = Self.areas(areas)
        let timeText = PaintingTimeText.approximate(seconds)
        return String(localized: "create.stats.summary", defaultValue: "\(colorsText) · \(areasText) · \(timeText)",
                      comment: "Template summary under the create sliders; the arguments are the colors, areas and estimated painting time, e.g. 24 colors · 1,284 areas · ~1.5 h")
    }
}
