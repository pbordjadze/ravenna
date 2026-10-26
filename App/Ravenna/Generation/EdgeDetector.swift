import CoreGraphics
import CoreML
import Foundation
import PaintCore

/// The maps a coloring book draws from, made by the two bundled models
/// (`Resources/Models`): HED (`HED.mlpackage`: ControlNet's Apache-2.0 retraining of Xie & Tu's
/// holistically-nested edge detector, converted by `tools/models/convert_hed.py`), a contour map
/// whose silhouettes are strong and closed, and the Informative Drawings generator
/// (`LineArt.mlpackage`: Chan, Durand & Isola's MIT-licensed line-drawing network, the one
/// ControlNet's lineart annotator runs, converted by `tools/models/convert_lineart.py`), a line
/// drawing with the fur, petals and glass a contour map lacks. `maps` makes both; `LineArtInputs`
/// lays the drawing over the contours (`EdgeMap.combined`), which is what the app generates from,
/// with the contours deciding the outlines.
///
/// A map is made the way the layered-lines research made its HED maps: the photo in sRGB,
/// area-resampled to at most the model's long side (PaintCore's own resampler, as `pbn` made the
/// research's working images), reflect-padded at the bottom and right to the network's stride,
/// the probability cropped back and rounded to the nearest of 256 levels. The models run on the
/// CPU only (`.cpuOnly`) in float32: the Neural Engine and GPU compute in reduced precision that
/// differs between chips, and the 8-bit rounding absorbs the float32 noise that is left, so a
/// photo gets the same map on every device (but where a value lies within that noise of a
/// rounding boundary, which moves it by one level).
nonisolated enum EdgeDetector {
    enum DetectorError: Error {
        /// The model's `.mlmodelc` isn't in the app bundle.
        case modelMissing(Model)
        /// The model returned something other than a float32 map of the input's size.
        case unexpectedOutput
    }

    /// A bundled model and how it is fed.
    enum Model: String, Sendable, CaseIterable {
        /// HED: contours, from `HED.mlmodelc`.
        case hed
        /// The line-drawing generator, from `LineArt.mlmodelc`.
        case lineArt

        /// The model's resource name in the bundle.
        var resource: String {
            switch self {
            case .hed: "HED"
            case .lineArt: "LineArt"
            }
        }

        /// The network's total stride: its input is padded to a multiple of it.
        var inputMultiple: Int {
            switch self {
            case .hed: 16
            case .lineArt: 4
            }
        }

        /// What a byte of the photo is in the model's input: HED takes 0...255, the drawing 0...1.
        var inputScale: Float {
            switch self {
            case .hed: 1
            case .lineArt: 1 / 255
            }
        }

        /// The model's output feature: a probability map, 1 where there is a line.
        var output: String {
            switch self {
            case .hed: "edges"
            case .lineArt: "lines"
            }
        }
    }

    /// Longest side the models accept (their input shapes' bound) and the default size of maps.
    static let maximumLongSide = 1152
    /// The long side the line drawing is made at: the generator was trained on small crops, so
    /// at 768 its lines are a touch heavier and cleaner than at 1152, and it runs four times
    /// faster; the drawing is resampled up to the map's size.
    static let drawingLongSide = 768
    /// HED's stride, the coarser of the two: its input is padded to a multiple of it.
    static let inputMultiple = Model.hed.inputMultiple

    /// The HED edge map of `image` (any color space; drawn into sRGB), at the image's own size or
    /// scaled down so its long side is at most `maxLongSide` (clamped to `maximumLongSide`).
    /// Synchronous and CPU-heavy (a VGG-16 pass, seconds at 1152 px): call it off the main actor.
    /// Throws `CancellationError` when the current task is cancelled (checked between steps).
    static func edgeMap(for image: CGImage, maxLongSide: Int = maximumLongSide) throws -> EdgeMap {
        try edgeMap(for: PhotoLoader.rgbaImage(from: image, colorSpace: .sRGB), maxLongSide: maxLongSide, cancel: .task)
    }

    /// The HED edge map of an sRGB image (see `edgeMap(for:maxLongSide:)`).
    static func edgeMap(for image: RGBAImage, maxLongSide: Int = maximumLongSide, cancel: CancellationCheck) throws -> EdgeMap {
        try map(.hed, for: image, maxLongSide: maxLongSide, cancel: cancel)
    }

    /// The line drawing of an sRGB image (see `edgeMap(for:maxLongSide:)`; `maxLongSide` defaults
    /// to `drawingLongSide`), ink probability per pixel.
    static func lineDrawing(for image: RGBAImage, maxLongSide: Int = drawingLongSide, cancel: CancellationCheck) throws -> EdgeMap {
        try map(.lineArt, for: image, maxLongSide: maxLongSide, cancel: cancel)
    }

    /// Both maps of a photo: the line drawing (made at `drawingLongSide`, resampled up to the
    /// HED map's size) and the HED map at `maxLongSide`. What the app generates from is the
    /// drawing over the contours (`EdgeMap.combined`) with the contours deciding the outlines, or
    /// either alone (`LineArtSettings.Detector`, `LineArtInputs`).
    static func maps(for image: CGImage, maxLongSide: Int = maximumLongSide) throws -> (drawing: EdgeMap, contours: EdgeMap) {
        try maps(for: PhotoLoader.rgbaImage(from: image, colorSpace: .sRGB), maxLongSide: maxLongSide, cancel: .task)
    }

    /// The maps of an sRGB image (see `maps(for:maxLongSide:)`).
    static func maps(
        for image: RGBAImage, maxLongSide: Int = maximumLongSide, cancel: CancellationCheck
    ) throws -> (drawing: EdgeMap, contours: EdgeMap) {
        let contours = try map(.hed, for: image, maxLongSide: maxLongSide, cancel: cancel)
        let drawing = try map(.lineArt, for: image, maxLongSide: min(drawingLongSide, maxLongSide), cancel: cancel)
        try cancel.throwIfCancelled()
        return (drawing.resampled(width: contours.width, height: contours.height), contours)
    }

    /// `model`'s map of `image`, at the image's size scaled down to `maxLongSide` (clamped to
    /// `maximumLongSide`).
    static func map(_ model: Model, for image: RGBAImage, maxLongSide: Int, cancel: CancellationCheck) throws -> EdgeMap {
        try cancel.throwIfCancelled()
        let size = mapSize(width: image.width, height: image.height, maxLongSide: maxLongSide)
        let input = size.width == image.width && size.height == image.height
            ? image
            : Resample.area(image, width: size.width, height: size.height)
        try cancel.throwIfCancelled()
        let loaded = try loadModel(model)
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: paddedInput(input, for: model))])
        try cancel.throwIfCancelled()
        let output = try loaded.prediction(from: features)
        try cancel.throwIfCancelled()
        guard let values = output.featureValue(for: model.output)?.multiArrayValue else { throw DetectorError.unexpectedOutput }
        return try edgeMap(from: values, width: input.width, height: input.height)
    }

    /// The size a map of a `width` × `height` photo has: the photo's, scaled down to fit
    /// `maxLongSide` (rounded as the generator rounds its working size).
    static func mapSize(width: Int, height: Int, maxLongSide: Int) -> (width: Int, height: Int) {
        let limit = min(max(maxLongSide, inputMultiple), maximumLongSide)
        let long = max(width, height)
        guard long > limit else { return (width, height) }
        let scale = Double(limit) / Double(long)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Where padded row or column `i` reads from in a line of `n` pixels: mirrored at the end
    /// without repeating the last pixel (NumPy's "reflect", which the research padded with).
    static func reflect(_ i: Int, _ n: Int) -> Int {
        guard i >= n else { return i }
        guard n > 1 else { return 0 }
        let period = 2 * (n - 1)
        let m = i % period
        return m < n ? m : period - m
    }

    /// A probability as a map level: the nearest of 256 (half up), like the reference maps the
    /// conversion scripts write.
    static func level(_ p: Float) -> UInt8 {
        guard p.isFinite else { return 0 }
        return UInt8(min(max((Double(p) * 255 + 0.5).rounded(.down), 0), 255))
    }

    private static func loadModel(_ model: Model) throws -> MLModel {
        guard let url = Bundle.main.url(forResource: model.resource, withExtension: "mlmodelc") else {
            throw DetectorError.modelMissing(model)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    /// The image as the model's [1, 3, H, W] float input, RGB scaled by the model's
    /// `inputScale`, reflect-padded at the bottom and right to multiples of its stride.
    private static func paddedInput(_ image: RGBAImage, for model: Model) throws -> MLMultiArray {
        let w = image.width, h = image.height
        let m = model.inputMultiple, scale = model.inputScale
        let paddedWidth = (w + m - 1) / m * m, paddedHeight = (h + m - 1) / m * m
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: paddedHeight), NSNumber(value: paddedWidth)], dataType: .float32)
        let columns = (0..<paddedWidth).map { reflect($0, w) }
        image.pixels.withUnsafeBufferPointer { source in
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { target, strides in
                let channel = strides[1], row = strides[2], column = strides[3]
                for y in 0..<paddedHeight {
                    let sourceRow = reflect(y, h) * w
                    for x in 0..<paddedWidth {
                        let s = (sourceRow + columns[x]) * 4
                        let t = y * row + x * column
                        target[t] = Float(source[s]) * scale
                        target[t + channel] = Float(source[s + 1]) * scale
                        target[t + 2 * channel] = Float(source[s + 2]) * scale
                    }
                }
            }
        }
        return array
    }

    /// The top-left `width` × `height` of the model's [1, 1, H, W] output, as levels.
    private static func edgeMap(from output: MLMultiArray, width: Int, height: Int) throws -> EdgeMap {
        let shape = output.shape.map(\.intValue)
        guard output.dataType == .float32, shape.count == 4, shape[0] == 1, shape[1] == 1,
              shape[2] >= height, shape[3] >= width
        else { throw DetectorError.unexpectedOutput }
        let strides = output.strides.map(\.intValue)
        var values = [UInt8](repeating: 0, count: width * height)
        output.withUnsafeBufferPointer(ofType: Float.self) { source in
            for y in 0..<height {
                for x in 0..<width {
                    values[y * width + x] = level(source[y * strides[2] + x * strides[3]])
                }
            }
        }
        return EdgeMap(width: width, height: height, values: values)
    }
}
