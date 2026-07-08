// ke.pbr.slang — engine PBR BRDF (Cook-Torrance, metallic-roughness). This is
// the single shading library both the forward pass and the deferred-lighting
// pass call: the math does not know which topology invokes it (§8.12). Moved
// here verbatim from forward_lit.slang's former inline copy so forward and
// deferred produce identical results.

static const float KE_PI = 3.14159265359;

float3 fresnel_schlick(float cos_theta, float3 f0) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}

float distribution_ggx(float3 n, float3 h, float rough) {
    float a = rough * rough;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0);
    float d = ndoth * ndoth * (a2 - 1.0) + 1.0;
    return a2 / max(KE_PI * d * d, 1e-4);
}

float geometry_schlick_ggx(float ndotv, float rough) {
    float r = rough + 1.0;
    float k = (r * r) / 8.0;
    return ndotv / (ndotv * (1.0 - k) + k);
}

float geometry_smith(float3 n, float3 v, float3 l, float rough) {
    return geometry_schlick_ggx(max(dot(n, v), 0.0), rough) *
           geometry_schlick_ggx(max(dot(n, l), 0.0), rough);
}

// One direct light's Cook-Torrance contribution. `l` is the direction toward
// the light (already normalized), `radiance` its color×intensity. Returns 0
// for back-facing fragments.
float3 pbr_direct(float3 n, float3 v, float3 l, float3 albedo_c, float3 f0,
                  float metallic, float rough, float3 radiance) {
    float ndotl = max(dot(n, l), 0.0);
    if (ndotl <= 0.0) return float3(0.0, 0.0, 0.0);
    float3 h   = normalize(v + l);
    float  ndf = distribution_ggx(n, h, rough);
    float  g   = geometry_smith(n, v, l, rough);
    float3 f   = fresnel_schlick(max(dot(h, v), 0.0), f0);
    float3 spec = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * ndotl + 1e-4);
    float3 kd   = (float3(1.0, 1.0, 1.0) - f) * (1.0 - metallic);
    float3 diff = kd * albedo_c / KE_PI;
    return (diff + spec) * radiance * ndotl;
}
