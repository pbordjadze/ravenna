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

`marks.py` stands in for the face detection the app runs (OpenCV's Haar cascades; needs
opencv-python-headless 4.x, since 5 dropped them); its misses are corrected by hand in the
round's marks file: `name|face box x0,y0,x1,y1|eyes cx,cy,r[,pupil];...` in the photo's own
pixels. `convert_hed.py --map` needs torch, torchvision (the same CPU build as torch) and
controlnet_aux 0.0.10.

| Round | Photos | What changed |
| --- | --- | --- |
| 1 | kodim04, kodim15, kodim17, astronaut, chelsea | Nothing: the prototype as the proposal left it, the baseline. |
