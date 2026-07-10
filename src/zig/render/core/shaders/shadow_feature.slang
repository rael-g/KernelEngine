// Shadow hook — a plain function reading a neutral-default resource.
// deferred_lighting.slang and transparent_forward.slang both always call
// sample_shadow_visibility(); when no shadow module produces real
// data, shadowMap is bound to the engine's 1x1 white default texture, which
// makes this function return 1.0 (fully lit) for every fragment — the neutral
// element for a visibility factor. There is no generic conformance to select;
// the hook is realized by which resource is bound, not by which type is linked.
//
// Resources are pinned module-scope globals in SET 0 (bindings 4-6, appended
// after frame/env/env_sampler/shadow_map at 0-3) — the same pattern as
// frame/env/mat/obj elsewhere in this file tree. Pinning the binding here
// keeps it deterministic regardless of what else is compiled into the module.
//
// A dedicated set 4 was considered and rejected: the C ABI's
// ke_gpu_render_pipeline_params.bind_group_layouts is fixed at 4 entries
// (sets 0-3) — a hard ABI limit, not a convenience choice. A bind-group
// LAYOUT itself has no such cap on entries *within* one set, so extending
// set 0 (already bound once per frame, before any per-mesh pipeline
// selection) needs no ABI change and no new bind() call at draw time.

import ke;

struct ShadowFeatureParams {
    float4x4 lightVP;
};
[[vk::binding(4, 0)]] ConstantBuffer<ShadowFeatureParams> shadowParams;
[[vk::binding(5, 0)]] Texture2D    shadowMap;
[[vk::binding(6, 0)]] SamplerState shadowSampler;

float sample_shadow_visibility(float3 worldPos) {
    float4 sc = mul(shadowParams.lightVP, float4(worldPos, 1.0));
    float3 coord = sc.xyz / sc.w;
    coord.x = coord.x * 0.5 + 0.5;
    coord.y = -coord.y * 0.5 + 0.5;
    if (any(coord < 0.0) || any(coord > 1.0)) return 1.0;
    float closest = shadowMap.Sample(shadowSampler, coord.xy).r;
    return (coord.z - 0.005 > closest) ? 0.3 : 1.0;
}
