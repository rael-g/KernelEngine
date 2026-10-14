# How does an asset path become a GPU resource, and what is shared between requests?

This is a map: the parts between a path and a resource on the GPU, what each receives and what it
hands on. How a part works inside is on the generated page of its file. Contracts are under
`src/c/asset/`, `src/c/text/` and `src/c/resource_cache/`, plugins under `src/zig/asset/`,
`src/zig/text/`, `src/zig/resource_cache/` and `src/zig/framework/`.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| image loader | `ke_image_loader` | stb_image | a file path | RGBA8 pixels in a `ke_texture_data` |
| font loader | `ke_font_loader` | stb_truetype | a path, a size, a codepoint range | an atlas and glyph metrics in a `ke_font_data` |
| model loader | `ke_asset_loader` | assimp | a model path | meshes, materials and textures in a `ke_model_data` |
| resolver | `ke_asset_resolver` | framework | the image and font loaders, a project root | decoded data, or handles of the render service |
| cache | `ke_resource_cache` | default | handles, path keys, a destroy callback | the handle for a key, with a reference |
| render service | `ke_render_service` | service | decoded data, a key | handles of meshes, textures and materials |

**The resolver turns an authored path into data or into a handle.** The `resolve_*` slots decode
and return data the caller frees and touch no GPU. The `resolve_*_into` slots take the render
service, ask it for the key first, and upload only on a miss. The key is the path as authored,
so the same file under two spellings is two resources. The prefix "res://" stands for the project
root given to `ke_asset_resolver_create`; "res://primitives/" names the meshes the resolver bakes
itself.

**The render service remembers by key.** It owns one `ke_resource_cache` for meshes, one for
textures, one for materials and one for shaders. An upload under a key already cached returns the
cached handle and compares nothing else; a miss creates the GPU objects and registers the handle
under the key. A material retains its two textures and releases them when it is destroyed.

**The cache counts references.** `register_resource` starts a handle at one, `retain` and
`release` move the count, and the release that reaches zero removes the handle and every path
that named it before it calls the destroy callback. `try_get_cached` retains for its caller, so
every hit owes one `release`; `cache_insert` takes no reference. The audio backend (`ke_audio`,
miniaudio) keeps its own cache the same way, keyed by sound id and path.

**Loaders own what they return.** The data a loader returns is freed through the same loader
(`free_image`, `free_font`, `free_model`). The model loader has a synchronous and an
asynchronous slot, and its records never refer to the imported scene.

## Who asks

The system "render.sprite2d.resolve" calls `resolve_texture_into` for a sprite's texture path.
The system "render.label.resolve" bakes a label's font through `resolve_font` and uploads the
atlas. The system "render.mesh.resolve" bakes the primitive a mesh component names and uploads it
without the resolver. Models are loaded by `ke_asset_loader` and uploaded by managed code.

## What the parts agree on without a contract

- The prefixes "res://" and "res://primitives/", and the names "quad", "plane", "cube" and
  "sphere" after the latter.
- The cache keys the render systems use: "primitive:quad", "primitive:plane", "primitive:cube",
  "primitive:sphere:0.5:24:32", and the font key "font:<path>:<size>:<atlas>:<first>:<count>".
- The vertex layout the resolver converts to for `upload_mesh`: eleven floats (position, normal,
  uv, tangent).
- The invalid handle of `ke_resource_cache` is `KE_RESOURCE_HANDLE_NONE`, not zero.
- `AddAssetResolver` takes `INativeImageLoader` and `INativeFontLoader` from the container, so
  `AddStbImageLoader` and `AddTextStbTrueType` have to be registered for textures and fonts to
  resolve.
