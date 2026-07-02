// UI overlay pass — screen-space textured quads composited over the tonemapped
// scene. Vertices carry pixel-space positions, atlas UVs, and a premultiplied
// color. The projection maps pixels to clip space (built CPU-side with the
// backend's NDC convention). Coverage lives in the texture's alpha channel
// (glyph atlas, or a 1x1 white texel for solid rects), so the fragment masks a
// premultiplied color by that alpha — correct for both text and flat quads.
//
// Matrices are float4x4 with mul(M, v) (row-vector convention), matching the
// other passes so Slang lowers to WGSL identically.

struct VsIn {
    float2 position : POSITION;   // pixels, top-left origin
    float2 uv       : TEXCOORD0;
    float4 color    : COLOR0;     // premultiplied alpha
};

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv    : TEXCOORD0;
    [[vk::location(1)]] float4 color : COLOR0;
};

struct UiFrame {
    float4x4 proj; // pixel-space → clip
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
    // Coverage/opacity from the texture alpha; color is already premultiplied.
    float a = t_tex.Sample(s_tex, i.uv).a;
    return i.color * a;
}
