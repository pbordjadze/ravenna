"""render.py <design.json> <photo> <finish A|B|C> <out.png> [boxes]: draws a mosaic_faces.py design.
Only the drawing changes between finishes, never the design (its tiles and paints):
  A  flat tiles in their paint, light uniform grout, a thin dark edge (the prototype's own drawing).
  B  the joints coloured by the setting bed under them: the tiles' colours round each joint, a little
     darker and greyer, as the painted beds under Byzantine tesserae were; no drawn edges.
  C  B plus material: each tile's tone varies a little within its paint (smalti batches differ), a lit
     face with a slight bevelled edge; glass outside the face boxes (sharper bevel, a glint), matte stone
     inside them (soft bevel, grain); gold tiles tilted at random, so each catches the light its own way.
boxes: "x0,y0,x1,y1;..." in photo pixels, the face boxes (stone in C). Deterministic: seeded by tile."""
import json, sys
import numpy as np, cv2
from scipy.ndimage import gaussian_filter

design, photo, finish, out = sys.argv[1:5]
BOXES = [tuple(map(float, b.split(","))) for b in (sys.argv[5] if len(sys.argv) > 5 else "").split(";") if b]
d = json.load(open(design))
R = d["scale"]
src = cv2.cvtColor(cv2.imread(photo), cv2.COLOR_BGR2RGB)
H, W = src.shape[0] * R, src.shape[1] * R
pal = np.array(d["palette"], np.float32)
tiles = d["tiles"]
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def oklab(rgb):
    l = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return np.cbrt(np.clip(l @ M1.T, 0, None)) @ M2.T
def srgb(lab):
    lin = np.clip((lab @ np.linalg.inv(M2).T) ** 3 @ np.linalg.inv(M1).T, 0, 1)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)

polys = [np.round(np.array(t["corners"]) * R * 4).astype(np.int32) for t in tiles]
if finish == "A":
    pv = np.ones((H, W, 3), np.float32) * np.array(d["grout"], np.float32)
    for t, q in zip(tiles, polys):
        cv2.fillPoly(pv, [q], pal[t["paint"]].tolist(), shift=2, lineType=cv2.LINE_AA)
        cv2.polylines(pv, [q], True, (0.2, 0.18, 0.17), 1, shift=2, lineType=cv2.LINE_AA)
    cv2.imwrite(out, cv2.cvtColor((np.clip(pv, 0, 1) * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
    sys.exit()

# A map of which tile covers each pixel (0 = joint), and each tile's colour.
ids = np.zeros((H, W), np.int32)
for i, q in enumerate(polys):
    cv2.fillPoly(ids, [q], i + 1, shift=2)
col = np.vstack([np.zeros((1, 3), np.float32), pal[[t["paint"] for t in tiles]]])
lab = oklab(col.astype(float))
if finish == "C":
    rng = np.random.default_rng(547)
    jit = rng.normal(0, 1, (len(lab), 3))
    lab = lab + jit * [0.009, 0.003, 0.003]
img = srgb(lab)[ids].astype(np.float32)
mask = (ids > 0).astype(np.float32)
pitch = d["pitch"] * R / 2
s = pitch * 0.5
blur = gaussian_filter(img * mask[..., None], (s, s, 0)) / np.maximum(gaussian_filter(mask, s), 1e-3)[..., None]
bed = oklab(blur.astype(float)) * [0.8, 0.65, 0.65]
pv = np.where(mask[..., None] > 0, img, srgb(bed).astype(np.float32))
if finish == "C":
    dist = cv2.distanceTransform((ids > 0).astype(np.uint8), cv2.DIST_L2, 5)
    gy, gx = np.gradient(gaussian_filter(dist, 0.8))
    lit = -(gx * -0.6 + gy * -0.8) / (np.hypot(gx, gy) + 1e-6)   # light from the upper left
    cx = np.array([np.array(t["corners"]).mean(0) for t in tiles])
    stone = np.zeros(len(tiles) + 1, bool)
    for x0, y0, x1, y1 in BOXES:
        stone[1:] |= (cx[:, 0] >= x0) & (cx[:, 0] <= x1) & (cx[:, 1] >= y0) & (cx[:, 1] <= y1)
    L, C = lab[:, 0], np.hypot(lab[:, 1], lab[:, 2])
    hue = np.degrees(np.arctan2(lab[:, 2], lab[:, 1]))
    gold = (L > 0.55) & (C > 0.07) & (hue > 55) & (hue < 105)
    tilt = 1 + np.random.default_rng(330).uniform(-0.22, 0.22, len(lab)) * gold
    st = stone[ids]
    b = np.where(st, 0.16, 0.24) * pitch
    edge = np.clip(1 - dist / b, 0, 1) ** 1.5
    shade = 1 + np.where(st, 0.16, 0.34) * lit * edge - np.where(st, 0.05, 0.10) * edge
    rngp = np.random.default_rng(1)
    grain = gaussian_filter(rngp.normal(0, 1, (H, W)), 0.7)
    shade *= 1 + np.where(st, 0.035, 0.012) * grain
    shade *= tilt[ids]
    # A glint on glass: a soft highlight towards each tile's lit corner.
    glint = np.clip(lit, 0, 1) * np.clip(1 - dist / (0.45 * pitch), 0, 1) * (~st) * (ids > 0)
    pv = np.where(mask[..., None] > 0, pv * shade[..., None] + 0.10 * glint[..., None] ** 3, pv)
cv2.imwrite(out, cv2.cvtColor((np.clip(pv, 0, 1) * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
