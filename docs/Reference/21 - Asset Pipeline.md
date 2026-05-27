# 21 — Asset Pipeline

> **Status**: 📋 Architectural decision. Not implemented. This chapter specifies the lifecycle of binary assets (meshes, textures, audio) from source files on disk to the form the runtime consumes — and how the editor, CLI, and CI all share the same pipeline.

## 1. The three stages

```
Source file              Import                  Runtime
─────────────             ─────────              ─────────────
assets/cube.glb    ─►   ke import / watch  ─►   build/cache/assets/cube.<hash>.mesh
                              │
                              ▼
                    asset_manifest.toml     (source → cache mapping)
```

Every binary asset passes through three stages: **Detect** (something changed on disk), **Import** (transform source into runtime-friendly form, cache the result), and **Manifest update** (record what was produced so the runtime and tooling can find it).

The runtime **never reads source files**. It reads from the cache via the manifest. This separation is what enables shipping builds without the source assets, deterministic loads, fast cold starts, and platform-specific output formats.

## 2. The cache, in concrete terms

```
build/cache/assets/
  cube.<hash>.mesh                    # processed mesh for the engine's format
  brick_albedo.<hash>.texture         # compressed (BC7, etc.) texture
  music.<hash>.audio                  # decoded/compressed audio buffer
```

The `<hash>` is a content hash of `(source bytes + import settings + cache schema version)`. Same inputs → same hash → same output filename. Different inputs → different file; old cache entries get garbage-collected on demand.

Cache files are binary, engine-internal, format-versioned. Their layout is not part of any public API — they can be tossed and regenerated.

## 3. Import settings — the `*.import` sidecar

Defined in [15 - Serialization & Project Files §6.3](15%20-%20Serialization%20%26%20Project%20Files.md#63-asset-import-settings-importtoml). Each binary asset *may* have a sidecar `<asset>.import` next to it. Without one, the importer uses category defaults.

```toml
# assets/textures/brick_albedo.png.import
[import]
type        = "texture"
srgb        = true
mipmaps     = true
compression = "bc7"
```

```toml
# assets/meshes/character.glb.import
[import]
type             = "mesh"
generate_normals = false
scale_factor     = 1.0
optimize         = true
```

The sidecar exists if either (a) the importer auto-generated it on first import, or (b) the developer edited the defaults. Sidecar IS the settings; no settings live elsewhere.

## 4. The manifest

A single TOML file per project, regenerated incrementally:

```toml
# asset_manifest.toml (at project root, gitignored)
[asset.assets_meshes_cube_glb]
source        = "res://assets/meshes/cube.glb"
import_hash   = "a3f9...c421"
content_hash  = "9d12...8e0a"
cache_path    = "build/cache/assets/cube.a3f9c421.mesh"
imported_at   = "2026-06-12T14:32:08Z"
importer      = "assimp:1.2.0"

[asset.assets_textures_brick_albedo_png]
source        = "res://assets/textures/brick_albedo.png"
import_hash   = "7b21...0f33"
content_hash  = "ee04...c901"
cache_path    = "build/cache/assets/brick_albedo.7b210f33.texture"
imported_at   = "2026-06-12T14:33:11Z"
importer      = "stb_image:1.0.0"
```

Lookups go source → cache. The runtime asks the manifest "give me the cache path for `res://assets/meshes/cube.glb`" and loads that file.

**Why gitignored:** the manifest is fully derivable from source + sidecar + cache. Checking it in invites merge conflicts and stale entries. CI regenerates it from scratch.

## 5. Modes — editor vs ship

The pipeline has two execution modes:

### 5.1 Editor mode (incremental, watch-based)

- A file watcher (`ke watch` or the editor lib's `AssetWatcher`) observes `assets/`.
- On change: enqueue an import for the affected file.
- Imports run on a background task, write to cache, update manifest entry.
- Editor receives a `OnAssetReimported` event (chapter 18 §7) and reloads the affected resource live if any open scene uses it.

This is the dev-loop ergonomics: save your `.glb` in Blender, the engine sees the new geometry within a second.

### 5.2 Ship mode (full, deterministic)

- `ke build <target>` discards the cache and reimports everything from scratch.
- No file watcher. No timestamps. Order of imports is deterministic (alphabetical on source path).
- The manifest is regenerated; both manifest and cache are bundled into the shipping artifact.
- The source assets are **not** shipped — only the cache.

The two modes share the importer code. The only differences are the trigger (watcher vs sweep) and the cache lifetime (persistent vs throwaway).

## 6. Importers — the plugin contract

Each importer is a plugin registered with a category (`mesh`, `texture`, `audio`). The pipeline routes files based on `[import] type = "..."` in the sidecar (when present) or by file extension (when not).

```csharp
public interface IAssetImporter
{
    string Category { get; }                       // "mesh" / "texture" / "audio"
    string Version  { get; }                       // semver string — bumps invalidate cache
    IReadOnlyCollection<string> Extensions { get; } // [".glb", ".gltf"]

    Task<Result<ImportedAsset, EditorError>> Import(
        string sourcePath,
        ImportSettings settings,
        string cacheOutputPath,
        CancellationToken ct);
}
```

Multiple importers per category coexist (e.g. `assimp` and a hypothetical `meshoptimizer-direct`). The plugin database (chapter 20) lists who can handle what. Project settings or per-asset settings choose the importer when there's ambiguity:

```toml
# Project
[import.defaults]
mesh    = "assimp"
texture = "stb_image"
audio   = "vorbis"

# Or per-asset override in the sidecar:
[import]
type     = "mesh"
importer = "meshoptimizer-direct"
```

## 7. Runtime path

Existing types (`Mesh`, `Texture`, `Material` — chapter 9) gain a `Load(string resPath)` method that:

1. Looks up the path in the manifest.
2. If found, loads the cache file directly into the engine's structures (fast — no parsing, no transcoding).
3. If not found, errors loudly. Importing-on-demand at runtime is **not** supported in ship mode; in editor mode, the editor can trigger an import-then-load fallback, but that's an editor concern, not a runtime one.

The runtime knows nothing about source formats. It only knows the cache format and the manifest.

## 8. Cache invalidation rules

Three things invalidate a cache entry:

1. **Source content hash changed** — file was edited.
2. **Import settings hash changed** — sidecar TOML was edited.
3. **Importer version changed** — importer plugin bumped its `Version`. Invalidates all assets it produced.

A fourth, implicit one: **cache schema version**. If the engine changes the binary layout of `.mesh` files, that bumps a global cache schema number and everything reimports. Rare — schema bumps are batched.

Garbage collection: orphaned cache files (no manifest entry pointing at them) are deleted by `ke build cache --gc`. Editor runs it lazily; CI runs it as part of every build.

## 9. Watcher semantics (editor mode)

The watcher debounces (300 ms by default) so rapid-fire saves from a DCC tool don't trigger N reimports. Concurrent imports cap at `Environment.ProcessorCount` to keep the machine responsive.

Conflicts (source file deleted while an import is queued) drop the queued import with a warning event. Conflicts (sidecar deleted while file remains) trigger a reimport with category defaults.

## 10. CLI surface

```bash
ke import <path>                  # import one asset
ke import --all                   # reimport everything from scratch
ke import --changed               # only reimport what's stale
ke import settings <path>         # print the current sidecar (or defaults)
ke import settings <path> --set "compression=bc1"  # edit sidecar
ke build cache --gc               # drop orphaned cache entries
ke build cache --info             # cache size, count, oldest entry
```

All of these map to Editor Lib operations (chapter 18 §2.4) — the CLI is the thin wrapper.

## 11. What this is NOT

- **Not an asset store / marketplace.** Local files only.
- **Not a CDN.** No remote cache. (Possible later — would be a separate service the importer talks to before doing local work.)
- **Not a version-controlled cache.** Cache is gitignored. Determinism is achieved by the source + sidecar + version being reproducible, not by checking in derived data.
- **Not runtime asset hotloading.** The editor's "live reload on save" is an editor convenience, not a runtime feature. Game code does not opt into it.

## 12. Cross-references

- File formats it consumes/produces: [15 - Serialization & Project Files §6.3](15%20-%20Serialization%20%26%20Project%20Files.md#63-asset-import-settings-importtoml).
- Editor lib operations that drive it: [18 - Editor Lib API §2.4](18%20-%20Editor%20Lib%20API.md#24-asset).
- CLI commands that wrap it: [19 - CLI & Agent Surface §2.2](19%20-%20CLI%20%26%20Agent%20Surface.md#22-examples).
- Importer plugins discovered via: [20 - Capability Database §4](20%20-%20Capability%20Database.md#4-plugin_databasetoml).
- Runtime asset loaders consuming the cache: [09 - Assets & Pipelines](09%20-%20Assets%20%26%20Pipelines.md).
