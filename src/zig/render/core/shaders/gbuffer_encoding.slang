// The G-buffer encoding contract shared by the encoder (gbuffer.slang) and the
// decoder (deferred_lighting.slang) — they MUST agree bit-for-bit. Normals are
// octahedral-encoded to two [0,1] channels (Cigolle et al. 2014, "A Survey of
// Efficient Representations for Independent Unit Vectors"): a unit world-space
// normal fits in RG8 with far better precision than raw xyz in 8-bit, freeing
// the remaining channels for roughness + ao.

float2 ke_oct_sign(float2 v) {
    return float2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

// Unit vector → [0,1]^2.
float2 ke_oct_encode(float3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    float2 e = (n.z >= 0.0) ? n.xy : (1.0 - abs(n.yx)) * ke_oct_sign(n.xy);
    return e * 0.5 + 0.5;
}

// [0,1]^2 → unit vector.
float3 ke_oct_decode(float2 f) {
    float2 e = f * 2.0 - 1.0;
    float3 n = float3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    float t = saturate(-n.z);
    n.x += (n.x >= 0.0) ? -t : t;
    n.y += (n.y >= 0.0) ? -t : t;
    return normalize(n);
}
