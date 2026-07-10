// Deferred lighting pass — the opaque path's second half. A fullscreen
// triangle that reads the G-buffer (gbuffer.slang wrote it) + the depth buffer,
// reconstructs world position from depth + inverse view-proj, decodes the
// surface, then shades it with the SAME hooks the forward pass calls:
// sample_shadow_visibility, accumulate_clustered_lights, ibl_contribution, and
// ke.pbr's pbr_direct. That the shading library runs unchanged here (a
// fullscreen dispatch) and in a forward fragment is the whole point of §8.12 —
// the library is topology-agnostic. Writes "hdr" (the same resource tonemap
// reads), so tonemap needs no changes.

import ke;               // pbr_direct (ke.pbr)
import gbuffer_encoding;  // ke_oct_decode
import shadow_feature;    // sample_shadow_visibility (set 0: 4,5,6)
import ibl_feature;       // ibl_contribution        (set 0: 7,8)
import cluster_feature;   // accumulate_clustered_lights (set 3)

// Set 0 binding 0 — per-frame. Bindings 4-8 are the shadow + IBL feature
// resources (declared in their own files), so this set's layout must match
// forward's frame set for those hooks to resolve. inv_view_proj reconstructs
// world position from the depth buffer; view gives the cluster z slice.
struct DeferredFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;   // rgb, w = intensity
    float4   ambient;
    float4   shadow_params; // z = directional-light active
    float4   viewport;      // x = width, y = height (px)
    float4x4 view;          // world → view (cluster z slice)
    float4x4 inv_view_proj; // clip → world (position reconstruction)
};
[[vk::binding(0, 0)]] ConstantBuffer<DeferredFrame> frame;

// Set 1 — the G-buffer, read by exact texel fetch (fullscreen 1:1, no sampler).
[[vk::binding(0, 1)]] Texture2D<float4> g_albedo;   // rgb albedo, a metallic
[[vk::binding(1, 1)]] Texture2D<float4> g_normal;   // rg octNormal, b roughness, a ao
[[vk::binding(2, 1)]] Texture2D<float4> g_emissive; // rgb emissive, a alpha
[[vk::binding(3, 1)]] Texture2D<float>  g_depth;    // D32 depth (unfilterable float)

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID) {
    // Fullscreen triangle covering the NDC square (no vertex buffer).
    float2 pos = float2((vid & 1u) ? 3.0 : -1.0,
                        (vid & 2u) ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target0 {
    int2 px = int2(input.clip.xy); // fragment pixel coords → exact G-buffer texel

    float depth = g_depth.Load(int3(px, 0)).x;
    // A texel the geometry never wrote keeps the depth clear (1.0 = far plane).
    // Nothing to shade there — the skybox pass fills the background afterward.
    if (depth >= 1.0) discard;

    // Reconstruct world position: the homogeneous clip point (ndc.xy, depth, 1)
    // pushed back through inv_view_proj, then perspective-divided. ndc.y uses
    // the WGPU framebuffer→NDC relation (y down in pixels, up in NDC); the
    // y-flip the projection applied is already baked into inv_view_proj.
    float2 ndc = float2(input.uv.x * 2.0 - 1.0, 1.0 - input.uv.y * 2.0);
    float4 h = mul(frame.inv_view_proj, float4(ndc, depth, 1.0));
    float3 world_pos = h.xyz / h.w;

    // Decode the surface from the G-buffer.
    float4 a0 = g_albedo.Load(int3(px, 0));
    float4 a1 = g_normal.Load(int3(px, 0));
    float4 a2 = g_emissive.Load(int3(px, 0));
    float3 albedo_c  = a0.rgb;
    float  metallic  = a0.a;
    float3 n         = ke_oct_decode(a1.rg);
    float  rough     = a1.b;
    float  ao        = a1.a;
    float3 emissive  = a2.rgb;
    float  alpha     = a2.a;

    float3 v  = normalize(frame.camera_pos.xyz - world_pos);
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo_c, metallic);

    float3 lit = float3(0.0, 0.0, 0.0);

    if (frame.shadow_params.z > 0.5) {
        float3 l        = -normalize(frame.light_dir.xyz);
        float3 radiance = frame.light_color.rgb * frame.light_color.w;
        float  shadow   = sample_shadow_visibility(world_pos);
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance) * shadow;
    }

    float view_z = mul(frame.view, float4(world_pos, 1.0)).z;
    lit += accumulate_clustered_lights(n, v, albedo_c, f0, metallic, rough, world_pos, input.clip.xy, view_z);

    float3 ibl     = ibl_contribution(n, v, albedo_c, metallic);
    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic) * ao;
    float3 color   = ambient + lit + emissive + ibl;

    // Linear HDR out — the ACES tonemap pass owns the tone curve + display gamma.
    return float4(color, alpha);
}
