// Minimal hardcoded triangle — no vertex buffer, no material template.
// Direct entry points; SV_VertexID drives the position/color lookup.

static const float2 positions[3] = {
    float2( 0.0, -0.5),
    float2( 0.5,  0.5),
    float2(-0.5,  0.5),
};

static const float3 colors[3] = {
    float3(1.0, 0.0, 0.0),
    float3(0.0, 1.0, 0.0),
    float3(0.0, 0.0, 1.0),
};

struct VsOut {
    float4 position : SV_Position;
    [[vk::location(0)]] float3 color : COLOR0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID) {
    VsOut o;
    float2 p = positions[vid];
    o.position = float4(p.x, -p.y, 0.0, 1.0);
    o.color    = colors[vid];
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target {
    return float4(i.color, 1.0);
}
