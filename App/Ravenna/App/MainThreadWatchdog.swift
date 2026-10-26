#if DEBUG
import Darwin
import Dispatch
import Foundation
import os
import Synchronization

/// Demo and UI-test launches: when the main thread stops answering for `threshold`, logs its
/// stack, again every `interval` while it stays stuck, and how long it was gone once it answers
/// (`Log.demo`, which CI keeps in each job's `test-app.log`). Painting screens on CI's
/// simulator have stopped answering for half a minute after opening, failing UI queries with
/// nothing in the app's own logs to say where.
///
/// The stack is read with the main thread suspended (its registers, then the frame-pointer chain
/// arm64 code always keeps), so nothing runs on the stuck thread and nothing allocates while it
/// may hold a lock; frames are named (`dladdr`, Swift names mangled) once it runs again.
nonisolated enum MainThreadWatchdog {
    static let threshold: Duration = .seconds(2)
    static let interval: Duration = .seconds(5)
    private static let maximumFrames = 128
    /// Bumped by the main queue each time it answers a ping.
    private static let answers = Atomic<Int>(0)

    /// Call on the main thread.
    static func start() {
        #if arch(arm64)
        dispatchPrecondition(condition: .onQueue(.main))
        let main = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(main))
        let stack = (top - UInt(pthread_get_stacksize_np(main)))...top
        let thread = pthread_mach_thread_np(main)
        let watcher = Thread { MainThreadWatchdog.watch(thread, stack: stack) }
        watcher.name = "MainThreadWatchdog"
        watcher.qualityOfService = .userInteractive
        watcher.start()
        #endif
    }

    #if arch(arm64)
    private static func watch(_ thread: thread_act_t, stack: ClosedRange<UInt>) {
        let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: maximumFrames)
        let clock = ContinuousClock()
        var seen = answers.load(ordering: .relaxed)
        var answered = clock.now
        var pinged = false
        var stall = 0
        var nextSample: ContinuousClock.Instant?
        var previous: [UInt] = []
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            let now = clock.now
            let count = answers.load(ordering: .relaxed)
            if count != seen {
                seen = count
                pinged = false
                if nextSample != nil {
                    Log.demo.error("Main thread answered after \(String(describing: now - answered), privacy: .public) (stall \(stall, privacy: .public))")
                    nextSample = nil
                    previous = []
                }
                answered = now
            }
            if !pinged {
                pinged = true
                DispatchQueue.main.async { _ = MainThreadWatchdog.answers.add(1, ordering: .relaxed) }
            }
            let gone = now - answered
            guard gone >= threshold, now >= nextSample ?? now else { continue }
            if nextSample == nil { stall += 1 }
            nextSample = now + interval
            let depth = sample(thread, stack: stack, into: frames)
            let addresses = Array(frames.prefix(depth))
            defer { previous = addresses }
            guard addresses != previous else {
                Log.demo.error("Main thread stuck for \(String(describing: gone), privacy: .public) (stall \(stall, privacy: .public)), at the same \(depth, privacy: .public) frames")
                continue
            }
            Log.demo.error("Main thread stuck for \(String(describing: gone), privacy: .public) (stall \(stall, privacy: .public)), \(depth, privacy: .public) frames:")
            for part in parts(addresses) {
                Log.demo.error("  stall \(stall, privacy: .public) \(part, privacy: .public)")
            }
        }
    }

    /// The frames named, a few to a message: a message per frame outpaced the log, which
    /// dropped most of them.
    private static func parts(_ addresses: [UInt]) -> [String] {
        var parts: [String] = [], part = ""
        for (index, address) in addresses.enumerated() {
            let frame = "#\(index) " + describe(address).prefix(240)
            if !part.isEmpty, part.utf8.count + frame.utf8.count > 800 {
                parts.append(part)
                part = ""
            }
            part += part.isEmpty ? frame : " | " + frame
        }
        if !part.isEmpty { parts.append(part) }
        return parts
    }

    /// The suspended thread's pc, lr and the return addresses up its frame records, innermost
    /// first; only addresses inside its stack are read.
    private static func sample(_ thread: thread_act_t, stack: ClosedRange<UInt>, into frames: UnsafeMutableBufferPointer<UInt>) -> Int {
        guard thread_suspend(thread) == KERN_SUCCESS else { return 0 }
        defer { thread_resume(thread) }
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, frames.count >= 2 else { return 0 }
        frames[0] = UInt(state.__pc)
        frames[1] = UInt(state.__lr)
        var depth = 2
        var record = UInt(state.__fp)
        // A frame record is the caller's record address, then the return address.
        while depth < frames.count, record % 8 == 0, stack.contains(record), stack.contains(record + 15) {
            let words = UnsafePointer<UInt>(bitPattern: record)!
            let caller = words[0], returnAddress = words[1]
            guard returnAddress != 0 else { break }
            frames[depth] = returnAddress
            depth += 1
            guard caller > record else { break }
            record = caller
        }
        return depth
    }

    /// "image symbol + offset" for a code address.
    private static func describe(_ address: UInt) -> String {
        var info = Dl_info()
        let hex = "0x" + String(address, radix: 16)
        guard address > 1, dladdr(UnsafeRawPointer(bitPattern: address - 1), &info) != 0 else { return hex }
        let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
        guard let name = info.dli_sname, let start = info.dli_saddr else { return "\(image) \(hex)" }
        return "\(image) \(String(cString: name)) + \(address - UInt(bitPattern: start))"
    }
    #endif
}
#endif
