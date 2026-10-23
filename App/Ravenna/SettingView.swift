import SwiftUI
import UIKit

/// One mosaic being set: the wall, the tray of smalti, and the painter's finger. Hold a paint from
/// the tray, then tap its tiles or drag along a row of them; each is pressed, settles into the bed
/// and catches the light as it does.
struct SettingView: View {
    @Environment(Library.self) private var library
    let work: Work

    @State private var bench: Bench?
    @State private var failed = false
    @State private var showingWork = false
    @State private var showingOptions = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            if let bench {
                VStack(spacing: 0) {
                    Wall(bench: bench, finish: library.finish, bed: library.image(work, "bed")) { set in
                        library.save(set, work, library.detail)
                    }
                    Tray(bench: bench)
                }
                if bench.setting.isComplete(bench.mosaic) {
                    Finished(work: work) { showingWork = true }
                }
            } else if failed {
                ContentUnavailableView("Couldn't open this mosaic", systemImage: "square.grid.3x3",
                                       description: Text("Its file is missing from the app."))
            } else {
                ProgressView().tint(Theme.tint)
            }
        }
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("About this work", systemImage: "info.circle") { showingWork = true }
                    Button("Options", systemImage: "slider.horizontal.3") { showingOptions = true }
                }
            }
        }
        .sheet(isPresented: $showingWork) { WorkView(work: work) }
        .sheet(isPresented: $showingOptions) { OptionsView() }
        .task(id: library.detail) {
            bench = nil
            failed = false
            do {
                let mosaic = try await library.mosaic(work, library.detail)
                bench = Bench(mosaic: mosaic, setting: library.setting(work, library.detail))
            } catch {
                failed = true
            }
        }
    }
}

/// A mosaic on the bench: its tiles, where they are, what is set, the paint in hand, and the tiles
/// going in now.
@Observable
final class Bench {
    let mosaic: Mosaic
    let index: TileIndex
    var setting: Setting
    var paint: Int?
    /// Tiles going in, and when each began; a row's are spaced out, some a moment ahead.
    var recent: [Int: Date] = [:]
    /// The tile under a finger that has just landed, its tessera held over it.
    var press: Int?
    /// When light began raking across the wall, just finished.
    var rake: Date?
    static let rakeTime = 2.4

    /// The next moment free in the stroke being laid, if one is.
    @ObservationIgnored private var stroke: Date?
    @ObservationIgnored private var laidInStroke = false
    @ObservationIgnored private var drawings: [Finish: Drawing] = [:]
    @ObservationIgnored private var wallImage: (finish: Finish, image: WallImage?)?
    /// A middling tile's side, to weigh each tile's sound and tap by its size.
    private let typical: Float

    enum Tap { case set(Date), miss, nothing }

    /// What setting tiles came to.
    struct Outcome {
        var changed = false
        var ranOut = false
        var finished = false
    }

    init(mosaic: Mosaic, setting: Setting) {
        self.mosaic = mosaic
        self.index = TileIndex(mosaic)
        self.setting = setting
        self.paint = setting.nextPaint(after: nil, in: mosaic)
        typical = (mosaic.width * mosaic.height / Float(max(mosaic.tiles.count, 1))).squareRoot()
    }

    func drawing(_ finish: Finish) -> Drawing {
        if let d = drawings[finish] { return d }
        let d = Drawing(mosaic, finish: finish)
        drawings[finish] = d
        return d
    }

    /// The wall's baked image in a finish; only the current finish's is kept.
    func wall(_ finish: Finish, bed: UIImage?) -> WallImage? {
        if let w = wallImage, w.finish == finish { return w.image }
        let image = WallImage(mosaic, drawing: drawing(finish), bed: bed)
        wallImage = (finish, image)
        return image
    }

    /// How large a tile is against a middling one, 0...1, for how loud and firm it lands.
    func weight(_ tile: Int) -> Double {
        let (lo, hi) = mosaic.tiles[tile].bounds, side = ((hi.x - lo.x) * (hi.y - lo.y)).squareRoot()
        return Double(min(max(side / max(typical, 0.01) * 0.6, 0), 1))
    }

    /// A finger landed: if the tile under it takes the paint in hand, its tessera rises.
    func pressDown(_ tile: Int?) {
        press = tile.flatMap { t in paint == mosaic.tiles[t].paint && !setting.isSet(t) ? t : nil }
    }

    /// Sets the tile if it takes the paint in hand. Call `afterSetting` once the tap is done.
    func tap(_ tile: Int) -> Tap {
        let held = press == tile
        press = nil
        guard let paint, !setting.isSet(tile) else { return .nothing }
        guard setting.place(tile, with: paint, in: mosaic) else { return .miss }
        // A tessera already raised by the press settles straight away.
        let at = held ? Date.now.addingTimeInterval(-Motion.press) : .now
        settle([(tile, at)])
        return .set(at)
    }

    /// Part of a stroke along a row: sets the tiles it passed over that take the paint in hand, one
    /// after another, however fast the finger went.
    func lay(_ passed: [Int]) -> [(tile: Int, at: Date)] {
        guard let paint else { return [] }
        var tiles = setting.laying(passed, with: paint, in: mosaic)
        // The tile the stroke began on goes in first.
        if stroke == nil, let p = press, !tiles.contains(p), mosaic.tiles[p].paint == paint, !setting.isSet(p) { tiles.insert(p, at: 0) }
        press = nil
        let now = Date.now
        var next = max(stroke ?? now, now)
        var laid: [(tile: Int, at: Date)] = []
        for t in tiles where setting.place(t, with: paint, in: mosaic) {
            laid.append((t, next))
            next += Motion.rowGap
        }
        stroke = next
        if !laid.isEmpty { laidInStroke = true }
        settle(laid)
        return laid
    }

    /// The stroke is over (or was taken off by a second finger).
    func endStroke() -> Outcome {
        press = nil
        guard stroke != nil else { return Outcome() }
        stroke = nil
        defer { laidInStroke = false }
        return laidInStroke ? afterSetting() : Outcome()
    }

    /// After tiles go in: take up the next paint when this one runs out, and see whether the work is set.
    func afterSetting() -> Outcome {
        var o = Outcome(changed: true)
        if let p = paint, setting.remaining(in: mosaic)[p] == 0 {
            paint = setting.nextPaint(after: p, in: mosaic)
            o.ranOut = true
        }
        o.finished = setting.isComplete(mosaic)
        return o
    }

    /// Light rakes once across the finished wall.
    func beginRake() {
        let start = Date.now.addingTimeInterval(recent.values.max().map { max($0.timeIntervalSinceNow + Motion.total * 0.6, 0) } ?? 0)
        rake = start
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(start.timeIntervalSinceNow + Bench.rakeTime + 0.05))
            if self?.rake == start { self?.rake = nil }
        }
    }

    private func settle(_ tiles: [(tile: Int, at: Date)]) {
        guard let end = tiles.map(\.at).max() else { return }
        for (t, at) in tiles { recent[t] = at }
        // Once they are all down, they leave `recent` and the wall's image takes them.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow + Motion.total + 0.05, 0)))
            guard let self else { return }
            let now = Date.now
            recent = recent.filter { now.timeIntervalSince($0.value) < Motion.total }
        }
    }
}

/// The smalti in hand: one chip per paint, its number and how many tiles it has left.
private struct Tray: View {
    let bench: Bench

    var body: some View {
        let left = bench.setting.remaining(in: bench.mosaic)
        VStack(spacing: 6) {
            Text("\(bench.setting.set.count.formatted()) of \(bench.mosaic.tiles.count.formatted()) tiles set")
                .font(Theme.body(13).monospacedDigit()).foregroundStyle(Theme.muted)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bench.mosaic.palette.indices, id: \.self) { p in
                            Button { bench.paint = p } label: {
                                Chip(color: bench.mosaic.palette[p], number: p + 1, left: left[p], held: bench.paint == p, cut: p)
                            }
                            .buttonStyle(.plain)
                            .disabled(left[p] == 0)
                            .id(p)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .onChange(of: bench.paint) { _, p in
                    if let p { withAnimation { proxy.scrollTo(p, anchor: .center) } }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.panel)
    }
}

/// A smalti chip, cut a little irregular as a tessera is.
private struct Chip: View {
    let color: SIMD3<Float>
    let number: Int
    let left: Int
    let held: Bool
    /// Which cut: each paint's chip is its own shape, always the same.
    let cut: Int
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 44

    var body: some View {
        let light = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z > 0.55
        let side = min(scaled, 64)
        VStack(spacing: 3) {
            Tessera(cut: cut)
                .fill(Color(color))
                .frame(width: side, height: side)
                .overlay {
                    if left == 0 {
                        Image(systemName: "checkmark").font(.system(size: side * 0.34, weight: .bold))
                            .foregroundStyle(light ? Color.black.opacity(0.6) : Color.white.opacity(0.8))
                    } else {
                        Text("\(number)").font(.system(size: side * 0.39, weight: .semibold, design: .serif))
                            .foregroundStyle(light ? Color.black.opacity(0.75) : Color.white.opacity(0.9))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 4).inset(by: -4)
                        .stroke(held ? Theme.tint : .clear, lineWidth: 2)
                }
                .scaleEffect(held ? 1.06 : 1)
                .animation(.snappy(duration: 0.18), value: held)
            Text(left == 0 ? " " : "\(left)").font(Theme.body(12).monospacedDigit()).foregroundStyle(Theme.muted)
        }
        .opacity(left == 0 ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left == 0 ? "Paint \(number), all set" : "Paint \(number), \(left) tiles left")
        .accessibilityAddTraits(held ? .isSelected : [])
    }
}

/// A square cut by hand: each corner a little off, the same way every time for a given cut.
private struct Tessera: Shape {
    let cut: Int

    func path(in r: CGRect) -> Path {
        let j = { (k: UInt64) in CGFloat(TileColor.wobble(cut, salt: k)) * min(r.width, r.height) * 0.05 }
        var p = Path()
        p.move(to: CGPoint(x: r.minX + j(1), y: r.minY + j(2)))
        p.addLine(to: CGPoint(x: r.maxX + j(3), y: r.minY + j(4)))
        p.addLine(to: CGPoint(x: r.maxX + j(5), y: r.maxY + j(6)))
        p.addLine(to: CGPoint(x: r.minX + j(7), y: r.maxY + j(8)))
        p.closeSubpath()
        return p
    }
}

/// Every tile in place.
private struct Finished: View {
    let work: Work
    let about: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Set").font(Theme.title(28)).foregroundStyle(Theme.gold)
            Text("Every tile of \(work.title) is in place.").font(Theme.body(15)).foregroundStyle(Theme.plaster)
                .multilineTextAlignment(.center)
            Button("About this work", action: about).buttonStyle(.bordered)
        }
        .padding(20)
        .background(Theme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
    }
}

/// The work behind a mosaic: its picture and its credit.
struct WorkView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let work: Work

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let photo = library.image(work, "photo") {
                        Image(uiImage: photo).resizable().scaledToFit()
                            .accessibilityLabel(work.title)
                    }
                    Text(work.title).font(Theme.title(24)).foregroundStyle(Theme.plaster)
                    Text("\(work.place), \(work.date)").font(Theme.body(16)).foregroundStyle(Theme.muted)
                    Text(work.medium).font(Theme.body(15)).foregroundStyle(Theme.muted)
                    Text(work.credit).font(Theme.body(14)).foregroundStyle(Theme.muted)
                    Link("See it at the Met", destination: work.url).font(Theme.body(15))
                }
                .padding(20)
            }
            .background(Theme.ground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
