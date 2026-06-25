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
    /// Uploads an RGBA8 cubemap: 6 faces of <paramref name="faceSize"/>² in the
    /// order +X,-X,+Y,-Y,+Z,-Z (concatenated). Used as a skybox background and the
    /// image-based-lighting environment. Throws on failure.
    /// </summary>
    TextureHandle UploadCubemap(uint faceSize, ReadOnlySpan<byte> faces);

    /// <summary>
    /// Creates a glTF metallic-roughness material: a base-color factor multiplied
    /// by an albedo texture (default <c>TextureHandle.White</c> = flat color), plus
    /// metallic (0 = dielectric, 1 = metal), roughness (0 = mirror, 1 = matte), and
    /// an optional tangent-space normal map (<c>null</c> = flat / no perturbation).
    /// </summary>
    MaterialHandle CreateMaterial(Vector4 baseColor, float metallic = 0f, float roughness = 0.5f,
                                  TextureHandle albedo = default, TextureHandle? normalMap = null);
}
