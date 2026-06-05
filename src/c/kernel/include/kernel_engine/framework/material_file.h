#ifndef KERNEL_ENGINE_FRAMEWORK_MATERIAL_FILE_H_
#define KERNEL_ENGINE_FRAMEWORK_MATERIAL_FILE_H_

// ke_material_file — parses `.material` TOML files declaratively. The C plugin
// produces a fully-populated ke_material_spec; the caller (asset resolver or a
// language binding) is responsible for uploading textures by path and building
// the final renderer material handle.
//
// Schema:
//
//     [material]
//     base_color = [1.0, 0.5, 0.2, 1.0]   # RGBA (default [1, 1, 1, 1])
//     metallic   = 0.0                      # 0..1 (default 0)
//     roughness  = 0.5                      # 0..1 (default 0.5)
//     albedo     = "res://textures/foo.png" # optional
//     normal     = "res://textures/bar.png" # optional

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <stdint.h>

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

    /// Parses a `.material` TOML file at <paramref name="path"/> into the supplied spec.
    /// Defaults apply for missing keys. Returns KE_ERROR_NOT_FOUND on a missing/unparseable
    /// file, KE_ERROR_INVALID_ARGUMENT on missing the `[material]` section.
    KE_FRAMEWORK_API ke_result ke_material_file_parse(
        const char       *path,
        ke_material_spec *out_spec);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_MATERIAL_FILE_H_
