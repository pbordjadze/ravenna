#include <metal_stdlib>
using namespace metal;

// Canvas renderer shaders. Positions arrive in canvas units and are mapped to target pixels
// with `pixel = canvas * transform.z + transform.xy` (origin top-left, +y down). All colors
// are linear Display P3; the render targets are *_srgb so blending happens in linear light.

// Must match `CanvasUniforms` (CanvasTypes.swift).
struct FrameUniforms {
    float4 transform;   // xy: translation (px), z: px per canvas unit, w: px per point
    float4 viewport;    // xy: target size (px), zw: canvas size (units)
    float4 background;  // rgb: backdrop around the paper; no shader reads it (the time-lapse clears to it)
    float4 paper;       // rgb: unpainted paper, a: drop shadow opacity
    float4 ink;         // rgb: outline and number ink, a: outline opacity
    float4 selected;    // rgb: selected paint, a: 1 when a color is selected
    float4 accent;      // rgb: selected paint lifted to read on this paper, a: brightest hatch ink luminance
    float4 rim;         // rgb: rim just outside the sheet, a: its opacity (0 = none)
    float4 outline;     // x: width (px), y: selected width (px), z: hatch strength, w: numbers visibility
    float4 labels;      // x…y: legibility fade (font px), z: max font px, w: min font px of a bumped number
    float4 numbers;     // x: number opacity, y: selected-color number opacity, z: selected boldness, w: reduce motion
    float4 time;        // x: now, y: selection change, z: pulse start, w: bump start
    float4 brush;       // xy: position (px), z: radius (px), w: opacity
    float4 shine;       // x: start of a light sweep over finished paint, y: its color (-1 = all)
    int4   ids;         // x: selected color, y: hovered region, z: pulsing region, w: bumped region
    float4 photo;       // x: source photo opacity
    float4 lineAlpha;   // ink opacity per line layer (x outline, y detail, z texture, w color)
    float4 lineWidth;   // line width (px) per layer
    float4 lineMode;    // x: 1 for a coloring book
    float4 lightInk;    // rgb: the tone writing over a dark paint draws in once its region is painted
    float4 tiles;       // x: 1 for a mosaic, y: finish (0 flat, 1 bed, 2 material), z: 1 with a bed texture, w: motion's pace
    float4 grout;       // rgb: the joints' colour on light grout (flat finish)
};

// Must match `RegionState` (CanvasTypes.swift).
struct RegionState {
    float2 origin;      // where the paint starts spreading (canvas units)
    float start;        // seconds (renderer clock)
    float duration;     // seconds
    float radius;       // distance from origin to the farthest point of the region
    float painted;      // 1 painted, 0 not (fading out while `now < start + duration`)
    float seed;         // per-region variation of the paint front
    float pad;
};

// Must match `GlyphInstance` (CanvasTypes.swift).
struct GlyphInstance {
    float2 center;      // label centre (canvas units)
    float size;         // font size that fits the label (canvas units)
    float offset;       // pen position of this glyph relative to the run centre (em)
    uint digit;
    uint region;
};

// Must match `TileShape` (TileScene.swift).
struct TileShape {
    float2 centre;      // canvas units
    float2 litCorner;   // the corner the light reaches first
    float size;         // side of a square of its bounds' area
    uint cornerStart;
    uint cornerCount;
    uint flags;         // kTile, kStone, kGold, kClockwise; 0 for the grout
    float turn;         // radians a raised tessera is turned at full lift
    float pad0, pad1, pad2;
};

constant uint kTile = 1u, kStone = 2u, kGold = 4u, kClockwise = 8u;

constant float kWetSettle = 0.7;
constant float kLightWriting = 4.0;      // OutlineGeometry.lightWritingMark (CanvasScene's line layers)
constant uint kOutside = 0xFFFFFFFFu;    // BoundaryEdge.outside (PaintCore): no region on that side

static float4 toClip(float2 px, constant FrameUniforms &u) {
    return float4(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0, 0.0, 1.0);
}

static float2 toPixels(float2 canvas, constant FrameUniforms &u) {
    return canvas * u.transform.z + u.transform.xy;
}

// MARK: - Paint

struct PaintSample {
    float coverage;     // 0 paper … 1 paint
    float wet;          // 1 while spreading, eases to 0 as the paint settles
    float rim;          // bright meniscus riding the leading edge
};

static PaintSample samplePaint(RegionState s, float2 p, float now, float unitsPerPixel) {
    PaintSample o;
    o.coverage = 0.0; o.wet = 0.0; o.rim = 0.0;
    float t = (now - s.start) / max(s.duration, 1e-4);
    if (s.painted < 0.5) {
        o.coverage = 1.0 - smoothstep(0.0, 1.0, t);
        return o;
    }
    if (t >= 1.0) {
        float settle = saturate((now - s.start - s.duration) / kWetSettle);
        o.coverage = 1.0;
        o.wet = (1.0 - settle) * (1.0 - settle);
        return o;
    }
    float e = 1.0 - pow(1.0 - saturate(t), 3.0);
    float2 d = p - s.origin;
    float dist = length(d);
    float angle = atan2(d.y, d.x);
    // An organic, slightly lobed front that rounds out as it spreads.
    float wobble = 1.0 + (0.05 * sin(5.0 * angle + s.seed) + 0.035 * sin(9.0 * angle - 1.7 * s.seed)) * (1.0 - e);
    float soft = max(s.radius * 0.1, 2.0 * unitsPerPixel);
    float front = e * (s.radius + soft) * 1.12 * wobble;
    o.coverage = 1.0 - smoothstep(front - soft, front, dist);
    float x = (dist - (front - soft * 0.7)) / (soft * 0.5);
    o.rim = exp(-x * x) * o.coverage;
    o.wet = 1.0;
    return o;
}

/// 0 → 1 as a region becomes painted (1 → 0 while it is being un-painted).
static float paintedAmount(RegionState s, float now) {
    float t = saturate((now - s.start) / max(s.duration, 1e-4));
    return s.painted > 0.5 ? smoothstep(0.3, 1.0, t) : 1.0 - smoothstep(0.0, 1.0, t);
}

static float3 wetPaint(float3 paint, PaintSample ps) {
    float3 c = paint * (1.0 - 0.12 * ps.wet);   // wet paint reads a little deeper
    float3 sheen = min(paint * 1.3 + 0.07, float3(1.0));
    return mix(c, sheen, ps.rim * 0.4);
}

/// Unpainted regions of the selected color: a light tint of the paint plus fine diagonal
/// hatching in screen space that glides in when the color is picked, then rests.
static float3 highlightPaper(float3 paper, float2 pt, constant FrameUniforms &u) {
    float3 sel = u.accent.rgb;
    float since = max(u.time.x - u.time.y, 0.0);
    float intro = exp(-since * 2.5);
    float phase = 6.0 * (1.0 - exp(-since * 1.8));
    float lum = dot(sel, float3(0.2126, 0.7152, 0.0722));
    float3 ink = lum > u.accent.a ? sel * (u.accent.a / lum) : sel;
    float3 tint = mix(paper, sel, 0.14 + 0.12 * intro);
    const float period = 6.0;                       // points
    float w = (pt.x + pt.y) * 0.70710678 + phase;
    float d = abs(fract(w / period) - 0.5) * period;
    float aa = 0.5 / u.transform.w;                 // half a pixel, in points
    float line = 1.0 - smoothstep(0.6 - aa, 0.6 + aa, d);
    return mix(tint, mix(paper, ink, 0.55 + 0.25 * intro), line * u.outline.z);
}

// Under Reduce Motion (`still`) the highlight shows at once and fades instead of throbbing.
static float pulse(float t, bool still) {
    if (t < 0.0 || t > 2.0) return 0.0;
    float wave = still ? 1.0 : 0.5 - 0.5 * cos(t * 6.2831853 / 0.66);
    return wave * (1.0 - t / 2.0);
}

// MARK: - Tiles

// A mosaic's tiles (MosaicKit's `Hand`, `Finish`; v0's `TileArt`): region i is tile i, the grout the
// last. The grout is the ground: light grout or the painted bed. An unset tile shows the ground with
// its number; a set tile is a tessera in its finish. A tile being set is held raised, settles into
// the bed with a damped spring and catches the light once (`Motion`, mirrored here); while raised
// it is drawn by the lift pass, above its neighbours, and its place below shows the ground.

constant float kPress = 0.09, kSettle = 0.29, kGlintStart = 0.22, kGlint = 0.54, kLift = 0.14;
constant float2 kLightFrom = float2(-0.6, -0.8);

static float settled(float t) {
    float x = saturate((t - kPress) / kSettle);
    return x >= 1.0 ? 1.0 : 1.0 - exp(-10.0 * x) * cos(9.0 * x);
}

/// Seconds since a tile began to be set, at the motion's pace (demos slow it).
static float tileTime(RegionState s, float now, constant FrameUniforms &u) {
    return (now - s.start) / max(u.tiles.w, 1e-3);
}

static bool isTile(constant FrameUniforms &u, TileShape shape) {
    return u.tiles.x > 0.5 && (shape.flags & kTile) != 0u;
}

/// Whether a tile being set is still raised: the lift pass draws it.
static bool isRaised(RegionState s, float now, constant FrameUniforms &u) {
    return u.numbers.w < 0.5 && s.painted > 0.5 && tileTime(s, now, u) < kPress + kSettle;
}

/// How much of a tile is set, 0…1: 1 once painted (the tessera covers its number at once), easing
/// in over 150 ms under Reduce Motion, easing out over the unpainting's duration (undo).
static float tileCoverage(RegionState s, float now, constant FrameUniforms &u) {
    if (s.painted > 0.5) return u.numbers.w > 0.5 ? saturate(tileTime(s, now, u) / 0.15) : 1.0;
    return 1.0 - smoothstep(0.0, 1.0, (now - s.start) / max(s.duration, 1e-4));
}

/// The light crossing a tile as it settles, 0…1, or -1 when it isn't crossing.
static float glinting(RegionState s, float now, constant FrameUniforms &u) {
    float x = (tileTime(s, now, u) - kGlintStart) / kGlint;
    return s.painted > 0.5 && x > 0.0 && x < 1.0 ? x : -1.0;
}

static float3 encode(float3 c) { return pow(max(c, 0.0), float3(1.0 / 2.2)); }
static float3 decode(float3 c) { return pow(max(c, 0.0), float3(2.2)); }

/// The ground at `p`: the painted bed, or light grout.
static float3 groundAt(float2 p, constant FrameUniforms &u, texture2d<float> bed) {
    if (u.tiles.y > 0.5 && u.tiles.z > 0.5) {
        constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
        return bed.sample(bilinear, p / u.viewport.zw).rgb;
    }
    return u.grout.rgb;
}

/// A set tile at `p` in its finish, its body colour `body` (linear); `glint` is the light crossing
/// it as it settles (-1: none). The edges' light and the glass's glint are worked in gamma-encoded
/// values, as v0's Core Graphics drew them.
static float3 tessera(float2 p, TileShape shape, float3 body, const device float2 *corners,
                      float glint, constant FrameUniforms &u) {
    int finish = int(u.tiles.y + 0.5);
    bool stone = (shape.flags & kStone) != 0u;
    bool gold = (shape.flags & kGold) != 0u;
    float3 c = encode(body);
    if (finish != 1) {
        // The nearest edge, and how lit it is.
        float nearest = 1e9, lit = 0.0;
        bool clockwise = (shape.flags & kClockwise) != 0u;
        for (uint k = 0; k < shape.cornerCount; k++) {
            float2 a = corners[shape.cornerStart + k];
            float2 b = corners[shape.cornerStart + (k + 1u) % shape.cornerCount];
            float2 ab = b - a;
            float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-6));
            float d = length(p - a - ab * h);
            if (d < nearest) {
                nearest = d;
                float2 n = float2(b.y - a.y, a.x - b.x) * (clockwise ? 1.0 : -1.0);
                lit = length(n) > 0.0 ? dot(normalize(n), kLightFrom) : 0.0;
            }
        }
        if (finish == 0) {
            // Flat: a thin dark edge.
            float w = shape.size * 0.04;
            c = mix(float3(0.2, 0.18, 0.17), c, smoothstep(w * 0.5, w, nearest));
        } else {
            // Glass and stone: a lit upper-left edge and a shaded lower-right one, glass sharper.
            float k = stone ? 0.16 : 0.34;
            float w = shape.size * (stone ? 0.1 : 0.14);
            float3 edge = c * (1.0 + k * lit) + (lit > 0.0 ? 0.03 * lit : 0.0);
            c = mix(edge, c, smoothstep(w * 0.75, w, nearest));
            if (!stone) {
                // Glass glints toward the corner the light reaches first.
                float g = 0.16 * saturate(1.0 - length(p - shape.litCorner) / (shape.size * 0.55));
                c = mix(c, float3(1.0, 0.98, 0.92), g);
            }
        }
    }
    if (glint >= 0.0) {
        // A band of warm light crossing it from its lit corner, once: gold catches it brightest.
        float reach = shape.size * 0.9;
        float2 from = shape.centre - reach, to = shape.centre + reach;
        float2 d = to - from;
        float along = dot(p - from, d) / dot(d, d);
        float at = 0.12 + 0.76 * glint;
        float peak = (gold ? 0.75 : stone ? 0.2 : 0.45) * sin(3.14159265 * glint);
        float3 warm = gold ? float3(1.0, 0.89, 0.59) : float3(1.0, 0.95, 0.84);
        c = mix(c, warm, peak * saturate(1.0 - abs(along - at) / 0.12));
        if (gold) c = mix(c, float3(0.79, 0.64, 0.29), 0.35 * (1.0 - glint));
    }
    return decode(c);
}

/// Light raking once across the wall, as a lamp carried past it (v0's finish), or across one
/// paint's tiles when it is used up: a band of gold light, added.
static float3 rake(float3 c, float2 p, int colorIndex, bool tile, constant FrameUniforms &u) {
    bool all = u.shine.y < 0.0;
    if (!(all || (tile && int(u.shine.y + 0.5) == colorIndex))) return c;
    float span = all ? 2.4 : 1.2;
    float t = (u.time.x - u.shine.x) / span;
    if (t <= 0.0 || t >= 1.0) return c;
    float2 wall = u.viewport.zw;
    float along = dot(p, wall) / dot(wall, wall);
    float at = -0.3 + 1.6 * t;
    float band = saturate(1.0 - abs(along - at) / 0.18);
    return c + decode(float3(0.788, 0.635, 0.290)) * 0.32 * sin(3.14159265 * t) * band;
}

// MARK: - Paper and shadow

struct RectOut {
    float4 position [[position]];
};

vertex RectOut canvasRectVertex(uint vid [[vertex_id]],
                                constant FrameUniforms &u [[buffer(0)]],
                                constant float &margin [[buffer(1)]]) {
    float2 lo = u.transform.xy - margin;
    float2 hi = u.transform.xy + u.viewport.zw * u.transform.z + margin;
    float2 p = float2((vid & 1u) != 0u ? hi.x : lo.x, (vid & 2u) != 0u ? hi.y : lo.y);
    RectOut o;
    o.position = toClip(p, u);
    return o;
}

static float boxDistance(float2 p, float2 center, float2 halfSize) {
    float2 q = abs(p - center) - halfSize;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

fragment float4 paperFragment(RectOut in [[stage_in]], constant FrameUniforms &u [[buffer(0)]]) {
    float pt = u.transform.w;
    float2 lo = u.transform.xy;
    float2 hi = lo + u.viewport.zw * u.transform.z;
    float2 center = 0.5 * (lo + hi);
    float2 halfSize = 0.5 * (hi - lo);
    float2 p = in.position.xy;
    float sd = boxDistance(p, center, halfSize);
    float paper = saturate(0.5 - sd);
    // A soft ambient shadow (offset down) plus a tight contact shadow.
    float ambient = boxDistance(p, center + float2(0.0, 4.0 * pt), halfSize);
    float blur = 22.0 * pt;
    float a = 1.0 - smoothstep(-0.3 * blur, blur, ambient);
    float contact = 1.0 - smoothstep(-0.5 * pt, 2.5 * pt, boxDistance(p, center + float2(0.0, 0.75 * pt), halfSize));
    float shadow = u.paper.a * (0.6 * a * a + 0.4 * contact);
    float alpha = paper + (1.0 - paper) * shadow;
    // Dark paper has no visible shadow: a one-pixel light rim outside the edge outlines it.
    float rim = u.rim.a * saturate(1.0 - abs(sd - 1.0)) * (1.0 - paper);
    // Premultiplied; the shadow is black.
    return float4(u.paper.rgb * paper + u.rim.rgb * rim, alpha + (1.0 - alpha) * rim);
}

// MARK: - Fills

struct FillOut {
    float4 position [[position]];
    float2 canvas;
    uint region [[flat]];
};

vertex FillOut fillVertex(uint vid [[vertex_id]],
                          const device float2 *positions [[buffer(0)]],
                          const device uint *vertexRegion [[buffer(1)]],
                          constant FrameUniforms &u [[buffer(2)]]) {
    float2 p = positions[vid];
    FillOut o;
    o.position = toClip(toPixels(p, u), u);
    o.canvas = p;
    o.region = vertexRegion[vid];
    return o;
}

fragment float4 fillFragment(FillOut in [[stage_in]],
                             const device float4 *regionColors [[buffer(0)]],
                             const device RegionState *states [[buffer(1)]],
                             constant FrameUniforms &u [[buffer(2)]],
                             const device TileShape *shapes [[buffer(3)]],
                             const device float2 *corners [[buffer(4)]],
                             const device float4 *bodies [[buffer(5)]],
                             texture2d<float> bed [[texture(0)]]) {
    uint r = in.region;
    float4 info = regionColors[r];
    RegionState s = states[r];
    float now = u.time.x;
    if (u.tiles.x > 0.5) {
        TileShape shape = shapes[r];
        int colorIndex = int(info.w + 0.5);
        float3 base = groundAt(in.canvas, u, bed);
        if (!isTile(u, shape)) return float4(rake(base, in.canvas, colorIndex, false, u), 1.0);
        float set = tileCoverage(s, now, u);
        if (u.selected.a > 0.5 && colorIndex == u.ids.x && set < 1.0) {
            base = highlightPaper(base, in.position.xy / u.transform.w, u);
        }
        if (int(r) == u.ids.y) base = mix(base, u.accent.rgb, 0.3);
        if (int(r) == u.ids.z) base = mix(base, u.accent.rgb, 0.6 * pulse(now - u.time.z, u.numbers.w > 0.5));
        // Raised, its place below shows the ground; the lift pass draws the tessera over it.
        if (isRaised(s, now, u)) return float4(base, 1.0);
        float3 c = base;
        if (set > 0.0) c = mix(base, tessera(in.canvas, shape, bodies[r].rgb, corners, glinting(s, now, u), u), set);
        return float4(rake(c, in.canvas, colorIndex, true, u), 1.0);
    }
    PaintSample ps = samplePaint(s, in.canvas, now, 1.0 / u.transform.z);

    float3 base = u.paper.rgb;
    int colorIndex = int(info.w + 0.5);
    if (u.selected.a > 0.5 && colorIndex == u.ids.x && ps.coverage < 1.0) {
        base = highlightPaper(base, in.position.xy / u.transform.w, u);
    }
    if (int(r) == u.ids.y) {
        base = mix(base, u.accent.rgb, 0.3);
    }
    if (int(r) == u.ids.z) {
        base = mix(base, u.accent.rgb, 0.6 * pulse(now - u.time.z, u.numbers.w > 0.5));
    }
    float3 paint = wetPaint(info.rgb, ps);
    // A color (or the whole painting) was just finished: a glossy band sweeps across it.
    float since = now - u.shine.x;
    if (since >= 0.0 && since < 1.1 && (u.shine.y < 0.0 || int(u.shine.y + 0.5) == colorIndex)) {
        float2 pt = in.position.xy / u.transform.w;
        float span = (u.viewport.x + u.viewport.y) / u.transform.w * 0.70710678;
        float head = mix(-160.0, span + 160.0, smoothstep(0.0, 1.1, since));
        float x = ((pt.x + pt.y) * 0.70710678 - head) / 70.0;
        paint = mix(paint, min(paint * 1.3 + 0.1, float3(1.0)), 0.55 * exp(-x * x));
    }
    float3 c = mix(base, paint, ps.coverage);
    return float4(c, 1.0);
}

// MARK: - Lift (tiles being set)

// Every tile still raised, drawn again over the fills and outlines: first its shadow below it
// (`shadow`), then the tessera, scaled up about its centre and turned a little as it is held, then
// settling. Every other region's triangles are moved off screen. Positions keep the tile's own
// canvas coordinates for its colours, so its edges and glint move with it.

struct LiftOut {
    float4 position [[position]];
    float2 canvas;
    uint region [[flat]];
    float lift [[flat]];
};

vertex LiftOut liftVertex(uint vid [[vertex_id]],
                          const device float2 *positions [[buffer(0)]],
                          const device uint *vertexRegion [[buffer(1)]],
                          constant FrameUniforms &u [[buffer(2)]],
                          const device TileShape *shapes [[buffer(3)]],
                          const device RegionState *states [[buffer(4)]],
                          constant uint &shadow [[buffer(5)]]) {
    LiftOut o;
    uint r = vertexRegion[vid];
    float2 p = positions[vid];
    TileShape shape = shapes[r];
    RegionState s = states[r];
    float now = u.time.x;
    o.canvas = p;
    o.region = r;
    float lift = 1.0 - settled(tileTime(s, now, u));
    o.lift = lift;
    if (!isTile(u, shape) || !isRaised(s, now, u) || (shadow != 0u && lift <= 0.02)) {
        o.position = float4(-2.0, -2.0, 0.0, 1.0);
        return o;
    }
    float k = 1.0 + kLift * lift;
    float a = shape.turn * max(lift, 0.0);
    float2 d = (p - shape.centre) * k;
    float2 q = shape.centre + float2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
    if (shadow != 0u) q += float2(0.14, 0.2) * shape.size * lift;
    o.position = toClip(toPixels(q, u), u);
    return o;
}

fragment float4 liftFragment(LiftOut in [[stage_in]],
                             constant FrameUniforms &u [[buffer(0)]],
                             const device TileShape *shapes [[buffer(1)]],
                             const device float2 *corners [[buffer(2)]],
                             const device float4 *bodies [[buffer(3)]],
                             const device RegionState *states [[buffer(4)]],
                             constant uint &shadow [[buffer(5)]]) {
    if (shadow != 0u) {
        float a = 0.45 * saturate(in.lift);
        return float4(0.0, 0.0, 0.0, a);    // premultiplied black
    }
    uint r = in.region;
    TileShape shape = shapes[r];
    RegionState s = states[r];
    float3 c = tessera(in.canvas, shape, bodies[r].rgb, corners, glinting(s, u.time.x, u), u);
    return float4(c, 1.0);
}

// MARK: - Outlines

// Pass 1: capsule segments expanded in screen space write ink opacity (r) into an RG16F target
// with MAX blending, so overlapping caps and joints never double-darken, and in g the share of
// it that is in the light tone.
//
// A segment belongs to a line: a boundary edge, or a stroke drawn inside a cell (line art, after
// the edges, with its region on both sides). Each line draws with its layer's opacity and width;
// classic templates put every line in layer 0, which is the classic line. A coloring book
// (lineMode.x) is a drawing over the paint: its lines never dissolve, and the selected color's
// cells are not outlined (the fill's highlight shows them); its color edges have no ink
// (lineAlpha.w = 0). Writing over a dark paint (a stroke whose layer carries `kLightWriting`,
// `OutlineGeometry.lightWritingMark`) is drawn in the light tone `lightInk` as its region is
// painted, so it reads on the paint instead of vanishing into it.

struct OutlineOut {
    float4 position [[position]];
    float4 ends [[flat]];       // segment endpoints (px)
    float halfWidth [[flat]];
    float alpha [[flat]];
    float light [[flat]];       // 0…1: how far the ink has turned to the light tone
};

vertex OutlineOut outlineVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device float2 *points [[buffer(0)]],
                                const device uint2 *segments [[buffer(1)]],
                                const device uint2 *lineRegions [[buffer(2)]],
                                const device RegionState *states [[buffer(3)]],
                                const device float4 *regionColors [[buffer(4)]],
                                constant FrameUniforms &u [[buffer(5)]],
                                const device float *lineLayers [[buffer(6)]]) {
    OutlineOut o;
    uint2 seg = segments[iid];
    uint2 nb = lineRegions[seg.y];
    float rawLayer = lineLayers[seg.y];
    bool lightWriting = rawLayer > kLightWriting - 0.5;
    uint layer = min(uint(rawLayer - (lightWriting ? kLightWriting : 0.0) + 0.5), 3u);
    float now = u.time.x;
    bool book = u.lineMode.x > 0.5;
    float left = paintedAmount(states[nb.x], now);
    float right = nb.y == kOutside ? 1.0 : paintedAmount(states[nb.y], now);
    // Classic edges between two painted regions dissolve, so finished areas read as a painting;
    // a coloring book's drawing stays over the paint whole.
    float visible = book ? 1.0 : 1.0 - min(left, right);
    // A classic template outlines the selected color's unpainted cells boldly, so every cell to
    // paint stands out. In a coloring book nothing is outlined for being selected: the drawing is
    // the drawing (strokes inside cells only come with one).
    bool hasSelection = u.selected.a > 0.5 && !book;
    bool selLeft = hasSelection && int(regionColors[nb.x].w + 0.5) == u.ids.x && left < 1.0;
    bool selRight = hasSelection && nb.y != kOutside && int(regionColors[nb.y].w + 0.5) == u.ids.x && right < 1.0;
    bool selected = selLeft || selRight;
    float lineWidth = u.lineWidth[layer];
    float lineAlpha = u.lineAlpha[layer];
    float width = selected ? max(u.outline.y, lineWidth) : lineWidth;
    // Thinner than a pixel: keep one pixel and fade instead, so lines never shimmer.
    float drawn = max(width, 1.0);
    float alpha = (selected ? max(lineAlpha, u.ink.a) : lineAlpha) * visible * (width / drawn) * (selected ? 1.3 : 1.0);
    float hw = 0.5 * drawn;

    float2 a = toPixels(points[seg.x], u);
    float2 b = toPixels(points[seg.x + 1], u);
    float2 ab = b - a;
    float len = length(ab);
    float2 dir = len > 1e-5 ? ab / len : float2(1.0, 0.0);
    float2 nrm = float2(-dir.y, dir.x);
    float ext = hw + 1.0;
    float2 corner = ((vid & 1u) != 0u ? b + dir * ext : a - dir * ext) + nrm * ((vid & 2u) != 0u ? ext : -ext);
    o.position = alpha < 0.002 ? float4(-2.0, -2.0, 0.0, 1.0) : toClip(corner, u);
    o.ends = float4(a, b);
    o.halfWidth = hw;
    o.alpha = min(alpha, 1.0);
    // A stroke lies in one region (both sides), so `left` is how far the paint has covered it.
    o.light = lightWriting ? left : 0.0;
    return o;
}

fragment float4 outlineFragment(OutlineOut in [[stage_in]]) {
    float2 p = in.position.xy;
    float2 a = in.ends.xy;
    float2 ba = in.ends.zw - a;
    float2 pa = p - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    float d = length(pa - ba * h);
    float coverage = saturate(in.halfWidth + 0.5 - d) * in.alpha;
    return float4(coverage, coverage * in.light, 0.0, 0.0);
}

// Pass 2: composite the ink opacity over the fills, in the ink or, where writing over a dark paint
// is, the light tone it has turned to.
fragment float4 outlineCompositeFragment(RectOut in [[stage_in]],
                                         texture2d<half, access::read> coverage [[texture(0)]],
                                         constant FrameUniforms &u [[buffer(0)]]) {
    float2 c = float2(coverage.read(uint2(in.position.xy)).rg);
    float a = c.x;
    float light = a > 0.0 ? saturate(c.y / a) : 0.0;
    return float4(mix(u.ink.rgb, u.lightInk.rgb, light) * a, a);
}

// MARK: - Numbers

struct GlyphOut {
    float4 position [[position]];
    float2 uv;
    float alpha [[flat]];
    float weight [[flat]];
};

vertex GlyphOut glyphVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            const device GlyphInstance *glyphs [[buffer(0)]],
                            constant float4 *digitRects [[buffer(1)]],
                            constant float4 *digitUVs [[buffer(2)]],
                            const device RegionState *states [[buffer(3)]],
                            const device float4 *regionColors [[buffer(4)]],
                            constant FrameUniforms &u [[buffer(5)]]) {
    GlyphInstance g = glyphs[iid];
    float now = u.time.x;
    float fontPx = g.size * u.transform.z;
    float legible = smoothstep(u.labels.x, u.labels.y, fontPx);
    fontPx = min(fontPx, u.labels.z);
    // A number tapped with the wrong paint pops up so it can be read at any zoom. Under
    // Reduce Motion it shows at the larger size at once and fades out instead of scaling.
    float bump = 0.0;
    if (int(g.region) == u.ids.w) {
        float t = now - u.time.w;
        if (t >= 0.0 && t < 1.4) {
            bool still = u.numbers.w > 0.5;
            float fade = 1.0 - smoothstep(0.8, 1.4, t);
            bump = (still ? 1.0 : sin(min(t / 0.16, 1.0) * 1.5707963)) * fade;
            fontPx = mix(fontPx, max(fontPx * 1.3, u.labels.w), still ? 1.0 : bump);
        }
    }
    // A mosaic's grout is set from the start, so its numbers never show.
    float coverage = u.tiles.x > 0.5 ? tileCoverage(states[g.region], now, u)
        : samplePaint(states[g.region], g.center, now, 1.0 / u.transform.z).coverage;
    bool selected = u.selected.a > 0.5 && int(regionColors[g.region].w + 0.5) == u.ids.x;
    float visibility = max(legible * u.outline.w, bump);
    float alpha = visibility * (1.0 - coverage) * (selected || bump > 0.0 ? u.numbers.y : u.numbers.x);

    float4 rect = digitRects[g.digit];
    float4 uvRect = digitUVs[g.digit];
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
    float2 em = float2(g.offset, 0.0) + mix(rect.xy, rect.zw, corner);
    float2 p = toPixels(g.center, u) + em * fontPx;
    GlyphOut o;
    o.position = alpha < 0.004 ? float4(-2.0, -2.0, 0.0, 1.0) : toClip(p, u);
    o.uv = mix(uvRect.xy, uvRect.zw, corner);
    o.alpha = alpha;
    o.weight = selected ? u.numbers.z : 0.0;
    return o;
}

fragment float4 glyphFragment(GlyphOut in [[stage_in]],
                              texture2d<float> atlas [[texture(0)]],
                              constant FrameUniforms &u [[buffer(0)]]) {
    constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
    float d = atlas.sample(bilinear, in.uv).r;
    float w = max(fwidth(d), 1e-3) * 0.7;
    float edge = 0.5 - in.weight;
    float a = smoothstep(edge - w, edge + w, d) * in.alpha;
    return float4(u.ink.rgb * a, a);
}

// MARK: - Source photo

// The photo the painting was made from, over the canvas rect (drawn with canvasRectVertex,
// margin 0). UVs come from the same transform as the fills, so it lines up exactly at any
// zoom and pan; mipmaps keep zoomed-out views free of aliasing.
fragment float4 photoFragment(RectOut in [[stage_in]],
                              texture2d<float> photo [[texture(0)]],
                              constant FrameUniforms &u [[buffer(0)]]) {
    constexpr sampler trilinear(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 uv = (in.position.xy - u.transform.xy) / (u.viewport.zw * u.transform.z);
    float a = u.photo.x;
    return float4(photo.sample(trilinear, uv).rgb * a, a);     // premultiplied
}

// MARK: - Brush (drag painting)

vertex RectOut brushVertex(uint vid [[vertex_id]], constant FrameUniforms &u [[buffer(0)]]) {
    float r = u.brush.z + 3.0 * u.transform.w;
    float2 p = u.brush.xy + float2((vid & 1u) != 0u ? r : -r, (vid & 2u) != 0u ? r : -r);
    RectOut o;
    o.position = toClip(p, u);
    return o;
}

fragment float4 brushFragment(RectOut in [[stage_in]], constant FrameUniforms &u [[buffer(0)]]) {
    float pt = u.transform.w;
    float d = distance(in.position.xy, u.brush.xy);
    float r = u.brush.z;
    float inside = 1.0 - smoothstep(r - 0.5, r + 0.5, d);
    float ring = saturate(1.0 - abs(d - r) / (0.9 * pt));
    float halo = saturate(1.0 - abs(d - r - 1.4 * pt) / (0.8 * pt));
    // Premultiplied: a tinted disc, a white rim and a faint dark halo for contrast on light paint.
    float fill = 0.28 * inside * (1.0 - ring);
    float3 rgb = u.selected.rgb * fill + float3(0.95 * ring);
    float a = fill + 0.95 * ring + 0.25 * halo * (1.0 - ring);
    return float4(rgb, a) * u.brush.w;
}
