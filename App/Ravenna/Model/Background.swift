import Foundation

nonisolated enum Background {
    /// Runs synchronous work (file IO, decoding, rendering) on the concurrent executor,
    /// off the caller's actor.
    @concurrent
    static func run<T: Sendable>(_ work: @Sendable () throws -> T) async rethrows -> T {
        try work()
    }
}
