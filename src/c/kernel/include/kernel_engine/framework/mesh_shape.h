#ifndef KERNEL_ENGINE_FRAMEWORK_MESH_SHAPE_H_
#define KERNEL_ENGINE_FRAMEWORK_MESH_SHAPE_H_

// ke_mesh_shape — common mesh primitives baked as CPU-side vertex/index
// buffers (Tier S — item 3 partial). Used by the asset resolver and by
// language bindings that need quick procedural geometry without involving
// an asset loader plugin.
//
// Output buffers are allocated through the supplied ke_allocator; pair every
// successful ke_mesh_shape_bake with a ke_mesh_shape_free using the same
// allocator.

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/render/mesh.h>
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

    /// Bakes <paramref name="prim"/> into a fresh vertex/index pair on the
    /// supplied allocator. <paramref name="segments"/> controls tessellation
    /// for the sphere (longitude divisions; ring count = segments/2). Ignored
    /// for non-sphere primitives. Pass 0 for the default of 32.
    ///
    /// Returns KE_ERROR_INVALID_ARGUMENT on a NULL allocator/output, or an
    /// unknown primitive. KE_ERROR_OUT_OF_MEMORY when allocation fails.
    KE_FRAMEWORK_API ke_result ke_mesh_shape_bake(
        ke_allocator       *alloc,
        ke_mesh_primitive   prim,
        uint32_t            segments,
        ke_mesh_shape_data *out_data);

    /// Releases the vertex + index buffers allocated by ke_mesh_shape_bake.
    /// Safe to pass a zero-initialised struct; the data fields are nulled out.
    KE_FRAMEWORK_API void ke_mesh_shape_free(
        ke_allocator       *alloc,
        ke_mesh_shape_data *data);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_MESH_SHAPE_H_
