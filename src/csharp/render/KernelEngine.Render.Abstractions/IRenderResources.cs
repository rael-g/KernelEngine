using System.Numerics;

namespace KernelEngine.Render;

/// <summary>
/// Creates GPU resources owned by the active render backend — meshes, textures,
/// and materials. Scene code (primitives, asset loaders, nodes) depends on this
/// abstraction rather than a concrete backend. The v2 render module implements
/// it over the render core. Call from the render worker — GPU resource creation
/// has thread affinity.
/// </summary>
public interface IRenderResources
{
    /// <summary>
    /// Uploads interleaved position+normal+uv vertices and 16-bit indices.
    /// Throws on failure — a bad upload is never swallowed.
    /// </summary>
    MeshHandle UploadMesh(ReadOnlySpan<MeshVertex> vertices, ReadOnlySpan<ushort> indices);

    /// <summary>
    /// Uploads an RGBA8 texture (<paramref name="rgba"/> is width*height*4 bytes,
    /// row-major). Throws on failure.
    /// </summary>
    TextureHandle UploadTexture(uint width, uint height, ReadOnlySpan<byte> rgba);

    /// <summary>
    /// Creates a material: a glTF-style base-color factor multiplied by an albedo
    /// texture. A default (<c>TextureHandle.White</c>) albedo yields a flat color.
    /// </summary>
    MaterialHandle CreateMaterial(Vector4 baseColor, TextureHandle albedo = default);
}
