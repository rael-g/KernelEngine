// No-shadow twin of mat_test_flat.slang: identical material and pass, but
// links FullyLit (ke.slang's no-op ILightVisibility) instead of
// ShadowMapVisibility — this file never imports shadow_feature.slang, so a
// game that opts out of shadows compiles zero shadow shader code, not a
// disabled branch. Selected by render_module.zig when shadow_enabled is false.

import ke;
import forward_lit;
import ibl_feature;
import cluster_feature;

struct TestFlatNoShadow : IMaterial {
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

static TestFlatNoShadow _mat;
static FullyLit _vis;
static IndirectIBL _ibl;
static ClusteredLights _lights;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target { return ke_forward_fs(_mat, _vis, _ibl, _lights, input); }
