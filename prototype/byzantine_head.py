"""byzantine_head.py <photo> <cand.json> <out.json> <preview.png>: a mosaic laid as a mosaicist lays one.

The cartoon first: the strands of the drawing (the red of the hair, brows, nose and lips, the
dark of the outline and lids), traced as smooth curves, each laid as one row of tiles turned
along it; each iris one round piece. Then the rest in rows that echo them (opus vermiculatum):
row k runs at k tile pitches from the nearest laid tile or the panel's edge, its tiles squares
turned along the row and cut where they meet a neighbour. Colors: the photo's own, a tile's the
median of its pixels, the field's shading calmed over its neighbours and gathered into a few
smalti per family."""
import json, sys, math
import numpy as np, cv2
from scipy.ndimage import gaussian_filter, gaussian_filter1d, distance_transform_edt
from scipy.spatial import cKDTree

photo, cand, out, preview = sys.argv[1:5]
X0, Y0, X1, Y1 = 600, 612, 1420, 1250
S = 24.0          # tile pitch
G = 4             # grout: the free gap round every tile
T = S - G         # tile side
W, H = X1 - X0, Y1 - Y0

img = cv2.cvtColor(cv2.imread(photo), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
box = img[Y0:Y1, X0:X1]
# The photo's own light, a little brighter: paint reads darker than lit stone.
LIFT = 1.12
def balanced(rgb):
    l = np.clip(np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4) * LIFT, 0, 1)
    return np.where(l <= 0.0031308, 12.92 * l, 1.055 * l ** (1 / 2.4) - 0.055)
def oklab(rgb):
    rgb = np.asarray(rgb, float)
    l = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
    M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
    return np.cbrt(np.clip(l @ M1.T, 0, None)) @ M2.T
def srgb(lab):
    M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
    M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
    lin = np.clip((np.asarray(lab) @ np.linalg.inv(M2).T) ** 3 @ np.linalg.inv(M1).T, 0, 1)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)

lab = oklab(gaussian_filter(box, (2.5, 2.5, 0)))
labd = oklab(gaussian_filter(box, (4, 4, 0)))
redm = (lab[..., 1] > 0.036) & (lab[..., 1] > lab[..., 2] * 0.6)
darkm = (labd[..., 0] < 0.33) & ~redm
goldm = (lab[..., 2] > 0.085) & (lab[..., 0] > 0.5) & ~redm

# The cartoon.
c = json.load(open(cand))
KEEP_DARK = {38, 33, 32, 40, 34, 30, 31}
guides = [("red", np.array(g["points"])) for g in c["red"]] + [("dark", np.array(g["points"])) for g in c["dark"] if g["id"] in KEEP_DARK]
# The right eye's lid, which the dark map breaks up: drawn by hand.
lid = np.array([(1303, 737), (1322, 726), (1345, 719), (1372, 717), (1398, 721), (1420, 730)], float)
guides.append(("dark", lid))
def resample(P, step):
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    n = max(1, int(d[-1] // step))
    off = (d[-1] - n * step) / 2 + step / 2
    at = off + step * np.arange(n) if d[-1] >= step * 0.6 else np.array([d[-1] / 2])
    return np.stack([np.interp(at, d, P[:, 0]), np.interp(at, d, P[:, 1])], 1), d[-1]
def smooth(P, sigma):
    return np.stack([gaussian_filter1d(P[:, 0], sigma, mode="nearest"), gaussian_filter1d(P[:, 1], sigma, mode="nearest")], 1)

forbid = np.zeros((H, W), np.uint8)       # tiles dilated by the grout
inside = np.zeros((H, W), np.uint8); inside[G:H - G, G:W - G] = 1
tiles = []
def place(poly, cls, min_frac=0.45, force=False):
    """A tile from `poly` (box coordinates), less what the grout round its neighbours takes."""
    m = np.zeros((H, W), np.uint8); cv2.fillPoly(m, [np.round(poly * 4).astype(np.int32)], 1, shift=2)
    full = m.sum()
    if full == 0: return False
    m &= inside; m[forbid > 0] = 0
    if not force and m.sum() < min_frac * T * T: return False
    n, lab_, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
    if n < 2: return False
    k = 1 + np.argmax(st[1:, cv2.CC_STAT_AREA]); m = (lab_ == k).astype(np.uint8)
    if not force and m.sum() < min_frac * T * T: return False
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    ring = max(cs, key=cv2.contourArea).reshape(-1, 2).astype(np.float32)
    # Straight sides: the cut piece's outline simplified, never past its pixels' hull.
    p = cv2.approxPolyDP(ring, 1.4, True).reshape(-1, 2).astype(np.float64)
    if len(p) < 3 or cv2.contourArea(p.astype(np.float32)) < 0.3 * T * T and not force: return False
    q = np.zeros((H, W), np.uint8); cv2.fillPoly(q, [np.round(p).astype(np.int32)], 1)
    k2 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * G + 1, 2 * G + 1))
    np.maximum(forbid, cv2.dilate(q, k2), out=forbid)
    tiles.append({"poly": p, "cls": cls})
    return True
def square(c, tdir, along=T, across=T):
    tdir = tdir / (np.hypot(*tdir) + 1e-9); nrm = np.array([-tdir[1], tdir[0]])
    return np.array([c + sa * along / 2 * tdir + sb * across / 2 * nrm for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))])

# Each iris one round piece, as the mosaicist set it.
for cx, cy, r in ((1069, 753, 21), (1366, 744, 19)):
    ang = np.linspace(0, 2 * math.pi, 20, endpoint=False)
    place(np.stack([cx - X0 + r * np.cos(ang), cy - Y0 + r * np.sin(ang)], 1), "dark", force=True)
# The strands, longest first, each a row of tiles along it.
order = sorted(guides, key=lambda g: -np.hypot(*np.diff(g[1], axis=0).T).sum())
for cls, P in order:
    P = smooth(P - [X0, Y0], 4)
    keep = (P[:, 0] > -S) & (P[:, 0] < W + S) & (P[:, 1] > -S) & (P[:, 1] < H + S)
    if keep.sum() < 3: continue
    P = P[keep]
    pts, length = resample(P, S)
    if length < S * 0.8: continue
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, len(pts) - 1)]
        if len(pts) == 1: a, b = P[0], P[-1]
        place(square(p, b - a), cls, min_frac=0.35)
laid_strands = len(tiles)
# Rows echoing the laid strands and the panel's edge.
seed = (forbid > 0).astype(np.uint8)
D = distance_transform_edt(1 - seed)
edge = np.minimum.reduce([np.arange(W)[None, :].repeat(H, 0), (W - 1 - np.arange(W))[None, :].repeat(H, 0),
                          np.arange(H)[:, None].repeat(W, 1), (H - 1 - np.arange(H))[:, None].repeat(W, 1)]).astype(float)
D = np.minimum(D, edge + G)
D = gaussian_filter(D, 1.5)
k = 0
while True:
    level = T / 2 + k * S + (G if k == 0 else G)
    if level > D.max(): break
    m = (D < level).astype(np.uint8)
    cs, _ = cv2.findContours(m, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    for ring in sorted(cs, key=lambda r: -len(r)):
        R = ring.reshape(-1, 2).astype(float)
        if len(R) < 8: continue
        R = np.stack([gaussian_filter1d(R[:, 0], 3, mode="wrap"), gaussian_filter1d(R[:, 1], 3, mode="wrap")], 1)
        R = np.vstack([R, R[:1]])
        pts, length = resample(R, S)
        if length < S: continue
        for i, p in enumerate(pts):
            a = pts[(i - 1) % len(pts)]; b = pts[(i + 1) % len(pts)]
            place(square(p, b - a), None)
    k += 1
# The gaps rows leave where they meet: a piece cut to each that holds one.
for _ in range(4):
    free = ((forbid == 0) & (inside > 0)).astype(np.uint8)
    dt = cv2.distanceTransform(free, cv2.DIST_L2, 5)
    peaks = np.argwhere((dt >= T * 0.3) & (dt == cv2.dilate(dt, np.ones((int(S), int(S)), np.uint8))))
    added = 0
    for y, x in sorted(peaks.tolist(), key=lambda q: -dt[q[0], q[1]]):
        if forbid[y, x]: continue
        gy, gx = np.gradient(D)[0][y, x], np.gradient(D)[1][y, x]
        if place(square(np.array([x, y], float), np.array([-gy, gx]) + 1e-6), None, min_frac=0.3): added += 1
    if not added: break

# Colors. A tile's family: its strand's, or the mask most of its pixels lie in.
fam_names = ["field", "red", "dark", "gold"]
med = []
for t in tiles:
    m = np.zeros((H, W), np.uint8); cv2.fillPoly(m, [np.round(t["poly"]).astype(np.int32)], 1)
    sel = m > 0; t["area"] = int(sel.sum())
    if t["cls"] is None:
        fr = {"red": redm[sel].mean(), "dark": darkm[sel].mean(), "gold": goldm[sel].mean()}
        best = max(fr, key=fr.get)
        t["cls"] = best if fr[best] > 0.5 else "field"
    # A tile's own color: its pixels' median, the body of the stones under it (a field tile's
    # without the strands it brushes against).
    own = sel & ~(redm | darkm | goldm) if t["cls"] == "field" else sel
    med.append(oklab(balanced(np.median(box[own if own.sum() >= 0.3 * sel.sum() else sel], 0))))
    t["center"] = t["poly"].mean(0)
med = np.array(med)
cls = np.array([t["cls"] for t in tiles]); C = np.array([t["center"] for t in tiles])
# The field's shading, calmed: each tile's lightness and hue the average of the field tiles
# within a tile and a half of it, so shade runs in zones as a mosaicist grades it, not speckle.
field = np.where(cls == "field")[0]
tree = cKDTree(C[field])
calm = med.copy()
for j, i in enumerate(field):
    nb = field[tree.query_ball_point(C[i], 2.2 * S)]
    calm[i] = 0.2 * med[i] + 0.8 * np.median(med[nb], 0)
# The field in a few stones of its own; each strand family one smalti, as the mosaicist chose
# one red, one black and one gold: its strongest pixels' color, by their lit half.
palette, paint = [], np.zeros(len(tiles), int)
crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 200, 1e-5)
idx = np.where(cls == "field")[0]
X = (calm[idx] * [1, 1.5, 1.5]).astype(np.float32)
_, a, _ = cv2.kmeans(X, 6, None, crit, 10, cv2.KMEANS_PP_CENTERS)
a = a.ravel()
for j in range(6):
    members = idx[a == j]
    if len(members) == 0: continue
    paint[members] = len(palette)
    palette.append({"family": "field", "lab": np.median(calm[members], 0)})
FL = oklab(box)
cores = {"red": FL[..., 1] > 0.08, "dark": FL[..., 0] < 0.27, "gold": (FL[..., 2] > 0.1) & (FL[..., 0] > 0.6)}
for f, core in cores.items():
    members = np.where(cls == f)[0]
    if len(members) == 0: continue
    px = box[core]; lum = px @ [0.2126, 0.7152, 0.0722]
    paint[members] = len(palette)
    palette.append({"family": f, "lab": oklab(balanced(np.median(px[lum >= np.median(lum)], 0)))})
rgbs = [srgb(p["lab"]) for p in palette]
# Mortar: the panel's plaster, beside the gold.
# Mortar: the photo's own grout, the light joints between the face's stones.
face = img[650:1200, 950:1250]; fl = oklab(face)
joints = (fl[..., 0] > gaussian_filter(fl[..., 0], 6) + 0.05) & (np.hypot(fl[..., 1], fl[..., 2]) < 0.05)
mortar = balanced(np.median(face[joints], 0))
design = {"box": [X0, Y0, X1, Y1], "pitch": S, "grout": G, "mortar": [round(float(v), 4) for v in mortar],
          "palette": [[round(float(v), 4) for v in r] for r in rgbs], "families": [p["family"] for p in palette],
          "tiles": [{"corners": (t["poly"] + [X0, Y0]).round(2).tolist(), "paint": int(paint[i]), "family": t["cls"]} for i, t in enumerate(tiles)]}
json.dump(design, open(out, "w"))
# Preview: the tiles in their paints on the mortar, ink round each, at 2x.
pv = np.ones((H * 2, W * 2, 3), np.float32) * mortar
for i, t in enumerate(tiles):
    q = np.round(t["poly"] * 2 * 4).astype(np.int32)
    cv2.fillPoly(pv, [q], rgbs[paint[i]].tolist(), shift=2, lineType=cv2.LINE_AA)
    cv2.polylines(pv, [q], True, (0.18, 0.15, 0.13), 1, shift=2, lineType=cv2.LINE_AA)
cv2.imwrite(preview, cv2.cvtColor((np.clip(np.hstack([cv2.resize(balanced(box), (W * 2, H * 2)), pv]), 0, 1) * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
fam = {f: int((cls == f).sum()) for f in fam_names}
print(len(tiles), "tiles;", laid_strands, "on strands;", fam, "; paints", len(palette), "; mortar", np.round(mortar, 3))
