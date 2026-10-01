# How does an asset path become a GPU resource, and what is shared between requests?

Three pieces take part. The **resolver** turns an authored path into decoded pixels, a baked mesh or
a parsed material (`src/zig/framework/src/asset_resolver.zig`, contract
`src/c/asset/kernel_engine/asset/asset_resolver.h`). The **render service** uploads them and
remembers what it uploaded by key (`src/zig/render/service/src/asset_upload.zig`). A
**`ke_resource_cache`** per resource kind does the remembering and the reference counting
(`src/zig/resource_cache/default/src/resource_cache.zig`).

## The resolver

`ke_asset_resolver_create(image_loader, font_loader, project_root)` takes borrowed loaders and a root,
each of which may be null (`asset_resolver_create.h`; `asset_resolver.zig:477-513`). It has two
families of slot.

**`resolve_*` decode and return data the caller frees**: `resolve_texture` (RGBA8 through the image
loader), `resolve_mesh`, `resolve_material`, `resolve_font`. Texture, mesh and font each have a
`free_*` slot; `resolve_material` fills a caller-owned `ke_material_spec` and has none
(`asset_resolver.h`, `asset_resolver.zig:501-507`). They touch no GPU.

- A path starting with `res://` has that prefix replaced by the project root, joined with a `/` only when neither side already supplies one; any
  other path is used as given. With no root, a `res://` path keeps only what follows the prefix
  (`resolvePath`, `joinPath`, `asset_resolver.zig:45-81`). The result is clamped to 1024 bytes (`:14`).
- `resolve_texture` and `resolve_font` fail with `KE_ERROR_INVALID_ARGUMENT` when their loader is
  null, with `KE_ERROR_NOT_FOUND` when the file cannot be opened, and otherwise return what the loader
  returns (`asset_resolver.zig:159-189`, `273-315`).
- `resolve_mesh` accepts one shape of path, `res://primitives/{quad|plane|cube|sphere}`, which it bakes
  with `ke_mesh_shape_bake_internal`. Anything else is `KE_ERROR_NOT_FOUND`; no model file extension is
  routed (`asset_resolver.zig:200-234`; contract text at `asset_resolver.h`, `resolve_mesh`).
- `resolve_material` parses a TOML file with a `[material]` table: `base_color` (array of up to
  four numbers), `metallic`, `roughness`, `alpha_cutoff`, `ior`, `distortion_strength`, `albedo`,
  `normal` (paths, kept as strings) and `alpha_mode` (`"MASK"` or `"BLEND"`; anything else is opaque).
  Missing keys take the defaults set at the top of `parseMaterialFile`. A missing file, a parse
  failure and a file without `[material]` all report `KE_ERROR_IO` (`asset_resolver.zig:99-157`,
  `249-271`).

**`resolve_*_into` do the whole trip.** They take the render service and return a handle:
`resolve_texture_into`, `resolve_mesh_into`, `resolve_material_into` (`asset_resolver.zig:319-466`).
Each starts with the service's `try_get_*` on the authored path. A hit returns the existing handle and
decodes nothing. A miss runs the matching `resolve_*`, converts if needed, and uploads under the same
path as the key:

- A texture goes to `upload_texture(core, path, w, h, pixels)` and the decoded buffer is freed
  (`:345-354`).
- A mesh is repacked from `ke_vertex` to the service's 11-float layout (position, normal, uv, tangent)
  and sent to `upload_mesh` (`:361-422`).
- A material resolves its `albedo` and `normal` paths through `resolve_texture_into` first, each
  keyed by its own path, and any that fails fails the material; then `create_material` is keyed by
  the material file's path (`:424-475`).

The key is the path **as authored**, not the resolved filesystem path, so `res://a.png` and the
absolute path of the same file are two textures.

## What the render service does with a key

`upload_mesh`, `upload_texture`, `upload_cubemap` and `create_material` all refuse an empty key with
`KE_ERROR_INVALID_ARGUMENT`, then ask the matching cache for the key before creating anything on the
GPU (`asset_upload.zig:20-27`, `72-80`, `116-124`, `179-195`). The service owns three caches for these, one per
kind (`mesh_cache`, `texture_cache`, `material_cache`, created at
`src/zig/render/service/src/render_service.zig:278-290`; a fourth serves shaders), each with a `destroy_fn` that frees the GPU
objects of one resource (`asset_upload.zig:319-343`).

- **A key already cached returns the existing handle**, and the call's remaining arguments are not
  compared: a second `create_material` under the same key with a different colour returns the first
  material (`asset_upload.zig:194-195`; the key and shader-name checks come first). The key alone
  decides identity.
- **A miss** creates the GPU objects, stores them in a slot map and registers the new handle in the
  cache with a count of 1, then maps the key to it (`registerCached`, `asset_upload.zig:15-18`).
- **A material holds its textures.** Creating one retains its albedo and normal handles; destroying
  it releases them (`asset_upload.zig:246-247`, `340-341`).
- A texture is uploaded with one mip level (`asset_upload.zig:89`).

## The cache

`ke_resource_cache` is two hash tables, one from handle to count and one from path key to handle
(`resource_cache.zig:117-123`).

- `register_resource` inserts a handle with count 1; `retain` adds one; `release` removes one and, at
  zero, drops the handle, evicts every path that mapped to it and calls the cache's `destroy_fn`
  (`resource_cache.zig:129-205`).
- **`try_get_cached` retains on behalf of the caller.** A hit increments the count of the handle it
  returns (`resource_cache.zig:207-222`), so every `try_get_*` or keyed upload that hits owes one
  `release`.
- The path table stores a 64-bit hash of the key and never the key (`keyFromPath`,
  `resource_cache.zig:15-23`, `108-113`). Two keys with equal hashes are the same entry.

## Who asks

- **Sprites.** A `ke_sprite2d_component` carries a `texture` path (`component_fields.h:65`). The
  `render.sprite2d.resolve` system, registered in `KE_PHASE_UPDATE` and unpinned
  (`render_module.zig:303-311`), calls `resolve_texture_into` and stores the handle on the component;
  it skips the call once the component's handle is valid (`sprite_resolve.zig:56-63`). A null
  resolver or an empty path leaves the sprite untextured (`:61-64`).
- **Labels.** The `label` resolve system bakes a font once per label through `resolve_font`, with the
  fixed parameters first codepoint 32, 95 codepoints and a 512 atlas, uploads the atlas under the key
  `font:<path>:<size>:<atlas>:<first>:<count>`, and registers it with the UI service
  (`label_resolve.zig:21-64`). A failure is logged under the tag `render.label` and the label draws
  no text.
- **Primitive meshes in scenes** do not go through the resolver. The mesh component names a
  `primitive`, and `render.mesh.resolve` bakes that primitive itself and uploads it under
  a key starting `primitive:` (`mesh_resolve.zig:25`, `38`, `79`, `131`; `resolveMesh` at `134`; registered at `render_module.zig:285-293`).
- **Models** are decoded by the Assimp loader and uploaded by game code through
  `IRenderResources` (`src/zig/asset/assimp/src/assimp_loader.zig:111`;
  `src/csharp/render/KernelEngine.Render.Webgpu/Assets/ModelExtensions.cs:33-34`, `64`), which
  keys by `{rootName}#mesh{i}` and the texture's path.

No code in `src` or `examples` calls `resolve_mesh_into` or `resolve_material_into`
(`grep -rn 'resolve_mesh_into\|resolve_material_into' src examples` finds only the resolver, its
header and generated wrappers); `resolve_texture_into` has the one caller above.

The resolver reaches the render module through a borrowed pointer given at creation:
`WebgpuRenderModule.OnLoad` passes `NativeAssetResolver`'s native handle if the container has one,
and null otherwise (`WebgpuRenderModule.cs:126-129`). `AddAssetResolver` registers the resolver with
the image and font loaders the container holds, and the project root defaulting to the application
base directory (`src/csharp/framework/KernelEngine.Framework/Assets/AssetResolverServiceCollectionExtensions.cs:18-26`).

## What does not exist

No import step, cache on disk, manifest, watcher or hot reload sits between a path and its pixels:
every miss decodes the source file synchronously on the calling thread, and the upload that follows
is a direct call (`asset_resolver.zig:338-347`). Nothing frees a cached resource except a `release`
that reaches zero.
