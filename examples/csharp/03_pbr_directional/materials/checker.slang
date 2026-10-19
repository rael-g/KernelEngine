import ke;
import forward_common;

struct Checker : IMaterial {
    void vertex(inout VertexInfo v) {
    }

    void fragment(inout SurfaceState s) {
        float4 tex   = mat.albedo.Sample(mat.tex_sampler, s.uv);
        bool   tile  = (uint(s.uv.x * 8.0) + uint(s.uv.y * 8.0)) % 2 == 0;
        float3 base  = mat.base_color.rgb * tex.rgb;
        s.albedo     = tile ? base : (float3(1.0) - base);
        s.alpha      = mat.base_color.a * tex.a;
        s.metallic   = mat.metallic;
        s.roughness  = mat.roughness;
        float3 tn    = mat.normal_map.Sample(mat.tex_sampler, s.uv).rgb * 2.0 - 1.0;
        s.normal     = normalize(mul(tn, s.tbn));

        if (s.alpha < mat.alpha_cutoff) discard;
    }
}
