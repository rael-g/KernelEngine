using System.Numerics;
using KernelEngine.Render;
using KernelEngine.Logger;
using KernelEngine.Common;

namespace KernelEngine.Framework.Legacy;

public static class ResourceFactoryExtensions
{
    public static Task<MeshHandle> CreateMeshAsync(this IResourceFactory factory, Vertex[] vertices, ushort[] indices)
    {
        if (factory is IAsyncResourceFactory async) return async.CreateMeshAsync(vertices, indices);
        return Task.FromResult(factory.CreateMesh(vertices, indices));
    }

    public static Task<TextureHandle> CreateTextureAsync(this IResourceFactory factory, uint width, uint height, byte[] pixels)
    {
        if (factory is IAsyncResourceFactory async) return async.CreateTextureAsync(width, height, pixels);
        return Task.FromResult(factory.CreateTexture(width, height, pixels));
    }

    public static Task<TextureHandle> CreateCubemapAsync(this IResourceFactory factory, uint faceSize, byte[] data)
    {
        if (factory is IAsyncResourceFactory async) return async.CreateCubemapAsync(faceSize, data);
        return Task.FromResult(factory.CreateCubemap(faceSize, data));
    }

    public static Task<MaterialHandle> CreateMaterialAsync(this IResourceFactory factory,
        Vector4 color,
        TextureHandle textureHandle = default,
        float metallic = 0f,
        float roughness = 0.5f,
        TextureHandle normalMapHandle = default)
    {
        if (factory is IAsyncResourceFactory async)
            return async.CreateMaterialAsync(color, textureHandle, metallic, roughness, normalMapHandle);
        return Task.FromResult(factory.CreateMaterial(color, textureHandle, metallic, roughness, normalMapHandle));
    }
}
