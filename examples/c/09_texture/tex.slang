[[vk::binding(0, 0)]] Texture2D u_tex;
[[vk::binding(1, 0)]] SamplerState u_sampler;

struct VsIn {
    [[vk::location(0)]] float2 pos : POSITION0;
    [[vk::location(1)]] float2 uv : TEXCOORD0;
};

struct VsOut {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(VsIn i) {
    VsOut o;
    o.position = float4(i.pos.x, -i.pos.y, 0.0, 1.0);
    o.uv       = i.uv;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target {
    return u_tex.Sample(u_sampler, i.uv);
}
