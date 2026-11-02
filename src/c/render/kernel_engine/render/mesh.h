#ifndef KERNEL_ENGINE_RENDER_MESH_H_
#define KERNEL_ENGINE_RENDER_MESH_H_

#include <kernel_engine/math/math.h>
#include <stdint.h>
#include <kernel_engine/render/handles.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [value] Per-vertex data of a mesh, as authored.
    typedef struct ke_vertex
    {
        float x, y, z;       ///< Object-space position
        float nx, ny, nz;    ///< Object-space normal (normalized)
        float u, v;          ///< UV texture coordinates
        float tx, ty, tz;    ///< Object-space tangent (normalized)
        float tw;            ///< Bitangent sign: +1 or -1 (bitangent = cross(N,T)*tw)
    } ke_vertex;

    /// [value] One interleaved vertex as a mesh is uploaded to the device.
    typedef struct ke_mesh_vertex
    {
        ke_vec3 position;
        ke_vec3 normal;
        ke_vec2 uv;
        ke_vec3 tangent;
    } ke_mesh_vertex;

#ifdef __cplusplus
}
#endif

#endif
