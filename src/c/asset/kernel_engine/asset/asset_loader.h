#ifndef KERNEL_ENGINE_ASSET_ASSET_LOADER_H_
#define KERNEL_ENGINE_ASSET_ASSET_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/scheduler/scheduler.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** Completion callback for ke_asset_loader::load_model_async.
     * @param error     NULL on success; pointer to a ke_error on failure (valid until the next
     *                  failing call on this thread — copy what you need before returning).
     * @param data      [optional] The loaded model; NULL when the load failed.
     * @param user_data [context] Opaque pointer forwarded from load_model_async. */
    typedef void (*ke_load_model_complete_func)(const ke_error *error,
                                                struct ke_model_data *data,
                                                void *user_data);

    /** [interface] ABI-stable vtable interface for loading 3D assets.
     * Concrete implementations (e.g., Assimp) are provided as separate plugins. */
    typedef struct ke_asset_loader
    {
        void *handle;

        /** Loads a 3D model from @p path into a newly allocated ke_model_data.
         * The caller owns the result and must release it with free_model.
         * @param path [utf8] Absolute or relative file path (.gltf, .glb, .obj, .fbx, …). */
        ke_model_data *(*load_model)(struct ke_asset_loader *self,
                                     const char *path,
                                     ke_error **out_error);

        /** [releases:Model] Frees a ke_model_data previously returned by load_model or the async variant.
         * The model must be given back to the same loader that produced it. A loader
         * owns its memory, so a foreign or hand-built ke_model_data is not a valid
         * argument. A null @p data is ignored. */
        void (*free_model)(struct ke_asset_loader *self, ke_model_data *data);

        /** Asynchronously loads a 3D model, calling @p on_complete on a scheduler thread
         * once the load has finished or failed.
         * @param scheduler [provider] Non-null task scheduler.
         * @param path [utf8] File path (copied internally; caller may free after return).
         * @param on_complete [completion:user_data] Callback invoked with the result; must not be NULL.
         * @param user_data  Forwarded unchanged to @p on_complete.
         * @return A ke_task* that can be waited on. */
        ke_task *(*load_model_async)(struct ke_asset_loader *self,
                                     ke_scheduler *scheduler,
                                     const char *path,
                                     ke_load_model_complete_func on_complete,
                                     void *user_data);

    } ke_asset_loader;

    typedef struct ke_asset_loader_handle
    {
        ke_asset_loader *ref;
        void (*destroy)(ke_asset_loader *self);
    } ke_asset_loader_handle;

#ifdef __cplusplus
}
#endif

#endif
