#ifndef KERNEL_ENGINE_ASSET_MESH_SHAPE_H_
#define KERNEL_ENGINE_ASSET_MESH_SHAPE_H_

#include <kernel_engine/render/mesh.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef enum ke_mesh_primitive
    {
        KE_MESH_PRIMITIVE_QUAD   = 0, ///< 1x1 quad in XY plane (normal +Z)
        KE_MESH_PRIMITIVE_PLANE  = 1, ///< 1x1 plane in XZ plane (normal +Y)
        KE_MESH_PRIMITIVE_CUBE   = 2, ///< Unit cube, 24 vertices (per-face normals)
        KE_MESH_PRIMITIVE_SPHERE = 3, ///< UV sphere of unit diameter
    } ke_mesh_primitive;

    typedef struct ke_mesh_shape_data
    {
        ke_vertex *vertices;
        uint32_t   vertex_count;
        uint16_t  *indices;
        uint32_t   index_count;
    } ke_mesh_shape_data;

#ifdef __cplusplus
}
#endif

#endif
