import SwiftUI
import UIKit

/// One mosaic being set: the wall, the tray of smalti, and the painter's finger. Hold a paint from
/// the tray, tap its tiles; a set tile drops into place and its gold catches the light as it does.
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
                ProgressView().tint(Theme.gold)
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

/// A mosaic on the bench: its tiles, where they are, what is set, and the paint in hand.
@Observable
final class Bench {
    let mosaic: Mosaic
    let index: TileIndex
    var setting: Setting
    var paint: Int?
    /// Tiles set in the last moment, and when: they are still dropping into place.
    var recent: [Int: Date] = [:]
    var placed = 0
    var misses = 0
    @ObservationIgnored private var drawings: [Finish: Drawing] = [:]

    init(mosaic: Mosaic, setting: Setting) {
        self.mosaic = mosaic
        self.index = TileIndex(mosaic)
        self.setting = setting
        self.paint = setting.nextPaint(after: nil, in: mosaic)
    }

    func drawing(_ finish: Finish) -> Drawing {
        if let d = drawings[finish] { return d }
        let d = Drawing(mosaic, finish: finish)
        drawings[finish] = d
        return d
    }

    /// Sets the tile if it takes the paint in hand; when that paint runs out, takes up the next.
    func tap(_ tile: Int) -> Bool {
        guard let paint, !setting.isSet(tile) else { return false }
        guard setting.place(tile, with: paint, in: mosaic) else { misses += 1; return false }
        placed += 1
        let now = Date.now
        recent[tile] = now
        if setting.remaining(in: mosaic)[paint] == 0 { self.paint = setting.nextPaint(after: paint, in: mosaic) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.recent = self?.recent.filter { Date.now.timeIntervalSince($0.value) < 0.5 } ?? [:]
        }
        return true
    }
}

/// What drawing a mosaic needs, worked out once per finish.
struct Drawing {
    var paths: [Path] = []
    var centres: [CGPoint] = []
    var boxes: [CGRect] = []
    /// A tile's size: the side of a square of its bounds' area.
    var sizes: [CGFloat] = []
    var body: [Color] = []
    var lit: [Color] = []
    var shade: [Color] = []

    init(_ m: Mosaic, finish: Finish) {
        for (i, t) in m.tiles.enumerated() {
            var p = Path()
            p.addLines(t.corners.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            p.closeSubpath()
            paths.append(p)
            let b = p.boundingRect
            boxes.append(b)
            sizes.append((b.width * b.height).squareRoot())
            centres.append(CGPoint(x: CGFloat(t.centre.x), y: CGFloat(t.centre.y)))
            let rgb = TileColor.body(m.palette[t.paint], tile: i, finish: finish)
            body.append(Color(rgb))
            let (l, s) = TileColor.bevel(rgb, stone: t.stone)
            lit.append(Color(l))
            shade.append(Color(s))
        }
    }
}

/// Where the mosaic sits on screen: fitted, then zoomed and moved by the painter.
struct Viewport {
    var size: CGSize
    var canvas: CGSize
    var zoom: CGFloat
    var offset: CGSize

    var scale: CGFloat { min(size.width / canvas.width, size.height / canvas.height) * 0.94 * zoom }

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width + (p.x - canvas.width / 2) * scale,
                y: size.height / 2 + offset.height + (p.y - canvas.height / 2) * scale)
    }

    func toCanvas(_ q: CGPoint) -> CGPoint {
        CGPoint(x: canvas.width / 2 + (q.x - size.width / 2 - offset.width) / scale,
                y: canvas.height / 2 + (q.y - size.height / 2 - offset.height) / scale)
    }
}

/// The wall: pinch to zoom, drag to move, tap to set.
private struct Wall: View {
    let bench: Bench
    let finish: Finish
    let bed: UIImage?
    let save: (Setting) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureStart: (zoom: CGFloat, offset: CGSize)?

    var body: some View {
        GeometryReader { geo in
            let canvas = CGSize(width: CGFloat(bench.mosaic.width), height: CGFloat(bench.mosaic.height))
            let vp = Viewport(size: geo.size, canvas: canvas, zoom: zoom, offset: offset)
            // Read here, in body, so SwiftUI redraws the wall when they change.
            let state = WallState(setting: bench.setting, held: bench.paint, recent: bench.recent)
            TimelineView(.animation(paused: state.recent.isEmpty)) { timeline in
                Canvas { ctx, size in
                    draw(&ctx, Viewport(size: size, canvas: canvas, zoom: zoom, offset: offset), state, now: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in tap(v.location, vp) })
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        let start = gestureStart ?? (zoom: zoom, offset: offset)
                        gestureStart = start
                        offset = CGSize(width: start.offset.width + v.translation.width,
                                        height: start.offset.height + v.translation.height)
                    }
                    .onEnded { _ in gestureStart = nil }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        let start = gestureStart ?? (zoom: zoom, offset: offset)
                        gestureStart = start
                        let z = min(max(start.zoom * v.magnification, 1), 14)
                        // Keep the point under the pinch where it is.
                        let a = v.startLocation
                        let cx = geo.size.width / 2, cy = geo.size.height / 2
                        let k = z / start.zoom
                        offset = CGSize(width: a.x - cx - (a.x - cx - start.offset.width) * k,
                                        height: a.y - cy - (a.y - cy - start.offset.height) * k)
                        zoom = z
                    }
                    .onEnded { _ in gestureStart = nil }
            )
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: bench.placed)
            .sensoryFeedback(.error, trigger: bench.misses)
        }
        .clipped()
    }

    private func tap(_ q: CGPoint, _ vp: Viewport) {
        let p = vp.toCanvas(q)
        let slop = Float(14 / vp.scale)
        guard let i = bench.index.tile(at: SIMD2(Float(p.x), Float(p.y)), slop: slop) else { return }
        if bench.tap(i) { save(bench.setting) }
    }

    private struct WallState {
        var setting: Setting
        var held: Int?
        var recent: [Int: Date]
    }

    private func draw(_ ctx: inout GraphicsContext, _ vp: Viewport, _ state: WallState, now: Date) {
        let m = bench.mosaic, d = bench.drawing(finish), s = vp.scale
        var g = ctx
        g.translateBy(x: vp.size.width / 2 + vp.offset.width, y: vp.size.height / 2 + vp.offset.height)
        g.scaleBy(x: s, y: s)
        g.translateBy(x: -vp.canvas.width / 2, y: -vp.canvas.height / 2)
        let wall = CGRect(origin: .zero, size: vp.canvas)
        if finish.paintedBed, let bed {
            g.draw(Image(uiImage: bed), in: wall)
        } else {
            g.fill(Path(wall), with: .color(Color(m.grout)))
        }
        let lo = vp.toCanvas(.zero), hi = vp.toCanvas(CGPoint(x: vp.size.width, y: vp.size.height))
        let visible = bench.index.tiles(in: SIMD2(Float(lo.x), Float(lo.y)), SIMD2(Float(hi.x), Float(hi.y)))
        let hair = 1 / s
        let outline = finish.paintedBed ? Color.black.opacity(0.35) : Color(red: 0.55, green: 0.52, blue: 0.48)
        let edge = Color(red: 0.2, green: 0.18, blue: 0.17)
        for i in visible {
            let path = d.paths[i]
            if state.setting.isSet(i) {
                var t: Double = 1
                if let at = state.recent[i] { t = min(max(now.timeIntervalSince(at) / 0.45, 0), 1) }
                var tg = g
                if t < 1 {
                    let c = d.centres[i], k = 1 + 0.45 * (1 - t) * (1 - t)
                    tg.translateBy(x: c.x, y: c.y)
                    tg.scaleBy(x: k, y: k)
                    tg.translateBy(x: -c.x, y: -c.y)
                }
                if finish == .material {
                    let b = d.boxes[i]
                    tg.fill(path, with: .linearGradient(Gradient(colors: [d.lit[i], d.body[i], d.shade[i]]),
                                                        startPoint: b.origin, endPoint: CGPoint(x: b.maxX, y: b.maxY)))
                } else {
                    tg.fill(path, with: .color(d.body[i]))
                }
                if finish == .flat { tg.stroke(path, with: .color(edge), lineWidth: hair * 0.8) }
                // Gold catches the light where a tile is being set, and only there.
                if t < 1 { tg.fill(path, with: .color(Theme.gold.opacity(0.7 * (1 - t)))) }
            } else {
                if m.tiles[i].paint == state.held { g.fill(path, with: .color(.white.opacity(0.18))) }
                g.stroke(path, with: .color(outline), lineWidth: hair * 0.7)
            }
        }
        // Numbers, once a tile is big enough on screen to read one.
        var texts: [Int: GraphicsContext.ResolvedText] = [:]
        let ink = finish.paintedBed ? Theme.plaster : Color(red: 0.25, green: 0.23, blue: 0.21)
        for i in visible where !state.setting.isSet(i) {
            let side = d.sizes[i] * s
            guard side >= 16 else { continue }
            let paint = m.tiles[i].paint
            let size = Int(min(max(side * 0.4, 8), 20))
            let key = paint * 64 + size
            let text = texts[key] ?? ctx.resolve(Text("\(paint + 1)")
                .font(.system(size: CGFloat(size), weight: .semibold, design: .rounded))
                .foregroundStyle(ink))
            texts[key] = text
            ctx.draw(text, at: vp.toScreen(d.centres[i]))
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
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bench.mosaic.palette.indices, id: \.self) { p in
                            Chip(color: bench.mosaic.palette[p], number: p + 1, left: left[p], held: bench.paint == p)
                                .id(p)
                                .onTapGesture { if left[p] > 0 { bench.paint = p } }
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

private struct Chip: View {
    let color: SIMD3<Float>
    let number: Int
    let left: Int
    let held: Bool

    var body: some View {
        let light = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z > 0.55
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(color))
                .frame(width: 44, height: 44)
                .overlay {
                    if left == 0 {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(light ? Color.black.opacity(0.6) : Color.white.opacity(0.8))
                    } else {
                        Text("\(number)").font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(light ? Color.black.opacity(0.75) : Color.white.opacity(0.9))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7).inset(by: -3)
                        .stroke(held ? Theme.gold : .clear, lineWidth: 2.5)
                }
            Text(left == 0 ? " " : "\(left)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
        }
        .opacity(left == 0 ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left == 0 ? "Paint \(number), all set" : "Paint \(number), \(left) tiles left")
        .accessibilityAddTraits(held ? .isSelected : [])
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
