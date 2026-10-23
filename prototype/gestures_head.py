"""gestures3.py <design.json> <out.json> [zoom]: a designed mosaic as a refiner lays it on Blank.

The canvas first takes the commonest stone with one Bucket tap; each tile is one closed Pen loop
of straight sides (ink alone, so it keeps that stone); the joints left between the loops, one
area, take the mortar with one tap; then each tile of another stone takes it with the Bucket."""
import json, sys, math
from collections import Counter
import numpy as np, cv2
W, H = 1920, 1828
d = json.load(open(sys.argv[1])); zoom = float(sys.argv[3]) if len(sys.argv) > 3 else 6
def n(p): return [round(p[0] / W, 6), round(p[1] / H, 6)]
common = Counter(t["paint"] for t in d["tiles"]).most_common(1)[0][0]
x0, y0, x1, y1 = d["box"]
g = [{"tool": "bucket", "at": n((x0 - 60, y0 - 60)), "rgb": d["palette"][common], "zoom": 1, "caption": "the commonest stone"}]
for i, t in enumerate(d["tiles"]):
    c = t["corners"] + [t["corners"][0]]
    pts = []
    for a, b in zip(c, c[1:]):
        k = max(1, int(math.dist(a, b) / 1.5))
        pts += [(a[0] + (b[0] - a[0]) * j / k, a[1] + (b[1] - a[1]) * j / k) for j in range(k)]
    pts.append(tuple(c[-1]))
    g.append({"tool": "pen", "points": [n(p) for p in pts], "inked": True, "zoom": zoom, "caption": f"tile {i}"})
g.append({"tool": "bucket", "at": n((x0 - 60, y0 - 60)), "rgb": d["mortar"], "zoom": 1, "caption": "the mortar"})
for i, t in enumerate(d["tiles"]):
    if t["paint"] == common: continue
    poly = np.array(t["corners"], np.float32)
    m = cv2.moments(poly)
    cx, cy = m["m10"] / m["m00"], m["m01"] / m["m00"]
    if cv2.pointPolygonTest(poly, (cx, cy), True) < 2:   # a bent piece: its deepest point
        xs, ys = np.meshgrid(np.arange(poly[:, 0].min(), poly[:, 0].max(), 0.5), np.arange(poly[:, 1].min(), poly[:, 1].max(), 0.5))
        dd = [cv2.pointPolygonTest(poly, (float(a), float(b)), True) for a, b in zip(xs.ravel(), ys.ravel())]
        j = int(np.argmax(dd)); cx, cy = float(xs.ravel()[j]), float(ys.ravel()[j])
    g.append({"tool": "bucket", "at": n((cx, cy)), "rgb": d["palette"][t["paint"]], "zoom": zoom, "caption": f"colour tile {i}"})
json.dump({"screen": {"width": 960, "zoom": zoom}, "gestures": g}, open(sys.argv[2], "w"))
print(len(g), "gestures")
