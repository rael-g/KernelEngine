#ifndef KERNEL_ENGINE_RENDER_HANDLES_H_
#define KERNEL_ENGINE_RENDER_HANDLES_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_HANDLE_NONE UINT32_MAX

    typedef struct ke_mesh_handle        { uint32_t idx; } ke_mesh_handle;
    typedef struct ke_texture_handle     { uint32_t idx; } ke_texture_handle;
    typedef struct ke_material_handle    { uint32_t idx; } ke_material_handle;
    typedef struct ke_cubemap_handle     { uint32_t idx; } ke_cubemap_handle;
    typedef struct ke_shadow_map_handle  { uint32_t idx; } ke_shadow_map_handle;

#ifndef CLANGSHARP
#define KE_MESH_NONE        ((ke_mesh_handle)      { KE_HANDLE_NONE })
#define KE_TEXTURE_NONE     ((ke_texture_handle)   { KE_HANDLE_NONE })
#define KE_MATERIAL_NONE    ((ke_material_handle)  { KE_HANDLE_NONE })
#define KE_CUBEMAP_NONE     ((ke_cubemap_handle)   { KE_HANDLE_NONE })
#define KE_SHADOW_MAP_NONE  ((ke_shadow_map_handle){ KE_HANDLE_NONE })
#endif

    static inline bool ke_mesh_is_valid(ke_mesh_handle h)
        { return h.idx != KE_HANDLE_NONE; }
    static inline bool ke_texture_is_valid(ke_texture_handle h)
        { return h.idx != KE_HANDLE_NONE; }
    static inline bool ke_material_is_valid(ke_material_handle h)
        { return h.idx != KE_HANDLE_NONE; }
    static inline bool ke_cubemap_is_valid(ke_cubemap_handle h)
        { return h.idx != KE_HANDLE_NONE; }
    static inline bool ke_shadow_map_is_valid(ke_shadow_map_handle h)
        { return h.idx != KE_HANDLE_NONE; }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_HANDLES_H_
