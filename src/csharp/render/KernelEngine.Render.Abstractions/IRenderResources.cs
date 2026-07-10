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
    /// <paramref name="alphaMode"/> selects which pass shades the material
    /// (gbuffer for <see cref="AlphaMode.Opaque"/>/<see cref="AlphaMode.Mask"/>,
    /// transparent forward for <see cref="AlphaMode.Blend"/>); <paramref name="alphaCutoff"/>
    /// only applies to <see cref="AlphaMode.Mask"/>. <paramref name="ior"/> (index of
    /// refraction) and <paramref name="distortionStrength"/> only apply to
    /// <see cref="AlphaMode.Blend"/> (ior: 1.0 = no bend, 1.33 = water, 1.5 = glass;
    /// distortionStrength: lateral shift of the sampled background, in normalized
    /// screen space).
    /// </summary>
    MaterialHandle CreateMaterial(Vector4 baseColor, float metallic = 0f, float roughness = 0.5f,
                                  TextureHandle albedo = default, TextureHandle? normalMap = null,
                                  AlphaMode alphaMode = AlphaMode.Opaque, float alphaCutoff = 0.5f,
                                  float ior = 1.5f, float distortionStrength = 0.05f);

    /// <summary>
    /// Queues a screen-space UI quad for this frame, drawn after tonemap so it
    /// composites over the rendered scene. <paramref name="dstX"/>/<paramref name="dstY"/>
    /// are pixel coordinates (top-left origin); <paramref name="texture"/> defaults to
    /// a built-in white pixel, so a flat-color quad just needs a color and no texture.
    /// UV selects a sub-region of the texture (glyph atlas lookup for text). Color is
    /// premultiplied alpha. Call from a render-phase system, before the frame's UI
    /// pass runs.
    /// </summary>
    void UiQuad(TextureHandle texture, float dstX, float dstY, float dstW, float dstH,
               float u0, float v0, float u1, float v1, Vector4 premultipliedColor);
}
