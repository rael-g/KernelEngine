using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Load-from-path façade for the resource pipeline (Phase 2). Wraps an <see cref="IAssetLoader"/>
/// (e.g. <c>KernelEngine.Asset.Assimp</c>) for CPU-side parse on worker threads and a
/// <see cref="ResourceManager"/> for non-blocking GPU upload; results are <b>cached</b> and
/// <b>deduped</b> by path so a second load of the same path returns the same ref-counted instance
/// (a fresh reference, retained for the caller). On the last release the cache evicts the entry
/// and the GPU resources are freed.
/// </summary>
public sealed class Assets
{
    private readonly IAssetLoader? _modelLoader;
    private readonly IImageLoader? _imageLoader;
    private readonly ResourceManager _resources;

    // Cache holds a strong reference; eviction is driven by Resource.OnDestroyed (set at insert).
    private readonly Dictionary<string, Resource> _cache = new(StringComparer.Ordinal);
    private readonly object _gate = new();

    public Assets(IAssetLoader? modelLoader, IImageLoader? imageLoader, ResourceManager resources)
    {
        _modelLoader = modelLoader;
        _imageLoader = imageLoader;
        _resources = resources;
    }

    /// <summary>
    /// Loads a model from <paramref name="path"/>, caching by path. Subsequent calls with the same
    /// path return the cached model with an extra reference (caller releases like any other).
    /// </summary>
    public async Task<Model> LoadModelAsync(string path)
    {
        if (_modelLoader == null) throw new InvalidOperationException("No IAssetLoader registered — call AddAssimpAssetLoader() (or equivalent) in your service collection.");

        // Cache fast path.
        lock (_gate)
        {
            if (_cache.TryGetValue(path, out var cached))
                return (Model)cached.Retain();
        }

        // CPU-side parse runs on the loader's worker threads (enkiTS via the task scheduler);
        // GPU upload routes through ResourceManager → ke.render. ke.sim never blocks.
        using var data = await _modelLoader.LoadModelAsync(path);

        var textures = new Texture[data.Textures.Count];
        for (int i = 0; i < data.Textures.Count; i++)
        {
            var t = data.Textures[i];
            textures[i] = await _resources.CreateTextureAsync(t.Width, t.Height, t.Pixels.ToArray());
        }

        var materials = new Material[data.Materials.Count];
        for (int i = 0; i < data.Materials.Count; i++)
        {
            var m = data.Materials[i];
            var albedo = m.AlbedoTextureIndex >= 0 ? textures[m.AlbedoTextureIndex] : null;
            var normal = m.NormalMapTextureIndex >= 0 ? textures[m.NormalMapTextureIndex] : null;
            materials[i] = await _resources.CreateMaterialAsync(m.BaseColor, albedo, m.Metallic, m.Roughness, normal);
        }

        var meshes = new ModelMesh[data.Meshes.Count];
        for (int i = 0; i < data.Meshes.Count; i++)
        {
            var md = data.Meshes[i];
            var mesh = await _resources.CreateMeshAsync(md.Vertices.ToArray(), md.Indices.ToArray());
            // Fallback to a default white material when the source mesh has none, so the model is
            // always renderable. Owned by the Model so it gets freed on release.
            Material material;
            if (md.MaterialIndex >= 0)
            {
                material = materials[md.MaterialIndex];
                material.Retain(); // each mesh entry holds its own reference into the materials list
            }
            else
            {
                material = await _resources.CreateMaterialAsync(new System.Numerics.Vector4(1f, 1f, 1f, 1f));
            }
            meshes[i] = new ModelMesh(md.Name, mesh, material);
        }

        var model = new Model(meshes, materials, textures);

        // Insert under lock; on race, drop our duplicate and return the winner with a fresh retain.
        lock (_gate)
        {
            if (_cache.TryGetValue(path, out var winner))
            {
                model.Release();
                return (Model)winner.Retain();
            }
            model.OnDestroyed = () => { lock (_gate) _cache.Remove(path); };
            _cache[path] = model;
        }
        return model;
    }

    /// <summary>
    /// Loads a 2D image file (PNG/JPG/...) into a ref-counted <see cref="Texture"/>, caching by
    /// path. CPU-side decode runs on a worker (<see cref="IImageLoader.LoadImageAsync"/>); the GPU
    /// upload routes through <see cref="ResourceManager"/> → ke.render. ke.sim never blocks.
    /// </summary>
    public async Task<Texture> LoadTextureAsync(string path)
    {
        if (_imageLoader == null) throw new InvalidOperationException("No IImageLoader registered — call AddStbImageLoader() (or equivalent) in your service collection.");

        lock (_gate)
        {
            if (_cache.TryGetValue(path, out var cached))
                return (Texture)cached.Retain();
        }

        using var img = await _imageLoader.LoadImageAsync(path);
        var pixels = img.Pixels.ToArray();
        var texture = await _resources.CreateTextureAsync(img.Width, img.Height, pixels);

        lock (_gate)
        {
            if (_cache.TryGetValue(path, out var winner))
            {
                texture.Release();
                return (Texture)winner.Retain();
            }
            texture.OnDestroyed = () => { lock (_gate) _cache.Remove(path); };
            _cache[path] = texture;
        }
        return texture;
    }
}
