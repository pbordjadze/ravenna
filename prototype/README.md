# The prototype

Python scripts from the session that proposed the mosaic (October 22–23, 2026). They are the
reference the Swift engine is ported from, and the sketchbook's bench until it exists.

| Script | What it does |
| --- | --- |
| `mosaic_look.py` | Any photo as a mosaic: strands from the contour map, rows that echo them, the photo's color edges and the frame, colors gathered into a few smalti. The parrots, lighthouse and hibiscus in the proposal. |
| `mosaic_faces.py` | The same with the face habits: finer tiles inside face boxes, eyes set as round pieces (a slit pupil for a cat), iris mixed as it looks. The cat and the girl in the proposal. |
| `byzantine_head.py` | The hand-designed Byzantine head (Paul liked this one): strands traced from the mosaic's own red and dark tiles (`head_guides.py` makes the candidate chains), one smalti per strand family, calm field shading, the photo's grout. |
| `gestures_look.py`, `gestures_head.py` | A design as Refine gestures from Blank (`pbn refine` in paint-by-number replays them): the proof that a mosaic is an ordinary, valid template. |

## Running them

They need Python 3.12 with `numpy`, `opencv-python-headless`, `scipy`, `scikit-image` and
`Pillow`, and a contour map of the photo, which paint-by-number makes:

```
python3 tools/models/convert_hed.py --map photo.ppm photo-contours.pgm   # in paint-by-number
python3 prototype/mosaic_look.py photo.ppm photo-contours.pgm out/photo 26 16 0.72
FINE=17 CUT_FINE=0.45 BOXES="200,60,780,580" EYES="341,230,58,11;645,275,47,9" \
  python3 prototype/mosaic_faces.py cat.ppm cat-contours.pgm out/cat 30 18 0.72
```

`convert_hed.py` downloads the HED weights from Hugging Face (lllyasviel/Annotators) on first
use. The six test photos and their committed contour maps are in paint-by-number's
`Tests/Corpus/` and `tools/baseline/lines/`. Each script writes `<prefix>.json` (the design:
tiles as polygons, paints, grout) and `<prefix>.png` (photo beside mosaic).

## What it taught

- Strands first, then rows that echo them (andamento), is what makes it read as a mosaic.
- Colors: one smalti per strand family; the field shaded in calm zones (a tile leans on its
  neighbours), never speckle; mortar from the photo's own grout. A tile's median color is the
  body of the stones under it; the eye reads glass and stone by their lit faces.
- Faces and pets fail untouched. Finer tiles in the face and eyes set as pieces make the cat
  read; the girl gets her eyes but not her nose and mouth.
- A mosaic of about 2,000 tiles is a valid paint-by-numbers template (2,084 areas, every number
  fitting), but built through Refine's edits it took 32 minutes: the engine should build the
  template directly.
