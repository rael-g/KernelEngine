#ifndef KERNEL_ENGINE_PHYSICS_BOX2D_BOX2D_PHYSICS_H_
#define KERNEL_ENGINE_PHYSICS_BOX2D_BOX2D_PHYSICS_H_

#include <kernel_engine/configuration/configuration.h>
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
 * @brief Creates a 2D physics world.
 * @param configuration [borrowed,optional] Holds gravity_x and gravity_y in section
 *        runtime.physics_2d; a missing key, or NULL here, selects (0, -9.81).
 * @param out_world [out] Receives the world; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null @p out_world;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when Box2D refuses the world.
 */
KE_PHYSICS_BOX2D_API ke_result ke_physics_2d_box2d_create(
    ke_configuration     *configuration,
    ke_physics_2d_handle *out_world);

#ifdef __cplusplus
}
#endif

#endif
