struct KeLighting {
    float4 direction;
    float4 color;
    float4 ambient;
};
ConstantBuffer<KeLighting> ke_lighting;

bool ke_has_directional_light() {
    return ke_lighting.direction.w > 0.5;
}
