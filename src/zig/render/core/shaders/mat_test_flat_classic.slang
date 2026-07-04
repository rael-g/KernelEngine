// Classic-forward comparison twin of mat_test_flat.slang: identical material
// and pass, only the light-iteration feature differs (AllLights instead of
// ClusteredLights) — isolates the froxel-cull cost so the two can be compared
// at the same light count.

import ke;
import forward_lit;
import shadow_feature;
import ibl_feature;
import all_lights_feature;

struct TestFlatClassic : IMaterial {
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

static TestFlatClassic _mat;
static ShadowMapVisibility _vis;
static IndirectIBL _ibl;
static AllLights _lights;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target { return ke_forward_fs(_mat, _vis, _ibl, _lights, input); }
