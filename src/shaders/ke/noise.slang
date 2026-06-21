// ke.noise.slang — noise functions. v1: hash + simplex stubs.

float hash1(float2 p) {
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float simplex2(float2 p) {
    // v1 — simple value noise
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash1(i);
    float b = hash1(i + float2(1, 0));
    float c = hash1(i + float2(0, 1));
    float d = hash1(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float fbm(float2 p, int octaves) {
    float v = 0.0, amp = 0.5, freq = 1.0;
    for (int i = 0; i < octaves; i++) {
        v += amp * simplex2(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return v;
}
