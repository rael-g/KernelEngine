#ifndef KERNEL_ENGINE_ASSET_ASSET_RESOLVER_H_
#define KERNEL_ENGINE_ASSET_ASSET_RESOLVER_H_

#include <kernel_engine/render/material_file.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/service/render_service.h>
#include <kernel_engine/asset/mesh_shape.h>
#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/text/font.h>
#include <kernel_engine/common/error.h>

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
         * Returns KE_ERROR_NOT_FOUND when the file is missing or the
         * extension is unsupported; KE_ERROR_INVALID_ARGUMENT when no
         * image loader was injected at construction time.
         * @param path [utf8]
         * @param out [out] Receives the decoded texture data on success.
         */
        bool (*resolve_texture)(struct ke_asset_resolver *self,
                                     const char               *path,
                                     ke_texture_data         **out,
                                     ke_error                **out_error);

        void (*free_texture)(struct ke_asset_resolver *self,
                             ke_texture_data           *data);

        /**
         * Resolves a mesh path. Two shapes are supported today:
         * "res://primitives/{quad|plane|cube|sphere}" -> baked primitive via
         * ke_mesh_shape_bake (additional model-file extensions land when an
         * asset loader is injected; .gltf/.fbx/.obj are not yet routed).
         * Caller owns the result; release with free_mesh.
         * @param path [utf8]
         * @param out [out] Receives the baked mesh vertex/index data on success.
         */
        bool (*resolve_mesh)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  ke_mesh_shape_data       *out,
                                  ke_error                **out_error);

        void (*free_mesh)(struct ke_asset_resolver *self,
                          ke_mesh_shape_data        *data);

        /**
         * Parses a `.material` TOML file into ke_material_spec. Texture
         * fields stay as path strings — feed them back through
         * resolve_texture to materialise.
         * @param path [utf8]
         * @param out [out] Receives the parsed material spec on success.
         */
        bool (*resolve_material)(struct ke_asset_resolver *self,
                                      const char               *path,
                                      ke_material_spec         *out,
                                      ke_error                **out_error);

        /**
         * Resolves a font file path into a freshly-baked ke_font_data (atlas
         * RGBA8 + glyph metrics). Caller owns the result; release with free_font.
         * Returns KE_ERROR_INVALID_ARGUMENT when no font loader was injected
         * at construction time.
         * @param path [utf8]
         * @param out [out] Receives the baked font atlas + glyph metrics on success.
         */
        bool (*resolve_font)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  float                     pixel_size,
                                  uint32_t                  first_codepoint,
                                  uint32_t                  codepoint_count,
                                  uint32_t                  atlas_size,
                                  ke_font_data            **out,
                                  ke_error                **out_error);

        void (*free_font)(struct ke_asset_resolver *self, ke_font_data *data);

        /**
         * Resolves and uploads a texture, deduped by `path`. On a cache hit,
         * nothing is decoded. KE_TEXTURE_NONE on failure (see resolve_texture's
         * error cases; upload failure also reports via out_error).
         * @param core [opaque] The render core to upload into — this consumer
         *             (the framework plugin, backend-agnostic) never names a
         *             concrete render backend's own struct.
         * @param path [utf8]
         */
        ke_texture_handle (*resolve_texture_into)(struct ke_asset_resolver *self,
                                                  ke_render_service *core, const char *path,
                                                  ke_error **out_error);

        /**
         * Resolves and uploads a mesh, deduped by `path`. Today only the
         * "res://primitives/*" shapes resolve_mesh understands; a broader
         * path is a future-loader concern. KE_MESH_NONE on failure.
         * @param core [opaque]
         * @param path [utf8]
         */
        ke_mesh_handle (*resolve_mesh_into)(struct ke_asset_resolver *self,
                                           ke_render_service *core, const char *path,
                                           ke_error **out_error);

        /**
         * Resolves a `.material` file, resolving/uploading its albedo and normal
         * textures (each deduped by their own path) and creating the material,
         * deduped by `path`. KE_MATERIAL_NONE on failure.
         * @param core [opaque]
         * @param path [utf8]
         */
        ke_material_handle (*resolve_material_into)(struct ke_asset_resolver *self,
                                                    ke_render_service *core, const char *path,
                                                    ke_error **out_error);

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
