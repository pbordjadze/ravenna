"""making_of_plan.py: the making-of show's plan, a pure function of the mosaic, the options and the time;
the reference Sources/MosaicKit's MakingOf is ported from (making_of.py draws it). Plain Python, no numpy,
float64 throughout, so the Swift port can match it to the last digits.

    plan = Plan(mosaic, Options(sinopia="red", hand=True, flow="scenes", names=False))
    f = plan.frame(t)          # what to draw at t, as plain data (see `frame`)

<mosaic> is the app's format (App/Ravenna/Resources/Mosaics/*.json, Sources/MosaicKit's Mosaic): "size",
"palette", "tiles" each {"c": flat corners, "p": paint, "s": 1 for stone, "g": its build stage}. The tiles are
in the order they were laid. A tile's scene comes from its stage: a face's features, its eyes and its stone
are the face; strands the outlines; rows and the field the andamento. Without stages (older files), stone
is the face and everything else the andamento.

    python3 prototype/making_of_plan.py <mosaic.json> --fixture <out.json>

writes the fixture Tests/MosaicKitTests/MakingOfTests.swift checks (Tests/Fixtures/making-of/) the port against.
"""
import json, math, struct, sys

SCENES = [("model", 3.0), ("smalti", 5.5), ("sinopia", 5.0), ("bed", 3.5), ("face", 6.5),
          ("outlines", 5.0), ("andamento", 9.0), ("light", 5.5), ("hold", 5.0)]
BUILD = ("face", "outlines", "andamento")
SET_TIME = 0.42          # seconds a tile takes to drop and settle
FADE = 0.5               # a card's fade in and out

# The cards (title, line, credit). Their words and sources: docs/making-of.md.
CARDS = {
    "model": ("The model", "{title}", "{credit}"),
    "smalti": ("Smalti", "Glass coloured with copper, cobalt, iron, antimony and tin, poured as a cake, then cut into tesserae.",
               "Anonymous glassmakers; where they worked is still unknown"),
    "sinopia": ("The drawing on the bed", "The design is drawn on the plaster first. At Classe, the drawing under the apse shows a different design from the one that was set.",
                "Sant'Apollinare in Classe, Ravenna, 6th century; anonymous"),
    "bed": ("The painted bed", "Each fresh patch of the bed is painted in full colour, “a finished painting in true fresco”, before a tile is set.",
            "Hagia Sophia, recorded by Thomas Whittemore, 1942"),
    "face": ("Opus vermiculatum", "The face in the smallest pieces, the eyes set as pieces of their own, row curving round row.",
             "As in the panels Dioskourides of Samos signed in tiny tesserae, Pompeii"),
    "outlines": ("The outlines", "Rows set first along the drawing’s lines: “the outline of the wing is shown by a row”.",
                 "Hagia Sophia, the Deesis; anonymous"),
    "andamento": ("Andamento", "Each row carries on the curve of the one before, so the rows show how the form moves.",
                  "Italian for ‘the way it goes’, a workshop word, not an ancient one"),
    "light": ("Set at a tilt", "Gold and glass set at slightly different angles, each catching the light its own way.",
              "Hagia Sophia; the Nativity, Bethlehem"),
    "hold": ("The makers", "Most mosaicists are anonymous; a few names survive.",
             "No source names the mosaicists of Ravenna or Hagia Sophia"),
}
# The closing card with the names, behind `names` until Paul decides (lore waits on him).
NAMED = ("The makers", "A few names survive: Sosus of Pergamon, Gnosis at Pella, Dioskourides of Samos, Ephraim at Bethlehem. Most mosaicists are anonymous.",
         "Pliny, Natural History 36.184, and the works they signed")
SINOPIA = {"red": (0.60, 0.25, 0.16), "indigo": (0.20, 0.25, 0.48)}   # Ravenna's red earth; Hagia Sophia's indigo
GOLD = (0.788, 0.635, 0.290)                                          # Theme.gold


class Options:
    """The show's creative forks, options until Paul narrows them. sinopia: "red" or "indigo"; hand: the
    setter's hand shown pressing each tile; flow: "scenes" (one stage after another, a card each) or
    "continuous" (one build that quickens, the cards following the stage being set); names: the closing card
    names the makers."""
    def __init__(self, sinopia="red", hand=False, flow="scenes", names=False):
        assert sinopia in SINOPIA and flow in ("scenes", "continuous")
        self.sinopia, self.hand, self.flow, self.names = sinopia, hand, flow, names


M64 = (1 << 64) - 1
def wobble(tile, salt=0):
    """TileColor.wobble: a deterministic number in -1...1 for a tile (SplitMix64's finaliser)."""
    z = (tile + 0x9E3779B97F4A7C15 * (salt + 1)) & M64
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    z ^= z >> 31
    return float(z >> 40) / float(1 << 23) - 1


def is_gold(rgb):
    """TileColor.isGold, in float64."""
    def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = map(lin, rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    hue = math.degrees(math.atan2(B, A))
    return L > 0.55 and math.hypot(A, B) > 0.07 and 55 < hue < 105


def f32(v):
    """A number as Swift's Mosaic holds it (Float), so the port starts from the same values."""
    return struct.unpack("f", struct.pack("f", float(v)))[0]


def dist(a, b):
    dx, dy = a[0] - b[0], a[1] - b[1]
    return math.sqrt(dx * dx + dy * dy)


def ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def card_text(scene, options, meta):
    title, line, credit = NAMED if scene == "hold" and options.names else CARDS[scene]
    return tuple(x.replace("{title}", meta.get("title", "")).replace("{credit}", meta.get("credit", "")) for x in (title, line, credit))


class Plan:
    def __init__(self, mosaic, options=None, meta=None):
        self.options = options or Options()
        self.meta = meta or {}
        self.width, self.height = map(f32, mosaic["size"])
        self.palette = [tuple(map(f32, c)) for c in mosaic["palette"]]
        tiles = mosaic["tiles"]
        n = len(tiles)
        self.corners = [[(f32(t["c"][k]), f32(t["c"][k + 1])) for k in range(0, len(t["c"]), 2)] for t in tiles]
        self.paint = [t["p"] for t in tiles]
        self.stone = [bool(t.get("s", 0)) for t in tiles]
        self.stage = [t.get("g") for t in tiles]
        self.centre = []
        for c in self.corners:
            x = y = 0.0
            for cx, cy in c: x += cx; y += cy
            self.centre.append((x / len(c), y / len(c)))
        areas = []
        for c in self.corners:
            a = 0.0
            for k in range(len(c)):
                a += c[k][0] * c[(k + 1) % len(c)][1] - c[(k + 1) % len(c)][0] * c[k][1]
            areas.append(abs(a) / 2)
        areas.sort()
        # The tiles' size: the side of the median tile.
        self.pitch = math.sqrt(areas[len(areas) // 2]) if areas else 1.0
        # Each tile's scene, and the order it is set in within it: the features, the eyes, then the rest by index.
        scene, rank = [], []
        for i in range(n):
            g, s = self.stage[i], self.stone[i]
            if g in ("feature", "eye") or s: scene.append("face")
            elif g == "strand": scene.append("outlines")
            else: scene.append("andamento")
            rank.append((0 if g == "feature" else 1 if g == "eye" else 2, i))
        self.scene_of = scene
        lengths = dict(SCENES)
        count = {k: scene.count(k) for k in BUILD}
        for k in ("face", "outlines"):
            if count[k] == 0: lengths[k] = 0.0
        self.times = {}
        t = 0.0
        for name, _ in SCENES:
            self.times[name] = (t, lengths[name]); t += lengths[name]
        self.duration = t
        # When each tile starts to drop.
        self.start = [math.inf] * n
        self.order = {}
        for k in BUILD:
            self.order[k] = sorted((i for i in range(n) if scene[i] == k), key=lambda i: rank[i])
        if self.options.flow == "scenes":
            for k in BUILD:
                s, d = self.times[k]; idx = self.order[k]
                for j, i in enumerate(idx):
                    u = j / (len(idx) - 1) if len(idx) > 1 else 0.0
                    # Slow to begin, as the first rows are found, then quicker as the setters fill in.
                    u = u ** (0.65 if k == "andamento" else 0.8)
                    self.start[i] = s + 0.15 * d + u * (0.72 * d - SET_TIME)
        else:
            s = self.times[BUILD[0]][0]
            d = 0.0
            for k in BUILD: d += self.times[k][1]      # not sum(): Python 3.12's sum compensates, Swift's + doesn't
            idx = [i for k in BUILD for i in self.order[k]]
            for j, i in enumerate(idx):
                u = (j / (len(idx) - 1) if len(idx) > 1 else 0.0) ** 0.7
                self.start[i] = s + 0.06 * d + u * (0.88 * d - SET_TIME)
        # The cards: one a scene, or in the continuous build one a stage from its first tile to the next's.
        self.cards = []
        for name, _ in SCENES:
            s, d = self.times[name]
            if d == 0: continue
            if self.options.flow == "continuous" and name in BUILD:
                continue
            self.cards.append((name, s, s + d))
        if self.options.flow == "continuous":
            firsts = [(k, self.start[self.order[k][0]]) for k in BUILD if self.order[k]]
            end = self.times["light"][0]
            for j, (k, a) in enumerate(firsts):
                b = firsts[j + 1][1] if j + 1 < len(firsts) else end
                self.cards.append((k, a - 0.3 if j else self.times[BUILD[0]][0], b))
            self.cards.sort(key=lambda c: c[1])
        # The sinopia: the strands' and features' tiles chained into strokes, nearest the face first.
        face = [self.centre[i] for i in range(n) if scene[i] == "face"]
        fc = (self.width / 2, self.height / 2)
        if face:
            x = y = 0.0
            for px, py in face: x += px; y += py
            fc = (x / len(face), y / len(face))
        strokes, cur = [], []
        for i in range(n):
            if self.stage[i] not in ("strand", "feature"): continue
            p = self.centre[i]
            if cur and (self.stage[cur[-1]] != self.stage[i] or dist(self.centre[cur[-1]], p) > 1.6 * self.pitch):
                strokes.append(cur); cur = []
            cur.append(i)
        if cur: strokes.append(cur)
        strokes = [[self.centre[i] for i in s] for s in strokes if len(s) >= 2]
        def far(s):
            d = 0.0
            for q in s: d += dist(q, fc)
            return d / len(s)
        keyed = sorted(((far(s), j) for j, s in enumerate(strokes)))
        strokes = [strokes[j] for _, j in keyed]
        self.strokes = strokes
        lens = []
        for s in strokes:
            L = 0.0
            for a, b in zip(s, s[1:]): L += dist(a, b)
            lens.append(L)
        total = 0.0
        for L in lens: total += L
        total = total or 1.0
        acc, self.stroke_span = 0.0, []
        for L in lens:
            self.stroke_span.append((acc / total, (acc + L) / total)); acc += L
        # The light: where each tile is along the sweep, and its tilt.
        self.sweep = [x / self.width * 0.55 + y / self.height * 0.45 for x, y in self.centre]
        self.gold = [is_gold(self.palette[p]) for p in self.paint]
        self.tilt = []
        for i in range(n):
            k = (0.25 if self.stone[i] else 1.0) * (1.6 if self.gold[i] else 1.0)
            self.tilt.append((wobble(i, 4) * k, wobble(i, 5) * k))
        # The smalti: each paint's cake, the most used first.
        counts = [0] * len(self.palette)
        for p in self.paint: counts[p] += 1
        self.cake_rank = sorted(range(len(self.palette)), key=lambda p: (-counts[p], p))

    def scene(self, t):
        for name, _ in SCENES:
            s, d = self.times[name]
            if d and t < s + d: return name, (t - s) / d
        return "hold", 1.0

    def card(self, t):
        """The card showing at t: (scene, opacity), or None. Two never show at once."""
        for name, a, b in self.cards:
            if a <= t < b or (name == "hold" and t >= a):
                op = ease((t - a) / FADE) * (1.0 if name == "hold" else ease((b - t) / FADE))
                return name, op
        return None

    def tile(self, i, t):
        """A tile at t: None while waiting, "set" once settled, or in flight {lift, scale, shadow, glow}: its
        lift above its place and its scale (both 0 and 1 when it lands), the shadow's strength under it,
        and the warm light it catches as it lands (gold for a moment, glass more than stone)."""
        s = self.start[i]
        if t < s: return None
        if t >= s + SET_TIME: return "set"
        u = (t - s) / SET_TIME
        e = 1 - (1 - u) ** 3
        return {"lift": (1 - e) * 0.9 * self.pitch, "scale": 1 + 0.45 * (1 - e),
                "shadow": 0.15 + 0.3 * (1 - e),
                "glow": math.exp(-((u - 0.82) / 0.12) ** 2) * (0.35 if self.stone[i] else 0.6)}

    def hand(self, t):
        """The setter's hand (when shown): at the tile most recently begun, while one is in flight."""
        if not self.options.hand: return None
        best = None
        for i, s in enumerate(self.start):
            if s <= t < s + SET_TIME and (best is None or s > self.start[best]): best = i
        if best is None: return None
        f = self.tile(best, t)
        x, y = self.centre[best]
        return (x, y - f["lift"])

    def sinopia(self, t):
        """How much of the drawing is drawn at t, 0...1 of its whole length."""
        s, d = self.times["sinopia"]
        return min(max((t - s - 0.4) / (d - 1.0), 0.0), 1.0)

    def bed(self, t):
        """The painted bed's front at t, down the wall: 0 none, past 1 all (its soft edge 0.08 deep)."""
        s, d = self.times["bed"]
        return (t - s - 0.2) / (d - 0.6) * 1.15

    def light(self, i, t):
        """How much tile i flares under the light crossing the finished mosaic, at t."""
        s, d = self.times["light"]
        u = min(max((t - s) / d, 0.0), 1.0)
        x = -0.25 + 1.5 * ease(u)
        ax, ay = math.cos(2.4 * u), math.sin(2.4 * u)
        tx, ty = self.tilt[i]
        meet = math.exp(-((self.sweep[i] - x) / 0.13) ** 2) * min(max(0.4 + 0.9 * (tx * ax + ty * ay), 0.0), 1.0)
        return meet * (0.25 if self.stone[i] else 0.7) * (1.8 if self.gold[i] else 1.0)

    def cake(self, p, u):
        """Paint p's cake in the smalti scene at its progress u: (shown, cool, cut), each 0...1."""
        n = len(self.palette); r = self.cake_rank.index(p) / max(n - 1, 1)
        appear = 0.05 + 0.4 * r
        return ease((u - appear) / 0.08), ease((u - appear) / 0.22), ease((u - 0.62 - 0.15 * r) / 0.12)


TILE_STEP = 19          # the fixture samples every 19th tile


def fixture(plan, times):
    """The values the Swift port is checked against."""
    out = {"duration": plan.duration, "pitch": plan.pitch,
           "times": {k: list(v) for k, v in plan.times.items()},
           "start": [s if s != math.inf else None for s in plan.start],
           "strokes": [[list(p) for p in s] for s in plan.strokes], "strokeSpan": [list(s) for s in plan.stroke_span],
           "cakeRank": plan.cake_rank, "frames": []}
    for t in times:
        c = plan.card(t)
        out["frames"].append({"t": t, "scene": plan.scene(t)[0], "u": plan.scene(t)[1],
                              "card": None if c is None else {"scene": c[0], "opacity": c[1], "text": list(card_text(c[0], plan.options, plan.meta))},
                              "sinopia": plan.sinopia(t), "bed": plan.bed(t), "hand": plan.hand(t),
                              "tiles": [None if (f := plan.tile(i, t)) is None else f if f == "set" else f for i in range(0, len(plan.start), TILE_STEP)],
                              "light": [plan.light(i, t) for i in range(0, len(plan.start), TILE_STEP)],
                              "cakes": [list(plan.cake(p, plan.scene(t)[1])) for p in range(len(plan.palette))]})
    return out


if __name__ == "__main__":
    m = json.load(open(sys.argv[1]))
    out = sys.argv[sys.argv.index("--fixture") + 1]
    res = {}
    for key, opt in (("scenes", Options()), ("continuous", Options(sinopia="indigo", hand=True, flow="continuous", names=True))):
        p = Plan(m, opt, {"title": "Test", "credit": "Credit"})
        res[key] = fixture(p, [0.5 + 1.37 * k for k in range(int(p.duration / 1.37) + 1)])
    json.dump(res, open(out, "w"), separators=(",", ":"))
