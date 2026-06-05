using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Creates ref-counted managed GPU resources (<see cref="Material"/>, <see cref="Mesh"/>,
/// <see cref="Texture"/>) on top of the low-level <see cref="IResourceFactory"/>. Every created
/// handle is registered in the native <see cref="NativeResourceCache"/> so refcount and destroy
/// are dispatched through the shared C primitive.
/// <para>
/// All creation is <b>async</b> by design: the GPU upload must run on ke.render, and the sim thread
/// (ke.sim) must never block on it. Callers <c>await</c> the returned <see cref="Task"/>; the
/// resource is fully formed when the task completes. Each result starts with one reference (the
/// caller's); dispose/release frees the GPU handle.
/// </para>
/// </summary>
public sealed class ResourceManager
{
    private readonly IResourceFactory    _factory;
    private readonly IResourceCacheBackend _meshCache;
    private readonly IResourceCacheBackend _materialCache;
    private readonly IResourceCacheBackend _textureCache;

    internal ResourceManager(IResourceFactory factory,
                             IResourceCacheBackend meshCache,
                             IResourceCacheBackend materialCache,
                             IResourceCacheBackend textureCache)
    {
        _factory       = factory;
        _meshCache     = meshCache;
        _materialCache = materialCache;
        _textureCache  = textureCache;
    }

    public Task<Material> CreateMaterialAsync(
        Vector4 color,
        Texture? albedo = null,
        float metallic = 0f,
        float roughness = 0.5f,
        Texture? normalMap = null)
    {
        var albedoHandle = albedo?.Handle ?? default;
        var normalHandle = normalMap?.Handle ?? default;
        return _factory
            .CreateMaterialAsync(color, albedoHandle, metallic, roughness, normalHandle)
            .ContinueWith(t =>
            {
                var handle  = t.Result;
                _materialCache.RegisterResource(handle.Value, () => _factory.DestroyMaterial(handle));
                return new Material(_materialCache, handle);
            }, TaskContinuationOptions.ExecuteSynchronously);
    }

    public Task<Mesh> CreateMeshAsync(Vertex[] vertices, ushort[] indices)
        => _factory.CreateMeshAsync(vertices, indices)
            .ContinueWith(t =>
            {
                var handle = t.Result;
                _meshCache.RegisterResource(handle.Value, () => _factory.DestroyMesh(handle));
                return new Mesh(_meshCache, handle);
            }, TaskContinuationOptions.ExecuteSynchronously);

    public Task<Texture> CreateTextureAsync(uint width, uint height, byte[] pixels)
        => _factory.CreateTextureAsync(width, height, pixels)
            .ContinueWith(t =>
            {
                var handle = t.Result;
                _textureCache.RegisterResource(handle.Value, () => _factory.DestroyTexture(handle));
                return new Texture(_textureCache, handle);
            }, TaskContinuationOptions.ExecuteSynchronously);

    public Task<Texture> CreateCubemapAsync(uint faceSize, byte[] data)
        => _factory.CreateCubemapAsync(faceSize, data)
            .ContinueWith(t =>
            {
                var handle = t.Result;
                _textureCache.RegisterResource(handle.Value, () => _factory.DestroyTexture(handle));
                return new Texture(_textureCache, handle);
            }, TaskContinuationOptions.ExecuteSynchronously);

    /// <summary>
    /// Builds a composite <see cref="Model"/> registering it in the cache with a synthetic
    /// handle whose destroy hook cascades releases to every owned sub-resource. Used by
    /// <see cref="Assets.LoadModelAsync"/> after sub-resources are fully built.
    /// </summary>
    internal Model CreateComposite(IReadOnlyList<ModelMesh> meshes,
                                   IReadOnlyList<Material>  materials,
                                   IReadOnlyList<Texture>   textures)
    {
        uint syntheticHandle = _textureCache.RegisterComposite(() =>
        {
            // Each ModelMesh entry holds its own reference to mesh + material; the materials and
            // textures lists separately hold the +1 reference from construction.
            foreach (var entry in meshes)
            {
                entry.Mesh.Release();
                entry.Material.Release();
            }
            foreach (var material in materials) material.Release();
            foreach (var texture  in textures)  texture.Release();
        });
        return new Model(_textureCache, syntheticHandle, meshes);
    }
}
