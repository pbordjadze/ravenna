import Foundation
import MosaicKit

/// How Ravenna sets tiles, fixed (Paul, October 28, issue #14: Settings is Paint by Moonlight's):
/// tiles in Glass and Stone, one finger moving the wall as Paint by Moonlight's does (a tap sets a
/// tile, a press then a drag lays a row), a row a quick run of the tune, and nothing round a
/// shared mosaic. v0's and earlier v1 builds' choices are retired (`Preferences.retiredKeys`).
nonisolated enum TileOptions {
    /// How set tiles look (MosaicKit's `Finish`): glass that glints and matte stone, with a lit edge.
    static let finish = Finish.material
}
