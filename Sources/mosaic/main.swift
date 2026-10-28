// mosaic <photo.ppm> <contours.pgm> <out prefix> [--features f.json]... [--long-side N] [--bed bed.ppm]
//        [--eyes asTheyLook|asInThePhoto] [--mouth asInThePhoto|byzantine] [--face-cut L]
//        [--mark kind:width:x,y;x,y;...]...
//
// Runs the engine on files, for comparison with the prototype: reads a binary PPM (P6) photo, its
// contour map as a binary PGM (P5) and any faces' features (sketchbook/features.py's JSON), and
// writes <prefix>.json in the format prototype/mosaic_faces.py writes, so sketchbook/render.py can
// draw it. Prints the tile and paint counts and each stage's time. --bed also writes the painted
// bed (MosaicEngine.bed) at twice the photo's size, as render.py's `bed` finish draws it. --mark
// draws one of Refine's marks (`MosaicEngine.Mark`: line, unline, gold or ungold, its width a share
// of the long side, its path in the photo's unit square) into the contours, or lays it on the tiles.
import Foundation
import MosaicEngine
import MosaicKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// A binary PNM's samples, 0...1.
struct PNM {
    var width: Int, height: Int, channels: Int
    var samples: [Float]

    init(path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
        let bytes = [UInt8](data)
        var i = 0
        func token() -> String {
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "#") {
                    while i < bytes.count && bytes[i] != 10 { i += 1 }
                } else if bytes[i] == 32 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13 {
                    i += 1
                } else { break }
            }
            var s = ""
            while i < bytes.count, !(bytes[i] == 32 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13) {
                s.append(Character(UnicodeScalar(bytes[i]))); i += 1
            }
            return s
        }
        let magic = token()
        switch magic {
        case "P6": channels = 3
        case "P5": channels = 1
        default: fail("\(path): not a binary PPM (P6) or PGM (P5)")
        }
        guard let w = Int(token()), let h = Int(token()), let maxval = Int(token()), w > 0, h > 0, maxval > 0, maxval < 65536 else {
            fail("\(path): bad header")
        }
        i += 1   // the single whitespace before the samples
        width = w; height = h
        let n = w * h * channels, wide = maxval > 255
        guard bytes.count - i >= n * (wide ? 2 : 1) else { fail("\(path): too short") }
        let scale = 1 / Float(maxval)
        var samples = [Float](repeating: 0, count: n)
        for k in 0..<n {
            let v: Int = wide ? Int(bytes[i + 2 * k]) << 8 | Int(bytes[i + 2 * k + 1]) : Int(bytes[i + k])
            samples[k] = Float(v) * scale
        }
        self.samples = samples
    }
}

/// Bilinear resampling with half-pixel centres (cv2.resize's INTER_LINEAR), any channel count.
func resample(_ src: [Float], _ w: Int, _ h: Int, channels c: Int, to W: Int, _ H: Int) -> [Float] {
    if w == W && h == H { return src }
    func taps(_ n: Int, _ N: Int) -> [(Int, Int, Float)] {
        (0..<N).map { d in
            let f = (Double(d) + 0.5) * Double(n) / Double(N) - 0.5
            var s = Int(f.rounded(.down)), t = Float(f - Double(s))
            if s < 0 { s = 0; t = 0 }
            if s >= n - 1 { s = n - 1; t = 0 }
            return (s, min(s + 1, n - 1), t)
        }
    }
    let xs = taps(w, W), ys = taps(h, H)
    var out = [Float](repeating: 0, count: W * H * c)
    for y in 0..<H {
        let (y0, y1, ty) = ys[y]
        for x in 0..<W {
            let (x0, x1, tx) = xs[x]
            for k in 0..<c {
                let a = src[(y0 * w + x0) * c + k] * (1 - tx) + src[(y0 * w + x1) * c + k] * tx
                let b = src[(y1 * w + x0) * c + k] * (1 - tx) + src[(y1 * w + x1) * c + k] * tx
                out[(y * W + x) * c + k] = a * (1 - ty) + b * ty
            }
        }
    }
    return out
}

/// Area-averaging downscale (a box per output pixel), for `--long-side` below the photo's size.
func shrink(_ src: [Float], _ w: Int, _ h: Int, channels c: Int, to W: Int, _ H: Int) -> [Float] {
    var out = [Float](repeating: 0, count: W * H * c)
    let sx = Double(w) / Double(W), sy = Double(h) / Double(H)
    for y in 0..<H {
        let fy0 = Double(y) * sy, fy1 = fy0 + sy
        for x in 0..<W {
            let fx0 = Double(x) * sx, fx1 = fx0 + sx
            var acc = [Double](repeating: 0, count: c), total = 0.0
            var yy = Int(fy0)
            while Double(yy) < fy1 && yy < h {
                let wy = min(Double(yy + 1), fy1) - max(Double(yy), fy0)
                var xx = Int(fx0)
                while Double(xx) < fx1 && xx < w {
                    let wgt = (min(Double(xx + 1), fx1) - max(Double(xx), fx0)) * wy
                    for k in 0..<c { acc[k] += Double(src[(yy * w + xx) * c + k]) * wgt }
                    total += wgt
                    xx += 1
                }
                yy += 1
            }
            for k in 0..<c { out[(y * W + x) * c + k] = Float(acc[k] / max(total, 1e-12)) }
        }
    }
    return out
}

func json(_ v: Double, _ places: Double) -> String {
    let r = (v * places).rounded() / places
    return r == r.rounded() && abs(r) < 1e15 ? String(Int(r)) + ".0" : "\(r)"
}

// MARK: Arguments

var positional: [String] = []
var featureFiles: [String] = []
var longSide: Int?
var bedFile: String?
var settings = MosaicEngine.Settings()
var marks: [MosaicEngine.Mark] = []
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--features": guard let f = args.popFirst() else { fail("--features needs a file") }; featureFiles.append(f)
    case "--long-side": guard let v = args.popFirst(), let n = Int(v), n > 0 else { fail("--long-side needs a number") }; longSide = n
    case "--bed": guard let f = args.popFirst() else { fail("--bed needs a file") }; bedFile = f
    case "--face-cut": guard let v = args.popFirst(), let c = Float(v), c > 0, c <= 1 else { fail("--face-cut needs a level in (0, 1]") }; settings.faceCut = c
    case "--mouth": guard let v = args.popFirst(), let m = MosaicEngine.Mouth(rawValue: v) else { fail("--mouth is asInThePhoto or byzantine") }; settings.mouth = m
    case "--eyes": guard let v = args.popFirst(), let e = MosaicEngine.Eyes(rawValue: v) else { fail("--eyes is asTheyLook or asInThePhoto") }; settings.eyes = e
    case "--mark":
        let parts = (args.popFirst() ?? "").split(separator: ":", maxSplits: 2).map(String.init)
        let points = parts.count == 3 ? parts[2].split(separator: ";").compactMap { p -> SIMD2<Double>? in
            let xy = p.split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? SIMD2(xy[0], xy[1]) : nil
        } : []
        guard parts.count == 3, let kind = MosaicEngine.Mark.Kind(rawValue: parts[0]), let width = Double(parts[1]), width > 0,
              !points.isEmpty else { fail("--mark is kind:width:x,y;x,y;... (kind line, unline, gold or ungold)") }
        marks.append(MosaicEngine.Mark(kind: kind, width: width, points: points))
    case "-h", "--help":
        print("mosaic <photo.ppm> <contours.pgm> <out prefix> [--features f.json]... [--long-side N] [--bed bed.ppm] [--eyes asTheyLook|asInThePhoto] [--mouth asInThePhoto|byzantine] [--face-cut L] [--mark kind:width:x,y;...]..."); exit(0)
    default: positional.append(a)
    }
}
guard positional.count == 3 else { fail("usage: mosaic <photo.ppm> <contours.pgm> <out prefix> [--features f.json]... [--long-side N] [--bed bed.ppm] [--eyes asTheyLook|asInThePhoto] [--mouth asInThePhoto|byzantine] [--face-cut L] [--mark kind:width:x,y;...]...") }

let clock = ContinuousClock()
let started = clock.now
func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18 }

let photoFile = try PNM(path: positional[0])
guard photoFile.channels == 3 else { fail("\(positional[0]): the photo must be a PPM (P6)") }
var w = photoFile.width, h = photoFile.height
var rgb = photoFile.samples
var k: Float = 1
if let n = longSide, n != max(w, h) {
    k = Float(n) / Float(max(w, h))
    let W = max(Int((Float(w) * k).rounded()), 1), H = max(Int((Float(h) * k).rounded()), 1)
    rgb = n < max(w, h) ? shrink(rgb, w, h, channels: 3, to: W, H) : resample(rgb, w, h, channels: 3, to: W, H)
    k = Float(W) / Float(w)
    w = W; h = H
}
let contourFile = try PNM(path: positional[1])
guard contourFile.channels == 1 else { fail("\(positional[1]): the contour map must be a PGM (P5)") }
var contours = resample(contourFile.samples, contourFile.width, contourFile.height, channels: 1, to: w, h)
let recipe = MosaicEngine.Recipe(marks: marks)
recipe.mark(contours: &contours, width: w, height: h)

var faces: [MosaicEngine.Face] = []
for f in featureFiles {
    guard let data = FileManager.default.contents(atPath: f) else { fail("can't read \(f)") }
    var face = try JSONDecoder().decode(MosaicEngine.Face.self, from: data)
    if k != 1 {
        face.box = face.box.map { $0 * k }
        face.eyes = face.eyes.map { $0.map { $0 * k } }
        face.lines = face.lines.map { .init(kind: $0.kind, pts: $0.pts.map { $0.map { $0 * k } }) }
    }
    faces.append(face)
}
let photo = MosaicEngine.Photo(width: w, height: h, rgb: (0..<(w * h)).map { SIMD3(rgb[3 * $0], rgb[3 * $0 + 1], rgb[3 * $0 + 2]) })
let read = clock.now - started

var trace = MosaicEngine.Trace()
let made = clock.now
let mosaic = recipe.laid(try MosaicEngine.make(photo: photo, contours: contours, faces: faces, settings: settings,
                                               cancel: { false }, trace: &trace))
let engine = clock.now - made

// The prototype's design JSON: canvas at twice the photo, corners in photo pixels.
var out = "{\"size\": [\(w * 2), \(h * 2)], \"scale\": 2, \"pitch\": \(json(Double(settings.pitch), 1000)), "
out += "\"grout\": [\(json(Double(mosaic.grout.x), 1e4)), \(json(Double(mosaic.grout.y), 1e4)), \(json(Double(mosaic.grout.z), 1e4))], "
out += "\"palette\": [" + mosaic.palette.map { "[\(json(Double($0.x), 1e4)), \(json(Double($0.y), 1e4)), \(json(Double($0.z), 1e4))]" }.joined(separator: ", ") + "], "
out += "\"tiles\": ["
out += mosaic.tiles.enumerated().map { i, t in
    let corners = t.corners.map { "[\(json(Double($0.x), 1000)), \(json(Double($0.y), 1000))]" }.joined(separator: ", ")
    let feature = trace.feature[i].map { ", \"feature\": \"\($0)\"" } ?? ""
    let stage = t.stage.map { ", \"stage\": \"\($0.rawValue)\"" } ?? ""
    return "{\"corners\": [\(corners)], \"paint\": \(t.paint), \"strand\": \(trace.strand[i])\(feature)\(stage)}"
}.joined(separator: ", ")
out += "]}"
let path = positional[2] + ".json"
guard FileManager.default.createFile(atPath: path, contents: Data(out.utf8)) else { fail("can't write \(path)") }

let onLines = trace.stages.first { $0.name == "strands" }?.tiles ?? 0
print("\(mosaic.tiles.count) tiles, \(onLines) on strands, \(mosaic.palette.count) paints")
for s in trace.stages {
    print("  " + s.name.padding(toLength: 9, withPad: " ", startingAt: 0) + String(format: " %6.3f s  %5d tiles", s.seconds, s.tiles))
}
print(String(format: "  engine    %6.3f s (reading %.3f s, total %.3f s)", seconds(engine), seconds(read), seconds(clock.now - started)))

if let bedFile {
    let bw = w * 2, bh = h * 2
    let bed = MosaicEngine.bed(of: mosaic, width: bw, height: bh)
    var bytes = [UInt8]("P6\n\(bw) \(bh)\n255\n".utf8)
    bytes.reserveCapacity(bytes.count + bw * bh * 3)
    for c in bed { for v in [c.x, c.y, c.z] { bytes.append(UInt8(max(0, min(255, (v * 255).rounded())))) } }
    guard FileManager.default.createFile(atPath: bedFile, contents: Data(bytes)) else { fail("can't write \(bedFile)") }
}
