// Transparent-forward pass, generic over IMaterial. The G-buffer/deferred-lighting
// half of the hybrid (§8.14) shades every OPAQUE/MASK surface; this pass is the
// other half — the only one that can express N-layer order-dependent blending,
// which a G-buffer cannot hold (one surface per pixel). Only BLEND materials
// reach it (gbuffer_module skips them; render_module.zig's draw loop here draws
// only them, sorted back-to-front).
//
// Shares the shading library with deferred-lighting.slang — the same ke.pbr +
// shadow_feature/ibl_feature/cluster_feature hooks, proving the library is
// topology-agnostic (§8.12) — plus a fourth hook deferred structurally cannot
// have: refraction_feature reads the frame's already-shaded color from before
// this pass ran, which only a pass that shades inline (not from a G-buffer) can
// do. This is the last hook the forward vocabulary needed; the pass is closed
// at four (§8.15.3).
//
// Depth-tests LEQUAL against the G-buffer's "depth" without writing it (this
// pass never occludes anything BEHIND a transparent surface — it composites
// over what deferred-lighting + skybox already shaded). Blends into "hdr".

import ke;                    // SurfaceState, IMaterial, ke.pbr (pbr_direct, …)
__exported import forward_common; // VsIn/VsOut/PerObject/Material + ke_forward_vs / ke_surface_from_vertex
import shadow_feature;        // sample_shadow_visibility — neutral default when off (white shadow map)
import ibl_feature;           // ibl_contribution — neutral default when off (black env cube)
import cluster_feature;       // accumulate_clustered_lights — neutral default when off (empty light lists)
import refraction_feature;    // refraction_contribution — no neutral default; only this pass calls it

// Set 0 — per frame. Same shadow/ibl gap-filling layout as deferred_lighting.slang's
// PerFrame, minus sky_view_proj (skybox is its own pass) and plus viewport
// (refraction needs the fragment's normalized screen position).
struct PerFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4   shadow_params; // z = directional-light-active flag
    float4   viewport;      // x=w, y=h
    float4x4 view;
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;

float4 ke_transparent_fs<T : IMaterial>(T material, VsOut input) {
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

    float view_z = mul(frame.view, float4(input.world_pos, 1.0)).z;
    lit += accumulate_clustered_lights(n, v, albedo_c, f0, metallic, rough, input.world_pos, input.clip.xy, view_z);

    float3 ibl = ibl_contribution(n, v, albedo_c, metallic);

    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic);
    float3 color   = ambient + lit + s.emissive + ibl;

    // Refraction: what's already shaded behind this fragment, bent by the
    // surface normal. Blended with the direct/indirect shading by the
    // surface's own alpha (a thin sheet of glass is mostly transmission;
    // a cloudier one is mostly its own shading) — this is the standard
    // "alpha blend against the scene-color snapshot" glass approximation.
    float3 refr = refraction_contribution(n, v, input.clip.xy / frame.viewport.xy, mat.ior, mat.distortion_strength);
    color = lerp(refr, color, s.alpha);

    // Linear HDR out — the ACES tonemap pass does the tone curve + display
    // gamma on resolve. Do not tonemap/gamma here (double-compresses).
    return float4(color, s.alpha);
}
