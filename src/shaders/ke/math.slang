// ke.math.slang — utility math for shader authors.

float remap(float v, float a, float b, float c, float d) {
    return c + (v - a) / (b - a) * (d - c);
}

float pow_safe(float x, float e) {
    return pow(max(x, 0.0), e);
}

float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float3 pack_normal(float3 n) {
    return n * 0.5 + 0.5;
}

float3x3 rotation_y(float angle) {
    float s, c;
    sincos(angle, s, c);
    return float3x3(c, 0, s, 0, 1, 0, -s, 0, c);
}
