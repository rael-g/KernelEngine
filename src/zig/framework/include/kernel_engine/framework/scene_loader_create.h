#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_CREATE_H_

#include <kernel_engine/framework/scene_loader.h>
#include <kernel_engine/framework/component_registry.h>
#include <kernel_engine/framework/scene_tree.h>
#include <kernel_engine/framework/signal_bus.h>
#include <kernel_engine/asset/asset_resolver.h>
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

    /// Allocates a scene loader. The loader resolves the components a block names through
    /// `registry` and `ecs`, fills them as the registry describes, and spawns the entities in
    /// `scene_tree`. A "res://" scene reference is resolved by `assets`.
    ///
    /// String lifetime: a value a block authors into a char field is copied into
    /// the component, but the parsed entries themselves come from an arena freed
    /// at loader.destroy(). Nothing the loader wrote outlives it by reference.
    /// @param ecs [borrowed] Holds the components; must outlive the loader.
    /// @param scene_tree [borrowed] Receives the scene's nodes; must outlive the loader.
    /// @param signal_bus [borrowed,optional] Receives the connections a scene declares; without
    ///        one, a connection block is reported and skipped.
    /// @param registry [borrowed] Describes the components; must outlive the loader.
    /// @param assets [borrowed] Resolves a "res://" reference; must outlive the loader.
    /// @param io [borrowed] What every scene file is read through; must outlive the loader.
    /// @param out_loader [out] Receives the loader; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p ecs, @p scene_tree, @p registry,
    ///         @p assets, @p io or @p out_loader, or KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_scene_loader_create(
        ke_ecs                 *ecs,
        ke_scene_tree          *scene_tree,
        ke_signal_bus          *signal_bus,
        ke_component_registry  *registry,
        ke_asset_resolver      *assets,
        ke_io                  *io,
        ke_scene_loader_handle *out_loader);

#ifdef __cplusplus
}
#endif

#endif
