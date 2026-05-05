using System.Numerics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

public sealed class ResourceCommandFactory : IResourceFactory
{
    private readonly ResourceCommandQueue _queue;

    public ResourceCommandFactory(ResourceCommandQueue queue)
    {
        _queue = queue;
    }

    private T SendCommand<T>(ResourceCommandType type, object? data, Func<uint, T> resultMapper)
    {
        var tcs = new TaskCompletionSource<uint>();
        _queue.Enqueue(new ResourceCommand { Type = type, Data = data, CompletionSource = tcs });
        // Blocking wait since the factory API is synchronous (as requested by the plan's context of decoupling)
        // Note: In a production engine, this might be async, but here we block ke.sim until ke.render processes it.
        uint result = tcs.Task.GetAwaiter().GetResult();
        return resultMapper(result);
    }

    public MeshHandle CreateMesh(ke_vertex[] vertices, ushort[] indices) =>
        SendCommand(ResourceCommandType.CreateMesh, (vertices, indices), val => new MeshHandle(val));

    public void DestroyMesh(MeshHandle handle) =>
        SendCommand(ResourceCommandType.DestroyMesh, handle.Value, _ => 0);

    public TextureHandle CreateTexture(uint width, uint height, byte[] pixels) =>
        SendCommand(ResourceCommandType.CreateTexture, (width, height, pixels), val => new TextureHandle(val));

    public TextureHandle CreateCubemap(uint faceSize, byte[] data) =>
        SendCommand(ResourceCommandType.CreateCubemap, (faceSize, data), val => new TextureHandle(val));

    public void DestroyTexture(TextureHandle handle) =>
        SendCommand(ResourceCommandType.DestroyTexture, handle.Value, _ => 0);

    public MaterialHandle CreateMaterial(Vector4 color, TextureHandle albedo = default, float metallic = 0, float roughness = 0.5F, TextureHandle normalMap = default) =>
        SendCommand(ResourceCommandType.CreateMaterial, (color, albedo, metallic, roughness, normalMap), val => new MaterialHandle(val));

    public void DestroyMaterial(MaterialHandle handle) =>
        SendCommand(ResourceCommandType.DestroyMaterial, handle.Value, _ => 0);

    public ShadowMapHandle CreateShadowMap(uint width, uint height) =>
        SendCommand(ResourceCommandType.CreateShadowMap, (width, height), val => new ShadowMapHandle(val));

    public void DestroyShadowMap(ShadowMapHandle handle) =>
        SendCommand(ResourceCommandType.DestroyShadowMap, handle.Value, _ => 0);
}
