#ifndef KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_
#define KERNEL_ENGINE_ASSET_IMAGE_LOADER_H_

#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** [interface] Decodes 2D images (PNG/JPG/...) from disk into RGBA8.
     * Async dispatch is the caller's responsibility. */
    typedef struct ke_image_loader
    {
        void *handle;

        /** Loads an image from @p path into a newly allocated ke_texture_data (RGBA8).
         * @param path [utf8] Image file path to decode.
         * @param out_image [out] Receives the image, which the caller owns and releases with
         *        free_image; NULL on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null path or out_image;
         *         KE_RESULT_NOT_FOUND when the file cannot be decoded, its reason logged;
         *         KE_RESULT_OUT_OF_MEMORY. */
        ke_result (*load_image)(struct ke_image_loader *self,
                                const char *path,
                                ke_texture_data **out_image);

        /** [releases:Image] Frees a ke_texture_data previously returned by load_image. A null
         * @p data is ignored. */
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
