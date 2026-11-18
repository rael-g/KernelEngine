#ifndef KERNEL_ENGINE_ASSET_ASSET_LOADER_H_
#define KERNEL_ENGINE_ASSET_ASSET_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** [interface] Loads 3D assets into ke_model_data. Async dispatch is the caller's concern. */
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

        /** [releases:Model] Frees a ke_model_data previously returned by load_model.
         * The model must be given back to the same loader that produced it. A foreign
         * or hand-built ke_model_data is not a valid argument. A null @p data is ignored. */
        void (*free_model)(struct ke_asset_loader *self, ke_model_data *data);

    } ke_asset_loader;

    /// [owner]
    typedef struct ke_asset_loader_handle
    {
        ke_asset_loader *ref;
        void (*destroy)(ke_asset_loader *self);
    } ke_asset_loader_handle;

#ifdef __cplusplus
}
#endif

#endif
