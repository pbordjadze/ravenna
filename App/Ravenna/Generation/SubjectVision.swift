import CoreGraphics
import Foundation
import os
import Vision

/// What Vision finds of a photo's subjects, from one pass of requests: its faces, with their
/// landmarks, and its animals, which Ravenna's engine lays as faces (`MosaicFaces`). Callers asking
/// for the same photo (the same `CGImage` instance) while its pass runs share that pass. Nothing is
/// kept once it ends.
///
/// Ravenna's seam: Paint by Moonlight's pass also made the saliency map and the foreground mask for
/// its generator's importance and its line art's subjects, which the engine doesn't read.
nonisolated enum SubjectVision {
    struct Findings: Sendable {
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
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let faces = VNDetectFaceLandmarksRequest()
        let animals = VNRecognizeAnimalsRequest()
        let requests: [VNRequest] = [faces, animals]
        for request in requests {
            do {
                try handler.perform([request])
            } catch {
                let name = String(describing: type(of: request))
                Log.create.error("\(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        return Findings(faces: Faces(observations: faces.results ?? []), animals: (animals.results ?? []).map(\.boundingBox))
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
