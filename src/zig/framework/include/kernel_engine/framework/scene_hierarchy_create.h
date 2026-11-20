#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_HIERARCHY_CREATE_H_

#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/part/part.h>
#include <kernel_engine/schedule/schedule.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FRAMEWORK_API
#if defined(_WIN32) || defined(__CYGWIN__)
#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API __declspec(dllexport)
#else
#define KE_FRAMEWORK_API __declspec(dllimport)
#endif
#endif
#else
#define KE_FRAMEWORK_API __attribute__((visibility("default")))
#endif
#endif

    /// Creates the module that keeps every world transform equal to its local transform composed
    /// with its parent's world transform: it registers one system in @p post_update_set of
    /// @p post_update, which orders the entities parents-before-children each run and walks them
    /// once. The transform and hierarchy components are resolved by the names a scene_tree registers
    /// them under, so a scene_tree must exist on @p ecs first. Destroying the module unregisters the
    /// system; components and entities stay.
    /// @param ecs [borrowed] Must outlive the module.
    /// @param post_update [borrowed] Must outlive the module.
    /// @param post_update_set The set of @p post_update the system joins.
    /// @param out_module [out] Receives the module; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_FOUND when the
    ///         scene tree components are not registered; KE_RESULT_OUT_OF_MEMORY; the code the
    ///         schedule refused the system with.
    KE_FRAMEWORK_API ke_result ke_scene_hierarchy_create(
        ke_ecs             *ecs,
        ke_schedule        *post_update,
        ke_schedule_set_id  post_update_set,
        ke_owner           *out_module);

#ifdef __cplusplus
}
#endif

#endif
