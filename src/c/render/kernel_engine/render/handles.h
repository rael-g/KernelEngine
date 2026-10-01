#ifndef KERNEL_ENGINE_RENDER_HANDLES_H_
#define KERNEL_ENGINE_RENDER_HANDLES_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_HANDLE_INDEX_BITS      20u
#define KE_HANDLE_GENERATION_BITS 12u

#define KE_HANDLE_INDEX_MASK      ((1u << KE_HANDLE_INDEX_BITS) - 1u)
#define KE_HANDLE_GENERATION_MASK ((1u << KE_HANDLE_GENERATION_BITS) - 1u)

    /// Lowest generation a live handle carries; 0 is reserved.
#define KE_HANDLE_GENERATION_FIRST 1u

    /// The invalid handle.
#define KE_HANDLE_NONE 0u

    typedef struct ke_mesh_handle        { uint32_t bits; } ke_mesh_handle;
    typedef struct ke_texture_handle     { uint32_t bits; } ke_texture_handle;
    typedef struct ke_material_handle    { uint32_t bits; } ke_material_handle;
    typedef struct ke_cubemap_handle     { uint32_t bits; } ke_cubemap_handle;
    typedef struct ke_shadow_map_handle  { uint32_t bits; } ke_shadow_map_handle;

    typedef enum ke_alpha_mode
    {
        KE_ALPHA_MODE_OPAQUE,
        KE_ALPHA_MODE_MASK,
        KE_ALPHA_MODE_BLEND,
    } ke_alpha_mode;

#ifndef CLANGSHARP
#define KE_MESH_NONE        ((ke_mesh_handle)      { KE_HANDLE_NONE })
#define KE_TEXTURE_NONE     ((ke_texture_handle)   { KE_HANDLE_NONE })
#define KE_MATERIAL_NONE    ((ke_material_handle)  { KE_HANDLE_NONE })
#define KE_CUBEMAP_NONE     ((ke_cubemap_handle)   { KE_HANDLE_NONE })
#define KE_SHADOW_MAP_NONE  ((ke_shadow_map_handle){ KE_HANDLE_NONE })
#endif

#ifdef __cplusplus
}
#endif

#endif
