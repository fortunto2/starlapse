#include <metal_stdlib>
using namespace metal;

// Accumulation runs in RGBA32Float. Eight-bit frames summed into an 8-bit buffer would
// clip after a handful of frames and quantise the very shadow detail the whole exercise
// exists to recover; float32 holds an hour of summation without breaking a sweat.

struct StackParams {
    // Maps accumulator coordinates to frame coordinates — the inverse of the sky's
    // rotation, so a star lands on the same texel in every frame.
    float3x3 transform;
    uint mode;        // 0 = sum (averaged on resolve), 1 = lighten (trails), 2 = replace
    uint frameIndex;
    uint useTransform;
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

// MARK: - Accumulation

kernel void accumulate(texture2d<float, access::sample> frame [[texture(0)]],
                       texture2d<float, access::read_write> accumulator [[texture(1)]],
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
        accumulator.write(incoming, gid);
        return;
    }

    float4 existing = accumulator.read(gid);

    if (params.mode == 1) {
        // Lighten: brightest value wins, per channel. Star trails are literally the union
        // of every position a star occupied, which is exactly max() over time.
        accumulator.write(max(existing, incoming), gid);
    } else {
        // Running sum. Divided by the frame count at resolve time, so a session can be
        // previewed at any point without disturbing the accumulation.
        accumulator.write(existing + incoming, gid);
    }
}

kernel void clear_accumulator(texture2d<float, access::write> accumulator [[texture(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= accumulator.get_width() || gid.y >= accumulator.get_height()) {
        return;
    }
    accumulator.write(float4(0.0), gid);
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
                    constant uint &frameCount [[buffer(1)]],
                    constant uint &mode [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= display.get_width() || gid.y >= display.get_height()) {
        return;
    }

    float4 accumulated = accumulator.read(gid);

    // Lighten mode is already a finished image; summation needs the divide.
    float3 linearColor = (mode == 1)
        ? accumulated.rgb
        : accumulated.rgb / max(float(frameCount), 1.0);

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
    float value = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    luma.write(float4(value, value, value, 1.0), gid);
}
