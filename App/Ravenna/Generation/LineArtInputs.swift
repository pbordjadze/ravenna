import CoreGraphics
import Foundation
import os
import PaintCore

/// What a coloring book draws from, computed once per photo: the line
/// drawing over the HED edge map, the HED map alone for the outlines (`EdgeDetector.maps`),
/// the eyes (`EyeFinder`), the subjects' silhouettes (`ObjectFinder`) and the lines of text
/// (`TextFinder`).
///
/// Inputs are cached by the photo's identity (the same `CGImage` instance) for the last
/// `cacheCapacity` photos, so the create flow's drafts, candidates and full resolution, and a
/// preview regenerating as settings move, run the model once per photo. Concurrent requests
/// for one photo share a single computation, which is cancelled once every task waiting for
/// it is (a cancelled caller still waiting alongside others gets the result when it comes).
nonisolated enum LineArtInputs {
    /// Photos whose inputs are kept: the photo being made into a painting and a preview's.
    static let cacheCapacity = 2

    /// Everything the models and Vision found in a photo, from which the input for any
    /// detector choice follows.
    struct Maps: Sendable, Equatable {
        var drawing: EdgeMap
        var contours: EdgeMap
        var eyes: [[SIMD2<Float>]]
        var objects: [[SIMD2<Float>]]
        var writing: [[SIMD2<Float>]]

        /// The input `detector` generates from, by the rule `pbn` follows too
        /// (`LineArtInput(drawing:contours:detector:)`).
        func input(for detector: LineArtSettings.Detector) -> LineArtInput {
            LineArtInput(
                drawing: drawing, contours: contours, detector: detector, eyes: eyes, objects: objects, writing: writing)
        }
    }

    /// The inputs `settings` need for `image`: nil for classic line art, which draws from the
    /// photo alone.
    static func make(for image: CGImage, settings: LineArtSettings) async throws -> LineArtInput? {
        guard settings.style.usesEdgeMap else { return nil }
        return try await cache.maps(for: image).input(for: settings.detector)
    }

    /// The inputs for a template about to be generated: `make` (or `compute` when not
    /// `cached`, for a one-off template), except that a failure other than cancellation is
    /// logged and gives nil, so a coloring book comes out classic, as the
    /// generator documents, rather than not at all. Nil for classic settings.
    static func forGeneration(of image: CGImage?, settings: LineArtSettings, cached: Bool) async throws -> LineArtInput? {
        guard settings.style.usesEdgeMap else { return nil }
        guard let image else {
            Log.create.error("Line art without a photo image: generating classic lines")
            return nil
        }
        do {
            if cached { return try await make(for: image, settings: settings) }
            return try await compute(for: image, detector: settings.detector)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.create.error("Line art inputs failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The inputs of `image` for `detector`, computed now, outside `make`'s per-photo cache.
    static func compute(for image: CGImage, detector: LineArtSettings.Detector = .drawingAndContours) async throws -> LineArtInput {
        try await maps(for: image).input(for: detector)
    }

    /// Everything found in `image`, computed now, outside `make`'s per-photo cache: both maps
    /// (the models one after the other) and, meanwhile, the eyes, the subjects and the text. Demo and test
    /// launches read and keep them on disk (`LineArtMapsCache`), so a CI run computes each
    /// picture once.
    @concurrent
    static func maps(for image: CGImage) async throws -> Maps {
        #if DEBUG
        if let cached = LineArtMapsCache.maps(for: image) { return cached }
        #endif
        async let eyes = findEyes(in: image)
        async let objects = findObjects(in: image)
        async let writing = findWriting(in: image)
        let maps = try EdgeDetector.maps(for: image)
        let found = Maps(
            drawing: maps.drawing, contours: maps.contours, eyes: await eyes, objects: await objects, writing: await writing)
        #if DEBUG
        LineArtMapsCache.store(found, for: image)
        #endif
        return found
    }

    @concurrent
    private static func findEyes(in image: CGImage) async -> [[SIMD2<Float>]] {
        await EyeFinder.eyes(in: image)
    }

    @concurrent
    private static func findObjects(in image: CGImage) async -> [[SIMD2<Float>]] {
        await ObjectFinder.objects(in: image)
    }

    @concurrent
    private static func findWriting(in image: CGImage) async -> [[SIMD2<Float>]] {
        TextFinder.lines(in: image)
    }

    private static let cache = InputCache()
}

/// The cache behind `LineArtInputs.make`: one computation task per photo (every map, so a
/// change of detector costs nothing), shared by the callers waiting for it.
private actor InputCache {
    private nonisolated struct Entry {
        let image: CGImage
        let task: Task<LineArtInputs.Maps, any Error>
        /// Callers waiting for `task`, and those of them whose own tasks were cancelled.
        var waiting: Set<UUID> = []
        var abandoned: Set<UUID> = []
    }

    /// Least recently requested first.
    private var entries: [Entry] = []

    func maps(for image: CGImage) async throws -> LineArtInputs.Maps {
        let caller = UUID()
        let task = join(image, as: caller)
        defer { leave(task, as: caller) }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.abandon(task, as: caller) }
            }
        } catch {
            // A failed or cancelled computation isn't kept: the next request starts afresh.
            entries.removeAll { $0.task == task }
            throw error
        }
    }

    /// The running or finished computation for `image`, or a new one when there is none (or
    /// only a cancelled one).
    private func join(_ image: CGImage, as caller: UUID) -> Task<LineArtInputs.Maps, any Error> {
        var entry: Entry
        if let index = entries.firstIndex(where: { $0.image === image }), !entries[index].task.isCancelled {
            entry = entries.remove(at: index)
        } else {
            entries.removeAll { $0.image === image }
            entry = Entry(image: image, task: Task { try await LineArtInputs.maps(for: image) })
        }
        entry.waiting.insert(caller)
        entries.append(entry)
        trim()
        return entry.task
    }

    private func leave(_ task: Task<LineArtInputs.Maps, any Error>, as caller: UUID) {
        guard let index = entries.firstIndex(where: { $0.task == task }) else { return }
        entries[index].waiting.remove(caller)
        entries[index].abandoned.remove(caller)
    }

    /// A caller's task was cancelled: the computation stops when nobody else waits for it.
    private func abandon(_ task: Task<LineArtInputs.Maps, any Error>, as caller: UUID) {
        guard let index = entries.firstIndex(where: { $0.task == task }), entries[index].waiting.contains(caller) else { return }
        entries[index].abandoned.insert(caller)
        if entries[index].abandoned == entries[index].waiting { task.cancel() }
    }

    /// Drops the least recently requested photos beyond the capacity that nobody waits for,
    /// cancelling their computations if they are still running.
    private func trim() {
        var index = 0
        while entries.count > LineArtInputs.cacheCapacity, index < entries.count - 1 {
            if entries[index].waiting.isEmpty {
                entries.remove(at: index).task.cancel()
            } else {
                index += 1
            }
        }
    }
}
