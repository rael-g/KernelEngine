#ifndef KERNEL_ENGINE_ASSET_ASSET_LOADER_H_
#define KERNEL_ENGINE_ASSET_ASSET_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/task_scheduler/task_scheduler.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Completion callback for ke_asset_loader::load_model_async.
    /// @param result   KE_OK on success, an error code on failure.
    /// @param data     Loaded model data (valid only when result == KE_OK); NULL on failure.
    /// @param user_data  Opaque pointer forwarded from load_model_async.
    typedef void (*ke_load_model_complete_func)(ke_result result,
                                                struct ke_model_data *data,
                                                void *user_data);

    /// @brief ABI-stable vtable interface for loading 3D assets.
    ///        Concrete implementations (e.g., Assimp) are provided as separate plugins.
    typedef struct ke_asset_loader
    {
        void *handle;

        /// @brief Destroys and frees the loader itself.
        void (*destroy)(struct ke_asset_loader *self);

        /// @brief Loads a 3D model from @p path into a newly allocated ke_model_data.
        ///        The caller owns the result and must release it with free_model.
        /// @param path  Absolute or relative file path (.gltf, .glb, .obj, .fbx, …).
        /// @param out   Receives a pointer to the allocated ke_model_data on success.
        ke_result (*load_model)(struct ke_asset_loader *self,
                                const char *path,
                                ke_model_data **out,
                                ke_error **out_error);

        /// @brief Frees a ke_model_data previously returned by load_model or the async variant.
        void (*free_model)(struct ke_asset_loader *self, ke_model_data *data);

        /// @brief Asynchronously loads a 3D model using @p scheduler.
        ///        Returns a ke_task* that can be waited on; @p on_complete is invoked on the
        ///        scheduler thread when the load finishes (or fails).
        /// @param scheduler  Non-null task scheduler.
        /// @param path       File path (copied internally; caller may free after return).
        /// @param on_complete Callback invoked with the result; must not be NULL.
        /// @param user_data  Forwarded unchanged to @p on_complete.
        ke_task *(*load_model_async)(struct ke_asset_loader *self,
                                     ke_task_scheduler *scheduler,
                                     const char *path,
                                     ke_load_model_complete_func on_complete,
                                     void *user_data);

    } ke_asset_loader;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ASSET_ASSET_LOADER_H_
