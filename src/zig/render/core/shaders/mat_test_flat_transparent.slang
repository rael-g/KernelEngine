// Built-in flat material bound into the transparent-forward pass. The TestFlat
// body is identical to mat_test_flat.slang's/mat_test_flat_gbuffer.slang's —
// the duplication is the hand-written stand-in for the per-material manifest
// codegen (§8), which will emit one wrapper per pass per authored material
// from a single material definition. Until then, a material used in every
// path is written once per path.

import ke;
import transparent_forward;

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
    }
}

static TestFlat _mat;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target { return ke_transparent_fs(_mat, input); }
