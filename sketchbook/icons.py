"""icons.py <out-dir>: alternatives to the provisional icon (icon.py's halo), 1024 px each, for Paul to
pick from. Each is laid as tesserae with a lit upper-left edge, and gold only where one catches the light.
  stars.png   Galla Placidia's vault: gold stars on lapis, in rings, as in the mausoleum at Ravenna (5th c.).
  tessera.png One gold tessera being set into rows of dark lapis that curve round it (andamento).
  rows.png    Rows of lapis laid round an arch, the last row half set, its newest tile lit.
Deterministic: seeded by name."""
import sys, os, math
import numpy as np, cv2

N = 1024; S = 4
LAPIS, DEEP, GOLD = (0.12, 0.16, 0.32), (0.08, 0.10, 0.20), (0.82, 0.64, 0.26)
BED = (0.07, 0.065, 0.06)

def canvas():
    img = np.zeros((N * S, N * S, 3), np.float32); img[:] = BED; return img

def tile(img, centre, size, angle, color, rng, jitter=0.06, lit=False, raised=0.0, outline=False):
    c = np.array(centre) * S; h = size * S / 2
    t = np.array([math.cos(angle), math.sin(angle)]); m = np.array([-t[1], t[0]])
    wob = rng.normal(0, 0.06, (4, 2)) * h
    poly = np.array([c + sx * h * t + sy * h * m for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]) + wob
    col = np.clip(np.array(color) * (1 + jitter * rng.normal()), 0, 1)
    if lit: col = np.clip(col * 0.55 + np.array([0.55, 0.47, 0.30]), 0, 1)
    if raised:
        sh = np.round(poly + raised * S * np.array([0.6, 0.9])).astype(np.int32)
        cv2.fillPoly(img, [sh], (0.02, 0.02, 0.02), lineType=cv2.LINE_AA)
    q = np.round(poly).astype(np.int32)
    if outline:
        # Not set yet: only its place, drawn on the bed.
        cv2.polylines(img, [q], True, (0.16, 0.15, 0.14), int(1.5 * S), cv2.LINE_AA); return
    cv2.fillPoly(img, [q], col.tolist(), lineType=cv2.LINE_AA)
    # A lit upper-left edge, a shaded lower-right one: pick by each edge's outward normal.
    for k in range(4):
        a, b = q[k], q[(k + 1) % 4]
        n = np.array([b[1] - a[1], a[0] - b[0]], float); n /= np.linalg.norm(n) + 1e-6
        light = -(n @ np.array([-0.6, -0.8]))
        shade = (col * (1 + 0.35 * light) + 0.04 * max(light, 0)).clip(0, 1)
        cv2.line(img, tuple(map(int, a)), tuple(map(int, b)), shade.tolist(), int(2.2 * S), cv2.LINE_AA)
    if lit:
        # The catch of light: a soft glow round the face, warm.
        glow = np.zeros(img.shape[:2], np.float32)
        cv2.fillPoly(glow, [q], 1.0, lineType=cv2.LINE_AA)
        glow = cv2.GaussianBlur(glow, (0, 0), size * S * 0.5)
        img += glow[..., None] * np.array([0.35, 0.26, 0.10], np.float32)

def save(img, path):
    out = cv2.resize(np.clip(img, 0, 1), (N, N), interpolation=cv2.INTER_AREA)
    cv2.imwrite(path, cv2.cvtColor((out * 255).astype(np.uint8), cv2.COLOR_RGB2BGR))

def rings(img, rng, centre, r0, r1, pitch, color, skip=None):
    r = r0
    while r < r1:
        n = max(int(2 * math.pi * r / pitch), 6)
        for k in range(n):
            a = 2 * math.pi * (k + 0.5 * (int(r / pitch) % 2)) / n
            p = (centre[0] + r * math.cos(a), centre[1] + r * math.sin(a))
            if skip and skip(p): continue
            tile(img, p, pitch - 7, a + math.pi / 2, color, rng)
        r += pitch

def stars(out):
    rng = np.random.default_rng(425); img = canvas(); c = (N / 2, N / 2); pitch = 30
    # Eight-pointed stars of gold tesserae (the arms' lengths by star), then the lapis laid round them.
    stars = [(c, 3)]
    for ring_r, count, arm in ((265, 8, 2), (455, 12, 2)):
        for k in range(count):
            a = 2 * math.pi * (k + 0.5 * (count == 12)) / count
            stars.append(((c[0] + ring_r * math.cos(a), c[1] + ring_r * math.sin(a)), arm))
    near = lambda p: min(math.dist(p, s) - (n + 0.6) * pitch * 0.62 for s, n in stars) < 0
    rings(img, rng, c, pitch * 0.6, N * 0.75, pitch, LAPIS, skip=near)
    for i, (s, n) in enumerate(stars):
        tile(img, s, pitch * 0.7, math.pi / 4, (0.95, 0.92, 0.82) if i == 0 else GOLD, rng)
        for k in range(8):
            a = k * math.pi / 4
            for j in range(1, n + 1):
                r = j * pitch * 0.62
                tile(img, (s[0] + r * math.cos(a), s[1] + r * math.sin(a)), pitch * (0.56 - 0.06 * j), a, GOLD, rng,
                     lit=(i == 2 and k == 5 and j == n))
    save(img, out)

def tessera(out):
    rng = np.random.default_rng(547); img = canvas(); c = (N * 0.54, N * 0.48); pitch = 74
    rings(img, rng, c, pitch * 3.2, N * 1.2, pitch, DEEP)
    # The rows nearest the gold one are lapis, and lighter: the light falls there.
    rings(img, rng, c, pitch * 1.2, pitch * 3.2, pitch, LAPIS)
    tile(img, (c[0] - 8, c[1] - 12), pitch * 1.15, 0.22, GOLD, rng, jitter=0, lit=True, raised=12)
    save(img, out)

def rows(out):
    rng = np.random.default_rng(330); img = canvas(); pitch = 46
    c = (N / 2, N * 1.03)
    last_row = 9; r = pitch * 1.6; row = 0
    while r < N * 1.45:
        n = max(int(math.pi * r / pitch), 3)
        color = GOLD if row == 5 else (LAPIS if row % 2 else DEEP)
        for k in range(n):
            a = math.pi + math.pi * (k + 0.5) / n
            p = (c[0] + r * math.cos(a), c[1] + r * math.sin(a))
            done = row < last_row or (row == last_row and k < n * 0.55)
            newest = row == last_row and k == int(math.ceil(n * 0.55)) - 1
            tile(img, p, pitch - 7, a + math.pi / 2, GOLD if newest else color, rng,
                 lit=newest, raised=8 if newest else 0, outline=not done)
        r += pitch; row += 1
    save(img, out)

d = sys.argv[1]; os.makedirs(d, exist_ok=True)
stars(os.path.join(d, "stars.png")); tessera(os.path.join(d, "tessera.png")); rows(os.path.join(d, "rows.png"))
