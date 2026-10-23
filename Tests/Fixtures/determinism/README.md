# Determinism fixture

The engine's inputs for one portrait, read by `Tests/MosaicCoreTests/DeterminismTests.swift`.

- **The work:** *Young Woman in Red*, Roman Egypt, 90–120 CE, encaustic on limewood with gold leaf.
  The Metropolitan Museum of Art, Rogers Fund, 1909 (09.181.6), public domain (Open Access):
  https://www.metmuseum.org/art/collection/search/547860
- `photo.ppm`: the Met's primary image (DP-41964-001.jpg), resized to 724 px on the long side
  (403 × 724, Pillow's Lanczos), the size of the detail option's Fewer pieces.
- `contours.pgm`: its contour map at the same size (`sketchbook/hed.py` through paint-by-number's
  `tools/models/convert_hed.py --map`).
- `features.json`: its face's features (`sketchbook/features.py` with MediaPipe's
  face_landmarker.task).

The inputs are fixed files, so only the Swift code decides the hashes. Remaking them with the
sketchbook's tools changes them, and the test's hashes would have to change with them.
