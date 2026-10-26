import CoreGraphics
import CoreVideo
import Foundation
import os
import PaintCore
import Vision

/// What Vision finds of a photo's subjects, from one pass of requests, for each of its readers:
/// `SubjectImportance` (the saliency heat map, the foreground mask, faces and animals),
/// `ObjectFinder` (the foreground mask, at its own size) and `EyeFinder` (the faces, whose
/// landmarks it asks for). The create flow and `ArtworkFactory` ask for a photo's importance and
/// its coloring-book inputs side by side, so callers asking for the same photo (the same `CGImage`
/// instance) while its pass runs share that pass. Nothing is kept once it ends: the photo itself
/// takes no place in memory beyond its callers' (`LineArtInputs` keeps the create flow's).
nonisolated enum SubjectVision {
    struct Findings: Sendable {
        /// The attention-based saliency heat map and the foreground mask (every instance), each
        /// box-sampled to `SubjectImportance.mapSize`; nil when Vision gave none.
        var saliency: Grid<Float>?
        var foreground: Grid<Float>?
        /// The foreground mask cut at half (`ObjectFinder.mask(from:)`); nil without a subject.
        var subjects: (inside: [Bool], width: Int, height: Int)?
        var faces = Faces()
        /// Normalized, with Vision's bottom-left origin.
        var animals: [CGRect] = []
    }

    /// Vision's face observations, which it never changes once returned.
    struct Faces: @unchecked Sendable {
        var observations: [VNFaceObservation] = []
    }

    /// The findings for `image`, from the pass running for it, or a new one.
    static func findings(in image: CGImage) async -> Findings {
        await running.findings(for: image)
    }

    /// One pass over `image`. Each request runs by itself, so one failing
    /// (common on simulators) doesn't sink the rest; every failure is logged.
    @concurrent
    static func find(in image: CGImage) async -> Findings {
        let size = SubjectImportance.mapSize(width: image.width, height: image.height)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let requests: [VNRequest] = [foreground, faces, animals, saliency]
        for request in requests {
            do {
                try handler.perform([request])
            } catch {
                let name = String(describing: type(of: request))
                Log.create.error("\(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }

        var found = Findings(
            faces: Faces(observations: faces.results ?? []), animals: (animals.results ?? []).map(\.boundingBox))
        if let heat = saliency.results?.first?.pixelBuffer {
            found.saliency = SubjectImportance.sample(heat, width: size.width, height: size.height)
        }
        if let observation = foreground.results?.first {
            do {
                let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                found.foreground = SubjectImportance.sample(mask, width: size.width, height: size.height)
                if !observation.allInstances.isEmpty { found.subjects = ObjectFinder.mask(from: mask) }
            } catch {
                Log.create.error("The subjects' mask failed: \(String(describing: error), privacy: .public)")
            }
        }
        return found
    }

    private static let running = RunningPasses()
}

/// The passes behind `SubjectVision.findings` while they run, each shared by its callers. A pass
/// isn't cancelled: Vision's requests can't stop midway.
private actor RunningPasses {
    private var entries: [(image: CGImage, task: Task<SubjectVision.Findings, Never>)] = []

    func findings(for image: CGImage) async -> SubjectVision.Findings {
        let task: Task<SubjectVision.Findings, Never>
        if let entry = entries.first(where: { $0.image === image }) {
            task = entry.task
        } else {
            task = Task { await SubjectVision.find(in: image) }
            entries.append((image, task))
        }
        let found = await task.value
        entries.removeAll { $0.task == task }
        return found
    }
}
