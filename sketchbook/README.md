# The sketchbook's bench

How the faces-first rounds (issue #1) are made. The page itself is a private Artifact (its link
is on issue #1); the photos and renders stay in the session's scratch, never here.

Each round: a few test photos (Kodak suite, scikit-image's `data`), marked, taken to a 1024 px
long side (the scale the prototype is tuned at: its grout is a fixed 4 px), contoured by
paint-by-number's HED model, then mosaicked.

```
python3 sketchbook/marks.py photo.ppm [cat]            # face box and eyes, as BOXES / EYES
python3 sketchbook/prep.py sketchbook/round1-marks.txt DIR   # DIR/<name>.ppm -> DIR/<name>-1024.ppm, marks scaled
python3 tools/models/convert_hed.py --map DIR/<name>-1024.ppm DIR/<name>-1024-contours.pgm   # in paint-by-number
FINE=17 CUT_FINE=0.45 BOXES=... EYES=... python3 prototype/mosaic_faces.py \
  DIR/<name>-1024.ppm DIR/<name>-1024-contours.pgm DIR/<name> 30 18 0.72
```

`render.py <design.json> <photo> A|B|C <out.png> [boxes]` draws a design in one of the finishes
(its docstring says what each changes); the drawing changes, never the template.

`features.py <photo> face_landmarker.task <out.json>` traces a face's features with MediaPipe's
face landmarker (standing in for Vision's face landmarks; needs mediapipe, shapely and, on Linux,
libegl1); `mosaic_faces.py` takes the result as `FEATURES=` and sets them as pieces first. With
mediapipe installed, controlnet_aux breaks `convert_hed.py`: run it through `hed.py`.

`marks.py` stands in for the face detection the app runs (OpenCV's Haar cascades; needs
opencv-python-headless 4.x, since 5 dropped them); its misses are corrected by hand in the
round's marks file: `name|face box x0,y0,x1,y1|eyes cx,cy,r[,pupil];...` in the photo's own
pixels. `convert_hed.py --map` needs torch, torchvision (the same CPU build as torch) and
controlnet_aux 0.0.10.

| Round | Photos | What changed |
| --- | --- | --- |
| 1 | kodim04, kodim15, kodim17, astronaut, chelsea | Nothing: the prototype as the proposal left it, the baseline. |
| 2 | kodim04, chelsea | 3 finishes at 1024 px (`render.py` A, B, C; B and C draw `mosaic_faces.py` with `GROUT=2 TIGHT=1`), and C at the detail slider's ends (`prep.py` at 724 and 1774 px: about ½ and 3× the tiles). |
| 3 | kodim04, kodim15, astronaut, two Fayum portraits (the Met, public domain; scratch only) | Faces: the features set as pieces (`features.py` → `FEATURES`), tight set, finish C; each beside its face without them. |
| 4 | the young woman in red, kodim04, chelsea | The Swift engine beside the Python bench (`.build/release/mosaic`, same inputs). |
| 5 | kodim04, kodim15, astronaut, two Fayum portraits | The mouth: as in the photo, or Byzantine (`mosaic --mouth byzantine`), small and closed. |
| 6 | kodim04, 15, 17, 18, astronaut, chelsea; Cameron's Julia Jackson, Tennyson, Herschel, Mrs. Herbert Duckworth and Capel Cure's dog "Peter" (the Met, public domain) | A wider set: each before and after the round's fixes (irises from the eye's own pixels, a profile's hidden eye left out, finer tiles for a small face, `--face-cut` 0.6, face tiles' paint by colour). Faces the landmarker misses are found zoomed in (`features.py --window`); pets get a box only, as on the phone. |

`bundle.py` makes the app's bundled mosaics, and the faces each was laid with (`<id>-faces.json`,
which the phone's engine lays a library picture with when no bundled mosaic stands for its recipe),
with the app's own engine (`swift build -c release`
first; it runs `.build/release/mosaic`), so each tile carries its build stage for the making-of.
The same inputs give the same files byte for byte.

The icons: Apse is the app's (Paul, October 28, issue #15). `icon_candidates.py OUT` draws it and
the other five candidates, each light, dark and tinted at 1024 px, laid in rows that follow their
forms (opencv-python-headless 4.x, numpy); `icon_candidates.py OUT --catalog
App/Ravenna/Resources/Assets.xcassets [name]` makes one the app's icon (Pillow; default apse). Same
files every run. `icon.py` (v0's halo) and `icons.py` (v0's Stars, Tessera and Rows) drew the icons
before it.
