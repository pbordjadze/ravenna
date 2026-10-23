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
- `sketchbook/`: how the faces-first rounds are made.
- `CLAUDE.md`: the rules for the agents working here.

The name comes from the city whose sixth-century mosaics are the touchstone. Medea, the Moon and
the Astrologer proposed it (paint-by-number's `factory/pieces/byzantine-name`); Paul chose it.
