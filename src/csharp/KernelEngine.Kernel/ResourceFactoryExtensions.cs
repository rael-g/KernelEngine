using System.Numerics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

public static class ResourceFactoryExtensions
{
    public static Task<MeshHandle> CreateMeshAsync(this IResourceFactory factory, ke_vertex[] vertices, ushort[] indices)
    {
        if (factory is ResourceCommandFactory rcf)
        {
            var tcs = new TaskCompletionSource<uint>();
            rcf.Queue.Enqueue(new ResourceCommand
            {
                Type = ResourceCommandType.CreateMesh,
                Data = (vertices, indices),
                CompletionSource = tcs
            });
            return tcs.Task.ContinueWith(t => new MeshHandle(t.Result), TaskContinuationOptions.ExecuteSynchronously);
        }
        return Task.FromResult(factory.CreateMesh(vertices, indices));
    }

    public static Task<TextureHandle> CreateTextureAsync(this IResourceFactory factory, uint width, uint height, byte[] pixels)
    {
        if (factory is ResourceCommandFactory rcf)
        {
            var tcs = new TaskCompletionSource<uint>();
            rcf.Queue.Enqueue(new ResourceCommand
            {
                Type = ResourceCommandType.CreateTexture,
                Data = (width, height, pixels),
                CompletionSource = tcs
            });
            return tcs.Task.ContinueWith(t => new TextureHandle(t.Result), TaskContinuationOptions.ExecuteSynchronously);
        }
        return Task.FromResult(factory.CreateTexture(width, height, pixels));
    }

    public static Task<MaterialHandle> CreateMaterialAsync(this IResourceFactory factory, 
        Vector4 color, 
        TextureHandle textureHandle = default, 
        float metallic = 0f, 
        float roughness = 0.5f, 
        TextureHandle normalMapHandle = default)
    {
        if (factory is ResourceCommandFactory rcf)
        {
            var tcs = new TaskCompletionSource<uint>();
            rcf.Queue.Enqueue(new ResourceCommand
            {
                Type = ResourceCommandType.CreateMaterial,
                Data = (color, textureHandle, metallic, roughness, normalMapHandle),
                CompletionSource = tcs
            });
            return tcs.Task.ContinueWith(t => new MaterialHandle(t.Result), TaskContinuationOptions.ExecuteSynchronously);
        }
        return Task.FromResult(factory.CreateMaterial(color, textureHandle, metallic, roughness, normalMapHandle));
    }
}
