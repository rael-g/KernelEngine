using System.Numerics;

namespace KernelEngine.Render;

/// <summary>
/// Creates and owns the GPU resources of the active render backend: meshes, textures, materials
/// and fonts. Every method must be called from the thread that owns GPU resource creation.
/// </summary>
public interface IRenderResources
{
    /// <summary>
    /// Uploads interleaved vertices and 16-bit indices. <paramref name="key"/> is required: a key
    /// already resident returns the existing handle with its reference count incremented and
    /// uploads nothing. The result always carries one reference, balanced with
    /// <see cref="ReleaseMesh"/>. Throws when the upload fails.
    /// </summary>
    MeshHandle UploadMesh(string key, ReadOnlySpan<MeshVertex> vertices, ReadOnlySpan<ushort> indices);

    /// <summary>
    /// Uploads an RGBA8 texture, <paramref name="rgba"/> being width by height by four bytes in row
    /// order. <paramref name="key"/> follows the rule of <see cref="UploadMesh"/>. Throws when the
    /// upload fails.
    /// </summary>
    TextureHandle UploadTexture(string key, uint width, uint height, ReadOnlySpan<byte> rgba);

    /// <summary>
    /// Uploads an RGBA8 cubemap of six square faces of <paramref name="faceSize"/> pixels,
    /// concatenated in the order +X, -X, +Y, -Y, +Z, -Z. <paramref name="key"/> follows the rule of
    /// <see cref="UploadMesh"/> and shares the texture cache. Throws when the upload fails.
    /// </summary>
    TextureHandle UploadCubemap(string key, uint faceSize, ReadOnlySpan<byte> faces);

    /// <summary>
    /// Creates a metallic-roughness material: <paramref name="baseColor"/> multiplied by the
    /// <paramref name="albedo"/> texture, where null means the white texture, with a tangent-space
    /// <paramref name="normalMap"/>, where null means no perturbation.
    /// <paramref name="alphaMode"/> selects the pass that shades the material, and
    /// <paramref name="alphaCutoff"/> applies only to <see cref="AlphaMode.Mask"/>.
    /// <paramref name="ior"/> and <paramref name="distortionStrength"/> apply only to
    /// <see cref="AlphaMode.Blend"/>; the strength is a lateral shift of the sampled background in
    /// normalized screen space. <paramref name="shader"/> is the file stem of an authored material
    /// shader, and null selects the engine default. <paramref name="key"/> follows the rule of
    /// <see cref="UploadMesh"/>.
    /// </summary>
    MaterialHandle CreateMaterial(string key, Vector4 baseColor, float metallic = 0f, float roughness = 0.5f,
                                  TextureHandle? albedo = null, TextureHandle? normalMap = null,
                                  AlphaMode alphaMode = AlphaMode.Opaque, float alphaCutoff = 0.5f,
                                  float ior = 1.5f, float distortionStrength = 0.05f,
                                  string? shader = null);

    /// <summary>The built-in white texture, the neutral albedo.</summary>
    TextureHandle WhiteTexture { get; }

    /// <summary>Adds one reference to a resource; balance with the matching release.</summary>
    void RetainMesh(MeshHandle h);
    /// <summary>Drops one reference; at zero the GPU objects are freed and the handle goes stale.</summary>
    void ReleaseMesh(MeshHandle h);
    /// <inheritdoc cref="RetainMesh"/>
    void RetainTexture(TextureHandle h);
    /// <inheritdoc cref="ReleaseMesh"/>
    void ReleaseTexture(TextureHandle h);
    /// <inheritdoc cref="RetainMesh"/>
    void RetainMaterial(MaterialHandle h);
    /// <inheritdoc cref="ReleaseMesh"/>
    void ReleaseMaterial(MaterialHandle h);

    /// <summary>
    /// Path-keyed probe: on a cache hit returns true, sets <paramref name="handle"/>,
    /// and retains it on the caller's behalf (as a keyed upload would). Lets a loader
    /// skip decoding a file whose upload is already resident.
    /// </summary>
    bool TryGetMesh(string key, out MeshHandle handle);
    /// <inheritdoc cref="TryGetMesh"/>
    bool TryGetTexture(string key, out TextureHandle handle);
    /// <inheritdoc cref="TryGetMesh"/>
    bool TryGetMaterial(string key, out MaterialHandle handle);

    /// <summary>
    /// Registers a font's glyph table with the UI pass, deduplicated by <paramref name="key"/>
    /// like <see cref="UploadTexture"/>. Throws when no font slot is free or the registration fails.
    /// </summary>
    FontHandle LoadFont(string key, TextureHandle atlas, ReadOnlySpan<FontGlyph> glyphs,
                        float lineHeight, float ascent);
}
