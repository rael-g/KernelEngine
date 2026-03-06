#ifndef KERNEL_ENGINE_KERNEL_ASSET_ASSET_LOADER_H_
#define KERNEL_ENGINE_KERNEL_ASSET_ASSET_LOADER_H_

#include <kernel_engine/kernel/asset/mesh_data.h>
#include <kernel_engine/kernel/common/error.h>

#ifdef __cplusplus
extern "C"
{
#endif

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
                                ke_model_data **out);

        /// @brief Frees a ke_model_data previously returned by load_model.
        void (*free_model)(struct ke_asset_loader *self, ke_model_data *data);

    } ke_asset_loader;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_ASSET_ASSET_LOADER_H_
