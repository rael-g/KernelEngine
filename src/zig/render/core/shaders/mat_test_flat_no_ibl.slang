// No-IBL twin of mat_test_flat.slang: identical material and pass, shadows
// still linked (ShadowMapVisibility), but ambient/reflection contribution is
// NoIndirect (ke.slang's no-op IIndirect) instead of IndirectIBL — this file
// never imports ibl_feature.slang. Selected by render_module.zig when
// enable_ibl is false and shadows are on.

import ke;
import forward_lit;
import shadow_feature;
import cluster_feature;

struct TestFlatNoIbl : IMaterial {
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

static TestFlatNoIbl _mat;
static ShadowMapVisibility _vis;
static NoIndirect _ibl;
static ClusteredLights _lights;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target { return ke_forward_fs(_mat, _vis, _ibl, _lights, input); }
