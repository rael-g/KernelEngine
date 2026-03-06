#ifndef KERNEL_ENGINE_KERNEL_RENDER_MATERIAL_H_
#define KERNEL_ENGINE_KERNEL_RENDER_MATERIAL_H_

#include <stdint.h>
#include <kernel_engine/kernel/render/texture.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Stable opaque handle to a material.
    typedef uint32_t ke_material_handle;

#define KE_MATERIAL_HANDLE_INVALID ((ke_material_handle)UINT32_MAX)

    /// @brief Material properties defining its appearance.
    typedef struct ke_material
    {
        float r, g, b, a;           ///< Albedo color tint (multiplied with texture)
        ke_texture_handle albedo;   ///< Albedo texture handle; KE_TEXTURE_HANDLE_WHITE for solid color
        float metallic;             ///< [0..1]: 0 = dielectric, 1 = metallic
        float roughness;            ///< [0..1]: 0 = mirror, 1 = fully rough
    } ke_material;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_MATERIAL_H_
