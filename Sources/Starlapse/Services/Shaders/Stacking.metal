#include <metal_stdlib>
using namespace metal;

// Accumulation runs in RGBA32Float. Eight-bit frames summed into an 8-bit buffer would
// clip after a handful of frames and quantise the very shadow detail the whole exercise
// exists to recover; float32 holds an hour of summation without breaking a sweat.

struct StackParams {
    // Maps accumulator coordinates to frame coordinates — the inverse of the sky's
    // rotation, so a star lands on the same texel in every frame.
    float3x3 transform;
    uint mode;        // 0 = sigma-clipped sum (averaged on resolve), 1 = lighten, 2 = replace
    uint frameIndex;
    uint useTransform;
    float kappa;      // sigma-clip threshold; 0 disables rejection
    uint warmup;      // samples before rejection starts
};

struct ToneParams {
    float blackPoint;   // sky background level to subtract
    float stretch;      // asinh strength
    float exposure;     // linear gain applied before the stretch
    float saturation;
};

constexpr sampler linearSampler(coord::normalized,
                                address::clamp_to_edge,
                                filter::linear);

// MARK: - Decoding

// Every frame is turned into linear light before anything else touches it. The camera
// hands over values after its transfer curve, and stacking adds photons, which only
// adds up in linear space. `starlapse-stack compare` measured what skipping this cost.

struct DecodeParams {
    uint fullRange;     // 420f / xf20: codes span the full range
    float hotRatio;     // cosmetic correction: spike over brightest neighbour, ×
    float hotFloor;     // and at least this much above the darkest one, linear
};

constant float3 lumaWeights = float3(0.2126, 0.7152, 0.0722);

// ITU-R BT.709 inverse OETF.
static inline float3 bt709_to_linear(float3 value)
{
    float3 v = max(value, 0.0);
    float3 low = v / 4.5;
    float3 high = pow((v + 0.099) / 1.099, 1.0 / 0.45);
    return select(high, low, v < 0.081);
}

// Biplanar 4:2:0 → linear RGB at one luma site. Normalised plane values work for 8-bit
// and for MSB-aligned 10-bit planes alike, so one path serves 420v/420f/x420/xf20.
static inline float3 ycbcr_linear(texture2d<float, access::read> lumaPlane,
                                  texture2d<float, access::read> chromaPlane,
                                  int2 site, bool fullRange)
{
    int2 size = int2(lumaPlane.get_width(), lumaPlane.get_height());
    int2 p = clamp(site, int2(0), size - 1);
    float y = lumaPlane.read(uint2(p)).r;
    float2 c = chromaPlane.read(uint2(p / 2)).rg;

    float luma = fullRange ? y : (y - 16.0 / 255.0) / (219.0 / 255.0);
    float2 chroma = fullRange ? c - 0.5 : (c - 128.0 / 255.0) / (224.0 / 255.0);

    float3 rgb = float3(luma + 1.5748 * chroma.y,
                        luma - 0.1873 * chroma.x - 0.4681 * chroma.y,
                        luma + 1.8556 * chroma.x);
    return bt709_to_linear(saturate(rgb));
}

// Hot pixels without dark frames: a value far above all eight neighbours cannot be a
// star, because the lens spreads even the faintest one over several pixels. Replaced
// by the neighbours' mean. Same rule as StackKit's CosmeticCorrection, which measured
// it removing 95–99% of hot pixels without touching faint stars.
static inline float3 cosmetic(float3 centre, thread const float3 *neighbours, constant DecodeParams &params)
{
    float brightest = -1e9;
    float darkest = 1e9;
    float3 sum = float3(0.0);
    for (int i = 0; i < 8; i++) {
        float l = dot(neighbours[i], lumaWeights);
        brightest = max(brightest, l);
        darkest = min(darkest, l);
        sum += neighbours[i];
    }
    float excess = dot(centre, lumaWeights) - darkest;
    bool hot = excess > params.hotFloor && excess > params.hotRatio * (brightest - darkest);
    return hot ? sum / 8.0 : centre;
}

constant int2 neighbourOffsets[8] = {
    int2(-1, -1), int2(0, -1), int2(1, -1), int2(-1, 0),
    int2(1, 0), int2(-1, 1), int2(0, 1), int2(1, 1)
};

kernel void decode_ycbcr(texture2d<float, access::read> lumaPlane [[texture(0)]],
                         texture2d<float, access::read> chromaPlane [[texture(1)]],
                         texture2d<float, access::write> decoded [[texture(2)]],
                         constant DecodeParams &params [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= decoded.get_width() || gid.y >= decoded.get_height()) {
        return;
    }
    bool fullRange = params.fullRange != 0;
    int2 site = int2(gid);
    float3 centre = ycbcr_linear(lumaPlane, chromaPlane, site, fullRange);
    float3 neighbours[8];
    for (int i = 0; i < 8; i++) {
        neighbours[i] = ycbcr_linear(lumaPlane, chromaPlane, site + neighbourOffsets[i], fullRange);
    }
    decoded.write(float4(cosmetic(centre, neighbours, params), 1.0), gid);
}

// BGRA from the camera, wrapped as an _srgb texture so every read is already linear.
kernel void decode_bgra(texture2d<float, access::read> frame [[texture(0)]],
                        texture2d<float, access::write> decoded [[texture(2)]],
                        constant DecodeParams &params [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= decoded.get_width() || gid.y >= decoded.get_height()) {
        return;
    }
    int2 size = int2(frame.get_width(), frame.get_height());
    float3 centre = frame.read(gid).rgb;
    float3 neighbours[8];
    for (int i = 0; i < 8; i++) {
        uint2 p = uint2(clamp(int2(gid) + neighbourOffsets[i], int2(0), size - 1));
        neighbours[i] = frame.read(p).rgb;
    }
    decoded.write(float4(cosmetic(centre, neighbours, params), 1.0), gid);
}

// MARK: - Accumulation

kernel void accumulate(texture2d<float, access::sample> frame [[texture(0)]],
                       texture2d<float, access::read_write> accumulator [[texture(1)]],
                       texture2d<float, access::read_write> spread [[texture(2)]],
                       constant StackParams &params [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= accumulator.get_width() || gid.y >= accumulator.get_height()) {
        return;
    }

    float2 coordinate = float2(gid) + 0.5;

    if (params.useTransform != 0) {
        float3 warped = params.transform * float3(coordinate, 1.0);
        coordinate = warped.xy / warped.z;
    }

    float2 uv = coordinate / float2(accumulator.get_width(), accumulator.get_height());

    // Outside the source frame there is no light to add. Bailing out rather than clamping
    // stops the frame edges from smearing into a bright border as the field rotates.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return;
    }

    float4 incoming = frame.sample(linearSampler, uv);

    if (params.mode == 2) {
        // Framing: this frame *is* the picture. Overwriting means the caller does not have
        // to clear the accumulator first, which at full sensor resolution is a ~200 MB
        // write of zeros that the very next instruction would overwrite anyway.
        accumulator.write(float4(incoming.rgb, 1.0), gid);
        spread.write(float4(0.0), gid);
        return;
    }

    float4 existing = accumulator.read(gid);

    if (params.mode == 1) {
        // Lighten: brightest value wins, per channel. Star trails are literally the union
        // of every position a star occupied, which is exactly max() over time.
        accumulator.write(float4(max(existing.rgb, incoming.rgb), 1.0), gid);
        return;
    }

    // Running sum of accepted samples in rgb, their count in alpha — per pixel, so the
    // edge of a rotating field divides by the frames that actually reached it.
    //
    // Sigma clipping on luminance: once a pixel has `warmup` samples, a new one more than
    // `kappa` standard deviations from its running mean is left out. Stars and sky are
    // static after alignment and pass; a plane, a satellite or a hot pixel walking across
    // the aligned field is there for one frame and does not. Welford's update keeps the
    // variance in one pass without the cancellation of sum-of-squares in float.
    float n = existing.a;
    float luminance = dot(incoming.rgb, lumaWeights);
    float mean = n > 0.0 ? dot(existing.rgb, lumaWeights) / n : 0.0;
    float m2 = spread.read(gid).r;

    if (params.kappa > 0.0 && n >= float(params.warmup) && n > 1.0) {
        float sigma = sqrt(m2 / (n - 1.0));
        if (abs(luminance - mean) > params.kappa * max(sigma, 1e-4)) {
            return;
        }
    }

    float delta = luminance - mean;
    float updatedMean = mean + delta / (n + 1.0);
    spread.write(float4(m2 + delta * (luminance - updatedMean)), gid);
    accumulator.write(existing + float4(incoming.rgb, 1.0), gid);
}

kernel void clear_accumulator(texture2d<float, access::write> accumulator [[texture(0)]],
                              texture2d<float, access::write> spread [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= accumulator.get_width() || gid.y >= accumulator.get_height()) {
        return;
    }
    accumulator.write(float4(0.0), gid);
    spread.write(float4(0.0), gid);
}

// MARK: - Tone mapping

// The asinh stretch, borrowed from professional astronomical imaging (Lupton et al. 2004,
// and every serious tool since). A gamma curve lifts the faint sky and blows the bright
// stars into flat white discs at the same time; asinh is nearly linear near zero and
// logarithmic further up, so the Milky Way comes out of the noise while stars keep their
// cores and colour. This is the "correction curve" that astrophotography actually uses.
static inline float3 asinh_stretch(float3 value, float blackPoint, float stretch)
{
    float3 pedestal = max(value - blackPoint, 0.0) / max(1.0 - blackPoint, 1e-4);
    float denominator = asinh(stretch);
    if (denominator < 1e-4) {
        return pedestal;
    }
    return asinh(stretch * pedestal) / denominator;
}

kernel void resolve(texture2d<float, access::read> accumulator [[texture(0)]],
                    texture2d<float, access::write> display [[texture(1)]],
                    constant ToneParams &tone [[buffer(0)]],
                    constant uint &mode [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= display.get_width() || gid.y >= display.get_height()) {
        return;
    }

    float4 accumulated = accumulator.read(gid);

    // Lighten mode is already a finished image; summation divides by this pixel's own
    // count of accepted samples. Dividing by the session's frame count instead darkened
    // the edges of a rotating field to half: frames that never reached a pixel counted
    // as black samples there.
    float3 linearColor = (mode == 1)
        ? accumulated.rgb
        : accumulated.rgb / max(accumulated.a, 1.0);

    linearColor *= tone.exposure;

    float3 stretched = asinh_stretch(saturate(linearColor), tone.blackPoint, tone.stretch);

    // Saturation is pushed after the stretch: star colour is real physical information
    // (blue giants against orange dwarfs) and the stretch flattens it.
    float luma = dot(stretched, float3(0.2126, 0.7152, 0.0722));
    stretched = mix(float3(luma), stretched, tone.saturation);

    display.write(float4(saturate(stretched), 1.0), gid);
}

// MARK: - Presentation

// Drawing the preview needs an actual render pass, not a blit. A blit copies pixel for
// pixel, so a 4032-wide sensor frame lands in a 1179-wide drawable as its top-left corner —
// which looks exactly like a broken camera. This scales instead, letterboxing to preserve
// the aspect ratio of the sky.

struct PresentVertex {
    float4 position [[position]];
    float2 uv;
};

vertex PresentVertex present_vertex(uint vertexID [[vertex_id]])
{
    // One oversized triangle covering the viewport — cheaper than a quad and with no seam.
    float2 positions[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    float2 coordinates[3] = { float2(0.0, 2.0), float2(0.0, 0.0), float2(2.0, 0.0) };

    PresentVertex out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = coordinates[vertexID];
    return out;
}

fragment float4 present_fragment(PresentVertex in [[stage_in]],
                                 texture2d<float, access::sample> source [[texture(0)]],
                                 constant float2 &scale [[buffer(0)]])
{
    // Aspect-fit: pull the sampling window in on whichever axis is over-wide, and paint
    // the remainder black rather than stretching the sky.
    float2 uv = (in.uv - 0.5) * scale + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return source.sample(linearSampler, uv);
}

// MARK: - Star detection support

// Luminance, downsampled by a fixed factor. Star finding does not need full resolution —
// it needs centroids, and a quarter-size buffer is 16× less data to pull back to the CPU
// while still locating a star to well under a pixel after centroiding.
kernel void downsample_luma(texture2d<float, access::sample> frame [[texture(0)]],
                            texture2d<float, access::write> luma [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= luma.get_width() || gid.y >= luma.get_height()) {
        return;
    }

    float2 uv = (float2(gid) + 0.5) / float2(luma.get_width(), luma.get_height());
    float4 color = frame.sample(linearSampler, uv);
    float value = dot(color.rgb, lumaWeights);
    luma.write(float4(value, value, value, 1.0), gid);
}
