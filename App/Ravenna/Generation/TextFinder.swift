import CoreGraphics
import Foundation
import os
import Vision

/// The lines of text in a photo (a note, a card, a sign), whose ink a coloring book traces from
/// the photo and draws legibly (`LineArtInput.writing`, PaintCore's
/// `Writing`): Vision's text recognition at the accurate level, which reads handwriting too.
/// Reading isn't the point, finding is: a line counts when Vision reads it with some confidence
/// (`minimumConfidence`) as at least `minimumCharacters` letters or digits, so a stray mark it
/// takes for a letter doesn't.
///
/// Polygons are each line's quadrilateral, normalized to the photo (0...1, origin top-left),
/// quantized to 1/4096 of the photo and ordered top to bottom, then left to right, so small
/// differences in Vision's output between runs don't reorder or jitter them.
///
/// The simulator finds none (`lines(in:)`): it runs Vision's networks on the CPU, where reading
/// took CI 8 to 42 s a 560-pixel picture and over 90 s a photo, and read nothing. `read(_:)`
/// asks Vision anywhere (`TextFinderTests`).
nonisolated enum TextFinder {
    /// Lines Vision reads with less confidence than this are skipped: handwriting reads at 0.3
    /// to 0.5 where print reads near 1.
    static let minimumConfidence: Float = 0.3
    /// Lines with fewer letters or digits than this are a mark taken for a letter.
    static let minimumCharacters = 2
    /// The lowest text looked for, per height of the photo: the writing stage keeps text from 10
    /// canvas pixels (`Writing.minimumHeight`), about this much of a canvas's short side. Vision's
    /// default, 1/32, misses a note photographed among other things: the words of one beside
    /// stuffed animals stood 1/51 to 1/22 of the photo's height.
    static let minimumTextHeight: Float = 1 / 128
    static let quantum = 4096.0

    /// The lines of text in `image` (upright pixels). Empty when there are none, on the
    /// simulator, or when Vision can't run.
    static func lines(in image: CGImage) -> [[SIMD2<Float>]] {
        #if targetEnvironment(simulator)
        return []
        #else
        return read(image)
        #endif
    }

    /// The lines Vision reads in `image`, the simulator's Vision included.
    static func read(_ image: CGImage) -> [[SIMD2<Float>]] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = minimumTextHeight
        let clock = ContinuousClock.now
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            Log.create.error("Finding text failed: \(String(describing: error), privacy: .public)")
            return []
        }
        let observations = request.results ?? []
        let found = observations.count
        Log.create.notice(
            "Found \(found, privacy: .public) lines of text in \(String(describing: ContinuousClock.now - clock), privacy: .public)")
        var lines: [[SIMD2<Double>]] = []
        for observation in observations {
            guard let best = observation.topCandidates(1).first, best.confidence >= minimumConfidence,
                  best.string.filter({ $0.isLetter || $0.isNumber }).count >= minimumCharacters
            else { continue }
            // Vision's normalized points have their origin at the bottom left.
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
            lines.append(corners.map { SIMD2(Double($0.x), 1 - Double($0.y)) })
        }
        return ordered(lines)
    }

    /// `lines` quantized and sorted by their top, then their left edge.
    static func ordered(_ lines: [[SIMD2<Double>]]) -> [[SIMD2<Float>]] {
        let quantized = lines.map { line in
            line.map { SIMD2(Float(($0.x * quantum).rounded() / quantum), Float(($0.y * quantum).rounded() / quantum)) }
        }
        return quantized.sorted { a, b in
            let ay = a.map(\.y).min() ?? 0, by = b.map(\.y).min() ?? 0
            if ay != by { return ay < by }
            return (a.map(\.x).min() ?? 0) < (b.map(\.x).min() ?? 0)
        }
    }
}
