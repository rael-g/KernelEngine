// stripes — a UV-derived emissive stripe pattern no uniform buffer could
// express, so a material selecting it resolves to a genuinely distinct PSO
// rather than only distinct bind-group contents. Like every authored material,
// it declares no entry point and imports no pass.

import ke;              // VertexInfo, SurfaceState, IMaterial
import forward_common;  // the fixed engine material set (set 1): mat, albedo, normal_map, tex_sampler

struct Stripes : IMaterial {
    void vertex(inout VertexInfo v) {
        // No vertex deformation — the difference is fragment-only.
    }

    void fragment(inout SurfaceState s) {
        float4 tex  = albedo.Sample(tex_sampler, s.uv);
        s.albedo    = mat.base_color.rgb * tex.rgb;
        s.alpha     = mat.base_color.a * tex.a;
        s.metallic  = mat.metallic;
        s.roughness = mat.roughness;
        float3 tn   = normal_map.Sample(tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal    = normalize(mul(tn, s.tbn));

        s.emissive = step(0.5, frac(s.uv.x * 8.0)) * s.albedo;

        if (s.alpha < mat.alpha_cutoff) discard;
    }
}
