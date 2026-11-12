
#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_BODY2D_MODULE_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_BODY2D_MODULE_H_

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/scheduler/scheduler.h>

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

typedef struct ke_physics_body2d_module ke_physics_body2d_module;

/// [borrowed] The values the body2d module is created with.
typedef struct ke_physics_body2d_module_config
{
    /// The set both systems join; its phase must run after scripts write bodies and transforms.
    ke_set_id set;
} ke_physics_body2d_module_config;

/// [owner]
typedef struct ke_physics_body2d_module_handle
{
    ke_physics_body2d_module *ref;
    void (*destroy)(ke_physics_body2d_module *self);
} ke_physics_body2d_module_handle;

/**
 * @brief Registers, in the config's set, the systems that create, step, and sync 2D bodies.
 * @param scheduler  Registers the systems; borrowed, must outlive the module.
 * @param ecs        Resolves the component ids; borrowed.
 * @param physics    The world to drive; borrowed.
 * @param scene_tree Tells when a collider's ancestors may have changed; borrowed, must outlive the module.
 * @param config     [borrowed] Required; every field is read as given.
 * @param out_module [out] Receives the module; left zeroed on failure.
 * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument;
 *         KE_RESULT_OUT_OF_MEMORY; the scheduler's code when it refuses a system.
 */
KE_PHYSICS_BODY2D_API ke_result ke_physics_body2d_module_create(
    ke_scheduler *scheduler, ke_ecs *ecs, ke_physics_2d *physics, ke_scene_tree *scene_tree,
    const ke_physics_body2d_module_config *config,
    ke_physics_body2d_module_handle *out_module);


#ifdef __cplusplus
}
#endif

#endif
