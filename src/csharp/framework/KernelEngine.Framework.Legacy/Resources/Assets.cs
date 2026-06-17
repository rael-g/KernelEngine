using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Load-from-path façade for the resource pipeline. Wraps an <see cref="IAssetLoader"/> (CPU-side
/// parse on worker threads) plus a <see cref="ResourceManager"/> (non-blocking GPU upload). Path
/// dedup is delegated to the native <see cref="NativeResourceCache"/>: a second load of the same
/// path returns a fresh wrapper holding the cached handle with an extra refcount, so freeing the
/// last reference fires the GPU destroy hook in C.
/// </summary>
public sealed class Assets
{
    private readonly IAssetLoader? _modelLoader;
    private readonly IImageLoader? _imageLoader;
    private readonly IFontLoader?  _fontLoader;
    private readonly ResourceManager _resources;
    private readonly IResourceCacheBackend _cache;
    private readonly IAssetResolverBackend? _resolver;

    internal Assets(IAssetLoader? modelLoader,
                    IImageLoader? imageLoader,
                    IFontLoader?  fontLoader,
                    ResourceManager resources,
                    IResourceCacheBackend cache,
                    IAssetResolverBackend? resolver = null)
    {
        _modelLoader = modelLoader;
        _imageLoader = imageLoader;
        _fontLoader  = fontLoader;
        _resources   = resources;
        _cache       = cache;
        _resolver    = resolver;
    }

    /// <summary>
    /// Loads a model from <paramref name="path"/>, caching by path. Subsequent calls with the same
    /// path return the cached handle with an extra reference (caller releases like any other).
    /// </summary>
    public async Task<Model> LoadModelAsync(string path)
    {
        if (_modelLoader == null) throw new InvalidOperationException("No IAssetLoader registered — call AddAssimpAssetLoader() (or equivalent) in your service collection.");

        if (_cache.TryGetCached(path, out var cachedHandle))
            return new Model(_cache, cachedHandle, Array.Empty<ModelMesh>()); // shared cache hit

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
            Material material;
            if (md.MaterialIndex >= 0)
            {
                material = materials[md.MaterialIndex];
                material.Retain();
            }
            else
            {
                material = await _resources.CreateMaterialAsync(new System.Numerics.Vector4(1f, 1f, 1f, 1f));
            }
            meshes[i] = new ModelMesh(md.Name, mesh, material);
        }

        var model = _resources.CreateComposite(meshes, materials, textures);
        _cache.CacheInsert(path, model.RawHandle);
        return model;
    }

    /// <summary>
    /// Loads a font into a <see cref="Font"/> at <paramref name="pixelSize"/>. CPU-side decode +
    /// atlas bake runs on a worker; the atlas-texture upload routes through
    /// <see cref="ResourceManager"/> → ke.render. ke.sim never blocks.
    /// </summary>
    /// <remarks>
    /// Not cached — each call produces a fresh Font (atlas + glyph dictionary).
    /// </remarks>
    public async Task<Font> LoadFontAsync(string path, float pixelSize)
    {
        if (_fontLoader == null)
            throw new InvalidOperationException("No IFontLoader registered — call AddTextStbTrueType() (or equivalent) in your service collection.");

        using var data = await _fontLoader.LoadFontAsync(path, pixelSize);
        var texture = await _resources.CreateTextureAsync(data.AtlasWidth, data.AtlasHeight, data.AtlasRgba);
        return new Font(texture, data.Glyphs, data.LineHeight, data.Ascent);
    }

    public async Task<Texture> LoadTextureAsync(string path)
    {
        if (_cache.TryGetCached(path, out var cachedHandle))
            return new Texture(_cache, new TextureHandle(cachedHandle));

        // Preferred path: native ke_asset_resolver decodes via the injected ke_image_loader.
        // Falls back to the managed IImageLoader when no resolver is wired (test/legacy paths).
        TextureBuffer buffer;
        if (_resolver is not null)
        {
            var resolved = await Task.Run(() => _resolver.ResolveTexture(path))
                ?? throw new FileNotFoundException($"Texture not resolvable: {path}", path);
            buffer = resolved;
        }
        else if (_imageLoader is not null)
        {
            using var img = await _imageLoader.LoadImageAsync(path);
            buffer = new TextureBuffer(img.Width, img.Height, img.Pixels.ToArray());
        }
        else
        {
            throw new InvalidOperationException(
                "No image source registered — wire ke_asset_resolver via Application or register an IImageLoader.");
        }

        var texture = await _resources.CreateTextureAsync(buffer.Width, buffer.Height, buffer.Pixels);
        _cache.CacheInsert(path, texture.RawHandle);
        return texture;
    }
}
