// Shadow feature component — an ILightVisibility conformance (§8.12 of
// RenderArchitectureV2.md). forward_lit.slang never imports this file and
// knows nothing about shadows; only a material wrapper that DOES want shadow
// sampling (see mat_test_flat.slang) imports it and specializes ke_forward_fs
// with ShadowMapVisibility.
//
// Resources are pinned module-scope globals in SET 0 (bindings 4-6, appended
// after frame/env/env_sampler/shadow_map at 0-3) — the same pattern as
// frame/env/mat/obj elsewhere in this file tree — NOT fields owned by the
// ShadowMapVisibility struct. A generic-owned resource field lets slangc's
// WGSL backend assign an unstable, auto-numbered binding (verified
// empirically: it silently shifts whenever an unrelated unused global
// elsewhere in `ke.*` changes). Pinning the binding here keeps it
// deterministic regardless of what else is compiled into the specialization.
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

struct ShadowMapVisibility : ILightVisibility {
    float visibility(float3 worldPos) {
        float4 sc = mul(shadowParams.lightVP, float4(worldPos, 1.0));
        float3 coord = sc.xyz / sc.w;
        coord.x = coord.x * 0.5 + 0.5;
        coord.y = -coord.y * 0.5 + 0.5;
        if (any(coord < 0.0) || any(coord > 1.0)) return 1.0;
        float closest = shadowMap.Sample(shadowSampler, coord.xy).r;
        return (coord.z - 0.005 > closest) ? 0.3 : 1.0;
    }
}
