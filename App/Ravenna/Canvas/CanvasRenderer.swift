import Dispatch
import Foundation
import Metal
import os
import PaintCore
import QuartzCore

/// Draws one canvas into a `CAMetalLayer`. Owns the per-region paint state and keeps up to
/// three frames in flight: every frame slot has its own state buffer, and a region change is
/// queued for each slot and copied in just before that slot is encoded again, so the CPU
/// never writes memory the GPU may still be reading.
final class CanvasRenderer {
    static let framesInFlight = 3

    let context: RenderContext
    let scene: CanvasScene
    private(set) var states: [RegionState]

    private let stateBuffers: [any MTLBuffer]
    private var pending: [[Int32]]
    private var pendingAll: [Bool]
    private var slot = 0
    private let inFlight = DispatchSemaphore(value: CanvasRenderer.framesInFlight)
    private var multisample: (any MTLTexture)?
    private var outlines: (any MTLTexture)?
    private var targetSize = SIMD2<Int>(0, 0)

    init?(scene: CanvasScene, context: RenderContext, states: [RegionState]) {
        precondition(states.count == scene.regionCount)
        let length = max(16, MemoryLayout<RegionState>.stride * states.count)
        var buffers: [any MTLBuffer] = []
        for _ in 0..<CanvasRenderer.framesInFlight {
            guard let b = context.device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
            buffers.append(b)
        }
        self.context = context
        self.scene = scene
        self.states = states
        stateBuffers = buffers
        pending = Array(repeating: [], count: CanvasRenderer.framesInFlight)
        pendingAll = Array(repeating: true, count: CanvasRenderer.framesInFlight)
        for k in pending.indices { pending[k].reserveCapacity(64) }
    }

    func update(_ region: Int, _ state: RegionState) {
        states[region] = state
        for k in pending.indices where !pendingAll[k] {
            if pending[k].count >= max(64, states.count / 4) {
                pendingAll[k] = true
                pending[k].removeAll(keepingCapacity: true)
            } else {
                pending[k].append(Int32(region))
            }
        }
    }

    /// Renders a frame into the layer's next drawable. Returns false when no frame could be
    /// produced (GPU still busy with earlier frames, or no drawable); try again next tick.
    /// `onPresented` is called, on a thread of Metal's, once the frame is on screen: a tenth of a
    /// second after the GPU finished it, which is a few refreshes after it was queued to be shown.
    @discardableResult
    func draw(
        in layer: CAMetalLayer, uniforms: CanvasUniforms, content: RenderContext.Content,
        onPresented: (@Sendable () -> Void)? = nil
    ) -> Bool {
        let size = SIMD2(Int(layer.drawableSize.width), Int(layer.drawableSize.height))
        guard size.x > 0, size.y > 0 else { return false }
        guard inFlight.wait(timeout: .now() + .milliseconds(2)) == .success else { return false }
        if size != targetSize || outlines == nil {
            multisample = context.makeMultisampleTarget(width: size.x, height: size.y)
            outlines = context.makeOutlineTarget(width: size.x, height: size.y)
            targetSize = size
        }
        guard let outlines else {
            inFlight.signal()
            return false
        }
        // A drawable is normally at hand; waiting for one holds the main thread (up to a second a
        // frame), so a long wait is logged: painting screens on CI's simulator have stopped
        // answering for seconds after opening.
        let asked = ContinuousClock.now
        let next = layer.nextDrawable()
        let waited = ContinuousClock.now - asked
        if waited > .milliseconds(250) {
            Log.canvas.notice("Waited \(String(describing: waited), privacy: .public) for a drawable")
        }
        guard let drawable = next, let commands = context.queue.makeCommandBuffer() else {
            inFlight.signal()
            return false
        }
        slot = (slot + 1) % Self.framesInFlight
        flush(slot)
        context.encode(
            commands, scene: scene, states: stateBuffers[slot], uniforms: uniforms,
            targets: RenderContext.Targets(color: drawable.texture, multisample: multisample, outlines: outlines),
            content: content)
        commands.addCompletedHandler(Self.signal(inFlight, then: onPresented))
        commands.present(drawable)
        commands.commit()
        return true
    }

    private func flush(_ k: Int) {
        guard !states.isEmpty else { return }
        let target = stateBuffers[k].contents().bindMemory(to: RegionState.self, capacity: states.count)
        if pendingAll[k] {
            states.withUnsafeBufferPointer { target.update(from: $0.baseAddress!, count: $0.count) }
            pendingAll[k] = false
        } else {
            for r in pending[k] { target[Int(r)] = states[Int(r)] }
        }
        pending[k].removeAll(keepingCapacity: true)
    }

    /// Built outside the main actor: Metal calls it on its own completion thread. A frame whose
    /// presentation is awaited (`onPresented`) is announced here, a tenth of a second after the
    /// GPU finished it: the drawable is shown at the next refresh after that.
    nonisolated private static func signal(
        _ semaphore: DispatchSemaphore, then onPresented: (@Sendable () -> Void)?
    ) -> MTLCommandBufferHandler {
        { _ in
            semaphore.signal()
            if let onPresented { DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { onPresented() } }
        }
    }
}
