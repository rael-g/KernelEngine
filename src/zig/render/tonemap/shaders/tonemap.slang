// ACES tonemapping pass — reads the HDR color buffer, applies the ACES fitted
// curve (Krzysztof Narkowicz approximation), and writes to the swapchain.
// A fullscreen triangle is emitted by the vertex stage without a vertex buffer.

[[vk::binding(0, 0)]] Texture2D<float4> t_hdr;
[[vk::binding(1, 0)]] SamplerState      s_hdr;

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID)
{
    // Fullscreen triangle: 3 vertices covering the NDC square.
    float2 pos = float2((vid & 1u) ? 3.0 : -1.0,
                        (vid & 2u) ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

// ACES fitted curve (Narkowicz 2015, "ACES Filmic Tone Mapping Curve").
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
    float3 hdr = t_hdr.Sample(s_hdr, i.uv).rgb;
    float3 ldr = aces(hdr);
    // Display gamma — the swapchain is a UNORM (non-sRGB) surface, so this pass
    // owns the linear -> display encode as the final resolve step.
    ldr = pow(ldr, float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2));
    return float4(ldr, 1.0);
}
