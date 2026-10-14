struct VsIn {
    float2 position : POSITION;
    float2 uv       : TEXCOORD0;
    float4 color    : COLOR0;
};

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv    : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

struct UiFrame {
    float4x4 proj;
};

[[vk::binding(0, 0)]] ConstantBuffer<UiFrame> frame;
[[vk::binding(0, 1)]] Texture2D    t_tex;
[[vk::binding(1, 1)]] SamplerState s_tex;

[shader("vertex")]
VsOut vs_main(VsIn input)
{
    VsOut o;
    o.clip  = mul(frame.proj, float4(input.position, 0.0, 1.0));
    o.uv    = input.uv;
    o.color = input.color;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target0
{
    float a = t_tex.Sample(s_tex, i.uv).a;
    return i.color * a;
}
