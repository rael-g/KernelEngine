using System.Numerics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Mediates creation and destruction of GPU resources.
/// May block the simulation thread if the command queue is full.
/// </summary>
public interface IResourceFactory
{
    MeshHandle CreateMesh(ke_vertex[] vertices, ushort[] indices);
    void DestroyMesh(MeshHandle handle);

    TextureHandle CreateTexture(uint width, uint height, byte[] pixels);
    TextureHandle CreateCubemap(uint faceSize, byte[] data);
    void DestroyTexture(TextureHandle handle);

    MaterialHandle CreateMaterial(Vector4 color, TextureHandle albedo = default, float metallic = 0.0f, float roughness = 0.5f, TextureHandle normalMap = default);
    void DestroyMaterial(MaterialHandle handle);

    ShadowMapHandle CreateShadowMap(uint width, uint height);
    void DestroyShadowMap(ShadowMapHandle handle);
}
