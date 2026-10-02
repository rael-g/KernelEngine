struct VsIn {
    [[vk::location(0)]] float2 pos : POSITION0;
    [[vk::location(1)]] float3 color : COLOR0;
};

struct VsOut {
    float4 position : SV_Position;
    [[vk::location(0)]] float3 color : COLOR0;
};

[shader("vertex")]
VsOut vs_main(VsIn i) {
    VsOut o;
    o.position = float4(i.pos.x, -i.pos.y, 0.0, 1.0);
    o.color    = i.color;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target {
    return float4(i.color, 1.0);
}
