import CoreGraphics
import CoreML
import Foundation
import PaintCore

/// The contour map Ravenna's engine lays its strands on, made by the bundled HED model
/// (`Resources/Models/HED.mlpackage`: ControlNet's Apache-2.0 retraining of Xie & Tu's
/// holistically-nested edge detector, converted by Paint by Moonlight's
/// `tools/models/convert_hed.py`), a contour map whose silhouettes are strong and closed.
/// Ravenna's seam: Paint by Moonlight's line-drawing model (`LineArt.mlpackage`) and the maps
/// made from both are left behind, since no such model ships here.
///
/// A map is made the way the layered-lines research made its HED maps: the photo in sRGB,
/// area-resampled to at most the model's long side (PaintCore's own resampler, as `pbn` made the
/// research's working images), reflect-padded at the bottom and right to the network's stride,
/// the probability cropped back and rounded to the nearest of 256 levels. The model runs on the
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

        /// The model's resource name in the bundle.
        var resource: String {
            switch self {
            case .hed: "HED"
            }
        }

        /// The network's total stride: its input is padded to a multiple of it.
        var inputMultiple: Int {
            switch self {
            case .hed: 16
            }
        }

        /// What a byte of the photo is in the model's input: HED takes 0...255.
        var inputScale: Float {
            switch self {
            case .hed: 1
            }
        }

        /// The model's output feature: a probability map, 1 where there is a line.
        var output: String {
            switch self {
            case .hed: "edges"
            }
        }
    }

    /// Longest side the models accept (their input shapes' bound) and the default size of maps.
    static let maximumLongSide = 1152
    /// HED's stride: its input is padded to a multiple of it.
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
