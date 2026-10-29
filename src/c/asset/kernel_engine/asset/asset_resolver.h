#ifndef KERNEL_ENGINE_ASSET_ASSET_RESOLVER_H_
#define KERNEL_ENGINE_ASSET_ASSET_RESOLVER_H_

#include <kernel_engine/render/material_file.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/asset/mesh_shape.h>
#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/text/font.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_asset_resolver
    {
        void *handle;

        /**
         * Resolves an image path into freshly-decoded RGBA8 pixel data.
         * Caller owns the result; release with free_texture.
         * @param path [utf8]
         * @param out [out] Receives the decoded texture data on success.
         * @return KE_OK; KE_RESULT_NOT_FOUND when the file is missing or the extension is
         *         unsupported; KE_RESULT_INVALID_ARGUMENT when no image loader was injected
         *         at construction time; the image loader's code otherwise.
         */
        ke_result (*resolve_texture)(struct ke_asset_resolver *self,
                                     const char               *path,
                                     ke_texture_data         **out);

        /** [releases:ResolvedTexture] Frees a ke_texture_data resolve_texture returned. A null
         * @p data is ignored. */
        void (*free_texture)(struct ke_asset_resolver *self,
                             ke_texture_data           *data);

        /**
         * Resolves a mesh path. "res://primitives/{quad|plane|cube|sphere}" names a
         * baked primitive, built via ke_mesh_shape_bake; a path that names none fails.
         * Caller owns the result; release with free_mesh.
         * @param path [utf8]
         * @param out [out] Receives the baked mesh vertex/index data on success; NULL on failure.
         * @return KE_OK, KE_RESULT_NOT_FOUND for a path that names no primitive, or
         *         KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*resolve_mesh)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  ke_mesh_shape_data      **out);

        /** [releases:ResolvedMesh] Frees a ke_mesh_shape_data resolve_mesh returned. A null
         * @p data is ignored. */
        void (*free_mesh)(struct ke_asset_resolver *self,
                          ke_mesh_shape_data        *data);

        /**
         * Parses a `.material` TOML file into ke_material_spec. Texture
         * fields stay as path strings — feed them back through
         * resolve_texture to materialise.
         * @param path [utf8]
         * @param out [out] Receives the parsed material spec on success.
         * @return KE_OK; KE_RESULT_NOT_FOUND when the file cannot be opened; KE_RESULT_IO when
         *         it is not TOML or holds no material table.
         */
        ke_result (*resolve_material)(struct ke_asset_resolver *self,
                                      const char               *path,
                                      ke_material_spec         *out);

        /**
         * Resolves a font file path into a freshly-baked ke_font_data (atlas
         * RGBA8 + glyph metrics). Caller owns the result; release with free_font.
         * @param path [utf8]
         * @param out [out] Receives the baked font atlas + glyph metrics on success.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT when no font loader was injected at
         *         construction time; KE_RESULT_NOT_FOUND when the file is missing; the font
         *         loader's code otherwise.
         */
        ke_result (*resolve_font)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  float                     pixel_size,
                                  uint32_t                  first_codepoint,
                                  uint32_t                  codepoint_count,
                                  uint32_t                  atlas_size,
                                  ke_font_data            **out);

        /** [releases:ResolvedFont] Frees a ke_font_data resolve_font returned. A null @p data is
         * ignored. */
        void (*free_font)(struct ke_asset_resolver *self, ke_font_data *data);

        /**
         * Resolves and uploads a texture, deduped by `path`. On a cache hit,
         * nothing is decoded.
         * @param core [borrowed] The render service to upload into.
         * @param path [utf8]
         * @param out_texture [out] Receives the texture; KE_TEXTURE_NONE on failure.
         * @return KE_OK, resolve_texture's codes, or KE_RESULT_GENERAL when the upload fails.
         */
        ke_result (*resolve_texture_into)(struct ke_asset_resolver *self,
                                          ke_render_service *core, const char *path,
                                          ke_texture_handle *out_texture);

        /**
         * Resolves and uploads a mesh, deduped by `path`. Resolution is that of
         * resolve_mesh.
         * @param core [borrowed] The render service to upload into.
         * @param path [utf8]
         * @param out_mesh [out] Receives the mesh; KE_MESH_NONE on failure.
         * @return KE_OK, resolve_mesh's codes, or KE_RESULT_GENERAL when the upload fails.
         */
        ke_result (*resolve_mesh_into)(struct ke_asset_resolver *self,
                                       ke_render_service *core, const char *path,
                                       ke_mesh_handle *out_mesh);

        /**
         * Resolves a `.material` file, resolving/uploading its albedo and normal
         * textures (each deduped by their own path) and creating the material,
         * deduped by `path`.
         * @param core [borrowed] The render service to upload into.
         * @param path [utf8]
         * @param out_material [out] Receives the material; KE_MATERIAL_NONE on failure.
         * @return KE_OK, the codes of resolve_material and resolve_texture, or
         *         KE_RESULT_GENERAL when an upload or the material creation fails.
         */
        ke_result (*resolve_material_into)(struct ke_asset_resolver *self,
                                           ke_render_service *core, const char *path,
                                           ke_material_handle *out_material);

        /**
         * Writes the file path `path` names into `out`, terminated: a path that begins with
         * "res://" is joined to the project root the resolver was created with, or stands as
         * its remainder when none was given; any other path is copied as written. Nothing
         * checks that the file exists.
         * @param path [utf8]
         * @param out [out,array_of:capacity] Receives the resolved path.
         * @param capacity Bytes `out` holds.
         * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT when the result and its terminator do not
         *         fit in `capacity` bytes.
         */
        ke_result (*resolve_path)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  char                     *out,
                                  size_t                    capacity);
    } ke_asset_resolver;

    typedef struct ke_asset_resolver_handle
    {
        ke_asset_resolver *ref;
        void (*destroy)(ke_asset_resolver *self);
    } ke_asset_resolver_handle;

#ifdef __cplusplus
}
#endif

#endif
