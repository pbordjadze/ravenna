"""mosaic_look.py <photo> <contours.png> <out prefix> [pitch] [paints] [cut]: a photo as a mosaic, for the
Mosaic look's proposal. The coloring book's own outlines (the contour model's map) give the cartoon:
its strong lines, smoothed, laid as single rows of tiles in a dark smalti of the local hue. The
rest goes in rows that echo them, the photo's color edges and the picture's edge (each row a
level of the distance to them), each tile a square turned along its row and cut where it meets
a neighbour. Colors: each tile's median, gathered into a few smalti. Writes <prefix>.json (the
design) and <prefix>.png (photo | mosaic)."""
import json, sys, math
import numpy as np, cv2
from scipy.ndimage import gaussian_filter, gaussian_filter1d, distance_transform_edt
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize, remove_small_objects

photo, contours, out = sys.argv[1:4]
S = float(sys.argv[4]) if len(sys.argv) > 4 else 34.0
K = int(sys.argv[5]) if len(sys.argv) > 5 else 14
CUT = float(sys.argv[6]) if len(sys.argv) > 6 else 0.55
G = 4
T = S - G
SCALE = 2
src = cv2.cvtColor(cv2.imread(photo), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
img = cv2.resize(src, (src.shape[1] * SCALE, src.shape[0] * SCALE), interpolation=cv2.INTER_CUBIC).clip(0, 1)
H, W = img.shape[:2]
draw = cv2.imread(contours, cv2.IMREAD_GRAYSCALE)
draw = cv2.resize(draw, (W, H), interpolation=cv2.INTER_LINEAR).astype(np.float32) / 255

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

# The cartoon: the drawing's strong lines as smooth chains.
strong = gaussian_filter(draw, 2.0) > CUT
strong = remove_small_objects(cv2.morphologyEx(strong.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) > 0, max_size=int(S * 4))
def nbrs(p, P):
    x, y = p; out = []
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if (x + dx, y + dy) in P: out.append((x + dx, y + dy))
    for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        if (x + dx, y + dy) in P and (x + dx, y) not in P and (x, y + dy) not in P: out.append((x + dx, y + dy))
    return out
def chains(mask):
    ys, xs = np.nonzero(skeletonize(mask)); P = set(zip(xs.tolist(), ys.tolist()))
    nodes = {p for p in P if len(nbrs(p, P)) != 2}; seen = set(); out = []
    def walk(n, q):
        path = [n, q]; seen.update({(n, q), (q, n)}); prev, cur = n, q
        while cur not in nodes:
            nxt = [r for r in nbrs(cur, P) if r != prev and (cur, r) not in seen]
            if not nxt: break
            r = nxt[0]; seen.update({(cur, r), (r, cur)}); path.append(r); prev, cur = cur, r
        return path
    for n in list(nodes) + list(P):
        for q in nbrs(n, P):
            if (n, q) not in seen: out.append(walk(n, q))
    return [np.array(c, float) for c in out]
def link(cs, reach, cosmin=0.6):
    cs = [c for c in cs if len(c) >= 6]
    def tang(c, end):
        k = min(len(c) - 1, 12)
        return (c[-1] - c[-1 - k]) if end else (c[0] - c[k])
    while True:
        ends = []
        for i, c in enumerate(cs):
            ends += [(c[0], i, 0), (c[-1], i, 1)]
        tree = cKDTree([e[0] for e in ends]); best = None
        for a, b in tree.query_pairs(reach):
            (pi, i, ei), (pj, j, ej) = ends[a], ends[b]
            if i == j: continue
            gap = pj - pi; d = np.hypot(*gap)
            if d < 1e-6: continue
            ti = tang(cs[i], ei); tj = -tang(cs[j], ej)
            ti = ti / (np.hypot(*ti) + 1e-9); tj = tj / (np.hypot(*tj) + 1e-9); gu = gap / d
            if min(ti @ gu, tj @ gu, ti @ tj) > cosmin and (best is None or d < best[0]): best = (d, i, j, ei, ej)
        if best is None: return cs
        _, i, j, ei, ej = best
        a = cs[i] if ei else cs[i][::-1]; b = cs[j][::-1] if ej else cs[j]
        cs = [c for k, c in enumerate(cs) if k not in (i, j)] + [np.vstack([a, b])]
guides = []
for P in link(chains(strong), reach=S * 0.9):
    if len(P) < 2.2 * S: continue
    guides.append(np.stack([gaussian_filter1d(P[:, 0], S * 0.35, mode="nearest"), gaussian_filter1d(P[:, 1], S * 0.35, mode="nearest")], 1))

forbid = np.zeros((H, W), np.uint8)
inside = np.zeros((H, W), np.uint8); inside[G:H - G, G:W - G] = 1
kern = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * G + 1, 2 * G + 1))
tiles = []
def place(poly, strand, min_frac=0.45):
    x0 = max(int(poly[:, 0].min()) - 2, 0); y0 = max(int(poly[:, 1].min()) - 2, 0)
    x1 = min(int(poly[:, 0].max()) + 3, W); y1 = min(int(poly[:, 1].max()) + 3, H)
    if x1 <= x0 or y1 <= y0: return False
    m = np.zeros((y1 - y0, x1 - x0), np.uint8)
    cv2.fillPoly(m, [np.round((poly - [x0, y0]) * 4).astype(np.int32)], 1, shift=2)
    m &= inside[y0:y1, x0:x1]; m[forbid[y0:y1, x0:x1] > 0] = 0
    if m.sum() < min_frac * T * T: return False
    n, lab_, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
    if n < 2: return False
    k = 1 + np.argmax(st[1:, cv2.CC_STAT_AREA]); m = (lab_ == k).astype(np.uint8)
    if m.sum() < min_frac * T * T: return False
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    p = cv2.approxPolyDP(max(cs, key=cv2.contourArea), 1.4, True).reshape(-1, 2).astype(np.float64) + [x0, y0]
    if len(p) < 3: return False
    q = np.zeros((y1 - y0 + 2 * G + 2, x1 - x0 + 2 * G + 2), np.uint8)
    cv2.fillPoly(q, [np.round(p - [x0 - G - 1, y0 - G - 1]).astype(np.int32)], 1)
    q = cv2.dilate(q, kern)
    ya, xa = y0 - G - 1, x0 - G - 1
    sy0, sx0 = max(ya, 0), max(xa, 0); sy1, sx1 = min(ya + q.shape[0], H), min(xa + q.shape[1], W)
    np.maximum(forbid[sy0:sy1, sx0:sx1], q[sy0 - ya:sy1 - ya, sx0 - xa:sx1 - xa], out=forbid[sy0:sy1, sx0:sx1])
    tiles.append({"poly": p, "strand": strand}); return True
def square(c, t):
    t = t / (np.hypot(*t) + 1e-9); n = np.array([-t[1], t[0]])
    return np.array([c + a * T / 2 * t + b * T / 2 * n for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
def resample(P, step, closed=False):
    d = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    n = max(1, int(d[-1] // step))
    at = (d[-1] - n * step) / 2 + step / 2 + step * np.arange(n)
    return np.stack([np.interp(at, d, P[:, 0]), np.interp(at, d, P[:, 1])], 1), d[-1]
for P in sorted(guides, key=lambda g: -len(g)):
    pts, length = resample(P, S)
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, len(pts) - 1)]
        if len(pts) == 1: a, b = P[0], P[-1]
        place(square(p, b - a), True, 0.35)
strands = len(tiles)
import os
STAGES = os.environ.get("STAGES")
PAPER, INK = np.array([0.95, 0.945, 0.93]), np.array([0.2, 0.18, 0.17])
def stage(name, fill=None, lines=None):
    if not STAGES: return
    pv = np.ones((H, W, 3), np.float32) * PAPER
    if lines is not None: pv[lines] = PAPER * 0.35 + np.array([0.48, 0.25, 0.5]) * 0.65
    for i, t in enumerate(tiles):
        q = np.round(t["poly"] * 4).astype(np.int32)
        col = fill(i, t) if fill else None
        if col is not None: cv2.fillPoly(pv, [q], list(map(float, col)), shift=2, lineType=cv2.LINE_AA)
        cv2.polylines(pv, [q], True, tuple(map(float, INK)), 1, shift=2, lineType=cv2.LINE_AA)
    cv2.imwrite(f"{STAGES}-{name}.png", cv2.cvtColor((np.clip(pv, 0, 1) * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
if STAGES:
    keep = list(tiles); tiles.clear()
    stage("1-outlines", lines=cv2.dilate(skeletonize(strong).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
    tiles.extend(keep)
    stage("2-strands", fill=lambda i, t: INK + 0.08)
# Rows echo the strands, the photo's color edges and the picture's edge.
lab = oklab(gaussian_filter(img, (S * 0.12, S * 0.12, 0)))
X = (lab.reshape(-1, 3) * [1, 1.6, 1.6]).astype(np.float32)
crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 1e-3)
sample = X[np.random.default_rng(3).choice(len(X), 60000, replace=False)]
_, _, cen = cv2.kmeans(sample, 8, None, crit, 3, cv2.KMEANS_PP_CENTERS)
seg = cKDTree(cen).query(X)[1].reshape(H, W).astype(np.int32)
seg = cv2.medianBlur(seg.astype(np.uint8), 9)
edges = (cv2.morphologyEx(seg, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8)) > 0)
edges = remove_small_objects(edges, max_size=int(S * 3))
seed = (forbid > 0) | edges
D = distance_transform_edt(~seed)
yy, xx = np.mgrid[0:H, 0:W]
D = np.minimum(D, np.minimum.reduce([xx, W - 1 - xx, yy, H - 1 - yy]).astype(float) + G)
D = gaussian_filter(D, 2.0)
k = 0
while T / 2 + G + k * S < D.max():
    level = T / 2 + G + k * S
    cs, _ = cv2.findContours((D < level).astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    for ring in sorted(cs, key=lambda r: -len(r)):
        R = ring.reshape(-1, 2).astype(float)
        if len(R) < 8: continue
        R = np.stack([gaussian_filter1d(R[:, 0], 4, mode="wrap"), gaussian_filter1d(R[:, 1], 4, mode="wrap")], 1)
        pts, length = resample(np.vstack([R, R[:1]]), S)
        if length < S: continue
        for i, p in enumerate(pts):
            place(square(p, pts[(i + 1) % len(pts)] - pts[(i - 1) % len(pts)]), False)
    k += 1
gy, gx = np.gradient(D)
for _ in range(4):
    free = ((forbid == 0) & (inside > 0)).astype(np.uint8)
    dt = cv2.distanceTransform(free, cv2.DIST_L2, 5)
    peaks = np.argwhere((dt >= T * 0.3) & (dt == cv2.dilate(dt, np.ones((int(S), int(S)), np.uint8))))
    added = 0
    for y, x in sorted(peaks.tolist(), key=lambda q: -dt[q[0], q[1]]):
        if not forbid[y, x] and place(square(np.array([x, y], float), np.array([-gy[y, x], gx[y, x]]) + 1e-6), False, 0.3): added += 1
    if not added: break
stage("3-rows", fill=lambda i, t: INK + 0.08 if t["strand"] else None)
# Colors: each tile's median; a strand tile, a dark smalti of the hue round it.
med = []
for t in tiles:
    p = t["poly"]; x0, y0 = np.floor(p.min(0)).astype(int); x1, y1 = np.ceil(p.max(0)).astype(int) + 1
    m = np.zeros((y1 - y0, x1 - x0), np.uint8); cv2.fillPoly(m, [np.round(p - [x0, y0]).astype(np.int32)], 1)
    px = img[y0:y1, x0:x1][m > 0]
    c = oklab(np.median(px, 0))
    if t["strand"]:
        c = np.array([min(c[0], 0.30), c[1] * 0.8, c[2] * 0.8])
    med.append(c)
med = np.array(med)
Xc = (med * [1, 1.5, 1.5]).astype(np.float32)
_, a, _ = cv2.kmeans(Xc, K, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 200, 1e-5), 10, cv2.KMEANS_PP_CENTERS)
a = a.ravel()
palette = []
remap = {}
for j in range(K):
    members = np.where(a == j)[0]
    if len(members) == 0: continue
    remap[j] = len(palette); palette.append(srgb(np.median(med[members], 0)))
paint = np.array([remap[j] for j in a])
grout = srgb(np.array([0.86, 0.004, 0.012]))
design = {"size": [W, H], "scale": SCALE, "pitch": S, "grout": [round(float(v), 4) for v in grout],
          "palette": [[round(float(v), 4) for v in c] for c in palette],
          "tiles": [{"corners": (t["poly"] / SCALE).round(3).tolist(), "paint": int(paint[i]), "strand": t["strand"]} for i, t in enumerate(tiles)]}
json.dump(design, open(out + ".json", "w"))
pv = np.ones((H, W, 3), np.float32) * grout
for i, t in enumerate(tiles):
    q = np.round(t["poly"] * 4).astype(np.int32)
    cv2.fillPoly(pv, [q], palette[paint[i]].tolist(), shift=2, lineType=cv2.LINE_AA)
    cv2.polylines(pv, [q], True, (0.2, 0.18, 0.17), 1, shift=2, lineType=cv2.LINE_AA)
cv2.imwrite(out + ".png", cv2.cvtColor((np.clip(np.hstack([img, pv]), 0, 1) * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
print(len(tiles), "tiles,", strands, "on strands,", len(palette), "paints")
