#ifndef KERNEL_ENGINE_RENDER_HANDLES_H_
#define KERNEL_ENGINE_RENDER_HANDLES_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_HANDLE_INDEX_BITS      20u
#define KE_HANDLE_GENERATION_BITS 12u

#define KE_HANDLE_INDEX_MASK      ((1u << KE_HANDLE_INDEX_BITS) - 1u)
#define KE_HANDLE_GENERATION_MASK ((1u << KE_HANDLE_GENERATION_BITS) - 1u)

    /// Lowest generation a live handle can carry. Generation 0 is reserved so no
    /// live handle is ever all-bits-zero.
#define KE_HANDLE_GENERATION_FIRST 1u

    /// The invalid handle: all bits zero, which is what uninitialized memory
    /// already holds.
#define KE_HANDLE_NONE 0u

    static inline uint32_t ke_handle_index(uint32_t bits)
    {
        return bits & KE_HANDLE_INDEX_MASK;
    }

    static inline uint32_t ke_handle_generation(uint32_t bits)
    {
        return (bits >> KE_HANDLE_INDEX_BITS) & KE_HANDLE_GENERATION_MASK;
    }

    static inline uint32_t ke_handle_make(uint32_t index, uint32_t generation)
    {
        return (index & KE_HANDLE_INDEX_MASK) |
               ((generation & KE_HANDLE_GENERATION_MASK) << KE_HANDLE_INDEX_BITS);
    }

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

    static inline bool ke_mesh_is_valid(ke_mesh_handle h)
        { return h.bits != KE_HANDLE_NONE; }
    static inline bool ke_texture_is_valid(ke_texture_handle h)
        { return h.bits != KE_HANDLE_NONE; }
    static inline bool ke_material_is_valid(ke_material_handle h)
        { return h.bits != KE_HANDLE_NONE; }
    static inline bool ke_cubemap_is_valid(ke_cubemap_handle h)
        { return h.bits != KE_HANDLE_NONE; }
    static inline bool ke_shadow_map_is_valid(ke_shadow_map_handle h)
        { return h.bits != KE_HANDLE_NONE; }

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_HANDLES_H_
