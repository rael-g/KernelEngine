// Both-off twin of mat_test_flat.slang: FullyLit (no shadow) + NoIndirect (no
// IBL) — imports neither shadow_feature.slang nor ibl_feature.slang. Selected
// by render_module.zig when both enable_shadows and enable_ibl are false.

import ke;
import forward_lit;
import cluster_feature;

struct TestFlatNoShadowNoIbl : IMaterial {
    void vertex(inout VertexInfo v) {
        // Flat material: no vertex deformation.
    }
    void fragment(inout SurfaceState s) {
        s.albedo    = mat.base_color.rgb * albedo.Sample(tex_sampler, s.uv).rgb;
        s.metallic  = mat.metallic;
        s.roughness = mat.roughness;
        float3 tn   = normal_map.Sample(tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal    = normalize(mul(tn, s.tbn));
    }
}

static TestFlatNoShadowNoIbl _mat;
static FullyLit _vis;
static NoIndirect _ibl;
static ClusteredLights _lights;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target { return ke_forward_fs(_mat, _vis, _ibl, _lights, input); }
