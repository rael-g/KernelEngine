// standard — the engine default material: glTF metallic-roughness surface
// (engine material UBO × albedo texture, tangent-space normal map, MASK
// cutoff). An authored material and nothing more: it declares no entry point,
// imports no pass, and does not know whether it will be encoded into a
// G-buffer or shaded inline. The build generates one wrapper per (material ×
// consuming pass) from this single definition.

import ke;              // VertexInfo, SurfaceState, IMaterial
import forward_common;  // the fixed engine material set (set 1): mat, albedo, normal_map, tex_sampler

struct Standard : IMaterial {
    void vertex(inout VertexInfo v) {
        // Flat material: no vertex deformation.
    }

    void fragment(inout SurfaceState s) {
        float4 tex  = albedo.Sample(tex_sampler, s.uv);
        s.albedo    = mat.base_color.rgb * tex.rgb;
        s.alpha     = mat.base_color.a * tex.a;
        s.metallic  = mat.metallic;
        s.roughness = mat.roughness;
        float3 tn   = normal_map.Sample(tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal    = normalize(mul(tn, s.tbn));

        // MASK: opaque with a hard cutoff, never a blend. OPAQUE/BLEND materials
        // carry alpha_cutoff == 0.0, so this never discards them.
        if (s.alpha < mat.alpha_cutoff) discard;
    }
}
