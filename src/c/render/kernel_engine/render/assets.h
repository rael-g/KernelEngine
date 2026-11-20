#ifndef KERNEL_ENGINE_RENDER_ASSETS_H_
#define KERNEL_ENGINE_RENDER_ASSETS_H_

#include <kernel_engine/render/handles.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// The resources a render service holds, each made once from the asset a path names and found by that path
    /// afterwards.
    typedef struct ke_render_assets
    {
        void *handle;

        /**
         * The texture the image at `path` makes. On a path the service already holds, nothing is read.
         * @param path [utf8] The path as authored; the texture is found by it.
         * @param out_texture [out] Receives the texture; KE_TEXTURE_NONE on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; the resolver's code for the image,
         *         KE_RESULT_PENDING among them while the file is still being read; KE_RESULT_GENERAL when the
         *         upload fails.
         */
        ke_result (*resolve_texture)(struct ke_render_assets *self, const char *path, ke_texture_handle *out_texture);

        /**
         * The mesh the asset at `path` makes. On a path the service already holds, nothing is baked.
         * @param path [utf8] The path as authored; the mesh is found by it.
         * @param out_mesh [out] Receives the mesh; KE_MESH_NONE on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; the resolver's code for the mesh;
         *         KE_RESULT_OUT_OF_MEMORY; KE_RESULT_GENERAL when the upload fails.
         */
        ke_result (*resolve_mesh)(struct ke_render_assets *self, const char *path, ke_mesh_handle *out_mesh);

        /**
         * The material the `.material` file at `path` makes, its albedo and normal textures each found by its own
         * path as resolve_texture finds them.
         * @param path [utf8] The path as authored; the material is found by it.
         * @param out_material [out] Receives the material; KE_MATERIAL_NONE on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; the codes of the resolver and of
         *         resolve_texture; KE_RESULT_GENERAL when the material creation fails.
         */
        ke_result (*resolve_material)(struct ke_render_assets *self, const char *path,
                                      ke_material_handle *out_material);
    } ke_render_assets;

    /// [owner]
    typedef struct ke_render_assets_handle
    {
        ke_render_assets *ref;
        void (*destroy)(ke_render_assets *self);
    } ke_render_assets_handle;

#ifdef __cplusplus
}
#endif

#endif
