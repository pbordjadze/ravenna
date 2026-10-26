import Foundation
import MosaicKit
import Observation
import PaintCore
import simd

/// Something that visualizes a painting session (the Metal canvas). The session tells it
/// what changed; the canvas owns animation and camera.
protocol PaintingCanvas: AnyObject {
    /// Regions became painted. `origin` is where the paint should spread from (canvas units).
    func session(_ session: PaintingSession, didPaint regions: [Int], from origin: SIMD2<Float>, animated: Bool)
    /// A region was un-painted (undo / reset).
    func session(_ session: PaintingSession, didUnpaint regions: [Int])
    /// The selected color changed (highlighting of matching regions must update).
    func sessionDidChangeSelection(_ session: PaintingSession)
    /// The user asked to be shown where to paint next.
    func session(_ session: PaintingSession, focusOn region: Int)
}

enum PaintEvent: Equatable {
    case painted(regions: [Int], color: Int)
    /// Tapped a region that needs another color.
    case rejected(region: Int, expectedColor: Int)
    case colorCompleted(Int)
    case artworkCompleted
    case undone(region: Int)
    /// A drag or Pencil stroke ended; `regions` are all it painted (it undoes as one step).
    case strokeEnded(regions: [Int])
    /// A tap painted nothing but landed just beside an unpainted area of the selected color
    /// that is small at this zoom: zooming in would help.
    case missedSmallArea(region: Int)
    /// The hint revealed `region`.
    case hintShown(region: Int)
}

/// The color a painting opens on. One nobody has painted on opens on the color of its largest
/// area, so the first tap finds a big area whose number reads at the opening zoom: by number it
/// opened on 1, often a few slivers that don't show there (the first-five-minutes walk, October
/// 23: on the corpus books 1 covered 0.1 to 4.6% of the canvas, the largest color 11 to 28%;
/// Paul: "let's build them all"). One begun opens as before, on the palette's first color with
/// areas left. SideStore and Debug builds only for now (`UNRELEASED`, root `CLAUDE.md` › App rules).
nonisolated enum OpeningColor {
    #if UNRELEASED
    static let isLargestArea = true
    #else
    static let isLargestArea = false
    #endif

    /// The color of `template`'s largest area, ties going to the lower number; nil without areas.
    static func largestArea(in template: Template, skipping skipped: Int? = nil) -> Int? {
        var best: (area: Float, color: Int)?
        for (i, region) in template.regions.enumerated() where i != skipped {
            let color = Int(region.colorIndex)
            if let current = best, region.area < current.area || (region.area == current.area && color >= current.color) {
                continue
            }
            best = (region.area, color)
        }
        return best?.color
    }
}

/// The live state of painting one artwork: template, progress, selection and the rules of
/// what may be painted where. UI observes it; the canvas is driven through `PaintingCanvas`.
@Observable
final class PaintingSession {
    let template: Template
    /// The mosaic the template was made of, when it is one (`TileWall`): the canvas lays tiles,
    /// a drag lays a row, and the grout is set from the start.
    let wall: TileWall?
    private(set) var progress: PaintProgress
    /// Palette index currently loaded on the brush.
    private(set) var selectedColor: Int?
    /// Regions left to paint per palette color.
    private(set) var remainingByColor: [Int]
    /// Whether every area is painted, whether any is, and the colors with none left. Set only
    /// when they change, unlike `progress` and `remainingByColor`, which change on every fill:
    /// the painting screen's layout and controls read only these, so a fill re-renders just the
    /// views that show progress.
    private(set) var isComplete: Bool
    private(set) var isStarted: Bool
    private(set) var completedColors: Set<Int>
    let totalByColor: [Int]
    /// Names of the palette colors, index-aligned with `template.palette`.
    let colorNames: [ColorName]
    /// Playful nicknames of the palette colors, index-aligned (nil where the color has none or the
    /// app doesn't run in English), fixed by `nicknameSeed` and `nicknameVersion`.
    let colorNicknames: [String?]
    /// Localized palette text, prepared once before the painting appears.
    let colorTitles: [String]
    let numberedColorNames: [String]
    let colorLabels: [String]
    /// Increments on every progress change; cheap to observe for autosave/thumbnails.
    private(set) var revision = 0
    /// While the canvas replays the painting: how many of its areas are on screen, in the order
    /// they were painted (all as the paint starts to lift, none once it has gone, then each as its
    /// fill begins); nil otherwise. The painting itself is untouched: `progress` stays whole.
    /// Only the progress badge reads it (`shownPaintedCount`, `shownFraction`,
    /// `shownPaintedByColor`), so it says what the canvas shows.
    private(set) var replayed: Int?
    /// A replay plays: Undo waits and Replay becomes Stop. Stored apart from `replayed`, which
    /// changes many times a second, so the screen around the badge renders only as it starts and ends.
    private(set) var isReplaying = false

    @ObservationIgnored weak var canvas: PaintingCanvas?
    @ObservationIgnored private var observers: [(PaintEvent) -> Void] = []
    @ObservationIgnored private var lastInteraction: ContinuousClock.Instant?
    @ObservationIgnored private let clock = ContinuousClock()
    /// Automatically select the next unfinished color along the palette when the selected one
    /// is completed (`nextIncompleteColor`).
    @ObservationIgnored var autoAdvance = SettingsDefault.autoAdvance
    /// The palette is in an order by areas left (`PaletteOrder.followsProgress`), which re-sorts
    /// as the painting goes: finishing a color then selects its first swatch left, the order's
    /// own next, not the one after it.
    @ObservationIgnored var advancesToFirstLeft = false
    /// Zen Mode: a moment after each fill the canvas flies to the nearest area left of the
    /// selected color, as the hint does (`zenPause`, `zenShinePause`).
    @ObservationIgnored var flowsToNextArea = false
    /// Reduce Motion: the canvas shines no finished color, so Zen Mode has none to wait out.
    @ObservationIgnored var reduceMotion = false
    /// The palette's order on screen (`PaletteOrder`), which picking the next color follows;
    /// nil goes by number. Its first value (the screen showing the palette) moves the selection
    /// a begun painting opened with (the first color by number with areas left) to the palette's
    /// first, as the swatches lead off; a color picked meanwhile stays, and so does the largest
    /// area's color a fresh painting opened on (`OpeningColor`), whatever the order.
    @ObservationIgnored var colorOrder: [Int]? {
        didSet {
            guard oldValue == nil, !opensOnLargestArea,
                  selectedColor == remainingByColor.firstIndex(where: { $0 > 0 }) else { return }
            select(color: firstIncompleteColor())
        }
    }
    /// The session opened on the color of the largest area, the painting being fresh (`OpeningColor`).
    private let opensOnLargestArea: Bool
    /// Fixes the colors' nicknames (it keyed the retired Custom palette order too).
    let nicknameSeed: UInt64
    /// The artwork's recorded vocabulary version, kept even when newer than this build knows.
    let nicknameVersion: Int
    /// Fills of the stroke in progress (nil between strokes).
    @ObservationIgnored private var strokeFills: [Int]?
    /// The color on the brush when the stroke in progress began: the stroke keeps painting it
    /// though finishing it moves the selection on (`paint`).
    @ObservationIgnored private var strokeColor: Int?

    /// Saved progress that belongs to a different template (e.g. a stale or damaged file).
    nonisolated struct ProgressMismatch: Error, Equatable {
        let templateRegions: Int
        let progressRegions: Int
    }

    /// A fresh painting of `template`. `nicknameSeed` (the artwork's `ColorNickname.seed(for:)`)
    /// and recorded `nicknameVersion` pick its derived names. Defaults are for demos and tests;
    /// a saved painting always supplies both from its artwork metadata.
    convenience init(template: Template, nicknameSeed: UInt64 = 0, nicknameVersion: Int = 1) {
        self.init(
            checked: template, progress: PaintProgress(regionCount: template.regions.count),
            nicknameSeed: nicknameSeed, nicknameVersion: nicknameVersion)
    }

    /// Resumes saved progress; throws instead of trapping when it does not fit the template.
    convenience init(template: Template, progress: PaintProgress, nicknameSeed: UInt64 = 0, nicknameVersion: Int = 1) throws {
        guard progress.regionCount == template.regions.count else {
            throw ProgressMismatch(templateRegions: template.regions.count, progressRegions: progress.regionCount)
        }
        self.init(checked: template, progress: progress, nicknameSeed: nicknameSeed, nicknameVersion: nicknameVersion)
    }

    /// Prepares immutable counts and palette text off the main actor, then installs the live
    /// session on it. Swatch bodies must not repeatedly resolve every color's localized words.
    static func make(template: Template, mosaic: Mosaic? = nil, nicknameSeed: UInt64 = 0, nicknameVersion: Int = 1) async -> PaintingSession {
        let wall = mosaic.flatMap { TileWall(mosaic: $0, template: template) }
        let progress = PaintProgress(regionCount: template.regions.count).groutSet(wall)
        let prepared = await Background.run {
            Prepared(template: template, progress: progress, wall: wall, seed: nicknameSeed, version: nicknameVersion)
        }
        return PaintingSession(
            checked: template, progress: progress, wall: wall, nicknameSeed: nicknameSeed, nicknameVersion: nicknameVersion,
            prepared: prepared)
    }

    static func make(
        template: Template, progress: PaintProgress, mosaic: Mosaic? = nil, nicknameSeed: UInt64 = 0, nicknameVersion: Int = 1
    ) async throws -> PaintingSession {
        guard progress.regionCount == template.regions.count else {
            throw ProgressMismatch(templateRegions: template.regions.count, progressRegions: progress.regionCount)
        }
        let wall = mosaic.flatMap { TileWall(mosaic: $0, template: template) }
        let progress = progress.groutSet(wall)
        let prepared = await Background.run {
            Prepared(template: template, progress: progress, wall: wall, seed: nicknameSeed, version: nicknameVersion)
        }
        try Task.checkCancellation()
        return PaintingSession(
            checked: template, progress: progress, wall: wall, nicknameSeed: nicknameSeed, nicknameVersion: nicknameVersion,
            prepared: prepared)
    }

    nonisolated private struct Prepared: Sendable {
        let totals: [Int]
        let remaining: [Int]
        let completed: Set<Int>
        let names: [ColorName]
        let nicknames: [String?]
        let titles: [String]
        let numbered: [String]
        let labels: [String]
        let opening: Int?
        let opensOnLargestArea: Bool

        init(template: Template, progress: PaintProgress, wall: TileWall? = nil, seed: UInt64, version: Int) {
            totals = template.regionCountsByColor
            var remaining = totals
            for (i, region) in template.regions.enumerated() where progress.isPainted(i) {
                remaining[Int(region.colorIndex)] -= 1
            }
            self.remaining = remaining
            completed = Set(remaining.indices.filter { remaining[$0] == 0 })
            opensOnLargestArea = OpeningColor.isLargestArea && progress.paintedCount == progress.groutCount(wall)
            // A mosaic's largest area is its grout, set already: its largest tile's paint then.
            opening = opensOnLargestArea
                ? OpeningColor.largestArea(in: template, skipping: wall?.groutRegion) : remaining.firstIndex { $0 > 0 }
            let names = template.palette.map(\.colorName)
            let nicknames = ColorNameText.nicknames(for: template.palette, seed: seed, version: version)
            self.names = names
            self.nicknames = nicknames
            titles = names.map(ColorNameText.title)
            numbered = names.indices.map {
                ColorNameText.numbered(number: $0 + 1, name: names[$0], nickname: nicknames[$0])
            }
            labels = names.indices.map {
                PaintSpeech.colorLabel(number: $0 + 1, name: names[$0], nickname: nicknames[$0])
            }
        }
    }

    private convenience init(checked template: Template, progress: PaintProgress, nicknameSeed: UInt64, nicknameVersion: Int) {
        self.init(
            checked: template, progress: progress, wall: nil, nicknameSeed: nicknameSeed, nicknameVersion: nicknameVersion,
            prepared: Prepared(template: template, progress: progress, seed: nicknameSeed, version: nicknameVersion))
    }

    private init(
        checked template: Template, progress: PaintProgress, wall: TileWall?, nicknameSeed: UInt64, nicknameVersion: Int,
        prepared: Prepared
    ) {
        self.template = template
        self.wall = wall
        self.progress = progress
        totalByColor = prepared.totals
        colorNames = prepared.names
        colorNicknames = prepared.nicknames
        colorTitles = prepared.titles
        numberedColorNames = prepared.numbered
        colorLabels = prepared.labels
        self.nicknameSeed = nicknameSeed
        self.nicknameVersion = nicknameVersion
        remainingByColor = prepared.remaining
        isComplete = progress.isComplete
        isStarted = progress.paintedCount > progress.groutCount(wall)
        completedColors = prepared.completed
        opensOnLargestArea = prepared.opensOnLargestArea
        selectedColor = prepared.opening
    }

    // MARK: Queries

    /// The nickname `color` goes by: nil where the vocabulary has none for it, and when the app
    /// doesn't run in English (its structured name is shown then).
    func nickname(of color: Int) -> String? { colorNicknames[color] }

    var paletteCount: Int { template.palette.count }
    var fractionComplete: Double {
        areaCount == 0 ? 0 : Double(progress.paintedCount - ground) / Double(areaCount)
    }

    /// The areas there are to paint: a mosaic's tiles, not its grout, set from the start.
    var areaCount: Int { progress.regionCount - ground }

    /// 1 for a mosaic's grout, set from the start and counted nowhere the painter sees, else 0.
    private var ground: Int { progress.groutCount(wall) }

    /// The canvas's replay has `count` of the painting's areas on screen (nil: no replay is
    /// playing, the painting shows as it stands).
    func showReplayed(_ count: Int?) {
        let shown = count.map { min(max($0, 0), progress.regionCount) }
        if replayed != shown { replayed = shown }
        if isReplaying != (shown != nil) { isReplaying = shown != nil }
    }

    /// The share of the areas the screen shows painted: the replay's while one plays, else
    /// `fractionComplete`.
    var shownFraction: Double {
        areaCount == 0 ? 0 : Double(shownPaintedCount) / Double(areaCount)
    }

    /// How many areas the screen shows painted: the replay's while one plays. A mosaic's grout,
    /// which leads its log, isn't one.
    var shownPaintedCount: Int { max((replayed ?? progress.paintedCount) - ground, 0) }

    /// The painted areas of each palette color, as the screen shows them: the first `replayed` of
    /// the stroke log while a replay plays, else what the painting holds.
    var shownPaintedByColor: [Int] {
        guard let replayed else {
            var counts = (0..<paletteCount).map { totalByColor[$0] - remainingByColor[$0] }
            if let wall, ground > 0 { counts[colorOf(wall.groutRegion)] -= 1 }
            return counts
        }
        var counts = [Int](repeating: 0, count: paletteCount)
        for stroke in progress.log.prefix(replayed) where Int(stroke.region) != wall?.groutRegion {
            counts[colorOf(Int(stroke.region))] += 1
        }
        return counts
    }

    func isPainted(_ region: Int) -> Bool { progress.isPainted(region) }
    func isColorComplete(_ color: Int) -> Bool { completedColors.contains(color) }
    func colorOf(_ region: Int) -> Int { Int(template.regions[region].colorIndex) }

    func onEvent(_ observer: @escaping (PaintEvent) -> Void) { observers.append(observer) }

    // MARK: Selection

    func select(color: Int?) {
        guard color != selectedColor else { return }
        if let color, !(0..<paletteCount).contains(color) { return }
        selectedColor = color
        canvas?.sessionDidChangeSelection(self)
    }

    // MARK: Painting

    /// Handles a tap at a canvas-space point. `tolerance` (canvas units) lets a slightly
    /// imprecise tap still hit a small region of the selected color nearby.
    @discardableResult
    func tap(at point: SIMD2<Float>, tolerance: Float) -> PaintEvent? {
        guard let color = brushColor, let hit = template.region(at: point) else { return nil }
        let target: Int?
        if !progress.isPainted(hit) && colorOf(hit) == color {
            target = hit
        } else {
            target = nearestPaintable(to: point, color: color, radius: tolerance)
        }
        guard let target else {
            let rejected: PaintEvent? = !progress.isPainted(hit) && colorOf(hit) != color
                ? .rejected(region: hit, expectedColor: colorOf(hit)) : nil
            if let rejected { emit(rejected) }
            // "Small" = its inscribed disc fits under the tolerance (a fingertip on screen).
            if tolerance > 0, let small = nearestPaintable(
                to: point, color: color, radius: tolerance * Self.nearMissReach, maxInscribedRadius: tolerance) {
                emit(.missedSmallArea(region: small))
            }
            return rejected
        }
        return paint([target], from: point, animated: true)
    }

    /// How far beyond the tap tolerance (as a multiple of it) a miss still counts as aimed
    /// at a small area.
    private static let nearMissReach: Float = 3

    /// Largest brush radius a drag paints with, in canvas units. The canvas never zooms out
    /// past "fit", so the finger's 11 pt covers at most about 78 units (the largest working
    /// canvas on the smallest iPhone) and about 24 on an iPad: the cap never bites on current
    /// devices, so drags paint the same at every zoom. It bounds the work should canvases or
    /// brushes grow; the capsule scan keeps the cost proportional to the area swept.
    static let maxBrushRadius: Float = 96

    /// The color a tap or drag paints: the one a stroke began with while one is under way,
    /// else the selected one.
    private var brushColor: Int? { strokeColor ?? selectedColor }

    /// Paints every region of the selected color that a brush of `radius` touches moving
    /// from `a` to `b`, in the order it reaches them (replays follow the stroke).
    @discardableResult
    func drag(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float) -> PaintEvent? {
        guard let color = brushColor else { return nil }
        let progress = self.progress
        if let wall {
            // A row: the tiles the finger passes over, not every one the brush's disc touches.
            let row = wall.laying(from: a, to: b, radius: min(max(0, radius), Self.maxBrushRadius), paint: color,
                                  isPainted: progress.isPainted)
            return row.isEmpty ? nil : paint(row, from: b, animated: true)
        }
        // Stroke parameter of the first contact per region it touches.
        var enter: [Int: Float] = [:]
        forEachRegion(
            inCapsuleFrom: a, to: b, radius: min(max(0, radius), Self.maxBrushRadius),
            where: { !progress.isPainted($0) && colorOf($0) == color }
        ) { region, t in
            guard t < enter[region, default: .infinity] else { return }
            enter[region] = t
        }
        guard !enter.isEmpty else { return nil }
        let found = enter.keys.sorted { (enter[$0]!, $0) < (enter[$1]!, $1) }
        return paint(found, from: b, animated: true)
    }

    /// Brackets a drag or Pencil stroke so everything it paints undoes together.
    func beginStroke() {
        strokeFills = []
        strokeColor = selectedColor
    }

    func endStroke() {
        guard let fills = strokeFills else { return }
        strokeFills = nil
        strokeColor = nil
        guard let last = fills.last else { return }
        emit(.strokeEnded(regions: fills))
        if flowsToNextArea {
            // A color it painted that has nothing left was finished by this stroke.
            let finishedColor = fills.contains { remainingByColor[colorOf($0)] == 0 }
            showNextArea(near: template.labels(ofRegion: last).first?.position ?? .zero, finishedColor: finishedColor)
        }
    }

    var isStroking: Bool { strokeFills != nil }

    /// Paints regions (programmatic entry point; also used by demos and tests).
    @discardableResult
    func paint(_ regions: [Int], from origin: SIMD2<Float>, animated: Bool) -> PaintEvent? {
        noteInteraction()
        var newly: [Int] = []
        for r in regions where progress.paint(r) {
            newly.append(r)
            remainingByColor[colorOf(r)] -= 1
        }
        guard !newly.isEmpty else { return nil }
        strokeFills?.append(contentsOf: newly)
        revision += 1
        let colors = Set(newly.map(colorOf))
        updateMilestones(colors: colors)
        canvas?.session(self, didPaint: newly, from: origin, animated: animated)
        let color = colorOf(newly[0])
        let event = PaintEvent.painted(regions: newly, color: color)
        emit(event)
        let completed = colors.filter { remainingByColor[$0] == 0 }
        for c in completed.sorted() { emit(.colorCompleted(c)) }
        if progress.isComplete {
            emit(.artworkCompleted)
        } else if autoAdvance, let selected = selectedColor, completed.contains(selected) {
            // The next along the palette, so the painter carries on where they were (the first
            // swatch left sent them back to 1 from the middle of a long palette).
            select(color: advancesToFirstLeft ? firstIncompleteColor() : nextIncompleteColor(after: selected))
        }
        // A stroke flies on when it ends (`endStroke`).
        if flowsToNextArea, !isStroking { showNextArea(near: origin, finishedColor: !completed.isEmpty) }
        return event
    }

    /// Unpaints the most recent fill; returns its region.
    @discardableResult
    func undo() -> Int? {
        // The grout is the ground, set before the first tile: nothing to undo.
        if let wall, progress.log.last.map({ Int($0.region) }) == wall.groutRegion { return nil }
        guard let region = progress.undo() else { return nil }
        remainingByColor[colorOf(region)] += 1
        revision += 1
        updateMilestones(colors: [colorOf(region)])
        // A reopened finished painting has no color on the brush: the undone area's.
        if selectedColor == nil { select(color: colorOf(region)) }
        canvas?.session(self, didUnpaint: [region])
        emit(.undone(region: region))
        return region
    }

    func reset() {
        // A mosaic's grout stays set.
        let painted = (0..<progress.regionCount).filter { progress.isPainted($0) && $0 != wall?.groutRegion }
        progress.reset()
        remainingByColor = totalByColor
        if let wall {
            progress = progress.groutSet(wall)
            remainingByColor[colorOf(wall.groutRegion)] -= 1
        }
        revision += 1
        updateMilestones(colors: 0..<paletteCount)
        canvas?.session(self, didUnpaint: painted)
        // Started over, the painting is fresh again: it opens as a fresh one does.
        select(color: OpeningColor.isLargestArea
            ? OpeningColor.largestArea(in: template, skipping: wall?.groutRegion) : firstIncompleteColor())
    }

    /// Asks the canvas to reveal the unpainted region of the selected color nearest to
    /// `point` (or the largest one when no point is given).
    func showHint(near point: SIMD2<Float>? = nil) {
        guard let color = selectedColor else { return }
        var best: Int?
        var bestScore = Float.infinity
        for (i, r) in template.regions.enumerated() where Int(r.colorIndex) == color && !progress.isPainted(i) {
            let score: Float
            if let point, let label = template.labels(ofRegion: i).first {
                score = simd_distance_squared(label.position, point)
            } else {
                score = -r.area
            }
            if score < bestScore { bestScore = score; best = i }
        }
        if let best {
            canvas?.session(self, focusOn: best)
            emit(.hintShown(region: best))
        }
    }

    /// The palette's colors in their order on screen (`colorOrder`, when it fits the palette).
    private var order: [Int] {
        colorOrder.flatMap { $0.count == paletteCount ? $0 : nil } ?? Array(0..<paletteCount)
    }

    /// The first color with areas left in the palette's order: its first swatch, finished colors
    /// having left it.
    func firstIncompleteColor() -> Int? {
        order.first { remainingByColor[$0] > 0 }
    }

    /// The next color with areas left after `color` (before it when `backwards`), in the
    /// palette's order (`colorOrder`), coming round; from the start (or the end) when `color`
    /// is nil.
    func nextIncompleteColor(after color: Int?, backwards: Bool = false) -> Int? {
        let order = order
        let n = order.count
        guard n > 0 else { return nil }
        let start = color.flatMap { order.firstIndex(of: $0) } ?? (backwards ? 0 : n - 1)
        // Stepping n - 1 places forward goes one back, without a negative remainder.
        let step = backwards ? n - 1 : 1
        for k in 1...n {
            let c = order[(start + k * step) % n]
            if remainingByColor[c] > 0 { return c }
        }
        return nil
    }

    /// How long a fill shows before Zen Mode flies on.
    static let zenPause: Duration = .milliseconds(350)
    /// How long a fill that finished a color shows instead: the canvas sweeps a shine over the
    /// color 0.35 s after it, for 1.1 s, and a flight leaving as it starts would hide it. Under
    /// Reduce Motion nothing shines, and `zenPause` holds.
    static let zenShinePause: Duration = .milliseconds(1300)

    /// Zen Mode's flight: the hint near `point`, unless something was painted, undone or
    /// finished meanwhile.
    private func showNextArea(near point: SIMD2<Float>, finishedColor: Bool) {
        let painted = revision
        let pause = finishedColor && !reduceMotion ? Self.zenShinePause : Self.zenPause
        Task {
            try? await Task.sleep(for: pause)
            guard revision == painted, !progress.isComplete else { return }
            showHint(near: point)
        }
    }

    // MARK: Internals

    private func emit(_ event: PaintEvent) {
        for o in observers { o(event) }
    }

    /// Brings `isComplete`, `isStarted` and `completedColors` up to date after `colors`' areas
    /// changed, writing each only when it flips: a write notifies observers even when the value
    /// stays the same.
    private func updateMilestones(colors: some Sequence<Int>) {
        for c in colors where (remainingByColor[c] == 0) != completedColors.contains(c) {
            if remainingByColor[c] == 0 { completedColors.insert(c) } else { completedColors.remove(c) }
        }
        if isComplete != progress.isComplete { isComplete = progress.isComplete }
        let started = progress.paintedCount > progress.groutCount(wall)
        if isStarted != started { isStarted = started }
    }

    private func noteInteraction() {
        let now = clock.now
        if let last = lastInteraction {
            let gap = now - last
            // Count time between strokes as painting time unless the user wandered off.
            if gap < .seconds(45) {
                progress.activeSeconds += Double(gap.components.seconds) + Double(gap.components.attoseconds) * 1e-18
            }
        }
        lastInteraction = now
    }

    private func nearestPaintable(
        to point: SIMD2<Float>, color: Int, radius: Float, maxInscribedRadius: Float = .infinity
    ) -> Int? {
        var best: Int?
        var bestD = Float.infinity
        forEachRegion(inDiscAt: point, radius: radius) { region, d2 in
            if d2 < bestD && !progress.isPainted(region) && colorOf(region) == color
                && template.regions[region].inscribedRadius <= maxInscribedRadius {
                bestD = d2
                best = region
            }
        }
        return best
    }

    /// Visits the pixels of the eligible regions within `r` of the segment a→b (the area a brush
    /// of radius `r` sweeps; pixel centres on the canvas grid), with the stroke parameter
    /// 0…1 at which the moving brush first covers each. This is the continuous limit of
    /// stamping the disc every canvas unit, at a cost proportional to the swept area.
    private func forEachRegion(
        inCapsuleFrom a: SIMD2<Float>, to b: SIMD2<Float>, radius r: Float, where isEligible: (Int) -> Bool,
        _ body: (_ region: Int, _ enter: Float) -> Void
    ) {
        let map = template.regionMap
        guard map.width > 0, map.height > 0 else { return }
        let d = b - a
        let len2 = simd_length_squared(d), len = len2.squareRoot()
        let r2 = r * r
        // The bounds below are padded by a pixel so rounding never drops an edge pixel; the
        // exact distance test decides.
        let pad: Float = 1
        let y0 = max(0, Int((min(a.y, b.y) - r - pad).rounded(.down)))
        let y1 = min(map.height - 1, Int((max(a.y, b.y) + r + pad).rounded(.up)))
        guard y0 <= y1 else { return }
        // Eligibility is asked once per run of pixels of one region, not per pixel.
        var lastRegion = -1, lastEligible = false
        map.storage.withUnsafeBufferPointer { regions in
            for y in y0...y1 {
                let cy = Float(y) + 0.5
                // Only the part of the segment within r (vertically) of this row can
                // bring its pixels within r.
                var t0: Float = 0, t1: Float = 1
                if d.y != 0 {
                    let u = (cy - r - pad - a.y) / d.y, v = (cy + r + pad - a.y) / d.y
                    t0 = max(0, min(u, v))
                    t1 = min(1, max(u, v))
                    if t0 > t1 { continue }
                } else if abs(cy - a.y) > r + pad {
                    continue
                }
                let xa = a.x + d.x * t0, xb = a.x + d.x * t1
                let x0 = max(0, Int((min(xa, xb) - r - pad).rounded(.down)))
                let x1 = min(map.width - 1, Int((max(xa, xb) + r + pad).rounded(.up)))
                guard x0 <= x1 else { continue }
                let row = y * map.width
                for x in x0...x1 {
                    let region = Int(regions[row + x])
                    if region != lastRegion {
                        lastRegion = region
                        lastEligible = isEligible(region)
                    }
                    guard lastEligible else { continue }
                    let p = SIMD2(Float(x) + 0.5, cy) - a
                    let along = len2 > 0 ? simd_dot(p, d) / len2 : 0
                    guard simd_length_squared(p - d * min(max(along, 0), 1)) <= r2 else { continue }
                    var enter: Float = 0
                    if len > 0 {
                        let perp2 = max(0, simd_length_squared(p) - along * along * len2)
                        enter = min(max(along - max(0, r2 - perp2).squareRoot() / len, 0), 1)
                    }
                    body(region, enter)
                }
            }
        }
    }

    /// Visits region indices under a disc (sampled on the canvas grid) with squared distance.
    private func forEachRegion(inDiscAt p: SIMD2<Float>, radius: Float, _ body: (Int, Float) -> Void) {
        let map = template.regionMap
        let r = max(0, radius)
        let x0 = max(0, Int((p.x - r).rounded(.down))), x1 = min(map.width - 1, Int((p.x + r).rounded(.up)))
        let y0 = max(0, Int((p.y - r).rounded(.down))), y1 = min(map.height - 1, Int((p.y + r).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return }
        let r2 = r * r
        map.storage.withUnsafeBufferPointer { buf in
            for y in y0...y1 {
                let dy = Float(y) + 0.5 - p.y
                for x in x0...x1 {
                    let dx = Float(x) + 0.5 - p.x
                    let d2 = dx * dx + dy * dy
                    if d2 <= r2 { body(Int(buf[y * map.width + x]), d2) }
                }
            }
        }
    }
}

nonisolated extension PaintProgress {
    /// 1 when a mosaic's grout is set (it is from the start), else 0: what the painter has set is
    /// `paintedCount` less this.
    func groutCount(_ wall: TileWall?) -> Int {
        guard let wall, wall.groutRegion < regionCount else { return 0 }
        return isPainted(wall.groutRegion) ? 1 : 0
    }

    /// The progress with a mosaic's grout set (`TileWall`): the ground, never painted by hand. It
    /// leads the log, where undo never reaches it, so progress saved without it, or with it
    /// elsewhere (v0's carried over paints it last), is laid again after it, each fill at its own
    /// time.
    func groutSet(_ wall: TileWall?) -> PaintProgress {
        guard let wall, wall.groutRegion < regionCount else { return self }
        if log.first.map({ Int($0.region) }) == wall.groutRegion { return self }
        var progress = PaintProgress(regionCount: regionCount)
        progress.activeSeconds = log.first.map { Double($0.time) } ?? activeSeconds
        progress.paint(wall.groutRegion)
        for stroke in log where Int(stroke.region) != wall.groutRegion {
            progress.activeSeconds = Double(stroke.time)
            progress.paint(Int(stroke.region))
        }
        progress.activeSeconds = activeSeconds
        return progress
    }
}
