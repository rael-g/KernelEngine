import ke;

Texture2D    hdr_opaque;
SamplerState hdr_opaque_sampler;

float3 refraction_contribution(float3 n, float3 v, float2 screen_uv, float ior, float distortion_strength) {
    float3 refracted = refract(-v, n, 1.0 / max(ior, 1.0));
    float2 uv = saturate(screen_uv + refracted.xy * distortion_strength);
    return hdr_opaque.Sample(hdr_opaque_sampler, uv).rgb;
}
