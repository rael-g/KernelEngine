#ifndef KERNEL_ENGINE_PHYSICS_BODY2D_SCENE_COMPONENTS_H_
#define KERNEL_ENGINE_PHYSICS_BODY2D_SCENE_COMPONENTS_H_

#include <kernel_engine/framework/scene_component_set.h>

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

/// @brief Adds physics's scene components to @p set: the 2D body and the 2D collider, with their
///        field tables, so [entity.body2d] and [entity.collider2d] blocks apply.
/// @param set [borrowed] The set the components are added to.
/// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p set, or the code of the set that refused
///         a component, after the components added before it.
KE_PHYSICS_BODY2D_API ke_result ke_physics_scene_components_create(ke_scene_component_set *set);

#ifdef __cplusplus
}
#endif

#endif
