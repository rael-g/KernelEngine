// Built-in flat material. Binds the TestFlat IMaterial conformance into the
// engine ForwardLit pass. This wrapper is the hand-written stand-in for what
// the material-manifest codegen will emit per authored material in a later
// phase (§8): a struct implementing IMaterial + the two entry points that call
// the engine's generic ke_forward_vs / ke_forward_fs with the concrete type.

import ke;
import forward_lit;
import shadow_feature;

struct TestFlat : IMaterial {
    void vertex(inout VertexInfo v) {
        // Flat material: no vertex deformation.
    }
    void fragment(inout SurfaceState s) {
        // Source the surface from the fixed engine material set (set 1): the
        // base-color UBO modulated by the albedo texture, plus tangent-space
        // normal mapping — matching forward.slang's flat-lit result.
        s.albedo    = mat.base_color.rgb * albedo.Sample(tex_sampler, s.uv).rgb;
        s.metallic  = mat.metallic;
        s.roughness = mat.roughness;
        float3 tn   = normal_map.Sample(tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal    = normalize(mul(tn, s.tbn));
    }
}

static TestFlat _mat;
static ShadowMapVisibility _vis;

[shader("vertex")]
VsOut vs_main(VsIn input) { return ke_forward_vs(_mat, input); }

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target { return ke_forward_fs(_mat, _vis, input); }
