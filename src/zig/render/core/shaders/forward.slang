// Forward lit mesh — minimal directional lighting. No IMaterial template (that
// is §8, deferred); direct entry points. Matrices arrive row-major (row-vector
// convention) so Slang's mul(M, v) lowering to WGSL transforms correctly.

struct VsIn {
    float3 position : POSITION;
    float3 normal   : NORMAL;
};

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float3 world_normal : NORMAL;
};

struct Globals {
    float4x4 mvp;        // model * view * proj (precomputed per object)
    float4x4 model;      // for transforming the normal to world space
    float4   light_dir;  // xyz = direction the light travels (normalized)
    float4   base_color; // rgb
};

[[vk::binding(0, 0)]] ConstantBuffer<Globals> g;

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    o.clip = mul(g.mvp, float4(input.position, 1.0));
    o.world_normal = mul((float3x3)g.model, input.normal);
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    float3 n = normalize(input.world_normal);
    float ndotl = max(dot(n, -normalize(g.light_dir.xyz)), 0.0);
    float3 lit = g.base_color.rgb * (0.15 + 0.85 * ndotl);
    return float4(lit, 1.0);
}
