#if DEBUG
import Foundation
import Metal
import os

/// What the canvas's frames cost, for the demo that measures a mosaic at the Pieces slider's top
/// (`paint-mosaic-measure`): the main thread's time in each tick that drew (uniforms and encoding),
/// the GPU's time on each frame, the time between frames drawn while something moves, and the memory
/// Metal holds for the app (the canvas's buffers and targets) beside what the system still lets it
/// have. Debug builds only.
nonisolated final class FrameMeter: @unchecked Sendable {
    static let shared = FrameMeter()

    private let lock = NSLock()
    private var cpu: [Double] = [], gpu: [Double] = [], gaps: [Double] = []
    private var lastFrame: CFTimeInterval?
    private var isOn = false

    /// Starts a fresh measurement.
    func start() {
        lock.withLock {
            cpu = []; gpu = []; gaps = []; lastFrame = nil; isOn = true
        }
    }

    /// A tick drew a frame, its work taking `seconds` on the main thread, at media time `at`.
    func drew(cpu seconds: Double, at: CFTimeInterval) {
        lock.withLock {
            guard isOn else { return }
            cpu.append(seconds)
            if let last = lastFrame { gaps.append(at - last) }
            lastFrame = at
        }
    }

    /// The GPU finished a frame.
    func finished(_ commands: any MTLCommandBuffer) {
        let seconds = commands.gpuEndTime - commands.gpuStartTime
        lock.withLock {
            guard isOn, seconds > 0 else { return }
            gpu.append(seconds)
        }
    }

    /// Megabytes Metal has allocated for the app, and the memory the system still lets the app
    /// have (0 where it sets no limit, as on the simulator).
    static func memory() -> String {
        let gpu = Double(RenderContext.shared?.device.currentAllocatedSize ?? 0) / 1_048_576
        let available = Double(os_proc_available_memory()) / 1_048_576
        return String(format: "Metal allocations %.1f MB, available to the app %.0f MB", gpu, available)
    }

    /// Stops and reports: frames, the median and 95th percentile of each time in milliseconds, and
    /// the footprint.
    func report(_ title: String) -> String {
        let (cpu, gpu, gaps) = lock.withLock {
            isOn = false
            return (self.cpu, self.gpu, self.gaps)
        }
        func line(_ name: String, _ values: [Double]) -> String {
            guard !values.isEmpty else { return "\(name): none" }
            let sorted = values.sorted()
            func ms(_ q: Double) -> String { String(format: "%.2f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))] * 1000) }
            return "\(name): median \(ms(0.5)) ms, p95 \(ms(0.95)) ms, max \(ms(1)) ms (\(values.count))"
        }
        let longGaps = gaps.filter { $0 > 1.5 / 60 }.count
        return [
            title,
            line("main thread per frame", cpu),
            line("GPU per frame", gpu),
            line("between frames", gaps),
            "gaps over 1.5 refreshes at 60 Hz: \(longGaps) of \(gaps.count)",
            "memory: " + Self.memory(),
        ].joined(separator: "\n")
    }
}
#endif
