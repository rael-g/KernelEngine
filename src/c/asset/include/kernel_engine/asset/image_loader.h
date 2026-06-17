#ifndef KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_
#define KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/common/error.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief ABI-stable vtable for decoding 2D images (PNG/JPG/...) from disk into RGBA8.
    ///        Concrete implementations are provided as separate plugins (e.g., stb_image);
    ///        async dispatch is the caller's responsibility (C# side wraps with Task.Run on a
    ///        worker), so this contract stays minimal.
    typedef struct ke_image_loader
    {
        void *handle;

        /// @brief Destroys and frees the loader itself.
        void (*destroy)(struct ke_image_loader *self);

        /// @brief Loads an image from @p path into a newly allocated ke_texture_data (RGBA8).
        ///        The caller owns the result and must release it with free_image.
        ke_result (*load_image)(struct ke_image_loader *self,
                                const char *path,
                                ke_texture_data **out,
                                ke_error **out_error);

        /// @brief Frees a ke_texture_data previously returned by load_image.
        void (*free_image)(struct ke_image_loader *self, ke_texture_data *data);

    } ke_image_loader;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_
