#ifndef KERNEL_ENGINE_RENDER_MATERIAL_FILE_H_
#define KERNEL_ENGINE_RENDER_MATERIAL_FILE_H_

#include <kernel_engine/render/handles.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_MATERIAL_PATH_MAX 256

    typedef struct ke_material_spec
    {
        float         base_color[4];
        float         metallic;
        float         roughness;
        char          albedo_path[KE_MATERIAL_PATH_MAX];
        char          normal_path[KE_MATERIAL_PATH_MAX];
        ke_alpha_mode alpha_mode;
        float         alpha_cutoff;
    } ke_material_spec;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_MATERIAL_FILE_H_
