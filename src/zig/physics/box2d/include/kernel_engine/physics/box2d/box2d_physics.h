#ifndef KERNEL_ENGINE_PHYSICS_BOX2D_BOX2D_PHYSICS_H_
#define KERNEL_ENGINE_PHYSICS_BOX2D_BOX2D_PHYSICS_H_

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

/// [bag] The values a world is created with, each applied as given.
typedef struct ke_physics_2d_box2d_config {
    float gravity_x; /**< Horizontal gravity, in metres per second squared. */
    float gravity_y; /**< Vertical gravity, in metres per second squared. */
} ke_physics_2d_box2d_config;


/**
 * @brief Creates a 2D physics world.
 * @param config [borrowed] The world's values; Required; every field is read as given.
 * @param out_world [out] Receives the world; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null @p out_world or a gravity that is not finite;
 *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when Box2D refuses the world.
 */
KE_PHYSICS_BOX2D_API ke_result ke_physics_2d_box2d_create(
    const ke_physics_2d_box2d_config *config,
    ke_physics_2d_handle             *out_world);

#ifdef __cplusplus
}
#endif

#endif
