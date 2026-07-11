#ifndef KERNEL_ENGINE_RENDER_HANDLES_H_
#define KERNEL_ENGINE_RENDER_HANDLES_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Resource handles are generational: `bits` packs a slot index with the
    // generation that slot carried when the handle was minted. Releasing a
    // resource frees its slot for reuse and bumps the slot's generation, so a
    // handle kept past its release no longer matches — it resolves to an error
    // instead of silently aliasing whatever resource landed in the slot next.
    // A bare index cannot express that, and the aliasing it permits is invisible
    // (wrong mesh drawn, no crash, no log).
    //
    // 20 index bits (1,048,575 live resources of one kind) and 12 generation
    // bits (4,095 reuses of a slot before the generation wraps and a very old
    // handle could collide again).

#define KE_HANDLE_INDEX_BITS      20u
#define KE_HANDLE_GENERATION_BITS 12u

#define KE_HANDLE_INDEX_MASK      ((1u << KE_HANDLE_INDEX_BITS) - 1u)
#define KE_HANDLE_GENERATION_MASK ((1u << KE_HANDLE_GENERATION_BITS) - 1u)

    /// Highest index value; reserved to spell "no handle", so it is never a live slot.
#define KE_HANDLE_INDEX_NONE KE_HANDLE_INDEX_MASK

    /// The invalid handle. Index bits are all-ones (the reserved index), so no
    /// generation can ever produce a live handle equal to it.
#define KE_HANDLE_NONE UINT32_MAX

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

    // glTF 2.0 material.alphaMode. OPAQUE and MASK both stay in the G-buffer (MASK
    // discards below alpha_cutoff but writes no blend); BLEND is the only mode the
    // transparent forward pass shades. Lives alongside the handles because both the
    // asset-side material spec and the render core's material creation need it,
    // and neither should pull in the other's header.
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

    // Cheap syntactic check only: a handle that passed here may still be stale
    // (released, slot reused). Staleness is only detectable by the owner, which
    // compares the generation against the slot's — hence resolution returns a
    // result, and callers handle it.
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
