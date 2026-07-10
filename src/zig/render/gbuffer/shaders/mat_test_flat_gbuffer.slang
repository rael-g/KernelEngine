// Built-in flat material bound into the deferred G-buffer encode pass. The
// TestFlat body is identical to mat_test_flat.slang's (the forward wrapper) —
// the duplication is the hand-written stand-in for the per-material manifest
// codegen (§8), which will emit one encode wrapper + one forward wrapper per
// authored material from a single material definition. Until then, a material
// used in both paths is written twice.

import ke;
import gbuffer;

struct TestFlat : IMaterial {
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

        // MASK: opaque with a hard cutoff, never a blend. OPAQUE materials carry
        // alpha_cutoff == 0.0, so this never discards them (alpha is never < 0).
        if (s.alpha < mat.alpha_cutoff) discard;
    }
}

static TestFlat _mat;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
GBufferOut fs_main(VsOut input) { return ke_gbuffer_fs(_mat, input); }
