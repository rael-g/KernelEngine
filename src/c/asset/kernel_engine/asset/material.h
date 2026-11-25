#ifndef KERNEL_ENGINE_ASSET_MATERIAL_H_
#define KERNEL_ENGINE_ASSET_MATERIAL_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /// How a material's alpha combines with what is behind it.
    typedef enum ke_alpha_mode
    {
        KE_ALPHA_MODE_OPAQUE,
        KE_ALPHA_MODE_MASK,
        KE_ALPHA_MODE_BLEND,
    } ke_alpha_mode;

    /// The bytes a texture path of a material holds, terminator included.
#define KE_MATERIAL_PATH_MAX 256

    /// [value] A material as a `.material` file describes it; its textures are paths.
    typedef struct ke_material_spec
    {
        float         base_color[4];
        float         metallic;
        float         roughness;
        char          albedo_path[KE_MATERIAL_PATH_MAX];
        char          normal_path[KE_MATERIAL_PATH_MAX];
        ke_alpha_mode alpha_mode;
        float         alpha_cutoff;
        float         ior;
        float         distortion_strength;
    } ke_material_spec;

#ifdef __cplusplus
}
#endif

#endif
