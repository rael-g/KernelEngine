#ifndef KERNEL_ENGINE_RENDER_MESH_H_
#define KERNEL_ENGINE_RENDER_MESH_H_

#include <kernel_engine/math/math.h>

#ifdef __cplusplus
extern "C"
{
#endif

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
