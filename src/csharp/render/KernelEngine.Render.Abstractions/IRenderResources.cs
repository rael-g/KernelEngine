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
    /// Throws on failure — a bad upload is never swallowed. <paramref name="key"/>
    /// is required — every upload is dedup-cached, there is no uncached path: a
    /// key already resident returns the existing handle with its refcount
    /// incremented, uploading nothing. The result always carries one reference;
    /// balance it with <see cref="ReleaseMesh"/>. Content loaded from a file
    /// should key by its path (see <c>NativeAssetResolver</c>'s cached-load
    /// methods, which do this for you); procedural content keys by its own
    /// generation parameters (e.g. <c>"primitive:cube"</c>) so identical calls
    /// dedup the same way file-backed content does.
    /// </summary>
    MeshHandle UploadMesh(string key, ReadOnlySpan<MeshVertex> vertices, ReadOnlySpan<ushort> indices);

    /// <summary>
    /// Uploads an RGBA8 texture (<paramref name="rgba"/> is width*height*4 bytes,
    /// row-major). Throws on failure. <paramref name="key"/> is required, same
    /// rule as <see cref="UploadMesh"/>.
    /// </summary>
    TextureHandle UploadTexture(string key, uint width, uint height, ReadOnlySpan<byte> rgba);

    /// <summary>
    /// Uploads an RGBA8 cubemap: 6 faces of <paramref name="faceSize"/>² in the
    /// order +X,-X,+Y,-Y,+Z,-Z (concatenated). Used as a skybox background and the
    /// image-based-lighting environment. Throws on failure. <paramref name="key"/>
    /// is required, same rule as <see cref="UploadMesh"/> (cubemaps share the
    /// texture cache).
    /// </summary>
    TextureHandle UploadCubemap(string key, uint faceSize, ReadOnlySpan<byte> faces);

    /// <summary>
    /// Creates a glTF metallic-roughness material: a base-color factor multiplied
    /// by an albedo texture (<c>null</c> = the built-in white = flat color), plus
    /// metallic (0 = dielectric, 1 = metal), roughness (0 = mirror, 1 = matte), and
    /// an optional tangent-space normal map (<c>null</c> = flat / no perturbation).
    /// <paramref name="alphaMode"/> selects which pass shades the material
    /// (gbuffer for <see cref="AlphaMode.Opaque"/>/<see cref="AlphaMode.Mask"/>,
    /// transparent forward for <see cref="AlphaMode.Blend"/>); <paramref name="alphaCutoff"/>
    /// only applies to <see cref="AlphaMode.Mask"/>. <paramref name="ior"/> (index of
    /// refraction) and <paramref name="distortionStrength"/> only apply to
    /// <see cref="AlphaMode.Blend"/> (ior: 1.0 = no bend, 1.33 = water, 1.5 = glass;
    /// distortionStrength: lateral shift of the sampled background, in normalized
    /// screen space). <paramref name="shaderVariant"/> selects which build-time-
    /// compiled fragment shader the drawing pass uses (§6 Mechanism 1 proof —
    /// distinct variants resolve to distinct PSOs, not just distinct bind-group
    /// data); 0 = the pass's default/flat variant. <paramref name="key"/> is
    /// required, same rule as <see cref="UploadMesh"/> — a caller with no file
    /// path (an inline scene-authored material, say) keys by its own parameters
    /// so two nodes authored identically share one material.
    /// </summary>
    MaterialHandle CreateMaterial(string key, Vector4 baseColor, float metallic = 0f, float roughness = 0.5f,
                                  TextureHandle? albedo = null, TextureHandle? normalMap = null,
                                  AlphaMode alphaMode = AlphaMode.Opaque, float alphaCutoff = 0.5f,
                                  float ior = 1.5f, float distortionStrength = 0.05f,
                                  uint shaderVariant = 0);

    /// <summary>The built-in 1×1 white texture (neutral albedo).</summary>
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
