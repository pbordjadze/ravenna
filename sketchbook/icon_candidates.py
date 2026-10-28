"""icon_candidates.py <out-dir> [name ...]: the candidates for Ravenna's icon (issue #15), the one that
would replace Paint by Moonlight's on the home screen when the mode is entered. Paul chose Apse. Each is 1024 px in three
appearances, as Paint by Moonlight's appiconset has them: <name>.png (light), <name>-dark.png and
<name>-tinted.png (grayscale, for iOS 18's tinted home screen).

Every picture is laid as tesserae with andamento: each region is filled in rows that follow its
edges (rows laid along the isolines of the distance to whatever borders the region, so a sky's rows
ripple round the moon), the motif outlined first by a row of its own, as a mosaicist works. Each
tile is cut to its region, tilted a little (its tone varies), lit on its upper-left edge and shaded
on its lower-right; gold only where the motif needs it. Light: tiles on a light grout (lime
plaster), the sky a little brighter. Dark: the painted bed of an apse.

  moonlight  Paint by Moonlight's own picture set in smalti: its crescent, sky and hills, the rows
             of the sky rippling round the moon. The sibling.
  delta      The same night, and the cream area's numeral 4 written as the Greek numeral Δʹ.
  star       One gold star on lapis, rows rippling out from it, after the starry vault of the
             Mausoleum of Galla Placidia, Ravenna (c. 425-450; UNESCO, whc.unesco.org/en/list/788).
  tessera    One gold tessera lifted over its place, the lapis rows already laid round the gap.
  nimbus     A gold nimbus outlined in red, on lapis rows that follow it, as the halos of San
             Vitale's apse and imperial panels (consecrated 547; UNESCO, as above).
  apse       A round-headed apse in lime plaster opening onto Paint by Moonlight's night: the door.

Deterministic: each candidate is seeded by its name; the same OpenCV draws the same pixels.
  icon_candidates.py <out-dir> --catalog App/Ravenna/Resources/Assets.xcassets [name]   makes one the
  app's icon (default apse, Paul's pick, October 28; the others stay here to be drawn again)."""
import sys, os, math, zlib
import numpy as np, cv2

N = 1024; S = 3; W = N * S          # drawn at 3x, then reduced
LIGHT = np.array([-0.6, -0.8])       # light from the upper left

# Ravenna's palette (the design page, Theme.swift), and the few colours a Byzantine wall adds.
APSE = (0.082, 0.075, 0.059); LIME = (0.914, 0.886, 0.827); OCHRE = (0.651, 0.612, 0.537)
GOLD = (0.788, 0.635, 0.290); LAPIS = (0.122, 0.165, 0.322); DEEP = (0.070, 0.090, 0.190)
SKY = (0.150, 0.205, 0.400); PORPHYRY = (0.330, 0.165, 0.270); WINE = (0.230, 0.110, 0.190)
RED = (0.560, 0.150, 0.120); INK = (0.110, 0.095, 0.085); SILVER = (0.860, 0.850, 0.800)


class Wall:
    """A wall at W px: its bed, the regions laid so far, and their tiles."""

    def __init__(self, name, light):
        self.rng = np.random.default_rng(zlib.crc32(name.encode()))
        self.light = light
        self.bed = np.array((0.70, 0.67, 0.61) if light else (0.055, 0.050, 0.042), np.float32)
        self.joint = int(2.6 * S)
        self.label = np.full((W, W), -1, np.float32)     # which tile each pixel is, -1 the bed
        self.colors, self.centres, self.pitches, self.glass, self.catch = [], [], [], [], []
        self.glow = np.zeros((W, W), np.float32); self.overlays = []

    def lay(self, mask, pitch, color, guide=None, gold=False, glass=True, lit=None, order=0.5):
        """Fills mask (bool, W x W) with rows of tiles pitch px (at 1024) apart, following guide's
        edges (default: the region's own edge). color is an RGB or a function of (x, y) in 0..1."""
        p = pitch * S
        g = (~mask if guide is None else guide).astype(np.uint8)
        dist = cv2.distanceTransform(1 - g, cv2.DIST_L2, 5)
        dist[~mask] = 0
        placed = []; grid = {}
        def free(c, r):
            i, j = int(c[0] // p), int(c[1] // p)
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    for q in grid.get((i + di, j + dj), ()):
                        if (q[0] - c[0]) ** 2 + (q[1] - c[1]) ** 2 < r * r: return False
            return True
        def put(c, ang, w, h):
            placed.append((c, ang, w, h)); grid.setdefault((int(c[0] // p), int(c[1] // p)), []).append(c)
        # Rows along the isolines of the distance to the guide, inside the region.
        top = dist.max(); k = 0
        while (k + order) * p < top:
            level = (k + order) * p
            band = ((dist >= level) & mask).astype(np.uint8)
            cs, _ = cv2.findContours(band, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
            for cnt in cs:
                pts = cnt[:, 0, :].astype(np.float32)
                if len(pts) < 8: continue
                seg = np.linalg.norm(np.diff(np.vstack([pts, pts[:1]]), axis=0), axis=1)
                arc = np.concatenate([[0], np.cumsum(seg)]); L = arc[-1]
                if L < p * 0.8: continue
                n = max(int(round(L / p)), 1); off = self.rng.uniform(0, L / n)
                h = max(int(p * 0.3), 2)
                for t in (off + L * np.arange(n) / n):
                    i = np.searchsorted(arc, t) % len(pts)
                    a, b = pts[(i - h) % len(pts)], pts[(i + h) % len(pts)]
                    ang = math.atan2(b[1] - a[1], b[0] - a[0])
                    c = pts[i].astype(np.float64)
                    if min(c[0], c[1], W - 1 - c[0], W - 1 - c[1]) < p * 0.45: continue   # the icon's edge is no row's guide
                    if free(c, p * 0.72): put(c, ang, min(L / n, p * 1.3), p)
            k += 1
        # Whatever the rows left (tight corners, the middle of a form), filled tile by tile.
        cover = np.zeros((W, W), np.uint8)
        for c, ang, w, h in placed: cv2.circle(cover, (int(c[0]), int(c[1])), int(p * 0.55), 1, -1)
        gy, gx = np.gradient(dist)
        for size, step in ((1.0, 0.5), (0.62, 0.25), (0.42, 0.15)):   # then smaller pieces, cut to plug the holes
            q = p * size
            for y in np.arange(q * 0.5, W, p * step):
                for x in np.arange(q * 0.5, W, p * step):
                    xi, yi = int(x), int(y)
                    if not mask[yi, xi] or cover[yi, xi] or dist[yi, xi] < q * 0.25: continue
                    if free((x, y), q * 0.7):
                        ang = math.atan2(gx[yi, xi], -gy[yi, xi])
                        put((x, y), ang, q, q); cv2.circle(cover, (xi, yi), int(q * 0.55), 1, -1)
        # Each tile claims its pixels in the region, the first laid first (its joints fall where
        # it meets its neighbours, in finish).
        local = np.full((W, W), -1, np.float32)
        n0 = len(self.colors)
        for i, (c, ang, w, h) in enumerate(placed):
            col = np.array(color(c[0] / W, c[1] / W) if callable(color) else color, np.float32)
            if gold: col = col * (0.80 + 0.38 * self.rng.random()) + self.rng.normal(0, 0.015, 3)  # set tilted
            else: col = col * (1 + 0.07 * self.rng.normal()) + self.rng.normal(0, 0.008, 3)
            self.colors.append(np.clip(col, 0, 1)); self.centres.append(c); self.pitches.append(p)
            self.glass.append(0.0 if not glass else (0.30 if gold else 0.45))
        for i in reversed(range(len(placed))):
            c, ang, w, h = placed[i]
            t = np.array([math.cos(ang), math.sin(ang)]); m = np.array([-t[1], t[0]])
            corners = np.array([np.array(c) + sx * w / 2 * t + sy * h / 2 * m
                                for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
            corners += self.rng.normal(0, 0.03, (4, 2)) * p
            cv2.fillPoly(local, [np.round(corners).astype(np.int32)], float(n0 + i))
        here = mask & (local >= 0)
        self.label[here] = local[here]
        if lit is not None:
            # One tile catching the light: the one nearest lit (x, y in 0..1) flashes warm.
            i = min(range(len(placed)), key=lambda k: (placed[k][0][0] / W - lit[0]) ** 2 + (placed[k][0][1] / W - lit[1]) ** 2)
            self.colors[n0 + i] = np.clip(np.array(GOLD) * 0.55 + np.array([0.55, 0.47, 0.30]), 0, 1)
            self.catch.append(n0 + i)
        return placed

    def finish(self):
        lab = self.label.copy()
        # Tiles run off the icon's edge: the rows stop a little short of it, so the strip along the
        # edge takes the nearest tile.
        m = 4 * self.joint; edge = np.ones((W, W), bool); edge[m:-m, m:-m] = False
        _, near = cv2.distanceTransformWithLabels((lab < 0).astype(np.uint8), cv2.DIST_L2, 5,
                                                  labelType=cv2.DIST_LABEL_PIXEL)
        fill = edge & (lab < 0)
        lab[fill] = lab[lab >= 0][near[fill] - 1]
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (self.joint, self.joint))
        inside = (cv2.dilate(lab, k, borderType=cv2.BORDER_REPLICATE) == cv2.erode(lab, k, borderType=cv2.BORDER_REPLICATE)) & (lab >= 0)
        idx = np.where(lab >= 0, lab, 0).astype(np.int32)
        colors = np.array(self.colors, np.float32); centres = np.array(self.centres, np.float32)
        pitch = np.array(self.pitches, np.float32)[idx]; glass = np.array(self.glass, np.float32)[idx]
        d = cv2.distanceTransform(cv2.copyMakeBorder(inside.astype(np.uint8), 1, 1, 1, 1, cv2.BORDER_REPLICATE), cv2.DIST_L2, 5)[1:-1, 1:-1]
        gy, gx = np.gradient(cv2.GaussianBlur(d, (0, 0), 1.0))
        norm = np.sqrt(gx * gx + gy * gy) + 1e-6
        lit = -(gx * LIGHT[0] + gy * LIGHT[1]) / norm            # +1 on an edge facing the light
        bevel = np.clip(1 - d / (pitch * 0.16), 0, 1) ** 1.5
        across = ((XX * W - centres[idx, 0]) * LIGHT[0] + (YY * W - centres[idx, 1]) * LIGHT[1]) / pitch
        body = colors[idx] * (1 + (glass * lit * bevel + 0.25 * glass * across)[..., None]) \
            + (0.06 * np.maximum(lit, 0) * bevel * (glass > 0))[..., None]
        img = np.where(inside[..., None], np.clip(body, 0, 1), self.bed)
        for over in self.overlays: img = over(img)
        for i in self.catch: self.glow[lab == i] = 1.0
        glow = cv2.GaussianBlur(self.glow, (0, 0), 26 * S); glow /= max(glow.max(), 1e-6)
        img = img + glow[..., None] * np.array([0.30, 0.22, 0.08], np.float32)
        return cv2.resize(np.clip(img, 0, 1), (N, N), interpolation=cv2.INTER_AREA)


# Shapes, as boolean masks at W px; coordinates in 0..1 of the icon.
YY, XX = np.mgrid[0:W, 0:W].astype(np.float32) / W
def disc(cx, cy, r): return (XX - cx) ** 2 + (YY - cy) ** 2 < r * r
def below(f): return YY > f(XX)
def poly(points):
    m = np.zeros((W, W), np.uint8)
    cv2.fillPoly(m, [np.round(np.array(points) * W).astype(np.int32)], 1)
    return m.astype(bool)
def band(mask, width):
    """The row along a mask's edge, inside it: an outline, width px (at 1024) wide."""
    k = max(int(width * S), 1)
    return mask & ~cv2.erode(mask.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1))).astype(bool)
def star(cx, cy, r_out, r_in, points=8, turn=0.0):
    pts = [(cx + (r_out if k % 2 == 0 else r_in) * math.cos(turn + math.pi * k / points),
            cy + (r_out if k % 2 == 0 else r_in) * math.sin(turn + math.pi * k / points)) for k in range(2 * points)]
    return poly(pts)
def gradient(top, bottom, y0=0.0, y1=1.0):
    top, bottom = np.array(top), np.array(bottom)
    return lambda x, y: top + (bottom - top) * min(max((y - y0) / (y1 - y0), 0), 1)


# The night of Paint by Moonlight's icon, re-laid: crescent, sky, two hills, the near ground.
def night(wall, moon=(0.66, 0.32, 0.19), crescent_cut=(0.085, -0.06, 0.92), hills=True, near=None,
          pitch=34, stars=((0.21, 0.20, 0.075), (0.36, 0.42, 0.045), (0.12, 0.40, 0.035)), within=None):
    L = wall.light
    everything = np.ones((W, W), bool) if within is None else within
    mx, my, mr = moon
    cx, cy, ck = crescent_cut
    crescent = disc(mx, my, mr) & ~disc(mx + cx, my + cy, mr * ck)
    far = below(lambda x: 0.66 - 0.075 * np.sin(2.6 * x + 0.9)) if hills else np.zeros((W, W), bool)
    mid = below(lambda x: 0.75 + 0.06 * np.sin(3.2 * x - 0.2)) if hills else np.zeros((W, W), bool)
    near = near if near is not None else below(lambda x: 0.86 + 0.05 * np.sin(4.0 * x - 2.4))
    sparks = np.zeros((W, W), bool)
    for sx, sy, sr in stars: sparks |= star(sx, sy, sr, sr * 0.28, points=4)
    sky = everything & ~far & ~mid & ~near & ~crescent & ~sparks
    # The motifs first, each with its outline row, then the ground rows that follow them.
    wall.lay(crescent & everything, pitch * 0.62, GOLD, gold=True, lit=(mx - mr * 0.75, my - mr * 0.35))
    wall.lay(sparks & everything, pitch * 0.42, SILVER)
    skyc = gradient((0.075, 0.095, 0.215) if not L else (0.10, 0.14, 0.30), SKY if not L else (0.20, 0.28, 0.52), 0.0, 0.62)
    wall.lay(sky, pitch * 0.82, skyc)
    if hills:
        wall.lay(far & ~mid & everything, pitch * 0.82, gradient((0.17, 0.17, 0.38), (0.27, 0.19, 0.42), 0.55, 0.78))
        mid_only = mid & ~near & everything
        wall.lay(band(mid_only, pitch * 0.42), pitch * 0.42, WINE, guide=~mid_only)
        wall.lay(mid_only & ~band(mid_only, pitch * 0.42), pitch * 0.82, gradient((0.48, 0.25, 0.44), PORPHYRY, 0.7, 0.9))
    near &= everything
    edge = band(near, pitch * 0.40)
    wall.lay(edge, pitch * 0.40, INK, glass=False, guide=~near)
    return near & ~edge


def moonlight(wall):
    ground = night(wall)
    wall.lay(ground, 30, LIME if wall.light else (0.86, 0.83, 0.76), glass=False)


def delta(wall):
    near = below(lambda x: 0.70 + 0.07 * np.sin(4.0 * x - 2.4))
    ground = night(wall, moon=(0.68, 0.27, 0.15), hills=False, near=near,
                   stars=((0.22, 0.18, 0.065), (0.40, 0.36, 0.04), (0.12, 0.44, 0.03)))
    # Δʹ, the Greek numeral four, where Paint by Moonlight writes 4.
    cx, cy, s = 0.47, 0.86, 0.105
    outer = poly([(cx, cy - s), (cx + s * 0.95, cy + s * 0.85), (cx - s * 0.95, cy + s * 0.85)])
    inner = poly([(cx, cy - s * 0.30), (cx + s * 0.52, cy + s * 0.52), (cx - s * 0.52, cy + s * 0.52)])
    glyph = (outer & ~inner) | poly([(cx + s * 1.18, cy - s * 0.95), (cx + s * 1.40, cy - s * 0.95), (cx + s * 1.18, cy - s * 0.30), (cx + s * 1.06, cy - s * 0.30)])
    glyph &= ground
    wall.lay(glyph, 16, INK, glass=False)
    wall.lay(ground & ~glyph, 26, LIME if wall.light else (0.86, 0.83, 0.76), glass=False)


def star_(wall):
    L = wall.light
    big = star(0.5, 0.5, 0.33, 0.15, points=8, turn=math.pi / 8)
    smalls = np.zeros((W, W), bool)
    for k in range(8):
        a = math.pi / 8 + k * math.pi / 4
        smalls |= star(0.5 + 0.45 * math.cos(a), 0.5 + 0.45 * math.sin(a), 0.055, 0.02, points=4, turn=a)
    heart = disc(0.5, 0.5, 0.065)
    wall.lay(band(big, 15), 15, (0.47, 0.34, 0.12), gold=True, guide=~big)
    wall.lay(big & ~band(big, 15) & ~heart, 28, GOLD, gold=True, lit=(0.36, 0.38))
    wall.lay(heart, 22, SILVER)
    wall.lay(smalls, 14, GOLD, gold=True)
    field = ~big & ~smalls
    wall.lay(field, 30, gradient((0.15, 0.20, 0.42) if L else LAPIS, (0.10, 0.13, 0.28) if L else DEEP, 0.2, 0.9),
             guide=big)


def tessera(wall):
    L = wall.light
    s = 0.30; cx, cy = 0.53, 0.55
    socket = poly([(cx - s / 2, cy - s / 2), (cx + s / 2, cy - s / 2), (cx + s / 2, cy + s / 2), (cx - s / 2, cy + s / 2)])
    field = ~socket
    blue = np.array((0.17, 0.23, 0.46) if L else LAPIS)
    wall.lay(field, 56, lambda x, y: blue * (1.22 - 0.55 * math.hypot(x - cx, y - cy)), guide=socket)
    # The gold one lifted over its place, turned as the hand holds it: its shadow on the rows, a
    # bevelled face, and the catch of light crossing it.
    c = np.array([cx - 0.035, cy - 0.055]) * W; side = s * W * 0.92; ang = 0.2
    t = np.array([math.cos(ang), math.sin(ang)]); m = np.array([-t[1], t[0]])
    corners = lambda k: np.array([c + sx * side * k / 2 * t + sy * side * k / 2 * m
                                  for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    q = corners(1)
    def lift(img):
        shadow = np.zeros((W, W), np.float32)
        cv2.fillPoly(shadow, [np.round(q + np.array([0.05, 0.075]) * W).astype(np.int32)], 1.0)
        shadow = cv2.GaussianBlur(shadow, (0, 0), 9 * S)
        img = img * (1 - 0.75 * shadow)[..., None]
        face = np.zeros((W, W), np.float32)
        cv2.fillPoly(face, [np.round(q).astype(np.int32)], 1.0, lineType=cv2.LINE_AA)
        u = ((XX - c[0] / W) * 0.8 + (YY - c[1] / W) * 0.6) / (s * 0.9)      # along the light, -0.5..0.5
        gold = np.array(GOLD, np.float32) * (0.78 + 0.12 * np.sin(XX * 61 + YY * 37))[..., None]
        sheen = np.exp(-((u + 0.12) / 0.16) ** 2)[..., None] * np.array([0.40, 0.34, 0.18], np.float32)
        body = gold + sheen
        for k in range(4):   # the bevel: lit on its upper-left sides, shaded on its lower-right
            a, b = q[k], q[(k + 1) % 4]
            n = np.array([b[1] - a[1], a[0] - b[0]]); n /= np.linalg.norm(n)
            lit = -(n @ LIGHT)
            e = np.zeros((W, W), np.float32)
            cv2.line(e, tuple(map(int, a)), tuple(map(int, b)), 1.0, int(side * 0.07), cv2.LINE_AA)
            body = body * (1 + 0.45 * lit * e[..., None]) + 0.06 * max(lit, 0) * e[..., None]
        return img * (1 - face[..., None]) + np.clip(body, 0, 1) * face[..., None]
    wall.overlays.append(lift)
    cv2.fillPoly(wall.glow, [np.round(corners(0.5)).astype(np.int32)], 1.0)


def nimbus(wall):
    L = wall.light
    cx, cy, r = 0.5, 0.5, 0.34
    halo = disc(cx, cy, r)
    edge = band(halo, 22)
    head = disc(cx, cy, r * 0.60)
    moon = disc(cx + 0.01, cy, r * 0.42) & ~disc(cx + 0.075, cy - 0.05, r * 0.40)
    wall.lay(moon, 18, LIME if L else (0.86, 0.83, 0.76), glass=False)
    wall.lay(head & ~moon, 24, (0.10, 0.13, 0.27) if L else DEEP, guide=moon)
    wall.lay(edge, 22, RED, guide=~halo)
    wall.lay(halo & ~edge & ~head, 26, GOLD, gold=True, lit=(cx - r * 0.55, cy - r * 0.55))
    wall.lay(~halo, 34, gradient((0.16, 0.21, 0.44) if L else LAPIS, (0.11, 0.14, 0.30) if L else DEEP, 0.1, 0.9), guide=halo)


def apse(wall):
    L = wall.light
    x0, x1, base, top = 0.22, 0.78, 0.93, 0.41
    r = (x1 - x0) / 2
    arch = (disc(0.5, top, r) & (YY <= top)) | ((XX > x0) & (XX < x1) & (YY >= top) & (YY < base))
    frame = (disc(0.5, top, r + 0.065) & (YY <= top)) | ((XX > x0 - 0.065) & (XX < x1 + 0.065) & (YY >= top) & (YY < base))
    border = frame & ~arch
    inside_edge = band(arch, 14)
    # The night through the arch, then its rows of red and gold, then the plaster wall round it.
    ground = night(wall, moon=(0.57, 0.40, 0.13), crescent_cut=(0.06, -0.045, 0.92), pitch=26, within=arch & ~inside_edge,
                   near=below(lambda x: 0.835 + 0.02 * np.sin(11 * x - 2.0)),
                   stars=((0.37, 0.36, 0.05), (0.45, 0.56, 0.03)))
    wall.lay(ground, 22, LIME if L else (0.86, 0.83, 0.76), glass=False)
    wall.lay(inside_edge, 14, INK, glass=False, guide=~arch)
    red = band(frame, 22) & border
    wall.lay(red, 22, RED, guide=~frame)
    wall.lay(border & ~red, 24, GOLD, gold=True, guide=~frame, lit=(0.30, 0.20))
    wall.lay(~frame, 34, (0.88, 0.85, 0.78) if L else (0.20, 0.18, 0.15), glass=False, guide=frame)


CANDIDATES = {"moonlight": moonlight, "delta": delta, "star": star_, "tessera": tessera, "nimbus": nimbus, "apse": apse}


def tinted(dark):
    """iOS 18's tinted appearance takes a grayscale picture: luminance, stretched so the motif is
    near white and the bed near black."""
    y = dark @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    lo, hi = np.percentile(y, 2), np.percentile(y, 99.5)
    return np.clip((y - lo) / (hi - lo), 0, 1) ** 0.9


def save(img, path):
    if img.ndim == 2: img = np.repeat(img[..., None], 3, axis=2)    # gray, in RGB as Paint by Moonlight's
    cv2.imwrite(path, cv2.cvtColor((img * 255 + 0.5).astype(np.uint8), cv2.COLOR_RGB2BGR))


def catalog(out, assets, name="apse"):
    """Puts a drawn candidate (in out) into the app's asset catalog as its icon, AppIcon.appiconset
    in three appearances. Apse is the app's (Paul, October 28)."""
    import json
    from PIL import Image
    d = os.path.join(assets, "AppIcon.appiconset"); os.makedirs(d, exist_ok=True)
    images = []
    for suffix, look in (("", None), ("-Dark", "dark"), ("-Tinted", "tinted")):
        fn = f"AppIcon{suffix}.png"
        # Indexed (octree, 256 colours) and the tinted one gray: about a quarter of the bytes,
        # no difference to see at any size the icon is shown.
        im = Image.open(os.path.join(out, f"{name}{suffix.lower()}.png")).convert("RGB")
        im = im.convert("L") if look == "tinted" else im.quantize(256, method=Image.Quantize.FASTOCTREE)
        im.save(os.path.join(d, fn), optimize=True)
        image = {"filename": fn, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if look: image = {"appearances": [{"appearance": "luminosity", "value": look}], **image}
        images.append(image)
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)


if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    if len(sys.argv) > 3 and sys.argv[2] == "--catalog": catalog(out, *sys.argv[3:5]); sys.exit()
    for name in sys.argv[2:] or CANDIDATES:
        for light in (True, False):
            wall = Wall(name, light); CANDIDATES[name](wall); img = wall.finish()
            save(img, os.path.join(out, f"{name}.png" if light else f"{name}-dark.png"))
            if not light: save(tinted(img), os.path.join(out, f"{name}-tinted.png"))
        print(name)
