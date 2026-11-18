#ifndef KERNEL_ENGINE_PHYSICS_BOX2D_BOX2D_PHYSICS_H_
#define KERNEL_ENGINE_PHYSICS_BOX2D_BOX2D_PHYSICS_H_

#include <kernel_engine/settings/settings.h>
#include <kernel_engine/job/job_system.h>
#include <kernel_engine/physics/physics_2d.h>

#ifndef KE_PHYSICS_BOX2D_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    if defined(KE_PHYSICS_BOX2D_STATIC)
#      define KE_PHYSICS_BOX2D_API
#    elif defined(KE_PHYSICS_BOX2D_EXPORT)
#      define KE_PHYSICS_BOX2D_API __declspec(dllexport)
#    else
#      define KE_PHYSICS_BOX2D_API __declspec(dllimport)
#    endif
#  else
#    define KE_PHYSICS_BOX2D_API __attribute__((visibility("default")))
#  endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Creates a 2D physics world whose solver runs its tasks on @p job_system, borrowed for the
 *        world's lifetime, one Box2D worker per worker slot.
 * @param settings [borrowed] Read once. KE_PHYSICS_2D_SETTING_GRAVITY_X and KE_PHYSICS_2D_SETTING_GRAVITY_Y,
 *        each default 0.
 * @param out_world [out] Receives the world; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p job_system, @p settings or @p out_world, or
 *         a setting refused or a gravity that is not finite;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when Box2D refuses the world.
 */
KE_PHYSICS_BOX2D_API ke_result ke_physics_2d_box2d_create(
    ke_job_system              *job_system,
    ke_settings                *settings,
    ke_physics_2d_handle             *out_world);

#ifdef __cplusplus
}
#endif

#endif
