
#pragma once

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/physics/physics_2d.h>
#include <kernel_engine/framework/world.h>
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

/// @brief Construction parameters for the 2D body reconciliation system.
typedef struct ke_physics_body2d_module_params
{
    ke_runtime    *runtime;      ///< Registers the system; borrowed, must outlive the module.
    ke_ecs        *ecs;          ///< Resolves the component ids; borrowed.
    ke_physics_2d *physics;      ///< The world to drive; borrowed.
    ke_logger     *logger;       ///< Reports shapes that resolve to no body; optional, borrowed.
} ke_physics_body2d_module_params;

typedef struct ke_physics_body2d_module ke_physics_body2d_module;

typedef struct ke_physics_body2d_module_handle
{
    ke_physics_body2d_module *ref;
    void (*destroy)(ke_physics_body2d_module *self);
} ke_physics_body2d_module_handle;

/// @brief Registers the system that creates, steps, and syncs 2D bodies.
/// @return Handle whose @c ref is NULL on failure.
KE_PHYSICS_BODY2D_API ke_physics_body2d_module_handle ke_physics_body2d_module_create(
    const ke_physics_body2d_module_params *params,
    ke_error **out_error);

/// @brief Registers physics's component ids and their scene-file field tables against
///        @p world, so an [entity.body2d] or [entity.collider2d] block applies.
/// @return false if either argument is NULL.
KE_PHYSICS_BODY2D_API bool ke_physics_register_scene_apply(ke_ecs *ecs, ke_world *world);

#ifdef __cplusplus
}
#endif
