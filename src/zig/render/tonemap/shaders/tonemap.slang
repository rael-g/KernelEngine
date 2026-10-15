import ke;

Texture2D<float4> t_hdr;

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID)
{
    float2 pos = float2((vid & 1u) ? 3.0 : -1.0,
                        (vid & 2u) ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

float3 aces(float3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target0
{
    float3 hdr = t_hdr.Sample(ke_samp_linear, i.uv).rgb;
    float3 ldr = aces(hdr);
    ldr = pow(ldr, float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2));
    return float4(ldr, 1.0);
}
