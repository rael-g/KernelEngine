// Skybox — draws the environment cubemap at the far plane. Shares descriptor
// set 0 (per-frame) with the forward pass and uses the rotation-only
// sky_view_proj so the cube stays centred on the camera (infinite background).
// Depth is forced to the far plane (z = w) and tested LEQUAL so the skybox only
// fills pixels the opaque meshes did not cover.

struct VsIn  { float3 position : POSITION; };
struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float3 dir : TEXCOORD0;
};

// Must match forward.slang's PerFrame (set 0, binding 0).
struct PerFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4x4 sky_view_proj;
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;
[[vk::binding(1, 0)]] TextureCube  env;
[[vk::binding(2, 0)]] SamplerState env_sampler;

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    o.dir = input.position;
    float4 p = mul(frame.sky_view_proj, float4(input.position, 1.0));
    o.clip = p.xyww; // z = w → depth 1 (far plane)
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    return float4(env.Sample(env_sampler, normalize(input.dir)).rgb, 1.0);
}
