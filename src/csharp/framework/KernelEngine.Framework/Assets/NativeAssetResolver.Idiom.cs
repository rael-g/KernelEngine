using System.Text;
using KernelEngine.Asset;
using KernelEngine.Asset.Native;
using KernelEngine.Common;
using KernelEngine.Common.Native;
using KernelEngine.Text;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework;

/// <summary>
/// The part of <see cref="NativeAssetResolver"/> that is not a direct image of the C
/// ABI: the convenience constructor that calls <c>ke_asset_resolver_create</c> itself
/// (no factory function lives in this domain's own headers — it belongs to the
/// framework plugin that creates this alongside the scene/world it composes), taking
/// the loader plugins and project root the factory needs. Everything that mirrors the
/// vtable 1:1 is generated in <c>Generated/NativeAssetResolver.g.cs</c>.
/// </summary>
public unsafe partial class NativeAssetResolver
{
    /// <summary>
    /// Creates a native asset resolver.
    /// </summary>
    /// <param name="imageLoader">
    /// Optional image-loader plugin. Pass <see langword="null"/> to disable
    /// <c>ResolveTexture</c>; it will throw <see cref="KernelError"/> when called.
    /// </param>
    /// <param name="fontLoader">
    /// Optional font-loader plugin. Pass <see langword="null"/> to disable
    /// <c>ResolveFont</c>; it will throw <see cref="KernelError"/> when called.
    /// </param>
    /// <param name="projectRoot">
    /// Optional project root for <c>res://</c> resolution. Pass <see langword="null"/>
    /// to restrict to absolute and CWD-relative paths.
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
            if (handle.@ref == null) throw KernelError.FromNative(err, "asset_resolver_create");
            return handle;
        }
    }

    /// <summary>
    /// Resolves an image path into freshly-decoded RGBA8 pixel data. Caller owns the
    /// result; release with <see cref="IDisposable.Dispose"/>.
    /// </summary>
    /// <exception cref="KernelError">
    /// File not found, unsupported extension, or no image loader was injected.
    /// </exception>
    public IImageData ResolveTextureData(string path)
    {
        var data = ResolveTexture(path);
        return new ResolvedTextureData((ke_asset_resolver*)((INativeAssetResolver)this).Native, data);
    }

    /// <summary>
    /// Resolves a mesh path to CPU-side vertex + index data. Caller owns the result;
    /// release with <see cref="IDisposable.Dispose"/>.
    /// Primitives: <c>res://primitives/{quad|plane|cube|sphere}</c>.
    /// </summary>
    /// <exception cref="KernelError">Path unresolvable or unsupported extension.</exception>
    public ResolvedMeshData ResolveMeshData(string path)
    {
        var data = ResolveMesh(path);
        return new ResolvedMeshData((ke_asset_resolver*)((INativeAssetResolver)this).Native, data);
    }

    /// <summary>
    /// Resolves a font file path to a freshly-baked <see cref="ResolvedFontData"/> (atlas RGBA8
    /// + glyph metrics). Caller owns the result and must dispose it.
    /// </summary>
    /// <param name="path">File path; <c>res://</c> prefix is expanded against the project root.</param>
    /// <param name="pixelSize">Desired bake size in pixels.</param>
    /// <param name="firstCodepoint">First Unicode codepoint to include (default 32 = space).</param>
    /// <param name="codepointCount">Number of contiguous codepoints to bake (default 95).</param>
    /// <param name="atlasSize">Square atlas dimension in pixels (default 512).</param>
    /// <exception cref="KernelError">
    /// File not found, unsupported format, or no font loader was injected.
    /// </exception>
    public ResolvedFontData ResolveFontData(string path, float pixelSize,
                                        uint firstCodepoint = 32, uint codepointCount = 95,
                                        uint atlasSize = 512)
    {
        var data = ResolveFont(path, pixelSize, firstCodepoint, codepointCount, atlasSize);
        return new ResolvedFontData((ke_asset_resolver*)((INativeAssetResolver)this).Native, data);
    }

    /// <summary>
    /// Parses a <c>.material</c> TOML file and returns the material spec as a value type.
    /// Texture fields inside the spec stay as path strings; feed them back through
    /// <see cref="ResolveTextureData"/> to obtain pixel data.
    /// </summary>
    /// <exception cref="KernelError">File not found or parse failure.</exception>
    public MaterialSpec ResolveMaterialSpec(string path) => MaterialSpec.FromNative(ResolveMaterial(path));
}
