
#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_BODY2D_MODULE_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_BODY2D_MODULE_H_

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/runtime/runtime.h>

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

/// [bag] @brief Construction parameters for the 2D body reconciliation system.
typedef struct ke_physics_body2d_module_params
{
    ke_runtime    *runtime;      ///< Registers the system; borrowed, must outlive the module.
    ke_ecs        *ecs;          ///< Resolves the component ids; borrowed.
    ke_physics_2d *physics;      ///< The world to drive; borrowed.
    ke_scene_tree *scene_tree;   ///< Tells when a collider's ancestors may have changed; borrowed, must outlive the module.
} ke_physics_body2d_module_params;

typedef struct ke_physics_body2d_module ke_physics_body2d_module;

/// [owner]
typedef struct ke_physics_body2d_module_handle
{
    ke_physics_body2d_module *ref;
    void (*destroy)(ke_physics_body2d_module *self);
} ke_physics_body2d_module_handle;

/**
 * @brief Registers the system that creates, steps, and syncs 2D bodies.
 * @param params [borrowed] The runtime, ECS, physics world and scene tree, none of them null.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument or a null field of @p params;
 *         KE_RESULT_OUT_OF_MEMORY; the runtime's code when it refuses a system.
 */
KE_PHYSICS_BODY2D_API ke_result ke_physics_body2d_module_create(
    const ke_physics_body2d_module_params *params,
    ke_physics_body2d_module_handle       *out_module);


#ifdef __cplusplus
}
#endif

#endif
