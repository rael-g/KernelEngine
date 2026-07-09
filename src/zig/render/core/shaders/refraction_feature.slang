// Refraction hook — the fourth and last term the transparent-forward pass
// needs. Unlike shadow/ibl/cluster (which have a neutral default and are
// meaningful when absent), refraction only ever runs inside the transparent
// pass itself: opaque/masked surfaces shade through the G-buffer and never
// call this. There is no "off" state to make neutral.
//
// A G-buffer cannot express this term at all — it holds one shaded surface per
// pixel, so there is nothing "behind" a G-buffer fragment to sample. The
// transparent-forward pass snapshots the frame's already-shaded color into
// "hdr_opaque" (a plain texture copy, issued once per frame before this pass's
// render pass opens) precisely so this hook has something to read without a
// read/write hazard against the "hdr" target it's also writing to.
//
// Resources continue set 0's shadow/ibl gap-filling convention (bindings 1-2;
// see shadow_feature.slang for why appending set 0 beats a 5th set).

import ke;

[[vk::binding(1, 0)]] Texture2D    hdr_opaque;
[[vk::binding(2, 0)]] SamplerState hdr_opaque_sampler;

// screen_uv is the fragment's own position normalized to [0,1] (SV_Position / viewport).
// ior: index of refraction (1.0 = no bend/air, 1.33 = water, 1.5 = glass).
float3 refraction_contribution(float3 n, float3 v, float2 screen_uv, float ior) {
    float3 refracted = refract(-v, n, 1.0 / max(ior, 1.0));
    // Visual distortion strength — how far the refracted ray's lateral
    // deviation shifts the sampled background, in normalized screen space.
    // A tuning constant, not a physical one; promote to a material field
    // if content ever needs per-material control (glass vs. thick water).
    const float DISTORTION_STRENGTH = 0.05;
    float2 uv = saturate(screen_uv + refracted.xy * DISTORTION_STRENGTH);
    return hdr_opaque.Sample(hdr_opaque_sampler, uv).rgb;
}
