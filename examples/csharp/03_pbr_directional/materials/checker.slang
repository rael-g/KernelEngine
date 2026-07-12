// checker — an example-owned material (NOT shipped by the engine). Lives in
// this example's own materials/ directory to prove a downstream project can
// author its own IMaterial shader alongside the engine defaults ("standard")
// without touching src/shaders/materials/ at all. A UV checkerboard toggling
// between the material's base color and its complement — a fragment-only
// difference, same proof shape as the engine's "stripes".

import ke;              // VertexInfo, SurfaceState, IMaterial
import forward_common;  // the fixed engine material set (set 1): mat, albedo, normal_map, tex_sampler

struct Checker : IMaterial {
    void vertex(inout VertexInfo v) {
        // No vertex deformation — the difference is fragment-only.
    }

    void fragment(inout SurfaceState s) {
        float4 tex   = albedo.Sample(tex_sampler, s.uv);
        bool   tile  = (uint(s.uv.x * 8.0) + uint(s.uv.y * 8.0)) % 2 == 0;
        float3 base  = mat.base_color.rgb * tex.rgb;
        s.albedo     = tile ? base : (float3(1.0) - base);
        s.alpha      = mat.base_color.a * tex.a;
        s.metallic   = mat.metallic;
        s.roughness  = mat.roughness;
        float3 tn    = normal_map.Sample(tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal     = normalize(mul(tn, s.tbn));

        if (s.alpha < mat.alpha_cutoff) discard;
    }
}
