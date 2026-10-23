"""making_of.py <design.json> <photo> <contours.pgm> <features.json | -> <out dir> [--stills] [--fps N]:
the making-of show, a mosaic set the way the old workshops set one, with the technique of each step
named on a card (the cards' words and their sources: docs/making-of.md).

The show is a pure function of the time: `Show(...).frame(t)` draws the frame at t, so it can seek,
hold still and be cut into stills; the same inputs and seed give the same show. Its scenes:

  model     the picture the mosaic is made from
  smalti    the glass: each of the design's paints a cake of glass, cooling, then cut into tesserae
  sinopia   the drawing on the bed: the contour model's strong lines, in red earth, stroke by stroke
  bed       the painted setting bed spreading over the drawing (the colour under the joints)
  face      the face first, in the finest pieces: its features' rows, the eyes as pieces, then the
            fine tesserae of the face (only when the design has a face)
  outlines  the dark rows that outline the figure (the strands), longest first
  andamento the rows that echo them, ring after ring, and the field
  light     the finished mosaic under a moving light: each tile set at its own small tilt
  hold      the finished mosaic, and the closing card

A tile is never painted on: it drops in from above, a little large, its shadow under it, and
settles; it catches a warm light the moment it lands (gold only where a tile catches the light).

<design.json> is mosaic_faces.py's design (its tiles in the order they were placed, each with
"strand" and "feature"); <features.json> is sketchbook/features.py's, the face's box and eyes, or -
for a picture without a face. Writes <out>/making-of.mp4 (with ffmpeg) and <out>/still-<scene>.png;
--stills writes only the stills. Environment: META ({"title", "credit"} for the model's card), SINOPIA
(red, the earth of Ravenna's drawings, or blue, the indigo of Hagia Sophia's: an option). Needs numpy, opencv-python-headless, scipy, scikit-image and Pillow.
"""
import json, math, os, subprocess, sys
import numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter
from skimage.morphology import skeletonize, remove_small_objects

# Ravenna's colours (App/Ravenna/Theme.swift): the dark of an apse, lime-plaster words, gold kept for light.
GROUND = np.array([0.082, 0.075, 0.059], np.float32)
PLASTER = np.array([0.914, 0.886, 0.827], np.float32)
MUTED = np.array([0.651, 0.612, 0.537], np.float32)
GOLD = np.array([0.788, 0.635, 0.290], np.float32)
LIME = np.array([0.84, 0.81, 0.75], np.float32)       # the bare lime of the bed
OCHRE = np.array([0.60, 0.25, 0.16], np.float32)      # sinopia, red earth (Ravenna, Classe)
INDIGO = np.array([0.20, 0.25, 0.48], np.float32)     # or indigo blue (Constantinople, Hagia Sophia)
FW, FH = 720, 1280                                    # the frame: a phone held upright
BOX = (24, 40, 696, 940)                              # where the picture sits in it
BAND = 968                                            # the card's top

SCENES = [("model", 3.0), ("smalti", 5.5), ("sinopia", 5.0), ("bed", 3.5), ("face", 6.5),
          ("outlines", 5.0), ("andamento", 9.0), ("light", 5.5), ("hold", 5.0)]
SET_TIME = 0.42                                       # seconds a tile takes to drop and settle

# The cards. Their words are docs/making-of.md's, where each claim has its source.
CARDS = {
    "model": ("The model", "{title}", "{credit}"),
    "smalti": ("Smalti", "Glass coloured with copper, cobalt, iron, antimony and tin, poured as a cake, then cut into tesserae.",
               "Anonymous glassmakers; where they worked is still unknown"),
    "sinopia": ("The drawing on the bed", "The design is drawn on the plaster first. At Classe, the drawing under the apse shows a different design from the one that was set.",
                "Sant'Apollinare in Classe, Ravenna, 6th century; anonymous"),
    "bed": ("The painted bed", "Each fresh patch of the bed is painted in full colour, \u201ca finished painting in true fresco\u201d, before a tile is set.",
            "Hagia Sophia, recorded by Thomas Whittemore, 1942"),
    "face": ("Opus vermiculatum", "The face in the smallest pieces, the eyes set as pieces of their own, row curving round row.",
             "As in the panels Dioskourides of Samos signed in tiny tesserae, Pompeii"),
    "outlines": ("The outlines", "Rows set first along the drawing's lines: \u201cthe outline of the wing is shown by a row\u201d.",
                 "Hagia Sophia, the Deesis; anonymous"),
    "andamento": ("Andamento", "Each row carries on the curve of the one before, so the rows show how the form moves.",
                  "Italian for \u2018the way it goes\u2019, a workshop word, not an ancient one"),
    "light": ("Set at a tilt", "Gold and glass set at slightly different angles, each catching the light its own way.",
              "Hagia Sophia; the Nativity, Bethlehem"),
    "hold": ("The makers", "A few names survive: Sosus of Pergamon, Gnosis at Pella, Dioskourides of Samos, Ephraim at Bethlehem. Most mosaicists are anonymous.",
             "Pliny, Natural History 36.184, and the works they signed"),
}

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def oklab(rgb):
    l = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return np.cbrt(np.clip(l @ M1.T, 0, None)) @ M2.T
def srgb(lab):
    lin = np.clip((lab @ np.linalg.inv(M2).T) ** 3 @ np.linalg.inv(M1).T, 0, 1)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)
def ease(u): u = min(max(u, 0.0), 1.0); return u * u * (3 - 2 * u)
def font(size, italic=False, bold=False):
    names = {(0, 0): "LiberationSerif-Regular", (1, 0): "LiberationSerif-Italic", (0, 1): "LiberationSerif-Bold"}
    for d in ("/usr/share/fonts/truetype/liberation", "/Library/Fonts", "/System/Library/Fonts/Supplemental"):
        p = f"{d}/{names[(int(italic), int(bold))]}.ttf"
        if os.path.exists(p): return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)


class Show:
    def __init__(self, design, photo, contours, features, meta, seed=547, sinopia="red"):
        self.ink = OCHRE if sinopia == "red" else INDIGO
        d = json.load(open(design))
        self.meta = meta
        self.photo = cv2.cvtColor(cv2.imread(photo), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
        ph, pw = self.photo.shape[:2]
        k = min((BOX[2] - BOX[0]) / pw, (BOX[3] - BOX[1]) / ph)
        self.k, self.w, self.h = k, round(pw * k), round(ph * k)
        self.x0 = (FW - self.w) // 2; self.y0 = BOX[1] + ((BOX[3] - BOX[1]) - self.h) // 2
        self.photo_f = cv2.resize(self.photo, (self.w, self.h), interpolation=cv2.INTER_AREA)
        self.pal = np.array(d["palette"], np.float32)
        tiles = d["tiles"]
        self.polys = [np.array(t["corners"], np.float64) * k for t in tiles]
        self.cent = np.array([p.mean(0) for p in self.polys])
        self.paint = np.array([t["paint"] for t in tiles])
        self.pitch = d["pitch"] / d["scale"] * k
        n = len(tiles)
        feat = json.load(open(features)) if features != "-" else None
        # Each tile's scene, from the order mosaic_faces.py placed them in.
        scene = np.full(n, "andamento", object)
        strand = np.array([t["strand"] for t in tiles]); kind = [t.get("feature") for t in tiles]
        scene[strand] = "outlines"
        self.box = None
        if feat:
            ne = len(feat["eyes"])
            bx = np.array(feat["box"], float) * k; self.box = bx
            # The face: the oval inside the features' box.
            inbox = (((self.cent[:, 0] - (bx[0] + bx[2]) / 2) / ((bx[2] - bx[0]) / 2)) ** 2
                     + ((self.cent[:, 1] - (bx[1] + bx[3]) / 2) / ((bx[3] - bx[1]) / 2)) ** 2) <= 1
            scene[inbox] = "face"
            for i in range(n):
                if kind[i]: scene[i] = "face"
            scene[:ne] = "face"; scene[n - ne:] = "face"
            self.eye = np.zeros(n, bool); self.eye[:ne] = True; self.eye[n - ne:] = True
        else:
            self.eye = np.zeros(n, bool)
        self.scene_of = scene
        self.stone = scene == "face"
        # The order a scene's tiles are set in: the features' rows, then the eyes (iris, then pupil), then
        # the face's field; elsewhere the order they were placed.
        rank = np.arange(n, dtype=float)
        if feat:
            fr = np.array([1.0 if kind[i] in ("dark", "mid", "tone") else 2.0 if self.eye[i] else 3.0 for i in range(n)])
            rank = rank + fr * n
        self.start = np.full(n, np.inf)
        self.times = {}
        t = 0.0
        for name, dur in SCENES:
            if name == "face" and not feat: dur = 0.0
            self.times[name] = (t, dur); t += dur
        self.duration = t
        for name in ("face", "outlines", "andamento"):
            s, dur = self.times[name]
            idx = np.where(scene == name)[0]
            if not len(idx): continue
            idx = idx[np.argsort(rank[idx], kind="stable")]
            u = np.linspace(0, 1, len(idx))
            # Slow to begin, as the first rows are found, then quicker as the setters fill in.
            u = u ** 0.8 if name != "andamento" else u ** 0.65
            self.start[idx] = s + 0.15 * dur + u * (0.72 * dur - SET_TIME)
        self.rng = np.random.default_rng(seed)
        self._build_layers(contours, feat)

    # The layers the frames are made from, built once.
    def _build_layers(self, contours, feat):
        w, h, n = self.w, self.h, len(self.polys)
        ids = np.zeros((h, w), np.int32)
        q4 = [np.round(p * 4).astype(np.int32) for p in self.polys]
        for i, q in enumerate(q4): cv2.fillPoly(ids, [q], i + 1, shift=2)
        self.ids = ids
        col = self.pal[self.paint]
        lab = oklab(col.astype(float))
        lab = lab + self.rng.normal(0, 1, (n, 3)) * [0.009, 0.003, 0.003]       # each batch of glass a little different
        self.body = srgb(lab).astype(np.float32)
        L, C = lab[:, 0], np.hypot(lab[:, 1], lab[:, 2]); hue = np.degrees(np.arctan2(lab[:, 2], lab[:, 1]))
        self.gold = (L > 0.55) & (C > 0.07) & (hue > 55) & (hue < 105)
        mask = (ids > 0).astype(np.float32)
        img = np.vstack([np.zeros((1, 3), np.float32), self.body])[ids]
        s = self.pitch * 0.5
        blur = gaussian_filter(img * mask[..., None], (s, s, 0)) / np.maximum(gaussian_filter(mask, s), 1e-3)[..., None]
        # The painted bed: the colours of the tiles that will cover it, darker and greyer (render.py's bed).
        self.bed = srgb(oklab(blur.astype(float)) * [0.8, 0.65, 0.65]).astype(np.float32)
        # The set tiles in the glass-and-stone finish (render.py's C): a lit face, a bevel, glass glints.
        dist = cv2.distanceTransform((ids > 0).astype(np.uint8), cv2.DIST_L2, 5)
        gy, gx = np.gradient(gaussian_filter(dist, 0.8))
        lit = -(gx * -0.6 + gy * -0.8) / (np.hypot(gx, gy) + 1e-6)
        st = np.r_[False, self.stone][ids]
        b = np.where(st, 0.16, 0.24) * self.pitch
        edge = np.clip(1 - dist / np.maximum(b, 1e-3), 0, 1) ** 1.5
        shade = 1 + np.where(st, 0.16, 0.34) * lit * edge - np.where(st, 0.05, 0.10) * edge
        shade *= 1 + np.where(st, 0.035, 0.012) * gaussian_filter(self.rng.normal(0, 1, (h, w)), 0.7)
        self.tilt = self.rng.uniform(-1, 1, (n, 2)) * np.where(self.stone, 0.25, 1.0)[:, None]
        self.tilt[self.gold] *= 1.6
        shade *= np.r_[1.0, 1 + 0.12 * self.tilt[:, 0] * self.gold][ids]
        glint = np.clip(lit, 0, 1) * np.clip(1 - dist / (0.45 * self.pitch), 0, 1) * (~st) * (ids > 0)
        self.set_img = (img * shade[..., None] + 0.10 * glint[..., None] ** 3).astype(np.float32)
        self.mask = mask
        # The sinopia: the contour model's strong lines (mosaic_faces.py's cartoon), each pixel with the
        # moment the brush reaches it: the lines nearest the face first, each followed from one end.
        dr = cv2.imread(contours, cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255
        dr = cv2.resize(dr, (w, h), interpolation=cv2.INTER_AREA)
        # A little more of the drawing than becomes strands: the cartoon carries more than its outlines.
        cut = np.full((h, w), 0.55, np.float32)
        if self.box is not None:
            x0, y0, x1, y1 = np.round(self.box).astype(int); cut[max(y0, 0):y1, max(x0, 0):x1] = 0.4
        strong = gaussian_filter(dr, 2.0 * self.k) > cut
        for ln in (feat["lines"] if feat else []):
            pts = np.round(np.array(ln["pts"]) * self.k).astype(np.int32)
            cv2.polylines(strong.view(np.uint8), [pts], ln["kind"] == "eye", 1, 1)
        strong = remove_small_objects(strong, max_size=int(self.pitch * 3))
        sk = skeletonize(strong)
        nlab, lab_ = cv2.connectedComponents(sk.astype(np.uint8), connectivity=8)
        order = np.full((h, w), np.inf, np.float32)
        # The figure first, from its face outward, the frame last.
        fc = ((self.box[0] + self.box[2]) / 2, (self.box[1] + self.box[3]) / 2) if self.box is not None else (w / 2, h / 2)
        def far(c):
            ys, xs = np.nonzero(lab_ == c); return np.hypot(xs - fc[0], ys - fc[1]).mean()
        comps = sorted(range(1, nlab), key=far)
        total = sk.sum(); done = 0
        for c in comps:
            ys, xs = np.nonzero(lab_ == c)
            pts = set(zip(ys.tolist(), xs.tolist()))
            deg = {p: sum((p[0] + dy, p[1] + dx) in pts for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx) for p in pts}
            first = min(pts, key=lambda p: (deg[p], p))
            seen = {first}; q = [first]; k = 0
            while q:                       # breadth first from an end: the line drawn outward from where the brush began
                nq = []
                for p in q:
                    order[p] = (done + k) / total; k += 1
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            r = (p[0] + dy, p[1] + dx)
                            if r in pts and r not in seen: seen.add(r); nq.append(r)
                q = nq
            done += len(pts)
        self.sinopia_order = order
        # The light sweeping the finished mosaic: where each tile is along the sweep.
        self.sweep = (self.cent[:, 0] / w * 0.55 + self.cent[:, 1] / h * 0.45)

    def scene(self, t):
        for name, dur in SCENES:
            s, d = self.times[name]
            if d and t < s + d: return name, (t - s) / d
        return "hold", 1.0

    def under(self, t):
        """What lies under the tiles at t: lime, the sinopia drawn so far, the painted bed laid so far."""
        s, d = self.times["sinopia"]
        prog = np.clip((t - s - 0.4) / (d - 1.0), 0, 1)
        line = (self.sinopia_order <= prog).astype(np.float32)
        line = gaussian_filter(cv2.dilate(line, np.ones((2, 2), np.uint8)), 0.7)
        bs, bd = self.times["bed"]
        # The bed laid down the wall in a soft front, a little uneven, as plaster is.
        yy = np.linspace(0, 1, self.h)[:, None] + 0.04 * np.sin(np.linspace(0, 9, self.w))[None, :]
        front = (t - bs - 0.2) / (bd - 0.6) * 1.15
        laid = np.clip((front - yy) / 0.08, 0, 1)
        base = LIME * (1 - laid[..., None]) + self.bed * laid[..., None]
        ink = np.clip(line * (1 - 0.82 * laid), 0, 1)[..., None]
        return base * (1 - 0.85 * ink) + self.ink * 0.85 * ink

    def mosaic(self, t):
        pic = self.under(t)
        settled = np.r_[False, self.start + SET_TIME <= t]
        m = settled[self.ids]
        pic = np.where(m[..., None], self.set_img, pic)
        flying = np.where((self.start <= t) & (self.start + SET_TIME > t))[0]
        if not len(flying): return pic
        lifts = {}
        shadow = np.zeros((self.h, self.w), np.float32)
        for i in flying:
            e = 1 - (1 - (t - self.start[i]) / SET_TIME) ** 3
            lift = (1 - e) * self.pitch * 0.9; lifts[i] = (e, lift)
            c, p = self.cent[i], self.polys[i]
            q = (p - c) * (1 + 0.15 * (1 - e)) + c + [lift * 0.3, lift * 0.4]
            cv2.fillPoly(shadow, [np.round(q * 4).astype(np.int32)], 0.15 + 0.3 * (1 - e), shift=2, lineType=cv2.LINE_AA)
        pic = pic * (1 - gaussian_filter(shadow, 1.2)[..., None])
        out = (np.clip(pic, 0, 1) * 255).astype(np.uint8)
        for i in flying:
            e, lift = lifts[i]
            u = (t - self.start[i]) / SET_TIME
            c, p = self.cent[i], self.polys[i]
            q = np.round(((p - c) * (1 + 0.45 * (1 - e)) + c - [0, lift]) * 4).astype(np.int32)
            # It catches a warm light as it lands, gold for a moment, glass more than stone.
            glow = math.exp(-((u - 0.82) / 0.12) ** 2) * (0.35 if self.stone[i] else 0.6)
            col = np.clip((self.body[i] * (1 - glow) + GOLD * 1.25 * glow) * 255, 0, 255)
            cv2.fillPoly(out, [q], tuple(int(v) for v in col), shift=2, lineType=cv2.LINE_AA)
            cv2.polylines(out, [q], True, tuple(int(v * 0.75) for v in col), 1, shift=2, lineType=cv2.LINE_AA)
        return out.astype(np.float32) / 255

    def light(self, t):
        """The finished mosaic under a light that moves across it: a tile flares where its tilt meets it."""
        s, d = self.times["light"]
        u = np.clip((t - s) / d, 0, 1)
        x = -0.25 + 1.5 * ease(u)
        ang = np.array([math.cos(2.4 * u), math.sin(2.4 * u)])
        meet = np.exp(-((self.sweep - x) / 0.13) ** 2) * np.clip(0.4 + 0.9 * (self.tilt @ ang), 0, 1)
        meet *= np.where(self.stone, 0.25, 0.7) * np.where(self.gold, 1.8, 1.0)
        g = np.r_[0.0, meet][self.ids][..., None].astype(np.float32)
        warm = np.where(np.r_[False, self.gold][self.ids][..., None], GOLD * 1.3, np.array([1.0, 0.93, 0.78], np.float32))
        pic = np.where(self.mask[..., None] > 0, self.set_img * (1 + 0.35 * g) + 0.28 * g * warm, self.under(t))
        return pic

    def smalti(self, u):
        """The glass: each paint a cake, glowing as it is poured, cooling to its colour, then cut."""
        w, h = self.w, self.h
        pic = np.ones((h, w, 3), np.float32) * GROUND * 1.4
        img = (pic * 255).astype(np.uint8)
        n = len(self.pal); cols = 4 if n <= 16 else 5
        rows = math.ceil(n / cols)
        cw = w / cols; chh = min(h / rows, cw * 1.05)
        oy = (h - rows * chh) / 2
        r = 0.36 * min(cw, chh)
        counts = np.bincount(self.paint, minlength=n)
        rng = np.random.default_rng(3)
        for j in np.argsort(-counts):
            rank = list(np.argsort(-counts)).index(j)
            cx = (rank % cols + 0.5) * cw; cy = oy + (rank // cols + 0.5) * chh
            appear = 0.05 + 0.4 * rank / max(n - 1, 1)
            a = ease((u - appear) / 0.08)
            if a <= 0: continue
            cool = ease((u - appear) / 0.22)
            hot = np.array([1.0, 0.62, 0.22], np.float32)
            col = self.pal[j] * cool + hot * (1 - cool)
            gold = TileGold(self.pal[j])
            cut = ease((u - 0.62 - 0.15 * rank / max(n - 1, 1)) / 0.12)
            # The cake, then the cuts: a grid of joints opening across it.
            sz = r * 2 / 4
            for gy in range(4):
                for gx in range(4):
                    px = cx - r + (gx + 0.5) * sz; py = cy - r + (gy + 0.5) * sz
                    if (px - cx) ** 2 + (py - cy) ** 2 > (r * 1.02) ** 2: continue
                    spread = 1 + 0.22 * cut
                    half = sz / 2 * (1 - 0.14 * cut)
                    qx = cx + (px - cx) * spread; qy = cy + (py - cy) * spread
                    jit = 1 + 0.06 * rng.normal()
                    c = np.clip(col * jit * (1.0 + (0.25 if gold else 0) * rng.normal()), 0, 1)
                    pts = np.array([[qx - half, qy - half], [qx + half, qy - half], [qx + half, qy + half], [qx - half, qy + half]])
                    if cut < 0.05:
                        continue
                    cv2.fillPoly(img, [np.round(pts * 4).astype(np.int32)], tuple(int(v * 255 * a) for v in c), shift=2, lineType=cv2.LINE_AA)
            if cut < 0.05 or cut < 1:
                # The whole cake while it is still whole (fading as it is cut).
                ov = img.copy()
                cv2.circle(ov, (int(cx * 4), int(cy * 4)), int(r * 4), tuple(int(v * 255) for v in col), -1, cv2.LINE_AA, shift=2)
                if gold or cool < 1:
                    cv2.circle(ov, (int((cx - r * 0.3) * 4), int((cy - r * 0.35) * 4)), int(r * 0.35 * 4),
                               tuple(int(v * 255) for v in np.clip(col * 1.3 + 0.1, 0, 1)), -1, cv2.LINE_AA, shift=2)
                al = a * (1 - cut)
                img = (img * (1 - al) + ov * al).astype(np.uint8)
        return img.astype(np.float32) / 255

    def card(self, frame, t):
        name, u = self.scene(t)
        title, line, credit = CARDS[name]
        s, d = self.times[name]
        a = ease((t - s) / 0.5) * ease((s + d - t) / 0.5) if name != "hold" else ease((t - s) / 0.5)
        if a <= 0: return frame
        im = Image.fromarray((np.clip(frame, 0, 1) * 255).astype(np.uint8))
        dr = ImageDraw.Draw(im)
        meta = self.meta
        title, line, credit = (x.format(**meta) for x in (title, line, credit))
        mix = lambda c: tuple(int(v) for v in (GROUND * (1 - a) + c * a) * 255)
        # A single gold tessera beside the technique's name: the only gold on the card.
        y = BAND + 26
        dr.rectangle([48, y + 12, 60, y + 24], fill=mix(GOLD))
        dr.text((76, y), title.upper(), font=font(30), fill=mix(PLASTER))
        y += 56
        for ln in wrap(line, font(25), FW - 124):
            dr.text((76, y), ln, font=font(25), fill=mix(PLASTER * 0.92)); y += 34
        y += 10
        for ln in wrap(credit, font(21, italic=True), FW - 124):
            dr.text((76, y), ln, font=font(21, italic=True), fill=mix(MUTED)); y += 28
        return np.asarray(im).astype(np.float32) / 255

    def frame(self, t):
        f = np.ones((FH, FW, 3), np.float32) * GROUND
        name, u = self.scene(t)
        if name == "model":
            pic = self.photo_f * (1 - ease((u - 0.75) / 0.25)) + LIME * ease((u - 0.75) / 0.25)
        elif name == "smalti":
            g = self.smalti(u)
            back = ease((u - 0.9) / 0.1)
            pic = g * (1 - back) + LIME * back
        elif name in ("light",):
            pic = self.light(t)
        else:
            pic = self.mosaic(t)
        f[self.y0:self.y0 + self.h, self.x0:self.x0 + self.w] = pic
        return np.clip(self.card(f, t), 0, 1)


def TileGold(rgb):
    lab = oklab(np.asarray(rgb, float))
    c = math.hypot(lab[1], lab[2]); hue = math.degrees(math.atan2(lab[2], lab[1]))
    return lab[0] > 0.55 and c > 0.07 and 55 < hue < 105


def wrap(text, f, width):
    words, lines, cur = text.split(), [], ""
    for wd in words:
        nxt = (cur + " " + wd).strip()
        if f.getlength(nxt) <= width: cur = nxt
        else: lines.append(cur); cur = wd
    if cur: lines.append(cur)
    return lines


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    design, photo, contours, features, out = args[:5]
    fps = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--fps=")), 30))
    meta = json.loads(os.environ.get("META", '{"title": "", "credit": ""}'))
    os.makedirs(out, exist_ok=True)
    show = Show(design, photo, contours, features, meta, sinopia=os.environ.get("SINOPIA", "red"))
    for name, _ in SCENES:
        s, d = show.times[name]
        if not d: continue
        t = s + d * (0.62 if name not in ("hold", "model") else 0.5)
        Image.fromarray((show.frame(t) * 255).astype(np.uint8)).save(f"{out}/still-{name}.png")
    if "--stills" in sys.argv: sys.exit()
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{FW}x{FH}",
                           "-r", str(fps), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23",
                           "-movflags", "+faststart", f"{out}/making-of.mp4"], stdin=subprocess.PIPE)
    for i in range(int(show.duration * fps)):
        ff.stdin.write((show.frame(i / fps) * 255).astype(np.uint8).tobytes())
    ff.stdin.close(); ff.wait()
    print(f"{show.duration:.1f} s, {len(show.polys)} tiles")
