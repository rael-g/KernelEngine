struct VsIn  { float3 position : POSITION; };
struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float depth : TEXCOORD0;
};

struct LightVP { float4x4 light_vp; };
[[vk::binding(0, 0)]] ConstantBuffer<LightVP> light;

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
    return float4(input.depth, 0.0, 0.0, 1.0);
}
