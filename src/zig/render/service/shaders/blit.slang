import ke;

Texture2D<float4> t_src;

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID)
{
    float2 pos = float2((vid & 1u) != 0u ? 3.0 : -1.0,
                        (vid & 2u) != 0u ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target0
{
    return t_src.Sample(ke_samp_linear, i.uv);
}
