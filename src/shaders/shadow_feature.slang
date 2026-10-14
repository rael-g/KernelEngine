import ke;

struct ShadowFeatureParams {
    float4x4 lightVP;
};
[[vk::binding(4, 0)]] ConstantBuffer<ShadowFeatureParams> shadowParams;
[[vk::binding(5, 0)]] Texture2D    shadowMap;
[[vk::binding(6, 0)]] SamplerState shadowSampler;

float sample_shadow_visibility(float3 worldPos) {
    float4 sc = mul(shadowParams.lightVP, float4(worldPos, 1.0));
    float3 coord = sc.xyz / sc.w;
    coord.x = coord.x * 0.5 + 0.5;
    coord.y = -coord.y * 0.5 + 0.5;
    if (any(coord < 0.0) || any(coord > 1.0)) return 1.0;
    float closest = shadowMap.Sample(shadowSampler, coord.xy).r;
    return (coord.z - 0.005 > closest) ? 0.3 : 1.0;
}
