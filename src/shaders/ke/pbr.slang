// ke.pbr.slang — engine PBR BRDF building blocks. Matches the C++ PBR exactly.

float GGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * denom * denom);
}

float Smith(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float3 Schlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), 5.0);
}

float3 SampleIBL(float3 R, float roughness, TextureCube<float4> envMap,
                             SamplerState samp) {
    float mip = roughness * (4.0); // 4 mip levels for a 16x16 cubemap
    return envMap.SampleLevel(samp, R, mip).xyz;
}

float3 DFG_LUT(float NdotV, float roughness) {
    // v1: analytical approximation. Full LUT texture later.
    float a = roughness;
    float f = 1.0 - pow(1.0 - NdotV, 5.0);
    return lerp(float3(1.0, 1.0, 1.0), float3(f, f, f), a);
}
