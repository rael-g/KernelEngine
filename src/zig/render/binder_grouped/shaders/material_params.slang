struct MaterialParams {
    float4       base_color;
    float        metallic;
    float        roughness;
    float        alpha_cutoff;
    float        ior;
    float        distortion_strength;
    Texture2D    albedo;
    SamplerState tex_sampler;
    Texture2D    normal_map;
};
ParameterBlock<MaterialParams> mat;
