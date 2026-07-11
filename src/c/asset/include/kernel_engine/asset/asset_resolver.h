#ifndef KERNEL_ENGINE_ASSET_ASSET_RESOLVER_H_
#define KERNEL_ENGINE_ASSET_ASSET_RESOLVER_H_

// ke_asset_resolver — maps res:// (and absolute) paths to typed CPU-side asset
// data using injected loader plugins. Part of item 3 of the Tier S scripting
// ABI: scene loader's set_property callbacks see resolved handles instead of
// raw "res://..." strings.
//
// Path schemes:
//   "res://x/y.png"   — prefix stripped, joined onto the project_root passed
//                       to ke_asset_resolver_create. Project_root must be set
//                       for res:// to work.
//   "/abs/path.png"   — used as-is.
//   "rel/path.png"    — used as-is (caller's CWD).
//
// Loader plugins (e.g. stb_image, assimp) are injected. The resolver never
// links them directly; bindings construct the loader, hand it over, and the
// resolver dispatches based on file extension.

#include <kernel_engine/render/material_file.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/render/core/render_core.h>
#include <kernel_engine/asset/mesh_shape.h>
#include <kernel_engine/asset/image_loader.h>
#include <kernel_engine/asset/mesh_data.h>
#include <kernel_engine/text/font.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_asset_resolver
    {
        void *handle;

        /// Resolves an image path into freshly-decoded RGBA8 pixel data.
        /// Caller owns the result; release with free_texture.
        ///
        /// Returns KE_ERROR_NOT_FOUND when the file is missing or the
        /// extension is unsupported; KE_ERROR_INVALID_ARGUMENT when no
        /// image loader was injected at construction time.
        bool (*resolve_texture)(struct ke_asset_resolver *self,
                                     const char               *path,
                                     ke_texture_data         **out,
                                     ke_error                **out_error);

        void (*free_texture)(struct ke_asset_resolver *self,
                             ke_texture_data           *data);

        /// Resolves a mesh path. Two shapes are supported today:
        ///   "res://primitives/{quad|plane|cube|sphere}" → baked primitive via
        ///                                                  ke_mesh_shape_bake
        ///   (additional model-file extensions land when an asset loader
        ///    is injected; .gltf/.fbx/.obj are not yet routed)
        /// Caller owns the result; release with free_mesh.
        bool (*resolve_mesh)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  ke_mesh_shape_data       *out,
                                  ke_error                **out_error);

        void (*free_mesh)(struct ke_asset_resolver *self,
                          ke_mesh_shape_data        *data);

        /// Parses a `.material` TOML file into ke_material_spec. Texture
        /// fields stay as path strings — feed them back through
        /// resolve_texture to materialise.
        bool (*resolve_material)(struct ke_asset_resolver *self,
                                      const char               *path,
                                      ke_material_spec         *out,
                                      ke_error                **out_error);

        /// Resolves a font file path into a freshly-baked ke_font_data (atlas
        /// RGBA8 + glyph metrics). Caller owns the result; release with free_font.
        ///
        /// Returns KE_ERROR_INVALID_ARGUMENT when no font loader was injected
        /// at construction time.
        bool (*resolve_font)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  float                     pixel_size,
                                  uint32_t                  first_codepoint,
                                  uint32_t                  codepoint_count,
                                  uint32_t                  atlas_size,
                                  ke_font_data            **out,
                                  ke_error                **out_error);

        void (*free_font)(struct ke_asset_resolver *self, ke_font_data *data);

        // ── Cached load-from-path (decode + upload + dedup, one call) ───────
        //
        // The path itself is the resource_cache key (see kernel_engine/resource_cache),
        // so a second call with the same path returns the already-uploaded handle
        // (retained) without touching disk or the GPU again. `core` is the render
        // core to upload into — a caller composes the resolver (CPU decode, this
        // plugin) with whichever render core owns the GPU resources; the resolver
        // holds no reference to it beyond the call. Callers own the returned
        // reference and release it like any other core handle.

        /// Resolves and uploads a texture, deduped by `path`. On a cache hit,
        /// nothing is decoded. KE_TEXTURE_NONE on failure (see resolve_texture's
        /// error cases; upload failure also reports via out_error).
        ke_texture_handle (*resolve_texture_into)(struct ke_asset_resolver *self,
                                                  ke_render_core *core, const char *path,
                                                  ke_error **out_error);

        /// Resolves and uploads a mesh, deduped by `path`. Today only the
        /// "res://primitives/*" shapes resolve_mesh understands; a broader
        /// path is a future-loader concern. KE_MESH_NONE on failure.
        ke_mesh_handle (*resolve_mesh_into)(struct ke_asset_resolver *self,
                                           ke_render_core *core, const char *path,
                                           ke_error **out_error);

        /// Resolves a `.material` file, resolving/uploading its albedo and normal
        /// textures (each deduped by their own path) and creating the material,
        /// deduped by `path`. KE_MATERIAL_NONE on failure.
        ke_material_handle (*resolve_material_into)(struct ke_asset_resolver *self,
                                                    ke_render_core *core, const char *path,
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

#endif // KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_H_
