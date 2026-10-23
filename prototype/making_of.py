"""making_of.py <mosaic.json> <photo> <out dir> [--stills] [--fps=N]: draws the making-of show, a mosaic set
the way the old workshops set one, with the technique of each step named on a card (the cards' words and
their sources: docs/making-of.md). What happens when is making_of_plan.py's (a pure function of the time,
which Sources/MosaicKit's MakingOf ports); this only draws it, as the app's view will.

  model     the picture the mosaic is made from
  smalti    the glass: each paint a cake of glass, cooling, then cut into tesserae
  sinopia   the drawing on the bed: the strands' and features' lines in red earth (or indigo), stroke by stroke
  bed       the painted setting bed spreading over the drawing (the colour under the joints)
  face      the face first: its features' rows, the eyes as pieces, then its fine stone
  outlines  the strands
  andamento the rows that echo them, ring after ring, and the field
  light     the finished mosaic under a moving light: each tile set at its own small tilt
  hold      the finished mosaic, and the closing card

A tile is never painted on: it drops in from above, a little large, its shadow under it, and settles; it
catches a warm light the moment it lands (gold only where a tile catches the light).

<mosaic.json> is the app's format with each tile's stage ("g"), the order it was laid; `from_design` makes
one from a mosaic_faces.py design and its features.json:

    python3 prototype/making_of.py --from-design <design.json> <features.json | -> <mosaic.json>

Environment: META ({"title", "credit"}: the model's card), and the options (making_of_plan.Options):
SINOPIA (red | indigo), HAND (1: the setter's hand shown), FLOW (scenes | continuous), NAMES (1: the closing
card names the makers). Writes <out>/making-of.mp4 (with ffmpeg) and <out>/still-<scene>.png; --stills
writes only the stills. Needs numpy, opencv-python-headless, scipy and Pillow.
"""
import json, math, os, subprocess, sys
import numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_plan as mp  # noqa: E402

# Ravenna's colours (App/Ravenna/Theme.swift): the dark of an apse, lime-plaster words, gold kept for light.
GROUND = np.array([0.082, 0.075, 0.059], np.float32)
PLASTER = np.array([0.914, 0.886, 0.827], np.float32)
MUTED = np.array([0.651, 0.612, 0.537], np.float32)
GOLD = np.array(mp.GOLD, np.float32)
LIME = np.array([0.84, 0.81, 0.75], np.float32)       # the bare lime of the bed
FW, FH = 720, 1280                                    # the frame: a phone held upright
BOX = (24, 40, 696, 940)                              # where the picture sits in it
BAND = 968                                            # the card's top

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def oklab(rgb):
    l = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return np.cbrt(np.clip(l @ M1.T, 0, None)) @ M2.T
def srgb(lab):
    lin = np.clip((lab @ np.linalg.inv(M2).T) ** 3 @ np.linalg.inv(M1).T, 0, 1)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)
def font(size, italic=False):
    name = "LiberationSerif-Italic" if italic else "LiberationSerif-Regular"
    for d in ("/usr/share/fonts/truetype/liberation", "/Library/Fonts", "/System/Library/Fonts/Supplemental"):
        if os.path.exists(f"{d}/{name}.ttf"): return ImageFont.truetype(f"{d}/{name}.ttf", size)
    return ImageFont.load_default(size)
def wrap(text, f, width):
    lines, cur = [], ""
    for wd in text.split():
        nxt = (cur + " " + wd).strip()
        if f.getlength(nxt) <= width: cur = nxt
        else: lines.append(cur); cur = wd
    if cur: lines.append(cur)
    return lines


def from_design(design, features):
    """A mosaic_faces.py design as the app's format with each tile's stage, until the bench writes them: the
    first and last tiles are the eyes (iris, pupil), the features' rows came before the strands, and the rest
    are rows (the design doesn't tell rows from the field)."""
    d = json.load(open(design)); feat = json.load(open(features)) if features != "-" else None
    tiles, n = d["tiles"], len(d["tiles"]); ne = len(feat["eyes"]) if feat else 0
    box = feat["box"] if feat else None
    out = []
    for i, t in enumerate(tiles):
        c = np.array(t["corners"]); cx, cy = c.mean(0)
        g = "eye" if i < ne or i >= n - ne else "feature" if t.get("feature") in ("dark", "mid", "tone") else "strand" if t["strand"] else "row"
        tile = {"c": [round(float(v), 1) for v in c.ravel()], "p": t["paint"], "g": g}
        if box and box[0] <= cx <= box[2] and box[1] <= cy <= box[3]: tile["s"] = 1
        out.append(tile)
    return {"size": [d["size"][0] / d["scale"], d["size"][1] / d["scale"]], "grout": d["grout"], "palette": d["palette"], "tiles": out}


class Show:
    def __init__(self, mosaic, photo, options, meta, seed=547):
        self.plan = p = mp.Plan(mosaic, options, meta)
        self.options = options
        self.photo = cv2.cvtColor(cv2.imread(photo), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
        k = min((BOX[2] - BOX[0]) / p.width, (BOX[3] - BOX[1]) / p.height)
        self.k, self.w, self.h = k, round(p.width * k), round(p.height * k)
        self.x0 = (FW - self.w) // 2; self.y0 = BOX[1] + ((BOX[3] - BOX[1]) - self.h) // 2
        self.photo_f = cv2.resize(self.photo, (self.w, self.h), interpolation=cv2.INTER_AREA)
        self.polys = [np.array(c) * k for c in p.corners]
        self.cent = np.array(p.centre) * k
        self.pitch = p.pitch * k
        self.ink = np.array(mp.SINOPIA[options.sinopia], np.float32)
        self.rng = np.random.default_rng(seed)
        self._layers()

    def _layers(self):
        """The set tiles in the glass-and-stone finish and the painted bed (sketchbook/render.py's C and bed)."""
        p, w, h, n = self.plan, self.w, self.h, len(self.polys)
        ids = np.zeros((h, w), np.int32)
        for i, q in enumerate(self.polys): cv2.fillPoly(ids, [np.round(q * 4).astype(np.int32)], i + 1, shift=2)
        self.ids = ids
        lab = oklab(np.array(p.palette, float)[p.paint]) + self.rng.normal(0, 1, (n, 3)) * [0.009, 0.003, 0.003]
        self.body = srgb(lab).astype(np.float32)
        stone = np.array(p.stone)
        mask = (ids > 0).astype(np.float32); self.mask = mask
        img = np.vstack([np.zeros((1, 3), np.float32), self.body])[ids]
        s = self.pitch * 0.5
        blur = gaussian_filter(img * mask[..., None], (s, s, 0)) / np.maximum(gaussian_filter(mask, s), 1e-3)[..., None]
        self.bed = srgb(oklab(blur.astype(float)) * [0.8, 0.65, 0.65]).astype(np.float32)
        dist = cv2.distanceTransform((ids > 0).astype(np.uint8), cv2.DIST_L2, 5)
        gy, gx = np.gradient(gaussian_filter(dist, 0.8))
        lit = -(gx * -0.6 + gy * -0.8) / (np.hypot(gx, gy) + 1e-6)
        st = np.r_[False, stone][ids]
        b = np.where(st, 0.16, 0.24) * self.pitch
        edge = np.clip(1 - dist / np.maximum(b, 1e-3), 0, 1) ** 1.5
        shade = 1 + np.where(st, 0.16, 0.34) * lit * edge - np.where(st, 0.05, 0.10) * edge
        shade *= 1 + np.where(st, 0.035, 0.012) * gaussian_filter(self.rng.normal(0, 1, (h, w)), 0.7)
        glint = np.clip(lit, 0, 1) * np.clip(1 - dist / (0.45 * self.pitch), 0, 1) * (~st) * (ids > 0)
        self.set_img = (img * shade[..., None] + 0.10 * glint[..., None] ** 3).astype(np.float32)
        self.goldmap = np.r_[False, np.array(p.gold)][ids]
        self.yy = np.linspace(0, 1, h)[:, None] + 0.04 * np.sin(np.linspace(0, 9, w))[None, :]

    def under(self, t):
        """Under the tiles at t: lime, the drawing so far, the painted bed laid so far."""
        p = self.plan
        prog = p.sinopia(t)
        line = np.zeros((self.h, self.w), np.float32)
        for s, (a, b) in zip(p.strokes, p.stroke_span):
            if prog <= a: continue
            pts = np.array(s) * self.k
            if prog < b:
                # The brush part way along this stroke.
                seg = np.r_[0, np.cumsum(np.hypot(*np.diff(pts, axis=0).T))]
                upto = (prog - a) / (b - a) * seg[-1]
                m = max(int(np.searchsorted(seg, upto)), 1)
                f = (upto - seg[m - 1]) / max(seg[m] - seg[m - 1], 1e-9)
                pts = np.vstack([pts[:m], pts[m - 1] + f * (pts[m] - pts[m - 1])])
            cv2.polylines(line, [np.round(pts * 4).astype(np.int32)], False, 1.0, 2, cv2.LINE_AA, shift=2)
        line = gaussian_filter(line, 0.6)
        laid = np.clip((p.bed(t) - self.yy) / 0.08, 0, 1)
        base = LIME * (1 - laid[..., None]) + self.bed * laid[..., None]
        ink = np.clip(line * (1 - 0.82 * laid), 0, 1)[..., None]
        return base * (1 - 0.85 * ink) + self.ink * 0.85 * ink

    def mosaic(self, t):
        p = self.plan
        state = [p.tile(i, t) for i in range(len(self.polys))]
        settled = np.r_[False, [s == "set" for s in state]]
        pic = np.where(settled[self.ids][..., None], self.set_img, self.under(t))
        flying = [i for i, s in enumerate(state) if isinstance(s, dict)]
        if not flying: return pic
        shadow = np.zeros((self.h, self.w), np.float32)
        for i in flying:
            f, c = state[i], self.cent[i]; lift = f["lift"] * self.k
            q = (self.polys[i] - c) * (1 + (f["scale"] - 1) / 3) + c + [lift * 0.3, lift * 0.4]
            cv2.fillPoly(shadow, [np.round(q * 4).astype(np.int32)], f["shadow"], shift=2, lineType=cv2.LINE_AA)
        pic = pic * (1 - gaussian_filter(shadow, 1.2)[..., None])
        out = (np.clip(pic, 0, 1) * 255).astype(np.uint8)
        for i in flying:
            f, c = state[i], self.cent[i]
            q = np.round(((self.polys[i] - c) * f["scale"] + c - [0, f["lift"] * self.k]) * 4).astype(np.int32)
            col = np.clip((self.body[i] * (1 - f["glow"]) + GOLD * 1.25 * f["glow"]) * 255, 0, 255)
            cv2.fillPoly(out, [q], tuple(int(v) for v in col), shift=2, lineType=cv2.LINE_AA)
            cv2.polylines(out, [q], True, tuple(int(v * 0.75) for v in col), 1, shift=2, lineType=cv2.LINE_AA)
        hand = p.hand(t)
        if hand is not None:
            # The setter's hand, as the shadow of a finger pressing the tile home from the lower right: a
            # fingertip two or three tiles wide.
            x, y = np.array(hand) * self.k; r = self.pitch * 1.2
            ov = np.zeros((self.h, self.w), np.float32)
            tip = (int((x + r * 0.3) * 4), int((y + r * 0.3) * 4))
            cv2.line(ov, tip, (int((x + r * 2.6) * 4), int((y + r * 4.4) * 4)), 1.0, max(int(r * 2), 1), cv2.LINE_AA, shift=2)
            ov = gaussian_filter(ov, r * 0.35)
            out = (out * (1 - 0.45 * ov[..., None])).astype(np.uint8)
        return out.astype(np.float32) / 255

    def light(self, t):
        p = self.plan
        meet = np.array([p.light(i, t) for i in range(len(self.polys))], np.float32)
        g = np.r_[0.0, meet][self.ids][..., None].astype(np.float32)
        warm = np.where(self.goldmap[..., None], GOLD * 1.3, np.array([1.0, 0.93, 0.78], np.float32))
        return np.where(self.mask[..., None] > 0, self.set_img * (1 + 0.35 * g) + 0.28 * g * warm, self.under(t))

    def smalti(self, u):
        """The glass: each paint a cake, glowing as it is poured, cooling to its colour, then cut."""
        p, w, h = self.plan, self.w, self.h
        img = (np.ones((h, w, 3), np.float32) * GROUND * 1.4 * 255).astype(np.uint8)
        n = len(p.palette); cols = 4 if n <= 16 else 5; rows = math.ceil(n / cols)
        cw = w / cols; ch = min(h / rows, cw * 1.05); oy = (h - rows * ch) / 2; r = 0.36 * min(cw, ch)
        hot = np.array([1.0, 0.62, 0.22], np.float32)
        for rank, j in enumerate(p.cake_rank):
            shown, cool, cut = p.cake(j, u)
            if shown <= 0: continue
            cx = (rank % cols + 0.5) * cw; cy = oy + (rank // cols + 0.5) * ch
            col = np.array(p.palette[j], np.float32) * cool + hot * (1 - cool)
            if cut > 0.05:
                sz = r / 2
                for gy in range(4):
                    for gx in range(4):
                        px = cx - r + (gx + 0.5) * sz; py = cy - r + (gy + 0.5) * sz
                        if (px - cx) ** 2 + (py - cy) ** 2 > (r * 1.02) ** 2: continue
                        qx = cx + (px - cx) * (1 + 0.22 * cut); qy = cy + (py - cy) * (1 + 0.22 * cut)
                        half = sz / 2 * (1 - 0.14 * cut)
                        c = np.clip(col * (1 + 0.05 * mp.wobble(gy * 4 + gx, j)), 0, 1)
                        pts = np.array([[qx - half, qy - half], [qx + half, qy - half], [qx + half, qy + half], [qx - half, qy + half]])
                        cv2.fillPoly(img, [np.round(pts * 4).astype(np.int32)], tuple(int(v * 255 * shown) for v in c), shift=2, lineType=cv2.LINE_AA)
            if cut < 1:
                ov = img.copy()
                cv2.circle(ov, (int(cx * 4), int(cy * 4)), int(r * 4), tuple(int(v * 255) for v in col), -1, cv2.LINE_AA, shift=2)
                cv2.circle(ov, (int((cx - r * 0.3) * 4), int((cy - r * 0.35) * 4)), int(r * 0.35 * 4),
                           tuple(int(v * 255) for v in np.clip(col * 1.3 + 0.1, 0, 1)), -1, cv2.LINE_AA, shift=2)
                al = shown * (1 - cut)
                img = (img * (1 - al) + ov * al).astype(np.uint8)
        return img.astype(np.float32) / 255

    def card(self, frame, t):
        c = self.plan.card(t)
        if c is None or c[1] <= 0: return frame
        name, a = c
        title, line, credit = mp.card_text(name, self.options, self.plan.meta)
        im = Image.fromarray((np.clip(frame, 0, 1) * 255).astype(np.uint8)); dr = ImageDraw.Draw(im)
        mix = lambda col: tuple(int(v) for v in (GROUND * (1 - a) + col * a) * 255)
        y = BAND + 26
        # A single gold tessera beside the technique's name: the only gold on the card.
        dr.rectangle([48, y + 12, 60, y + 24], fill=mix(GOLD))
        dr.text((76, y), title.upper(), font=font(30), fill=mix(PLASTER)); y += 56
        for ln in wrap(line, font(25), FW - 124):
            dr.text((76, y), ln, font=font(25), fill=mix(PLASTER * 0.92)); y += 34
        y += 10
        for ln in wrap(credit, font(21, True), FW - 124):
            dr.text((76, y), ln, font=font(21, True), fill=mix(MUTED)); y += 28
        return np.asarray(im).astype(np.float32) / 255

    def frame(self, t):
        f = np.ones((FH, FW, 3), np.float32) * GROUND
        name, u = self.plan.scene(t)
        if name == "model":
            a = mp.ease((u - 0.75) / 0.25); pic = self.photo_f * (1 - a) + LIME * a
        elif name == "smalti":
            a = mp.ease((u - 0.9) / 0.1); pic = self.smalti(u) * (1 - a) + LIME * a
        elif name == "light":
            pic = self.light(t)
        else:
            pic = self.mosaic(t)
        f[self.y0:self.y0 + self.h, self.x0:self.x0 + self.w] = pic
        return np.clip(self.card(f, t), 0, 1)


if __name__ == "__main__":
    if sys.argv[1] == "--from-design":
        design, features, out = sys.argv[2:5]
        json.dump(from_design(design, features), open(out, "w"), separators=(",", ":")); sys.exit()
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    mosaic, photo, out = args[:3]
    fps = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--fps=")), 30))
    env = os.environ.get
    options = mp.Options(sinopia=env("SINOPIA", "red"), hand=env("HAND") == "1", flow=env("FLOW", "scenes"), names=env("NAMES") == "1")
    show = Show(json.load(open(mosaic)), photo, options, json.loads(env("META", '{"title": "", "credit": ""}')))
    os.makedirs(out, exist_ok=True)
    for name, _ in mp.SCENES:
        s, d = show.plan.times[name]
        if not d: continue
        t = s + d * (0.5 if name in ("hold", "model") else 0.62)
        Image.fromarray((show.frame(t) * 255).astype(np.uint8)).save(f"{out}/still-{name}.png")
    if "--stills" in sys.argv: sys.exit()
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{FW}x{FH}",
                           "-r", str(fps), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23",
                           "-movflags", "+faststart", f"{out}/making-of.mp4"], stdin=subprocess.PIPE)
    for i in range(int(show.plan.duration * fps)):
        ff.stdin.write((show.frame(i / fps) * 255).astype(np.uint8).tobytes())
    ff.stdin.close(); ff.wait()
    print(f"{show.plan.duration:.1f} s, {len(show.polys)} tiles")
