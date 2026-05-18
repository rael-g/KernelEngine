using System.Numerics;

namespace KernelEngine.Kernel;

public static class ResourceFactoryExtensions
{
    public static Task<MeshHandle> CreateMeshAsync(this IResourceFactory factory, Vertex[] vertices, ushort[] indices)
    {
        if (factory is ResourceCommandFactory rcf)
            return rcf.EnqueueAsync(ResourceCommandType.CreateMesh, (vertices, indices), val => new MeshHandle(val));
        return Task.FromResult(factory.CreateMesh(vertices, indices));
    }

    public static Task<TextureHandle> CreateTextureAsync(this IResourceFactory factory, uint width, uint height, byte[] pixels)
    {
        if (factory is ResourceCommandFactory rcf)
            return rcf.EnqueueAsync(ResourceCommandType.CreateTexture, (width, height, pixels), val => new TextureHandle(val));
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
            return rcf.EnqueueAsync(ResourceCommandType.CreateMaterial,
                (color, textureHandle, metallic, roughness, normalMapHandle),
                val => new MaterialHandle(val));
        return Task.FromResult(factory.CreateMaterial(color, textureHandle, metallic, roughness, normalMapHandle));
    }
}
