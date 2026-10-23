"""gestures_look.py <design.json> <photo width> <photo height> <out.json>: a mosaic_look design as Refine gestures
from Blank: the commonest paint by one Bucket tap, each tile one closed inked Pen loop at 8x, the
joints the grout with one tap in the margin, then each other tile its paint."""
import json, sys, math
from collections import Counter
import numpy as np, cv2
d = json.load(open(sys.argv[1])); W, H = float(sys.argv[2]), float(sys.argv[3]); zoom = 8
def n(p): return [round(p[0] / W, 6), round(p[1] / H, 6)]
common = Counter(t["paint"] for t in d["tiles"]).most_common(1)[0][0]
g = [{"tool": "bucket", "at": n((0.6, 0.6)), "rgb": d["palette"][common], "zoom": 1, "caption": "the commonest paint"}]
for i, t in enumerate(d["tiles"]):
    c = t["corners"] + [t["corners"][0]]
    pts = []
    for a, b in zip(c, c[1:]):
        k = max(1, int(math.dist(a, b) / 0.75))
        pts += [(a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k) for j in range(k)]
    pts.append(tuple(c[-1]))
    g.append({"tool": "pen", "points": [n(p) for p in pts], "inked": True, "zoom": zoom})
g.append({"tool": "bucket", "at": n((0.6, 0.6)), "rgb": d["grout"], "zoom": 1, "caption": "the grout"})
for i, t in enumerate(d["tiles"]):
    if t["paint"] == common: continue
    poly = np.array(t["corners"], np.float32)
    m = cv2.moments(poly); cx, cy = m["m10"] / m["m00"], m["m01"] / m["m00"]
    if cv2.pointPolygonTest(poly, (cx, cy), True) < 1:
        xs, ys = np.meshgrid(np.arange(poly[:, 0].min(), poly[:, 0].max(), 0.25), np.arange(poly[:, 1].min(), poly[:, 1].max(), 0.25))
        dd = [cv2.pointPolygonTest(poly, (float(a), float(b)), True) for a, b in zip(xs.ravel(), ys.ravel())]
        j = int(np.argmax(dd)); cx, cy = float(xs.ravel()[j]), float(ys.ravel()[j])
    g.append({"tool": "bucket", "at": n((cx, cy)), "rgb": d["palette"][t["paint"]], "zoom": zoom})
json.dump({"screen": {"width": 960, "zoom": zoom}, "gestures": g}, open(sys.argv[4], "w"))
print(len(g), "gestures")
