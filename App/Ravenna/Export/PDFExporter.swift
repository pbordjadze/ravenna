import CoreGraphics
import CoreText
import Foundation
import PaintCore
import simd

/// Printable template: the outline template with numbers (vector, crisp at any zoom), then the
/// color key (number, paint and name of every color) plus a small reference of the finished
/// picture.
///
/// Numbers keep to their regions' room at every scale (`LabelSizing`), so a detailed
/// template fitted to one page would print its smallest numbers at about 1 pt. Such a
/// template is printed on several overlapping sheets instead (`Sheets`), after an overview
/// page showing how they fit together; a detail area's number (`Template.detailRegions`) has a
/// print floor of its own, `minimumDetailNumberSize`.
nonisolated enum PDFExporter {
    /// The paper a template is laid out for: the region's usual size (`default(for:)`).
    enum Paper: String, Sendable, CaseIterable {
        case letter, a4

        /// Portrait size in points.
        var size: CGSize {
            switch self {
            case .letter: CGSize(width: 612, height: 792)
            case .a4: CGSize(width: 595.28, height: 841.89)
            }
        }

        /// Letter where it is the norm, A4 everywhere else.
        static func `default`(for region: Locale.Region?) -> Paper {
            let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "GT", "PR", "CR", "DO", "PA", "SV"]
            return letterRegions.contains(region?.identifier ?? "") ? .letter : .a4
        }
    }

    /// Smallest number printed (points); smaller digits blur into specks on paper.
    static let minimumNumberSize: CGFloat = 2.6
    /// Smallest number of a detail area printed (points): an area the painter filled, whose
    /// number the canvas draws down to about half the usual floor, read zoomed in. At
    /// `minimumNumberSize` one filled star would print a 150-color template on about four
    /// times the sheets (the scale doubles); at 2 pt, digits about half a millimetre tall and
    /// still six dots of a 300-dpi printer, on about two and a half times, read close up or
    /// with a magnifier as the canvas is zoomed in.
    static let minimumDetailNumberSize: CGFloat = 2
    /// How far neighbouring sheets overlap (points), room to tape them together. Numbers on
    /// sheets are at most this wide, so each one is whole on at least one sheet.
    static let sheetOverlap: CGFloat = 18

    /// How the template is printed: on one page when its smallest number comes out at
    /// `minimumNumberSize` or larger there (a detail area's at `minimumDetailNumberSize`),
    /// otherwise on a grid of overlapping sheets at a scale that makes it so (a 150-color
    /// detail-1 template takes about four, more with detail areas).
    struct Sheets: Equatable, Sendable {
        /// Points per canvas unit.
        var scale: CGFloat
        var columns: Int
        var rows: Int
        /// The largest part of the template one page shows (points): the page body.
        var body: CGSize
        /// The whole template at `scale` (points).
        var printed: CGSize

        var count: Int { columns * rows }
        var isTiled: Bool { count > 1 }

        /// The part of the printed template (points, origin top-left) sheet (`column`, `row`)
        /// shows; neighbours share `sheetOverlap`.
        func window(column: Int, row: Int) -> CGRect {
            let x = CGFloat(column) * (body.width - PDFExporter.sheetOverlap)
            let y = CGFloat(row) * (body.height - PDFExporter.sheetOverlap)
            return CGRect(x: x, y: y, width: min(body.width, printed.width - x), height: min(body.height, printed.height - y))
        }
    }

    static func sheets(for t: Template, paper: Paper) -> Sheets {
        let body = bodyRect(pageBox(for: t, paper: paper)).size
        let width = CGFloat(max(t.width, 1)), height = CGFloat(max(t.height, 1))
        func make(scale: CGFloat, columns: Int, rows: Int) -> Sheets {
            Sheets(scale: scale, columns: columns, rows: rows, body: body, printed: CGSize(width: width * scale, height: height * scale))
        }
        let fitted = min(body.width / width, body.height / height)
        guard let needed = legibleScale(t), fitted < needed else {
            return make(scale: fitted, columns: 1, rows: 1)
        }
        // n sheets with overlap o cover n·(w − o) + o.
        func count(_ extent: CGFloat, _ window: CGFloat) -> Int {
            max(1, Int(((extent * needed - sheetOverlap) / (window - sheetOverlap)).rounded(.up)))
        }
        let columns = count(width, body.width), rows = count(height, body.height)
        // Fill the grid: the scale only grows past `needed`, and no row or column is left empty.
        let scale = min(
            (CGFloat(columns) * (body.width - sheetOverlap) + sheetOverlap) / width,
            (CGFloat(rows) * (body.height - sheetOverlap) + sheetOverlap) / height)
        return make(scale: scale, columns: columns, rows: rows)
    }

    /// The scale (points per canvas unit) that prints the smallest number at
    /// `minimumNumberSize` and a detail area's smallest at `minimumDetailNumberSize`, or nil
    /// without labels.
    static func legibleScale(_ t: Template) -> CGFloat? {
        let usual = smallestNumberSize(t, detail: false).map { minimumNumberSize / $0 }
        let detail = smallestNumberSize(t, detail: true).map { minimumDetailNumberSize / $0 }
        return [usual, detail].compactMap { $0 }.max()
    }

    /// Size (canvas units) of the smallest number `TemplateRasterizer` prints in the detail
    /// areas, or in the others, or nil without labels there.
    static func smallestNumberSize(_ t: Template, detail: Bool) -> CGFloat? {
        let maximum = Float(TemplateRasterizer.Style.printable.maximumNumberFraction) * Float(max(t.width, t.height))
        var smallest: Float?
        for label in t.labels where Int(label.region) < t.regions.count && t.isDetailRegion(Int(label.region)) == detail {
            let digits = LabelSizing.digitCount(colorIndex: t.regions[Int(label.region)].colorIndex)
            let size = LabelSizing.fontSize(radius: label.radius, digits: digits, maximum: maximum, detail: detail)
            smallest = min(smallest ?? size, size)
        }
        return smallest.map { CGFloat($0) }
    }

    /// `nicknames` (index-aligned with the palette, nil where a color has none) head the color key
    /// entries, with the plain color name below them; without them the plain name heads each entry.
    static func document(for t: Template, title: String, paper: Paper, nicknames: [String?] = []) -> Data {
        let data = NSMutableData()
        var box = pageBox(for: t, paper: paper)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Paint by Moonlight"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
        else { return Data() }

        let colorsText = TemplateCounts.colors(t.palette.count), areasText = TemplateCounts.areas(t.regions.count)
        let stats = String(localized: "pdf.stats", defaultValue: "\(colorsText) · \(areasText)",
                           comment: "Header of the printable template's pages; the arguments are the number of colors and the number of areas")
        let rasterResolution = CGSize(width: t.width * 2, height: t.height * 2)
        let sheets = Self.sheets(for: t, paper: paper)
        if sheets.isTiled {
            page(ctx, box) { content in
                let sheetsText = String(localized: "pdf.sheets", defaultValue: "\(sheets.count) sheets",
                                        comment: "How many sheets the template is printed on; the argument is the count")
                let overviewDetail = String(localized: "pdf.stats.withSheets", defaultValue: "\(stats) · \(sheetsText)",
                                            comment: "Header of the overview page of a template printed on several sheets; the arguments are the colors and areas text and the number of sheets")
                let body = header(ctx, in: content, title: title, detail: overviewDetail)
                let rect = fit(aspect: CGFloat(t.width) / CGFloat(t.height), in: body)
                // A map for putting the sheets together; the numbers are on the sheets.
                var overview = TemplateRasterizer.Style.printable
                overview.numbers = false
                TemplateRasterizer.draw(t, painted: nil, style: overview, in: ctx, rect: rect, rasterResolution: rasterResolution)
                sheetGrid(ctx, sheets, in: rect)
            }
            // Numbers no wider than the overlap: each is whole on some sheet.
            var style = TemplateRasterizer.Style.printable
            let widest = CGFloat(LabelSizing.digitCount(of: t.palette.count)) * CGFloat(LabelSizing.digitAdvance)
            style.maximumNumberFraction = min(
                style.maximumNumberFraction, sheetOverlap / (widest * sheets.scale * CGFloat(max(t.width, t.height))))
            for row in 0..<sheets.rows {
                for column in 0..<sheets.columns {
                    let window = sheets.window(column: column, row: row)
                    let number = row * sheets.columns + column + 1, total = sheets.count
                    let detail = String(localized: "pdf.sheet.detail",
                                        defaultValue: "Sheet \(number) of \(total) · row \(row + 1), column \(column + 1)",
                                        comment: "Header of one sheet of a template printed on several; the arguments are the sheet's number, the number of sheets, and its row and column in the grid of sheets")
                    page(ctx, box) { content in
                        let body = header(ctx, in: content, title: title, detail: detail)
                        let visible = CGRect(origin: body.origin, size: window.size)
                        let whole = CGRect(
                            x: body.minX - window.minX, y: body.minY - window.minY,
                            width: sheets.printed.width, height: sheets.printed.height)
                        ctx.saveGState()
                        ctx.clip(to: visible)
                        TemplateRasterizer.draw(t, painted: nil, style: style, in: ctx, rect: whole, rasterResolution: rasterResolution)
                        ctx.restoreGState()
                        ctx.setStrokeColor(gray(0.75))
                        ctx.setLineWidth(0.5)
                        ctx.stroke(visible)
                    }
                }
            }
        } else {
            page(ctx, box) { content in
                let body = header(ctx, in: content, title: title, detail: stats)
                let rect = fit(aspect: CGFloat(t.width) / CGFloat(t.height), in: body)
                TemplateRasterizer.draw(t, painted: nil, style: .printable, in: ctx, rect: rect, rasterResolution: rasterResolution)
                ctx.setStrokeColor(gray(0.75))
                ctx.setLineWidth(0.5)
                ctx.stroke(rect)
            }
        }
        page(ctx, box) { content in
            let body = header(ctx, in: content, title: String(localized: "Color Key"), detail: title)
            let used = legend(ctx, t, nicknames: nicknames, in: body)
            let remaining = CGRect(x: body.minX, y: used.maxY + 24, width: body.width, height: body.maxY - used.maxY - 24)
            if remaining.height > 110 {
                text(ctx, String(localized: "Reference"), font: font(.emphasizedSystem, 10), color: gray(0.35), at: CGPoint(x: remaining.minX, y: remaining.minY + 10))
                let area = CGRect(x: remaining.minX, y: remaining.minY + 20, width: remaining.width, height: remaining.height - 20)
                let rect = fit(aspect: CGFloat(t.width) / CGFloat(t.height), in: area)
                TemplateRasterizer.draw(
                    t, painted: nil, style: .painting, in: ctx, rect: rect,
                    rasterResolution: CGSize(width: rect.width * 3, height: rect.height * 3))
            }
        }
        ctx.closePDF()
        return data as Data
    }

    // MARK: Layout

    private static let margin: CGFloat = 36
    private static let headerHeight: CGFloat = 36

    /// The page, turned to landscape for wide templates.
    private static func pageBox(for t: Template, paper: Paper) -> CGRect {
        let landscape = t.width > t.height
        return CGRect(origin: .zero, size: landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size)
    }

    /// The part of a page below its header, in page coordinates.
    static func bodyRect(_ box: CGRect) -> CGRect {
        body(of: box.insetBy(dx: margin, dy: margin))
    }

    private static func body(of content: CGRect) -> CGRect {
        CGRect(x: content.minX, y: content.minY + headerHeight, width: content.width, height: content.height - headerHeight)
    }

    /// Runs `body` for one page with a y-down user space and the content rect inside margins.
    private static func page(_ ctx: CGContext, _ box: CGRect, _ body: (CGRect) -> Void) {
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: box.height)
        ctx.scaleBy(x: 1, y: -1)
        let content = box.insetBy(dx: margin, dy: margin)
        body(content)
        text(ctx, String(localized: "Paint by Moonlight"), font: font(.system, 7.5), color: gray(0.6), at: CGPoint(x: content.minX, y: content.maxY + 16))
        ctx.restoreGState()
        ctx.endPDFPage()
    }

    /// Draws the page header and returns the rect below it.
    private static func header(_ ctx: CGContext, in content: CGRect, title: String, detail: String) -> CGRect {
        text(ctx, title, font: font(.emphasizedSystem, 17), color: gray(0.1), at: CGPoint(x: content.minX, y: content.minY + 14))
        text(ctx, detail, font: font(.system, 9), color: gray(0.45), at: CGPoint(x: content.maxX, y: content.minY + 13), alignment: .right)
        ctx.setStrokeColor(gray(0.85))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: content.minX, y: content.minY + 24))
        ctx.addLine(to: CGPoint(x: content.maxX, y: content.minY + 24))
        ctx.strokePath()
        return body(of: content)
    }

    /// Outlines each sheet's part of the template on the overview `rect`, with its number.
    private static func sheetGrid(_ ctx: CGContext, _ sheets: Sheets, in rect: CGRect) {
        let factor = rect.width / sheets.printed.width
        ctx.setStrokeColor(gray(0.3, alpha: 0.8))
        ctx.setLineWidth(0.75)
        ctx.stroke(rect)
        for row in 0..<sheets.rows {
            for column in 0..<sheets.columns {
                let window = sheets.window(column: column, row: row)
                let frame = CGRect(
                    x: rect.minX + window.minX * factor, y: rect.minY + window.minY * factor,
                    width: window.width * factor, height: window.height * factor)
                ctx.setStrokeColor(gray(0.3, alpha: 0.8))
                ctx.stroke(frame.insetBy(dx: 1, dy: 1))
                let size = min(28, frame.height * 0.3)
                text(ctx, "\(row * sheets.columns + column + 1)", font: font(.emphasizedSystem, size), color: gray(0.3, alpha: 0.8),
                     at: CGPoint(x: frame.midX, y: frame.midY + size * 0.35), alignment: .center)
            }
        }
    }

    /// How the color key's entries are laid out: `rows` per column, filled column by column.
    nonisolated struct KeyLayout: Equatable, Sendable {
        var columns: Int
        var scale: CGFloat
        var columnWidth: CGFloat
        var rowHeight: CGFloat
        var rows: Int
        var count: Int

        var height: CGFloat { count == 0 ? 0 : CGFloat(rows) * rowHeight }
    }

    private static let keyGap: CGFloat = 12
    /// Width of an entry left of its name: number and dot, at scale 1.
    private static let keyNameInset: CGFloat = 36

    /// The largest scale (1 down to 0.6), then the fewest columns (3–5, or 4–6 on a wide page),
    /// whose rows fit the page and whose widest entry (`widestEntry` at scale 1) fits a column.
    /// When nothing fits, the smallest scale and most columns; long names then truncate. Entries
    /// are `lines` lines tall: two (name, hex and areas), or three with a nickname above the plain name.
    static func keyLayout(count: Int, widestEntry: CGFloat, lines: Int = 2, in rect: CGRect) -> KeyLayout {
        let base = rect.width > 600 ? 4 : 3
        func layout(scale: CGFloat, columns: Int) -> KeyLayout {
            KeyLayout(
                columns: columns, scale: scale,
                columnWidth: (rect.width - keyGap * CGFloat(columns - 1)) / CGFloat(columns),
                rowHeight: (lines > 2 ? 32 : 24) * scale, rows: max(1, (count + columns - 1) / columns), count: count)
        }
        for scale: CGFloat in [1, 0.9, 0.8, 0.7, 0.6] {
            for columns in base...(base + 2) {
                let candidate = layout(scale: scale, columns: columns)
                if candidate.height <= rect.height && widestEntry * scale <= candidate.columnWidth { return candidate }
            }
        }
        return layout(scale: 0.6, columns: base + 2)
    }

    /// The color key as a list: number, a dot of the paint and the color's name, with its hex
    /// value and area count below. A color with a nickname is headed by it, and its plain name
    /// follows in secondary type. Returns the rect it used.
    private static func legend(_ ctx: CGContext, _ t: Template, nicknames: [String?], in rect: CGRect) -> CGRect {
        let shades = t.palette.map { ColorNameText.title($0.colorName) }
        let given = t.palette.indices.map { $0 < nicknames.count ? nicknames[$0] : nil }
        let heads = t.palette.indices.map { given[$0] ?? shades[$0] }
        let nameFont = font(.emphasizedSystem, 8), detailFont = font(.system, 6)
        let widestName = t.palette.indices.map {
            max(width(of: heads[$0], font: nameFont), given[$0] == nil ? 0 : width(of: shades[$0], font: detailFont))
        }.max() ?? 0
        let lines = given.contains { $0 != nil } ? 3 : 2
        let layout = keyLayout(count: t.palette.count, widestEntry: keyNameInset + widestName, lines: lines, in: rect)
        let s = layout.scale
        let counts = t.regionCountsByColor
        for (i, color) in t.palette.enumerated() {
            let col = i / layout.rows, row = i % layout.rows
            let x = rect.minX + CGFloat(col) * (layout.columnWidth + keyGap)
            let y = rect.minY + CGFloat(row) * layout.rowHeight
            text(ctx, "\(i + 1)", font: font(.emphasizedSystem, 8 * s), color: gray(0.12),
                 at: CGPoint(x: x + 18 * s, y: y + 10 * s), alignment: .right)
            let diameter = 9 * s
            let dot = CGRect(x: x + 26.5 * s - diameter / 2, y: y + 7 * s - diameter / 2, width: diameter, height: diameter)
            ctx.setFillColor(TemplateRasterizer.cgColor(SIMD4(color.rgb, 1), space: t.colorSpace))
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(gray(0, alpha: 0.12))
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: dot)
            let textX = x + keyNameInset * s
            let textWidth = layout.columnWidth - keyNameInset * s
            text(ctx, heads[i], font: font(.emphasizedSystem, 8 * s), color: gray(0.12),
                 at: CGPoint(x: textX, y: y + 10 * s), maxWidth: textWidth)
            var detailY = y + 19 * s
            if given[i] != nil {
                text(ctx, shades[i], font: font(.system, 6 * s), color: gray(0.45),
                     at: CGPoint(x: textX, y: detailY), maxWidth: textWidth)
                detailY += 8 * s
            }
            let hexText = color.hexCode, areasText = TemplateCounts.areas(counts[i])
            let detail = String(localized: "pdf.key.detail", defaultValue: "\(hexText) · \(areasText)",
                                comment: "Second line of a color key entry; the arguments are the color's hex code and its number of areas")
            text(ctx, detail, font: font(.system, 6 * s), color: gray(0.5),
                 at: CGPoint(x: textX, y: detailY), maxWidth: textWidth)
        }
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: layout.height)
    }

    private static func fit(aspect: CGFloat, in rect: CGRect) -> CGRect {
        var size = CGSize(width: rect.width, height: rect.width / aspect)
        if size.height > rect.height { size = CGSize(width: rect.height * aspect, height: rect.height) }
        return CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height)
    }

    // MARK: Text & color

    private enum Alignment { case left, center, right }

    private static func font(_ type: CTFontUIFontType, _ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(type, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(gray: white, alpha: alpha)
    }

    private static func line(_ string: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private static func width(of string: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(string, font: font, color: gray(0)), nil, nil, nil))
    }

    /// Draws one line of text with its baseline at `point` (y-down page space), truncated with
    /// an ellipsis when wider than `maxWidth`.
    private static func text(
        _ ctx: CGContext, _ string: String, font: CTFont, color: CGColor, at point: CGPoint,
        alignment: Alignment = .left, maxWidth: CGFloat? = nil
    ) {
        var run = line(string, font: font, color: color)
        var runWidth = CGFloat(CTLineGetTypographicBounds(run, nil, nil, nil))
        if let maxWidth, runWidth > maxWidth,
           let truncated = CTLineCreateTruncatedLine(
               run, Double(max(maxWidth, 0)), .end, line("…", font: font, color: color)) {
            run = truncated
            runWidth = CGFloat(CTLineGetTypographicBounds(run, nil, nil, nil))
        }
        let x: CGFloat = switch alignment {
        case .left: point.x
        case .center: point.x - runWidth / 2
        case .right: point.x - runWidth
        }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(run, ctx)
        ctx.restoreGState()
    }
}
