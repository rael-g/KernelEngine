// Shadow-depth pass — renders shadow casters from the directional light's point
// of view into an R32F map (depth written to the red channel). Translated from
// the legacy bgfx vs_shadow/fs_shadow. Set 0 = light view-proj (per frame),
// set 2 = per-object model (dynamic offset) — same set indices as the forward
// so the per-object ring is reused.

struct VsIn  { float3 position : POSITION; };
struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float depth : TEXCOORD0;
};

// Set 0, binding 0 — the light's view-projection.
struct LightVP { float4x4 light_vp; };
[[vk::binding(0, 0)]] ConstantBuffer<LightVP> light;

// Set 1, binding 0 — per-object model (dynamic offset, matches the forward ring).
struct PerObject { float4x4 model; };
[[vk::binding(0, 1)]] ConstantBuffer<PerObject> obj;

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    float4 world = mul(obj.model, float4(input.position, 1.0));
    o.clip  = mul(light.light_vp, world);
    o.depth = o.clip.z / o.clip.w;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    // Normalized light-space depth in red; matches the legacy R32F shadow map.
    return float4(input.depth, 0.0, 0.0, 1.0);
}
