# Assets & Pipelines

Asset handling spans a kernel contract, a plugin backend, the managed abstraction, and a planned coordinator/pipeline layer.

## Model loading ✅

- **Contract**: `ke_asset_loader` (kernel) — loads a model into `ke_model_data` (meshes as `ke_vertex` arrays, materials, decoded RGBA8 textures), sync and async.
- **Backend**: the Assimp plugin (`src/cpp/asset/assimp/`) handles fbx/gltf/obj/etc. and decodes textures.
- **Managed surface**: `IAssetLoader` + `IModel` in `Abstractions`. The Assimp wrapper's concrete types (`AssetLoader`, `ModelData`, `MeshData`, `MaterialData`, `TextureData`) are **`internal`** and implement the interfaces; `AddAssimpAssetLoader()` registers `IAssetLoader` (never the concrete).

The model abstraction:

```
IAssetLoader        LoadModel(path) / LoadModelAsync(path) → IModel
IModel : IDisposable  Meshes, Materials, Textures  (IReadOnlyList<…>)
IModelMesh            Name, MaterialIndex, ReadOnlySpan<Vertex> Vertices, ReadOnlySpan<ushort> Indices
IModelMaterial        Name, BaseColor, Metallic, Roughness, AlbedoTextureIndex, NormalMapTextureIndex
IModelTexture         Path, Width, Height, ReadOnlySpan<byte> Pixels
```

Crucially, `IModelMesh.Vertices` exposes the engine `Vertex` (binary-compatible with the native `ke_vertex`, cast **inside** the plugin) — so consumers never touch `KernelEngine.Kernel.Native`. Game code resolves `IAssetLoader` via DI and iterates the interfaces only.

## Texture loading ✅

`TextureLoader` decodes PNGs (via SixLabors.ImageSharp) and cubemaps (6 faces, +X −X +Y −Y +Z −Z), returning GPU handles. (Planned to be reframed behind a high-level `Texture` type — see Framework Tier A.)

## How a model reaches the screen today

Examples currently do the upload by hand to keep the steps explicit and educational:

1. Load via `IAssetLoader.LoadModelAsync(path)` → `IModel`.
2. For each `IModelTexture` → `resources.CreateTextureAsync(...)`.
3. For each `IModelMaterial` → `resources.CreateMaterialAsync(...)` wiring albedo/normal.
4. For each `IModelMesh` → `resources.CreateMeshAsync(mesh.Vertices.ToArray(), mesh.Indices.ToArray())` + add a `MeshNode`.

This manual loop is a known framework leak; it will collapse to `scene.Add(assets.LoadModel(path))` once the high-level asset façade lands (Framework Tier A — see [06 - Framework](06%20-%20Framework.md)).

## Planned — `KernelEngine.AssetPipeline` 📋

The current Assimp wrapper is a single half-finished loader. The planned coordinator (tracked as `[B5.6]` in the Kanban) adds:

- **`IAssetPipeline`** — a dispatcher that routes a path to the right `IAssetLoader` by extension; `RegisterLoader(extension, loader)`.
- **`AssetCache`** — `path → IModel` with ref-counting and (future) hot-reload.
- **Per-format loader plugins** — Assimp (fbx/gltf/obj) today; future `KernelEngine.Asset.Ktx2` (compressed textures), `KernelEngine.Asset.Bake` (engine-baked format).
- **`IModelNode`** — preserved model hierarchy (Assimp/glTF node tree) so instancing can keep structure rather than flattening.
- **Baking / offline pipeline** — raw → optimized binary, and an `IAssetWatcher` for filesystem hot-reload.

Adding a new format must require only implementing `IAssetLoader` — no framework or kernel change.

## Scene serialization 📋

Reuse and serialization follow the framework's **"everything is a Scene"** model (see [06 - Framework](06%20-%20Framework.md)):

- Phase 1 (code-based): a Scene factory builds a node subtree; `scene.Instantiate()` deep-copies it for reuse. No separate "Prefab" type.
- Phase 2 (deferred): **`SceneAsset`** — the serialized on-disk form (`.kescene` or similar), part of the asset family. `assets.LoadScene(path)` → a `Scene` you `.Instantiate()`. This ties into the offline asset pipeline above.

## Build-time asset steps

Shader compilation (`scripts/compile_shaders.py`) and binding generation (`scripts/generate_bindings.cs`) are build-time pipelines covered in [10 - Build & Tooling](10%20-%20Build%20%26%20Tooling.md).
