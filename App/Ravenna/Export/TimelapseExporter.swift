import AVFoundation
import CoreVideo
import Foundation

/// Encodes a replay of a painting session as a short video.
///
/// Renderer-agnostic: the caller draws each frame into the provided pixel buffer (Metal via a
/// CVMetalTextureCache, or CoreGraphics on the buffer's base address). `TimelapseSchedule`
/// decides how many strokes are visible in each frame.
nonisolated enum TimelapseExporter {
    struct Options: Sendable {
        var size: CGSize
        var framesPerSecond: Int = 60
        /// Length of the painting part of the video (excluding intro/outro holds).
        var paintingSeconds: Double = 9
        var introSeconds: Double = 0.6
        var outroSeconds: Double = 1.8
    }

    enum ExportError: Error { case writerSetup, appendFailed }

    /// Frames drawn ahead of the encoder: the GPU renders the next frames while the oldest
    /// one is appended, instead of stalling on every frame.
    static let framesInFlight = 3

    /// Blocks until the frame's pixels are in its buffer; throws if the GPU didn't draw them.
    typealias FrameCompletion = () throws -> Void

    /// Waits for the encoder to take another frame. A writer that has failed or been cancelled
    /// never becomes ready again, so that throws its error instead of waiting for good.
    static func waitUntilReady(
        isReady: () -> Bool, writerStatus: () -> AVAssetWriter.Status, writerError: () -> (any Error)?
    ) async throws {
        while !isReady() {
            switch writerStatus() {
            case .failed, .cancelled: throw writerError() ?? ExportError.appendFailed
            default: break
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Writes an HEVC movie to `url`. Runs on the caller's executor (frames are rendered by the
    /// caller's closure), so call it from a background task for large exports. Cancellation is
    /// checked every frame; it throws `CancellationError`, and like any failure leaves no file.
    /// - Parameters:
    ///   - renderFrame: starts drawing frame `index` showing the first `strokes` fills
    ///     of the log (plus `fraction` 0…1 of the next one, for smooth in-progress fills) into the
    ///     buffer and returns the wait for it. When it is called for frame `i`, every frame up to
    ///     `i − framesInFlight` has completed, so per-frame state can live in a ring of
    ///     `framesInFlight` slots indexed by `i % framesInFlight`.
    static func export(
        strokeCount: Int,
        options: Options,
        to url: URL,
        progress: (@Sendable (Double) -> Void)? = nil,
        renderFrame: (_ index: Int, _ strokes: Int, _ fraction: Float, _ buffer: CVPixelBuffer) throws -> FrameCompletion
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(options.size.width) & ~1, height = Int(options.size.height) & ~1
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: width * height * 8],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw ExportError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writerSetup }
        writer.startSession(atSourceTime: .zero)

        let schedule = TimelapseSchedule(strokeCount: strokeCount, options: options)
        let frameCount = schedule.frameCount
        let timescale = CMTimeScale(options.framesPerSecond)
        var pending: [(buffer: CVPixelBuffer, time: CMTime, done: FrameCompletion)] = []
        var appended = 0

        func appendOldest() async throws {
            let frame = pending.removeFirst()
            try frame.done()
            try await waitUntilReady(
                isReady: { input.isReadyForMoreMediaData }, writerStatus: { writer.status }, writerError: { writer.error })
            guard adaptor.append(frame.buffer, withPresentationTime: frame.time) else {
                throw writer.error ?? ExportError.appendFailed
            }
            appended += 1
            progress?(Double(appended) / Double(frameCount))
        }

        do {
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                // Leaves at most framesInFlight − 1 frames pending, so frame − framesInFlight
                // (the previous user of this frame's slot) has completed.
                while pending.count >= framesInFlight { try await appendOldest() }
                guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerSetup }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw ExportError.appendFailed }
                let (strokes, fraction) = schedule.state(atFrame: frame)
                let done = try renderFrame(frame, strokes, fraction, buffer)
                pending.append((buffer, CMTime(value: CMTimeValue(frame), timescale: timescale), done))
            }
            while !pending.isEmpty { try await appendOldest() }
            input.markAsFinished()
            await writer.finishWriting()
            if writer.status != .completed { throw writer.error ?? ExportError.appendFailed }
        } catch {
            // Let the GPU finish writing into the pending buffers before they are released.
            for frame in pending { try? frame.done() }
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

/// Maps video frames to replay progress: a short hold on the blank template, strokes
/// accelerating in and easing out (so early and final strokes are visible individually while
/// the long middle flies by), then a hold on the finished painting.
nonisolated struct TimelapseSchedule: Sendable {
    let strokeCount: Int
    let introFrames: Int
    let paintingFrames: Int
    let outroFrames: Int

    init(strokeCount: Int, options: TimelapseExporter.Options) {
        self.strokeCount = strokeCount
        let fps = Double(options.framesPerSecond)
        introFrames = Int(options.introSeconds * fps)
        // Very small paintings shouldn't be stretched into a long, slow video.
        let seconds = min(options.paintingSeconds, max(1.5, Double(strokeCount) * 0.12))
        paintingFrames = max(1, Int(seconds * fps))
        outroFrames = Int(options.outroSeconds * fps)
    }

    var frameCount: Int { introFrames + paintingFrames + outroFrames }

    /// Completed strokes and the fraction of the next stroke's fill at a frame.
    func state(atFrame frame: Int) -> (strokes: Int, fraction: Float) {
        if frame < introFrames { return (0, 0) }
        let f = frame - introFrames
        if f >= paintingFrames { return (strokeCount, 0) }
        let t = Double(f) / Double(paintingFrames)
        // Smoothstep easing of stroke index over time.
        let eased = t * t * (3 - 2 * t)
        let position = eased * Double(strokeCount)
        let whole = min(strokeCount, Int(position))
        return (whole, whole < strokeCount ? Float(position - Double(whole)) : 0)
    }
}
