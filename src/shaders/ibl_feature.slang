// IBL hook — a plain function reading a neutral-default resource.
// deferred_lighting.slang and transparent_forward.slang both always call
// ibl_contribution(); when no IBL module produces a real
// environment, ibl_env is bound to the engine's black default cubemap, which
// makes this function return 0 for every fragment — the neutral element for
// an additive indirect term. There is no generic conformance to select; the
// hook is realized by which resource is bound, not by which type is linked.
//
// Resources are pinned module-scope globals in set 0 (bindings 7-8, continuing
// after the shadow feature's 4-6 — see shadow_feature.slang for why pinning
// beats a generic-owned resource field). The env cubemap is the same resource
// the skybox pass (skybox.slang, a separate compiled module) also binds at its
// own fixed 1/2 — bound twice at different slots in the shared set-0 bind
// group is harmless (WebGPU allows the same resource at multiple bindings);
// the two passes are decoupled at the source level even though they share
// physical data today.

import ke;

[[vk::binding(7, 0)]] TextureCube  ibl_env;
[[vk::binding(8, 0)]] SamplerState ibl_env_sampler;

float3 ibl_contribution(float3 n, float3 v, float3 albedo, float metallic) {
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 f_ibl       = f0 + (1.0 - f0) * pow(saturate(1.0 - max(dot(n, v), 0.0)), 5.0);
    float3 ibl_spec    = ibl_env.Sample(ibl_env_sampler, reflect(-v, n)).rgb * f_ibl;
    float3 ibl_diffuse = ibl_env.Sample(ibl_env_sampler, n).rgb * albedo * (1.0 - metallic) * (1.0 - f_ibl);
    return ibl_spec + ibl_diffuse;
}
