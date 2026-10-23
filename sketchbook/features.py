"""features.py <photo> <model.task> <out.json> [preview.png] [--window left,top,side]: a face's
features as mosaic_faces.py's FEATURES, from MediaPipe's face landmarker (standing in for Vision's
face landmarks in the app). Writes, in the photo's pixels: "box" (the face, with a margin), "eyes"
([cx, cy, iris r, pupil r] each) and "lines", each {"kind", "pts"}: how a mosaicist sets a feature as
its own pieces:
  dark  a row in a dark smalti of the local hue: the upper lids, the line where the lips meet
  mid   a row in the feature's own shadow colour: brows, the shadow side of the nose, the nostrils
  tone  a row in the photo's colour, which the rows round it echo: lower lids, the lips' outline
  eye   an eye's opening: it clips the iris and pupil as the lids do, and its tiles are the white,
        in the lit part of the stones under them
  lips  the lips' outline: its tiles keep their own colour (never smoothed into their neighbours)
The model: face_landmarker.task (float16, v1) from storage.googleapis.com/mediapipe-models."""
import json, sys
import numpy as np, cv2
import mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions

C = vision.FaceLandmarksConnections
args = sys.argv[1:]
window = None
if "--window" in args:
    i = args.index("--window"); window = [float(v) for v in args[i + 1].split(",")]; del args[i:i + 2]
photo, model, out = args[:3]
rgb = cv2.cvtColor(cv2.imread(photo), cv2.COLOR_BGR2RGB)
H, W = rgb.shape[:2]
lm = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
    base_options=BaseOptions(model_asset_path=model), num_faces=1))
if window:
    # A small or painted face (an icon's) is found only zoomed in: the landmarker sees the window
    # (left, top as fractions of the width and height, its side as a fraction of the long side)
    # at 768 px, and its points are mapped back to the photo's pixels.
    x0, y0, s = round(window[0] * W), round(window[1] * H), round(window[2] * max(W, H))
    crop = np.ascontiguousarray(cv2.resize(rgb[y0:y0 + s, x0:x0 + s], (768, 768), interpolation=cv2.INTER_CUBIC))
    res = lm.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=crop))
    if not res.face_landmarks:
        sys.exit(f"{photo}: no face found in the window")
    sw, sh = rgb[y0:y0 + s, x0:x0 + s].shape[1], rgb[y0:y0 + s, x0:x0 + s].shape[0]
    P = np.array([[x0 + p.x * sw, y0 + p.y * sh] for p in res.face_landmarks[0]])
else:
    res = lm.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    if not res.face_landmarks:
        sys.exit(f"{photo}: no face found")
    P = np.array([[p.x * W, p.y * H] for p in res.face_landmarks[0]])

def chain(a, b, conns):
    """The path from landmark a to b along a connection set."""
    nb = {}
    for c in conns:
        nb.setdefault(c.start, []).append(c.end); nb.setdefault(c.end, []).append(c.start)
    prev = {a: None}; q = [a]
    while q:
        n = q.pop(0)
        if n == b: break
        for m in nb.get(n, []):
            if m not in prev: prev[m] = n; q.append(m)
    path = [b]
    while prev[path[-1]] is not None: path.append(prev[path[-1]])
    return path[::-1]
def via(a, b, mid, conns):
    return chain(a, mid, conns) + chain(mid, b, conns)[1:]

lines = []
def add(kind, idx): lines.append({"kind": kind, "pts": P[idx].round(1).tolist()})
# Eyes: corners 33/133 (right) and 263/362 (left); 159/386 on the upper lids, 145/374 on the lower.
for c0, c1, up, lo, eye in ((33, 133, 159, 145, C.FACE_LANDMARKS_RIGHT_EYE), (263, 362, 386, 374, C.FACE_LANDMARKS_LEFT_EYE)):
    u, l = via(c0, c1, up, eye), via(c0, c1, lo, eye)
    add("dark", u); add("tone", l)
    lines.append({"kind": "eye", "pts": P[u + l[::-1]].round(1).tolist()})
# Brows: the set holds each brow's lower and upper edge, outer end to inner; the row runs between.
for lower, upper in (([46, 53, 52, 65, 55], [70, 63, 105, 66, 107]), ([276, 283, 282, 295, 285], [300, 293, 334, 296, 336])):
    lines.append({"kind": "mid", "pts": ((P[lower] + P[upper]) / 2).round(1).tolist()})
# Lips: corners 61/291 outside, 78/308 inside; 0/17 the outer top and bottom, 13/14 the inner.
lips = C.FACE_LANDMARKS_LIPS
up, lo = via(61, 291, 0, lips), via(61, 291, 17, lips)
add("tone", up); add("tone", lo)
lines.append({"kind": "lips", "pts": P[up + lo[::-1]].round(1).tolist()})
add("dark", via(78, 308, 13, lips))
# Nose: the side in shadow, from beside the bridge (the inner brow end) to the wing and nostril.
side = {"right": [193, 245, 188, 174, 198, 209, 49, 64, 98, 240], "left": [417, 465, 412, 399, 420, 429, 279, 294, 327, 460]}
lum = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(float)
def mean_lum(idx):
    return np.mean([lum[min(max(int(y), 0), H - 1), min(max(int(x), 0), W - 1)] for x, y in P[idx]])
shadow = min(side, key=lambda s: mean_lum(side[s]))
add("mid", side[shadow])
add("mid", [64, 98, 97, 2] if shadow == "right" else [294, 327, 326, 2])
# Irises (refined landmarks 468-477): centre and radius; the pupil about 40 % of it.
eyes = []
for c, ring in ((468, [469, 470, 471, 472]), (473, [474, 475, 476, 477])):
    r = float(np.mean(np.hypot(*(P[ring] - P[c]).T)))
    eyes.append([round(float(P[c][0]), 1), round(float(P[c][1]), 1), round(r, 1), round(0.4 * r, 1)])
oval = P[sorted({c.start for c in C.FACE_LANDMARKS_FACE_OVAL})]
(x0, y0), (x1, y1) = oval.min(0), oval.max(0)
m = 0.12 * (x1 - x0)
box = [max(0, int(x0 - m)), max(0, int(y0 - m)), min(W, int(x1 + m)), min(H, int(y1 + m))]
json.dump({"box": box, "eyes": eyes, "lines": lines}, open(out, "w"))
print(f"{photo}: box {box}, eyes {eyes}, {len(lines)} lines, nose shadow on the {shadow}")
if len(args) > 3:
    pv = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    col = {"dark": (0, 0, 255), "mid": (0, 200, 255), "tone": (255, 200, 0), "eye": (0, 255, 0), "lips": (0, 255, 0)}
    for ln in lines:
        cv2.polylines(pv, [np.round(np.array(ln["pts"])).astype(np.int32)], ln["kind"] in ("eye", "lips"), col[ln["kind"]], 1, cv2.LINE_AA)
    for cx, cy, r, _ in eyes: cv2.circle(pv, (int(cx), int(cy)), int(r), (255, 0, 255), 1, cv2.LINE_AA)
    cv2.imwrite(args[3], pv[box[1]:box[3], box[0]:box[2]])
