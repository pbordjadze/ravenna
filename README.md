# Ravenna

A photo laid as a Byzantine mosaic, tile by tile, and then set by hand. Ravenna is the working
name of Paint by Moonlight's secret workshop: for now a separate app on SideStore, one day an era
hidden inside Paint by Moonlight, reached by turning a hidden clock all the way back.

Not announced. Built on Paint by Moonlight's engine
([pbordjadze/paint-by-number](https://github.com/pbordjadze/paint-by-number)), pinned.

- `docs/brief.md`: what this is, Paul's words and decisions, and the plan.
- `prototype/`: the Python prototype the engine is ported from.
- `Sources/MosaicCore`: a mosaic as a PaintCore template (`MosaicCore.template(of:)`: a numbered
  area per tile, the grout one more), on PaintCore at a pinned commit, tested on Linux:
  `tools/paintcore.sh && swift test` (the script checks out only that commit of paint-by-number;
  `tools/swift.sh` runs SwiftPM in the swift:6.2 image where no toolchain is installed).
- `Sources/MosaicEngine`: the mosaic generator in Swift (photo, contours and faces in; a `Mosaic`
  out), ported from `prototype/mosaic_faces.py`, with no dependencies. `swift run mosaic` runs it
  on a PPM and its contour map, for the bench.
- `sketchbook/`: how the faces-first rounds are made, and `bundle.py`, which makes the app's mosaics
  with the Swift engine.
- `App/`: the app (iOS 26, SwiftUI, bundle `com.pbordjadze.ravenna`). v1, in the making (issue
  #13): Paint by Moonlight's app with Ravenna's engine, making-of and look (`App/CLAUDE.md`); v0's
  code waits in `App/v0/` until v1 replaces it. Builds on macOS only when asked (`[compile]`) or on
  `main` when it changed, as an unsigned IPA for SideStore: add
  `https://raw.githubusercontent.com/pbordjadze/ravenna/sidestore/source.json` in SideStore.
- `CLAUDE.md`: the rules for the agents working here.

The name comes from the city whose sixth-century mosaics are the touchstone. Medea, the Moon and
the Astrologer proposed it (paint-by-number's `factory/pieces/byzantine-name`); Paul chose it.
