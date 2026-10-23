"""head_guides.py <photo> <out.json> <vis.png>: candidate strands (red, dark) as smoothed chains, numbered for review."""
import numpy as np, cv2, sys, json
from scipy.ndimage import gaussian_filter, gaussian_filter1d
from skimage.morphology import skeletonize, remove_small_objects
def oklab(rgb):
    l = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
    M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
    return np.cbrt(l @ M1.T) @ M2.T
img = cv2.cvtColor(cv2.imread(sys.argv[1]), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
X0, Y0, X1, Y1 = 380, 580, 1440, 1290
sub = img[Y0:Y1, X0:X1]
lab = oklab(gaussian_filter(sub, (2.5, 2.5, 0)))
labd = oklab(gaussian_filter(sub, (4, 4, 0)))
L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
red = (a > 0.036) & (a > b * 0.6)
dark = (labd[..., 0] < 0.36) & ~red
gold = (b > 0.085) & (L > 0.5) & ~red
def clean(m, close=5, minarea=250):
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((close, close), np.uint8))
    return remove_small_objects(m > 0, minarea)
red, dark, gold = clean(red), clean(dark, 7, 400), clean(gold, 9, 600)
def nbrs(p, S):
    x, y = p; out = []
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        if (x + dx, y + dy) in S: out.append((x + dx, y + dy))
    for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        if (x + dx, y + dy) in S and (x + dx, y) not in S and (x, y + dy) not in S: out.append((x + dx, y + dy))
    return out
def chains(mask):
    sk = skeletonize(mask)
    ys, xs = np.nonzero(sk); S = set(zip(xs.tolist(), ys.tolist()))
    deg = {p: len(nbrs(p, S)) for p in S}
    nodes = {p for p in S if deg[p] != 2}
    seen = set(); out = []
    def walk(n, q):
        path = [n, q]; seen.add((n, q)); seen.add((q, n)); prev, cur = n, q
        while cur not in nodes:
            nxt = [r for r in nbrs(cur, S) if r != prev and (cur, r) not in seen]
            if not nxt: break
            r = nxt[0]; seen.add((cur, r)); seen.add((r, cur)); path.append(r); prev, cur = cur, r
        return path
    for n in nodes:
        for q in nbrs(n, S):
            if (n, q) not in seen: out.append(walk(n, q))
    for p in S:
        for q in nbrs(p, S):
            if (p, q) not in seen: out.append(walk(p, q))
    return out
def link(cs, reach=42, cosmin=0.55):
    cs = [np.array(c, float) for c in cs if len(c) >= 12]
    def tang(c, end):
        k = min(len(c) - 1, 15)
        return (c[-1] - c[-1 - k]) if end else (c[0] - c[k])
    changed = True
    while changed:
        changed = False
        best = None
        for i in range(len(cs)):
            for j in range(len(cs)):
                if i == j: continue
                for ei in (0, 1):
                    for ej in (0, 1):
                        pi = cs[i][-1] if ei else cs[i][0]; pj = cs[j][-1] if ej else cs[j][0]
                        gap = pj - pi; d = np.hypot(*gap)
                        if d > reach or d < 1e-6: continue
                        ti = tang(cs[i], ei); tj = -tang(cs[j], ej)
                        ti = ti / (np.hypot(*ti) + 1e-9); tj = tj / (np.hypot(*tj) + 1e-9); gu = gap / d
                        sc = min(ti @ gu, tj @ gu, ti @ tj)
                        if sc > cosmin and (best is None or d < best[0]): best = (d, i, j, ei, ej)
        if best:
            _, i, j, ei, ej = best
            a = cs[i] if ei else cs[i][::-1]; b = cs[j][::-1] if ej else cs[j]
            new = np.vstack([a, b]); cs = [c for k, c in enumerate(cs) if k not in (i, j)] + [new]; changed = True
    return cs
res = {}
vis = (sub * 255).astype(np.uint8).copy()
vis = (vis * 0.6).astype(np.uint8)
k = 0
for name, mask, col in (("red", red, (255, 60, 60)), ("dark", dark, (80, 160, 255))):
    res[name] = []
    for P in link(chains(mask)):
        if len(P) < 40: continue
        P = np.stack([gaussian_filter1d(P[:, 0], 9, mode="nearest"), gaussian_filter1d(P[:, 1], 9, mode="nearest")], 1)
        res[name].append({"id": k, "points": (P + [X0, Y0]).round(1).tolist()})
        cv2.polylines(vis, [P.astype(np.int32)], False, col, 2)
        m = P[len(P) // 2].astype(int)
        cv2.putText(vis, str(k), (int(m[0]) + 3, int(m[1]) - 3), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 0), 1)
        k += 1
over = vis.copy(); over[gold] = (over[gold] * 0.5 + np.array([60, 200, 60]) * 0.5).astype(np.uint8)
json.dump(res, open(sys.argv[2], "w"))
cv2.imwrite(sys.argv[3], cv2.cvtColor(over, cv2.COLOR_RGB2BGR))
cv2.imwrite("masks2.png", cv2.cvtColor(np.dstack([red * 255, gold * 255, dark * 255]).astype(np.uint8), cv2.COLOR_RGB2BGR))
print({n: len(v) for n, v in res.items()})
