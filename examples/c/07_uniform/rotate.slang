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

struct Uniforms {
    float angle;
};

[[vk::binding(0, 0)]] ConstantBuffer<Uniforms> u;

struct VsOut {
    float4 position : SV_Position;
    [[vk::location(0)]] float3 color : COLOR0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID) {
    float c = cos(u.angle);
    float s = sin(u.angle);
    float2 p = positions[vid];
    VsOut o;
    o.position = float4(c * p.x - s * p.y, -(s * p.x + c * p.y), 0.0, 1.0);
    o.color    = colors[vid];
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut i) : SV_Target {
    return float4(i.color, 1.0);
}
