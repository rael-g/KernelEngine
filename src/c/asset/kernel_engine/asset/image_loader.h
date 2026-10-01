#ifndef KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_
#define KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/common/error.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** ABI-stable vtable for decoding 2D images (PNG/JPG/...) from disk into RGBA8.
     * Concrete implementations are provided as separate plugins;
     * async dispatch is the caller's responsibility, so this contract stays minimal. */
    typedef struct ke_image_loader
    {
        void *handle;

        /** Loads an image from @p path into a newly allocated ke_texture_data (RGBA8).
         * The caller owns the result and must release it with free_image.
         * @param path [utf8] Image file path to decode. */
        ke_texture_data *(*load_image)(struct ke_image_loader *self,
                                       const char *path,
                                       ke_error **out_error);

        /** Frees a ke_texture_data previously returned by load_image. */
        void (*free_image)(struct ke_image_loader *self, ke_texture_data *data);

    } ke_image_loader;

    typedef struct ke_image_loader_handle
    {
        ke_image_loader *ref;
        void (*destroy)(ke_image_loader *self);
    } ke_image_loader_handle;

#ifdef __cplusplus
}
#endif

#endif
