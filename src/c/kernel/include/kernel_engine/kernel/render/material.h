#ifndef KERNEL_ENGINE_KERNEL_RENDER_MATERIAL_H_
#define KERNEL_ENGINE_KERNEL_RENDER_MATERIAL_H_

#include <stdint.h>
#include <kernel_engine/kernel/common/handles.h>
#include <kernel_engine/kernel/render/texture.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Material properties defining its appearance.
    typedef struct ke_material
    {
        float r, g, b, a;           ///< Albedo color tint (multiplied with texture)
        ke_texture_handle albedo;   ///< Albedo texture handle; KE_TEXTURE_HANDLE_WHITE for solid color
        float metallic;             ///< [0..1]: 0 = dielectric, 1 = metallic
        float roughness;            ///< [0..1]: 0 = mirror, 1 = fully rough
        ke_texture_handle normal_map; ///< Tangent-space normal map; 0 = disabled (flat normal)
    } ke_material;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_MATERIAL_H_
