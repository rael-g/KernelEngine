// Second built-in material for the gbuffer encode pass — deliberately a
// SHADER difference (a UV-derived stripe pattern no uniform buffer could
// express), not a data difference, proving materials can select distinct PSOs
// at runtime (§6 Mechanism 1) rather than only varying bind-group contents.
// See TestFlat (mat_test_flat_gbuffer.slang) for the shape this mirrors.

import ke;
import gbuffer;

struct Stripes : IMaterial {
    void vertex(inout VertexInfo v) {
        // No vertex deformation — the proof is a fragment-only shader diff.
    }
    void fragment(inout SurfaceState s) {
        float4 tex  = albedo.Sample(tex_sampler, s.uv);
        s.albedo    = mat.base_color.rgb * tex.rgb;
        s.alpha     = mat.base_color.a * tex.a;
        s.metallic  = mat.metallic;
        s.roughness = mat.roughness;
        float3 tn   = normal_map.Sample(tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal    = normalize(mul(tn, s.tbn));

        float stripe = step(0.5, frac(s.uv.x * 8.0));
        s.emissive = stripe * s.albedo;

        if (s.alpha < mat.alpha_cutoff) discard;
    }
}

static Stripes _mat;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
GBufferOut fs_main(VsOut input) { return ke_gbuffer_fs(_mat, input); }
