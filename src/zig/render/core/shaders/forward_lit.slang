// Forward PBR pass, generic over IMaterial. The surface (albedo/metallic/
// roughness/normal) comes from the author's material.fragment() via the shared
// ke_surface_from_vertex prologue (forward_common.slang); the shading math is
// the shared ke.pbr library — the same pbr_direct the deferred-lighting pass
// calls, proving the shading library is topology-agnostic (§8.12).
//
// PARKED (2026-07-06): with the deferred opaque path live, this pass is not
// wired into the default chain. It stays compiled + correct as the reference
// for the upcoming transparency (forward+) pass. See render_module.zig.

import ke;                    // SurfaceState, IMaterial, ke.pbr (pbr_direct, …)
__exported import forward_common; // VsIn/VsOut/PerObject/Material + ke_forward_vs / ke_surface_from_vertex
import shadow_feature;        // sample_shadow_visibility — neutral default when off (white shadow map)
import ibl_feature;           // ibl_contribution — neutral default when off (black env cube)
import cluster_feature;       // accumulate_clustered_lights — neutral default when off (empty light lists)

// Set 0 — per frame. shadow_map/light_vp live in shadow_feature.slang,
// env/env_sampler in ibl_feature.slang, and cluster_grid + the light lists in
// cluster_feature.slang — this file declares none of them, but always calls
// their plain hook functions; a neutral-default resource makes each a no-op
// when its feature is off. shadow_params.z = directional-light-active flag.
struct PerFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4x4 sky_view_proj;
    float4   shadow_params;
    float4x4 view;
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;

float4 ke_forward_fs<T : IMaterial>(T material, VsOut input) {
    SurfaceState s = ke_surface_from_vertex(material, input);

    float3 albedo_c = s.albedo;
    float  metallic = s.metallic;
    float  rough    = s.roughness;
    float3 n        = normalize(s.normal);

    float3 v  = normalize(frame.camera_pos.xyz - input.world_pos);
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo_c, metallic);

    float3 lit = float3(0.0, 0.0, 0.0);

    if (frame.shadow_params.z > 0.5) {
        float3 l        = -normalize(frame.light_dir.xyz);
        float3 radiance = frame.light_color.rgb * frame.light_color.w;
        float  shadow   = sample_shadow_visibility(input.world_pos);
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance) * shadow;
    }

    float  view_z = mul(frame.view, float4(input.world_pos, 1.0)).z;
    lit += accumulate_clustered_lights(n, v, albedo_c, f0, metallic, rough, input.world_pos, input.clip.xy, view_z);

    float3 ibl = ibl_contribution(n, v, albedo_c, metallic);

    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic);
    float3 color   = ambient + lit + s.emissive;
    color += ibl;

    // Linear HDR out — the ACES tonemap pass does the tone curve + display
    // gamma on resolve. Do not tonemap/gamma here (double-compresses).
    return float4(color, s.alpha);
}
