#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_FILES_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_FILES_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/framework/scene_files.h>
#include <kernel_engine/io/io.h>
#include <kernel_engine/scheduling/schedule.h>
#include <kernel_engine/configuration/settings.h>

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

    /// Creates scene files that spawn through `node_types`, look components up and write their
    /// fields through `ecs`, resolve a `res://` path through `assets` and read every file through
    /// `io`; each must outlive the scene files. It registers through `node_types` the node type
    /// `scene_slot`, carrying a ke_scene_slot_component, whose update replaces a slot's children
    /// when its path changes; the scene files must outlive every tick that runs it. With the
    /// setting `first_scene`, a `res://` path, it also registers in @p first_scene_set of
    /// @p first_scene an exclusive system that, on its first run, does what `open` does with that
    /// path, and nothing on any later run; without it, no system. Destroying the scene files
    /// unregisters that system.
    /// @param first_scene [borrowed] Must outlive the scene files.
    /// @param first_scene_set The set of @p first_scene the system joins.
    /// @param settings [borrowed] Read during the call: `first_scene`, none by default.
    /// @param out_files [out] Receives the scene files; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p node_types, @p assets,
    ///         @p io, @p first_scene, @p settings or @p out_files, settings it refuses, or a first
    ///         scene longer than a slot holds; KE_RESULT_OUT_OF_MEMORY; the node types' code when
    ///         they refuse the scene slot type, or the schedule's when it refuses the system.
    KE_FRAMEWORK_API ke_result ke_scene_files_create(
        ke_ecs                *ecs,
        ke_node_types         *node_types,
        ke_asset_resolver     *assets,
        ke_io                 *io,
        ke_schedule           *first_scene,
        ke_schedule_set_id     first_scene_set,
        ke_settings           *settings,
        ke_scene_files_handle *out_files);

#ifdef __cplusplus
}
#endif

#endif
