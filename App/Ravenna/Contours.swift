import CoreGraphics
import CoreML
import Foundation

/// A photo's contour map, from the bundled HED model (`Resources/Models/HED.mlpackage`, ControlNet's
/// Apache-2.0 retraining of Xie & Tu's holistically-nested edge detector, copied from Paint by
/// Moonlight with its conversion; ACKNOWLEDGEMENTS.md). Adapted from Paint by Moonlight's
/// `EdgeDetector`: the photo in sRGB bytes, reflect-padded at the bottom and right to the network's
/// stride of 16, run on the CPU in float32 (the same map on every device), the probability cropped
/// back and rounded to the nearest of 256 levels.
nonisolated enum Contours {
    enum ContoursError: Error { case modelMissing, unexpectedOutput }

    /// The longest side the model accepts.
    static let maximumLongSide = 1152
    static let stride = 16

    /// The contour map of an sRGB RGBA8 image (`width` × `height`, 4 bytes a pixel), 0...1, at the
    /// image's size (which must be at most `maximumLongSide`). Seconds of CPU: call it off the main actor.
    static func map(rgba: [UInt8], width: Int, height: Int) throws -> [Float] {
        precondition(max(width, height) <= maximumLongSide)
        try Task.checkCancellation()
        guard let url = Bundle.main.url(forResource: "HED", withExtension: "mlmodelc") else { throw ContoursError.modelMissing }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let input = try padded(rgba, width: width, height: height)
        try Task.checkCancellation()
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: input)]))
        guard let values = output.featureValue(for: "edges")?.multiArrayValue, values.dataType == .float32 else {
            throw ContoursError.unexpectedOutput
        }
        let shape = values.shape.map(\.intValue), strides = values.strides.map(\.intValue)
        guard shape.count == 4, shape[2] >= height, shape[3] >= width else { throw ContoursError.unexpectedOutput }
        var map = [Float](repeating: 0, count: width * height)
        values.withUnsafeBufferPointer(ofType: Float.self) { source in
            for y in 0..<height {
                for x in 0..<width {
                    let p = source[y * strides[2] + x * strides[3]]
                    map[y * width + x] = p.isFinite ? (min(max(p, 0), 1) * 255).rounded() / 255 : 0
                }
            }
        }
        return map
    }

    /// Mirrored at the end without repeating the last pixel (NumPy's "reflect").
    static func reflect(_ i: Int, _ n: Int) -> Int {
        guard i >= n else { return i }
        guard n > 1 else { return 0 }
        let period = 2 * (n - 1), m = i % period
        return m < n ? m : period - m
    }

    /// [1, 3, H, W] float32, RGB in 0...255, padded to multiples of the stride.
    private static func padded(_ rgba: [UInt8], width w: Int, height h: Int) throws -> MLMultiArray {
        let pw = (w + stride - 1) / stride * stride, ph = (h + stride - 1) / stride * stride
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: ph), NSNumber(value: pw)], dataType: .float32)
        let columns = (0..<pw).map { reflect($0, w) }
        rgba.withUnsafeBufferPointer { source in
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { target, strides in
                let channel = strides[1], row = strides[2], column = strides[3]
                for y in 0..<ph {
                    let sourceRow = reflect(y, h) * w
                    for x in 0..<pw {
                        let s = (sourceRow + columns[x]) * 4, t = y * row + x * column
                        target[t] = Float(source[s])
                        target[t + channel] = Float(source[s + 1])
                        target[t + 2 * channel] = Float(source[s + 2])
                    }
                }
            }
        }
        return array
    }
}
