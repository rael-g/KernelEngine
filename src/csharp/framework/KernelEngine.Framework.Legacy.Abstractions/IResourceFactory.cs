using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Mediates creation and destruction of GPU resources from the simulation thread.
/// Calls block the simulation thread until the render thread processes them.
/// </summary>
public interface IResourceFactory
{
    MeshHandle CreateMesh(Vertex[] vertices, ushort[] indices);
    void DestroyMesh(MeshHandle handle);

    TextureHandle CreateTexture(uint width, uint height, byte[] pixels);
    TextureHandle CreateCubemap(uint faceSize, byte[] data);
    void DestroyTexture(TextureHandle handle);

    MaterialHandle CreateMaterial(Vector4 color, TextureHandle albedo = default, float metallic = 0.0f, float roughness = 0.5f, TextureHandle normalMap = default);
    void DestroyMaterial(MaterialHandle handle);

    ShadowMapHandle CreateShadowMap(uint width, uint height);
    void DestroyShadowMap(ShadowMapHandle handle);
}
