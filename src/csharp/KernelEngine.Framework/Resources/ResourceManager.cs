using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Creates ref-counted managed GPU resources (<see cref="Material"/>, <see cref="Mesh"/>,
/// <see cref="Texture"/>) on top of the low-level <see cref="IResourceFactory"/>.
/// <para>
/// All creation is <b>async</b> by design: the GPU upload must run on ke.render, and the sim thread
/// (ke.sim) must never block on it. Callers <c>await</c> the returned <see cref="Task"/>; the
/// resource is fully formed when the task completes. Each result starts with one reference (the
/// caller's); dispose/release frees the GPU handle.
/// </para>
/// <para>
/// Phase 1 of the resource pipeline: handle encapsulation + lifetime + non-blocking creation.
/// Caching/dedup by key arrives with the <see cref="IAssetLoader"/>-fronted Assets façade (Phase 2),
/// where CPU-side parse/decode runs on enkiTS worker threads via the engine task scheduler.
/// </para>
/// </summary>
public sealed class ResourceManager
{
    private readonly IResourceFactory _factory;

    public ResourceManager(IResourceFactory factory)
    {
        _factory = factory;
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
            .ContinueWith(t => new Material(_factory, t.Result), TaskContinuationOptions.ExecuteSynchronously);
    }

    public Task<Mesh> CreateMeshAsync(Vertex[] vertices, ushort[] indices)
        => _factory.CreateMeshAsync(vertices, indices)
            .ContinueWith(t => new Mesh(_factory, t.Result), TaskContinuationOptions.ExecuteSynchronously);

    /// <summary>Uploads a <see cref="MeshShape"/> descriptor (e.g. <c>MeshShape.Cube()</c>) as a ref-counted <see cref="Mesh"/>.</summary>
    public Task<Mesh> CreateMeshAsync(MeshShape shape) => CreateMeshAsync(shape.Vertices, shape.Indices);

    public Task<Texture> CreateTextureAsync(uint width, uint height, byte[] pixels)
        => _factory.CreateTextureAsync(width, height, pixels)
            .ContinueWith(t => new Texture(_factory, t.Result), TaskContinuationOptions.ExecuteSynchronously);

    public Task<Texture> CreateCubemapAsync(uint faceSize, byte[] data)
        => _factory.CreateCubemapAsync(faceSize, data)
            .ContinueWith(t => new Texture(_factory, t.Result), TaskContinuationOptions.ExecuteSynchronously);
}
