// Private to the framework plugin — do not include from outside src/c/framework/.
// Bake/free helpers for ke_mesh_shape primitives. External consumers reach
// these through ke_asset_resolver->resolve_mesh.

#ifndef KE_FRAMEWORK_MESH_SHAPE_INTERNAL_H_
#define KE_FRAMEWORK_MESH_SHAPE_INTERNAL_H_

#include <kernel_engine/asset/mesh_shape.h>
#include <kernel_engine/common/error.h>

#ifdef __cplusplus
extern "C" {
#endif

bool ke_mesh_shape_bake_internal(ke_mesh_primitive   prim,
                                  uint32_t            segments,
                                  ke_mesh_shape_data *out_data);

void ke_mesh_shape_free_internal(ke_mesh_shape_data *data);

#ifdef __cplusplus
}
#endif

#endif
