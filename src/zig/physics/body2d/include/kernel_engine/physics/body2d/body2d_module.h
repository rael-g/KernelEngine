
#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_BODY2D_MODULE_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_BODY2D_MODULE_H_

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/part/part.h>
#include <kernel_engine/schedule/schedule.h>

#ifndef KE_PHYSICS_BODY2D_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    if defined(KE_PHYSICS_BODY2D_STATIC)
#      define KE_PHYSICS_BODY2D_API
#    elif defined(KE_PHYSICS_BODY2D_EXPORT)
#      define KE_PHYSICS_BODY2D_API __declspec(dllexport)
#    else
#      define KE_PHYSICS_BODY2D_API __declspec(dllimport)
#    endif
#  else
#    define KE_PHYSICS_BODY2D_API __attribute__((visibility("default")))
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Creates the module that creates, steps and syncs 2D bodies: it registers its two systems in
 *        @p fixed_post_update_set of @p fixed_post_update. Destroying the module unregisters them and
 *        destroys the bodies it created.
 * @param ecs        Resolves the component ids; borrowed.
 * @param physics    The world to drive; borrowed, must outlive the module.
 * @param scene_tree Tells when a collider's ancestors may have changed; borrowed, must outlive the module.
 * @param fixed_post_update Borrowed, must outlive the module.
 * @param fixed_post_update_set The set of @p fixed_post_update the two systems join.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_OUT_OF_MEMORY; the
 *         ecs's code when it refuses a component; the schedule's code when it refuses a system,
 *         nothing left registered.
 */
KE_PHYSICS_BODY2D_API ke_result ke_physics_body2d_create(
    ke_ecs *ecs, ke_physics_2d *physics, ke_scene_tree *scene_tree,
    ke_schedule *fixed_post_update, ke_schedule_set_id fixed_post_update_set,
    ke_owner *out_module);

#ifdef __cplusplus
}
#endif

#endif
