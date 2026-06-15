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

#include <kernel_engine/kernel/framework/material_file.h>  // framework-opinion POD consumed via resolve_material
#include <kernel_engine/kernel/asset/mesh_shape.h>
#include <kernel_engine/kernel/asset/image_loader.h>
#include <kernel_engine/kernel/asset/mesh_data.h>
#include <kernel_engine/kernel/text/font.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>

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
        ke_result (*resolve_texture)(struct ke_asset_resolver *self,
                                     const char               *path,
                                     ke_texture_data         **out);

        void (*free_texture)(struct ke_asset_resolver *self,
                             ke_texture_data           *data);

        /// Resolves a mesh path. Two shapes are supported today:
        ///   "res://primitives/{quad|plane|cube|sphere}" → baked primitive via
        ///                                                  ke_mesh_shape_bake
        ///   (additional model-file extensions land when an asset loader
        ///    is injected; .gltf/.fbx/.obj are not yet routed)
        /// Caller owns the result; release with free_mesh.
        ke_result (*resolve_mesh)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  ke_mesh_shape_data       *out);

        void (*free_mesh)(struct ke_asset_resolver *self,
                          ke_mesh_shape_data        *data);

        /// Parses a `.material` TOML file into ke_material_spec. Texture
        /// fields stay as path strings — feed them back through
        /// resolve_texture to materialise.
        ke_result (*resolve_material)(struct ke_asset_resolver *self,
                                      const char               *path,
                                      ke_material_spec         *out);

        /// Resolves a font file path into a freshly-baked ke_font_data (atlas
        /// RGBA8 + glyph metrics). Caller owns the result; release with free_font.
        ///
        /// Returns KE_ERROR_INVALID_ARGUMENT when no font loader was injected
        /// at construction time.
        ke_result (*resolve_font)(struct ke_asset_resolver *self,
                                  const char               *path,
                                  float                     pixel_size,
                                  uint32_t                  first_codepoint,
                                  uint32_t                  codepoint_count,
                                  uint32_t                  atlas_size,
                                  ke_font_data            **out);

        void (*free_font)(struct ke_asset_resolver *self, ke_font_data *data);

        void (*destroy)(struct ke_asset_resolver *self);
    } ke_asset_resolver;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_ASSET_RESOLVER_H_
