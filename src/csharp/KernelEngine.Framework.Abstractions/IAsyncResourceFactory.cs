using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Optional async surface that a queueing <see cref="IResourceFactory"/> implementation may
/// expose. Lets <see cref="ResourceFactoryExtensions"/> route <c>CreateXxxAsync</c> calls
/// straight through the queue (non-blocking on the caller thread) when the underlying factory
/// supports it, instead of falling back to a sync wrap.
/// </summary>
public interface IAsyncResourceFactory
{
    Task<MeshHandle>     CreateMeshAsync(Vertex[] vertices, ushort[] indices);
    Task<TextureHandle>  CreateTextureAsync(uint width, uint height, byte[] pixels);
    Task<TextureHandle>  CreateCubemapAsync(uint faceSize, byte[] data);
    Task<MaterialHandle> CreateMaterialAsync(System.Numerics.Vector4 color,
                                              TextureHandle albedo,
                                              float metallic,
                                              float roughness,
                                              TextureHandle normalMap);
}
