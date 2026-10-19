import ke;

struct SkyFrame {
    float4x4 inv_sky_view_proj;
};
ConstantBuffer<SkyFrame> sky;
TextureCube  env;
Texture2D<float> g_depth;

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID) {
    float2 pos = float2((vid & 1u) != 0u ? 3.0 : -1.0,
                        (vid & 2u) != 0u ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target0 {
    int2 px = int2(input.clip.xy);
    if (g_depth.Load(int3(px, 0)).x < 1.0) discard;

    float2 ndc = float2(input.uv.x * 2.0 - 1.0, 1.0 - input.uv.y * 2.0);
    float4 d = mul(sky.inv_sky_view_proj, float4(ndc, 1.0, 1.0));
    float3 dir = normalize(d.xyz / d.w);
    return float4(env.Sample(ke_samp_linear, dir).rgb, 1.0);
}
