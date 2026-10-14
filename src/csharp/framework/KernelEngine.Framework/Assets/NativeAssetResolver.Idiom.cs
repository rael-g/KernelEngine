using System.Text;
using KernelEngine.Asset;
using KernelEngine.Asset.Native;
using KernelEngine.Common;
using KernelEngine.Common.Native;
using KernelEngine.Text;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native asset resolver, which turns texture, mesh, material and font
/// paths into engine data. This part declares the constructor that calls the native factory
/// and the typed resolve methods; the members that mirror the vtable are generated.
/// </summary>
public unsafe partial class NativeAssetResolver
{
    /// <summary>
    /// Creates a native asset resolver.
    /// </summary>
    /// <exception cref="InvalidOperationException">The native factory fails.</exception>
    /// <param name="imageLoader">
    /// Image loader, borrowed. Without one <c>ResolveTexture</c> throws.
    /// </param>
    /// <param name="fontLoader">
    /// Font loader, borrowed. Without one <c>ResolveFont</c> throws.
    /// </param>
    /// <param name="projectRoot">
    /// Project root that <c>res://</c> paths resolve against; with <see langword="null"/> such a
    /// path resolves to the bare remainder.
    /// </param>
    public NativeAssetResolver(INativeImageLoader? imageLoader = null,
                               INativeFontLoader? fontLoader = null, string? projectRoot = null)
        : this(Create(imageLoader, fontLoader, projectRoot))
    {
    }

    private static ke_asset_resolver_handle Create(INativeImageLoader? imageLoader,
        INativeFontLoader? fontLoader, string? projectRoot)
    {
        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        ke_image_loader* imagePtr = imageLoader is not null ? imageLoader.Native : null;
        ke_font_loader*  fontPtr  = fontLoader  is not null ? fontLoader.Native  : null;
        fixed (byte* rootPtr = rootBytes)
        {
            ke_error* err = null;
            var handle = KernelEngine.Framework.Native.NativeMethods.asset_resolver_create(
                imagePtr, fontPtr, (sbyte*)rootPtr, &err);
            if (handle.@ref == null) throw NativeErrors.FromNative(err, "asset_resolver_create");
            return handle;
        }
    }

    /// <summary>
    /// Resolves an image path into decoded RGBA8 pixel data. The caller owns the result and
    /// releases it with <see cref="IDisposable.Dispose"/>.
    /// </summary>
    /// <exception cref="Exception">
    /// File not found, unsupported extension, or no image loader was given.
    /// </exception>
    public IImageData ResolveTextureData(string path)
    {
        var data = ResolveTexture(path);
        return new ResolvedTextureData((ke_asset_resolver*)((INativeAssetResolver)this).Native, data);
    }

    /// <summary>
    /// Resolves a mesh path to vertex and index data. The caller owns the result and releases it
    /// with <see cref="IDisposable.Dispose"/>. Only the paths
    /// <c>res://primitives/{quad|plane|cube|sphere}</c> resolve.
    /// </summary>
    /// <exception cref="Exception">The path is not a primitive.</exception>
    public ResolvedMeshData ResolveMeshData(string path)
    {
        var data = ResolveMesh(path);
        return new ResolvedMeshData((ke_asset_resolver*)((INativeAssetResolver)this).Native, data);
    }

    /// <summary>
    /// Resolves a font file path to a baked <see cref="ResolvedFontData"/> (atlas RGBA8 and glyph
    /// metrics). The caller owns the result and must dispose it.
    /// </summary>
    /// <param name="path">
    /// File path; a <c>res://</c> prefix is expanded against the project root.
    /// </param>
    /// <param name="pixelSize">Desired bake size in pixels.</param>
    /// <param name="firstCodepoint">First Unicode codepoint to include.</param>
    /// <param name="codepointCount">Number of contiguous codepoints to bake.</param>
    /// <param name="atlasSize">Square atlas dimension in pixels.</param>
    /// <exception cref="Exception">
    /// File not found, unsupported format, or no font loader was given.
    /// </exception>
    public ResolvedFontData ResolveFontData(string path, float pixelSize,
                                        uint firstCodepoint = 32, uint codepointCount = 95,
                                        uint atlasSize = 512)
    {
        var data = ResolveFont(path, pixelSize, firstCodepoint, codepointCount, atlasSize);
        return new ResolvedFontData((ke_asset_resolver*)((INativeAssetResolver)this).Native, data);
    }

    /// <summary>
    /// Parses a <c>.material</c> TOML file and returns the spec. The texture fields stay as path
    /// strings.
    /// </summary>
    /// <exception cref="Exception">File not found or parse failure.</exception>
    public MaterialSpec ResolveMaterialSpec(string path) => MaterialSpec.FromNative(ResolveMaterial(path));
}
