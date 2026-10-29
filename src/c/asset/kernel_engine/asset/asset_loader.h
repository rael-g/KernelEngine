#ifndef KERNEL_ENGINE_ASSET_ASSET_LOADER_H_
#define KERNEL_ENGINE_ASSET_ASSET_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/task_pool/task_pool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** Completion callback for ke_asset_loader::load_model_async.
     * @param result    KE_OK, or the code of the load that failed, whose reason is logged.
     * @param data      [optional] The loaded model; NULL when the load failed.
     * @param user_data [context] Opaque pointer forwarded from load_model_async. */
    typedef void (*ke_load_model_complete_func)(ke_result result,
                                                struct ke_model_data *data,
                                                void *user_data);

    /** [interface] Loads 3D assets into ke_model_data. */
    typedef struct ke_asset_loader
    {
        void *handle;

        /** Loads a 3D model from @p path into a newly allocated ke_model_data.
         * @param path [utf8] Absolute or relative file path (.gltf, .glb, .obj, .fbx, …).
         * @param out_model [out] Receives the model, which the caller owns and releases with
         *        free_model; NULL on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null path or out_model;
         *         KE_RESULT_NOT_FOUND when the importer cannot read the file, its reason logged;
         *         KE_RESULT_OUT_OF_MEMORY. */
        ke_result (*load_model)(struct ke_asset_loader *self,
                                const char *path,
                                ke_model_data **out_model);

        /** [releases:Model] Frees a ke_model_data previously returned by load_model or the async variant.
         * The model must be given back to the same loader that produced it. A foreign
         * or hand-built ke_model_data is not a valid argument. A null @p data is ignored. */
        void (*free_model)(struct ke_asset_loader *self, ke_model_data *data);

        /** Asynchronously loads a 3D model, calling @p on_complete on a task pool thread
         * once the load has finished or failed.
         * @param task_pool [provider] Non-null task pool.
         * @param path [utf8] File path (copied internally; caller may free after return).
         * @param on_complete [completion:user_data] Callback invoked with the result; must not be NULL.
         * @param user_data  Forwarded unchanged to @p on_complete.
         * @return A ke_task* that can be waited on. */
        ke_task *(*load_model_async)(struct ke_asset_loader *self,
                                     ke_task_pool *task_pool,
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
