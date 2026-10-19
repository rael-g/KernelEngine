import ke;

TextureCube  ibl_env;

float3 ibl_contribution(float3 n, float3 v, float3 albedo, float metallic) {
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 f_ibl       = f0 + (1.0 - f0) * pow(saturate(1.0 - max(dot(n, v), 0.0)), 5.0);
    float3 ibl_spec    = ibl_env.Sample(ke_samp_linear, reflect(-v, n)).rgb * f_ibl;
    float3 ibl_diffuse = ibl_env.Sample(ke_samp_linear, n).rgb * albedo * (1.0 - metallic) * (1.0 - f_ibl);
    return ibl_spec + ibl_diffuse;
}
