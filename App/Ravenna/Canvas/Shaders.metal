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
                             constant FrameUniforms &u [[buffer(2)]]) {
    uint r = in.region;
    float4 info = regionColors[r];
    RegionState s = states[r];
    float now = u.time.x;
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
    PaintSample ps = samplePaint(states[g.region], g.center, now, 1.0 / u.transform.z);
    bool selected = u.selected.a > 0.5 && int(regionColors[g.region].w + 0.5) == u.ids.x;
    float visibility = max(legible * u.outline.w, bump);
    float alpha = visibility * (1.0 - ps.coverage) * (selected || bump > 0.0 ? u.numbers.y : u.numbers.x);

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
