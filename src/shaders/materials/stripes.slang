import ke;
import forward_common;

struct Stripes : IMaterial {
    void vertex(inout VertexInfo v) {
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
