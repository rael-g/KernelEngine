// Skybox — deferred background fill. A fullscreen triangle: for every pixel the
// geometry did NOT cover (G-buffer depth still at the far plane), reconstruct
// the world-space view direction and sample the environment cubemap; pixels the
// geometry covered are discarded. This replaces the old forward-embedded cube
// (drawn inside the forward pass with a hardware LEQUAL test) — in the deferred
// path the skybox is a resolve-time fill of un-written pixels, the standard
// deferred approach, needing no depth attachment.

struct SkyFrame {
    float4x4 inv_sky_view_proj; // clip → world direction (rotation-only view × proj, inverted)
};
[[vk::binding(0, 0)]] ConstantBuffer<SkyFrame> sky;
[[vk::binding(1, 0)]] TextureCube  env;
[[vk::binding(2, 0)]] SamplerState env_sampler;
[[vk::binding(3, 0)]] Texture2D<float> g_depth; // G-buffer depth (unfilterable, texel-fetched)

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID) {
    float2 pos = float2((vid & 1u) ? 3.0 : -1.0,
                        (vid & 2u) ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target0 {
    int2 px = int2(input.clip.xy);
    // Depth < far → geometry was written here; the deferred-lighting pass
    // already shaded it. The skybox only fills the untouched (far) pixels.
    if (g_depth.Load(int3(px, 0)).x < 1.0) discard;

    float2 ndc = float2(input.uv.x * 2.0 - 1.0, 1.0 - input.uv.y * 2.0);
    float4 d = mul(sky.inv_sky_view_proj, float4(ndc, 1.0, 1.0));
    float3 dir = normalize(d.xyz / d.w);
    return float4(env.Sample(env_sampler, dir).rgb, 1.0);
}
