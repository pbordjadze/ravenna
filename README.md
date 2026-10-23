# Ravenna

A photo laid as a Byzantine mosaic, tile by tile, and then set by hand. Ravenna is the working
name of Paint by Moonlight's secret workshop: for now a separate app on SideStore, one day an era
hidden inside Paint by Moonlight, reached by turning a hidden clock all the way back.

Not announced. Built on Paint by Moonlight's engine
([pbordjadze/paint-by-number](https://github.com/pbordjadze/paint-by-number)), pinned.

- `docs/brief.md`: what this is, Paul's words and decisions, and the plan.
- `prototype/`: the Python prototype the engine is ported from.
- `Sources/MosaicCore`: the engine (Swift, on PaintCore pinned by revision), tested on Linux:
  `tools/paintcore-mirror.sh && swift test` (the script fetches only the pinned PaintCore commit;
  `tools/swift.sh` runs SwiftPM in the swift:6.2 image where no toolchain is installed).
- `Sources/MosaicEngine`: the mosaic generator in Swift (photo, contours and faces in; a `Mosaic`
  out), ported from `prototype/mosaic_faces.py`, with no dependencies so the app compiles it
  directly. `swift run mosaic` runs it on a PPM and its contour map, for the bench.
- `sketchbook/`: how the faces-first rounds are made, and `bundle.py`, which makes the app's mosaics.
- `App/`: the app (iOS 26, SwiftUI, bundle `com.pbordjadze.ravenna`), v0: five public-domain
  ancient works from the Met, laid as mosaics on the bench, set tile by tile. It compiles
  `Sources/MosaicKit` directly. Builds on macOS only when asked (`[compile]`) or on `main` when it
  changed, as an unsigned IPA for SideStore: add
  `https://raw.githubusercontent.com/pbordjadze/ravenna/sidestore/source.json` in SideStore.
- `CLAUDE.md`: the rules for the agents working here.

The name comes from the city whose sixth-century mosaics are the touchstone. Medea, the Moon and
the Astrologer proposed it (paint-by-number's `factory/pieces/byzantine-name`); Paul chose it.
