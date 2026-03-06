#ifndef KERNEL_ENGINE_KERNEL_RENDER_MESH_H_
#define KERNEL_ENGINE_KERNEL_RENDER_MESH_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Stable opaque handle to a GPU mesh. Returned by ke_render::create_mesh.
    typedef uint32_t ke_mesh_handle;

#define KE_MESH_HANDLE_INVALID ((ke_mesh_handle)UINT32_MAX)

    /// @brief Per-vertex data expected by ke_render::create_mesh.
    typedef struct ke_vertex
    {
        float x, y, z;       ///< Object-space position
        float nx, ny, nz;    ///< Object-space normal (normalized)
        float u, v;          ///< UV texture coordinates
        float tx, ty, tz;    ///< Object-space tangent (normalized)
        float tw;            ///< Bitangent sign: +1 or -1 (bitangent = cross(N,T)*tw)
    } ke_vertex;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_MESH_H_
