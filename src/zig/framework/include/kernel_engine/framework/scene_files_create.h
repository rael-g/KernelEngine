#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_FILES_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_FILES_CREATE_H_

#include <kernel_engine/asset/asset_resolver.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/framework/node_types.h>
#include <kernel_engine/framework/scene_files.h>
#include <kernel_engine/io/io.h>

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
    /// `io`; each must outlive the scene files.
    /// @param out_files [out] Receives the scene files; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p node_types, @p assets,
    ///         @p io or @p out_files, or KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_scene_files_create(
        ke_ecs                *ecs,
        ke_node_types         *node_types,
        ke_asset_resolver     *assets,
        ke_io                 *io,
        ke_scene_files_handle *out_files);

#ifdef __cplusplus
}
#endif

#endif
