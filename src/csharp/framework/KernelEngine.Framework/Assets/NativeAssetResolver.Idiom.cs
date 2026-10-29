using System.Text;

using KernelEngine.Asset;
using KernelEngine.Asset.Native;
using KernelEngine.Common;
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
    /// Creates a native asset resolver that reads every file through <paramref name="io"/>.
    /// </summary>
    /// <exception cref="InvalidOperationException">The native factory fails.</exception>
    /// <param name="io">The io files are read through, borrowed; must outlive the resolver.</param>
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
    public NativeAssetResolver(KernelEngine.Io.INativeIo io, INativeImageLoader? imageLoader = null,
                               INativeFontLoader? fontLoader = null, string? projectRoot = null)
        : this(Create(io, imageLoader, fontLoader, projectRoot))
    {
    }

    private static ke_asset_resolver_handle Create(KernelEngine.Io.INativeIo io, INativeImageLoader? imageLoader,
        INativeFontLoader? fontLoader, string? projectRoot)
    {
        ArgumentNullException.ThrowIfNull(io);
        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        ke_image_loader* imagePtr = imageLoader is not null ? imageLoader.Native : null;
        ke_font_loader* fontPtr = fontLoader is not null ? fontLoader.Native : null;
        fixed (byte* rootPtr = rootBytes)
        {
            ke_asset_resolver_handle handle;
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.asset_resolver_create(
                imagePtr, fontPtr, (sbyte*)rootPtr, io.Native, &handle), "ke_asset_resolver_create");
            return handle;
        }
    }

    /// <summary>
    /// Parses a <c>.material</c> TOML file and returns the spec. The texture fields stay as path
    /// strings.
    /// </summary>
    /// <exception cref="Exception">File not found or parse failure.</exception>
    public MaterialSpec ResolveMaterialSpec(string path) => MaterialSpec.FromNative(ResolveMaterial(path));
}
