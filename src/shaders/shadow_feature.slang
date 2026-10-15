import ke;

struct ShadowFeatureParams {
    float4x4 lightVP;
};
ConstantBuffer<ShadowFeatureParams> shadowParams;
Texture2D    shadowMap;

float sample_shadow_visibility(float3 worldPos) {
    float4 sc = mul(shadowParams.lightVP, float4(worldPos, 1.0));
    float3 coord = sc.xyz / sc.w;
    coord.x = coord.x * 0.5 + 0.5;
    coord.y = -coord.y * 0.5 + 0.5;
    if (any(coord < 0.0) || any(coord > 1.0)) return 1.0;
    float closest = shadowMap.Sample(ke_samp_shadow, coord.xy).r;
    return (coord.z - 0.005 > closest) ? 0.3 : 1.0;
}
