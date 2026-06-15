#ifndef KERNEL_ENGINE_FRAMEWORK_MATERIAL_FILE_H_
#define KERNEL_ENGINE_FRAMEWORK_MATERIAL_FILE_H_

// ke_material_spec — POD describing the framework's opinionated material
// schema. The schema itself is parsed from `.material` TOML files, but
// parsing is internal to the framework plugin: external consumers reach the
// result via ke_asset_resolver->resolve_material(path, &spec).
//
// Schema:
//
//     [material]
//     base_color = [1.0, 0.5, 0.2, 1.0]   # RGBA (default [1, 1, 1, 1])
//     metallic   = 0.0                      # 0..1 (default 0)
//     roughness  = 0.5                      # 0..1 (default 0.5)
//     albedo     = "res://textures/foo.png" # optional
//     normal     = "res://textures/bar.png" # optional

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_MATERIAL_PATH_MAX 256

    typedef struct ke_material_spec
    {
        float base_color[4];                ///< RGBA, default {1,1,1,1}
        float metallic;                     ///< 0..1, default 0
        float roughness;                    ///< 0..1, default 0.5
        char  albedo_path[KE_MATERIAL_PATH_MAX]; ///< empty = no albedo texture
        char  normal_path[KE_MATERIAL_PATH_MAX]; ///< empty = no normal map
    } ke_material_spec;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_MATERIAL_FILE_H_
