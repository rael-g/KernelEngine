#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_PHYSICS_BODY2D_PARTS_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_PHYSICS_BODY2D_PARTS_H_

#include <kernel_engine/physics/body2d/body2d_module.h>
#include <kernel_engine/part/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_physics_body2d contains: `physics_body2d`, providing nothing, with the slots `ecs`, `physics` and `scene_tree` and the hook `fixed_post_update`, in the set `fixed_post_update` by default.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_PHYSICS_BODY2D_API const ke_part *ke_physics_body2d_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
