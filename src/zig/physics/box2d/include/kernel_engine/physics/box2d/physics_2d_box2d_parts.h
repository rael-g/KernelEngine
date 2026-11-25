#ifndef KERNEL_ENGINE_PHYSICS_BOX2D_PHYSICS_2D_BOX2D_PARTS_H_
#define KERNEL_ENGINE_PHYSICS_BOX2D_PHYSICS_2D_BOX2D_PARTS_H_

#include <kernel_engine/physics/box2d/box2d_physics.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_physics_2d_box2d contains: `physics_2d_box2d`, providing ke_physics_2d, with the slot `job_system`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_PHYSICS_BOX2D_API const ke_part *ke_physics_2d_box2d_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
