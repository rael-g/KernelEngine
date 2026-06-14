using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Framework.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_asset_resolver</c> vtable. Resolves
/// <c>res://</c>-prefixed (and absolute) asset paths to CPU-side data using
/// injected loader plugins. Callers own each resolved result and must dispose it.
/// </summary>
/// <remarks>
/// Path schemes accepted by every resolve method:
/// <list type="bullet">
///   <item><description><c>res://x/y.png</c> — stripped and joined onto the <paramref name="projectRoot"/> passed at construction.</description></item>
///   <item><description><c>/abs/path.png</c> — used as-is.</description></item>
///   <item><description><c>rel/path.png</c> — resolved relative to the process CWD.</description></item>
/// </list>
/// </remarks>
public sealed unsafe class NativeAssetResolver : IDisposable
{
    private ke_asset_resolver* _native;

    /// <summary>
    /// Creates a native asset resolver.
    /// </summary>
    /// <param name="allocator">Allocator used for internal storage.</param>
    /// <param name="imageLoader">
    /// Optional image-loader plugin. Pass <see langword="null"/> to disable
    /// <see cref="ResolveTexture"/>; it will throw <see cref="KernelException"/> when called.
    /// </param>
    /// <param name="fontLoader">
    /// Optional font-loader plugin. Pass <see langword="null"/> to disable
    /// <see cref="ResolveFont"/>; it will throw <see cref="KernelException"/> when called.
    /// </param>
    /// <param name="projectRoot">
    /// Optional project root for <c>res://</c> resolution. Pass <see langword="null"/>
    /// to restrict to absolute and CWD-relative paths.
    /// </param>
    public NativeAssetResolver(Allocator allocator, INativeImageLoader? imageLoader = null,
                               INativeFontLoader? fontLoader = null, string? projectRoot = null)
    {
        ArgumentNullException.ThrowIfNull(allocator);

        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        ke_asset_resolver* p;
        ke_image_loader* imagePtr = imageLoader is not null ? imageLoader.Native : null;
        ke_font_loader*  fontPtr  = fontLoader  is not null ? fontLoader.Native  : null;
        fixed (byte* rootPtr = rootBytes)
        {
            KernelException.ThrowIfFailed(
                KernelEngine.Framework.Native.NativeMethods.asset_resolver_create(
                    allocator.Native,
                    imagePtr,
                    fontPtr,
                    (sbyte*)rootPtr,
                    &p).ToManaged());
        }
        _native = p;
    }

    /// <summary>
    /// Resolves an image path to freshly-decoded RGBA8 pixel data. Caller disposes the result.
    /// </summary>
    /// <exception cref="KernelException">
    /// File not found, unsupported extension, or no image loader was injected.
    /// </exception>
    public IImageData ResolveTexture(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(path);

        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_texture_data* data;
        ke_result result;
        fixed (byte* p = bytes)
            result = _native->resolve_texture(_native, (sbyte*)p, &data);
        KernelException.ThrowIfFailed(result.ToManaged());
        return new ResolvedTextureData(_native, data);
    }

    /// <summary>
    /// Resolves a mesh path to CPU-side vertex + index data. Caller disposes the result.
    /// Primitives: <c>res://primitives/{quad|plane|cube|sphere}</c>.
    /// </summary>
    /// <exception cref="KernelException">Path unresolvable or unsupported extension.</exception>
    public ResolvedMeshData ResolveMesh(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(path);

        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_mesh_shape_data meshData = default;
        ke_result result;
        fixed (byte* p = bytes)
            result = _native->resolve_mesh(_native, (sbyte*)p, &meshData);
        KernelException.ThrowIfFailed(result.ToManaged());
        return new ResolvedMeshData(_native, meshData);
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
    /// <exception cref="KernelException">
    /// File not found, unsupported format, or no font loader was injected.
    /// </exception>
    public ResolvedFontData ResolveFont(string path, float pixelSize,
                                        uint firstCodepoint = 32, uint codepointCount = 95,
                                        uint atlasSize = 512)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(path);

        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_font_data* data;
        ke_result result;
        fixed (byte* p = bytes)
            result = _native->resolve_font(_native, (sbyte*)p, pixelSize,
                                           firstCodepoint, codepointCount, atlasSize, &data);
        KernelException.ThrowIfFailed(result.ToManaged());
        return new ResolvedFontData(_native, data);
    }

    /// <summary>
    /// Parses a <c>.material</c> TOML file and returns the material spec as a value type.
    /// Texture path fields inside the spec stay as strings; feed them back through
    /// <see cref="ResolveTexture"/> to obtain pixel data.
    /// </summary>
    /// <exception cref="KernelException">File not found or parse failure.</exception>
    public MaterialSpec ResolveMaterial(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentException.ThrowIfNullOrEmpty(path);

        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_material_spec spec = default;
        ke_result result;
        fixed (byte* p = bytes)
            result = _native->resolve_material(_native, (sbyte*)p, &spec);
        KernelException.ThrowIfFailed(result.ToManaged());
        return MaterialSpec.FromNative(spec);
    }

    /// <inheritdoc cref="IDisposable.Dispose"/>
    public void Dispose()
    {
        if (_native is not null) { _native->destroy(_native); _native = null; }
    }
}

/// <summary>
/// Owns a <see cref="ke_texture_data"/> returned by <see cref="NativeAssetResolver.ResolveTexture"/>.
/// Freed via the resolver's <c>free_texture</c> slot on dispose.
/// </summary>
public sealed unsafe class ResolvedTextureData : IImageData
{
    private ke_asset_resolver* _resolver;
    private ke_texture_data* _data;

    internal ResolvedTextureData(ke_asset_resolver* resolver, ke_texture_data* data)
    {
        _resolver = resolver;
        _data = data;
        Path = new string((sbyte*)&data->path);
    }

    /// <inheritdoc/>
    public string Path { get; }

    /// <inheritdoc/>
    public uint Width => _data != null ? _data->width : 0u;

    /// <inheritdoc/>
    public uint Height => _data != null ? _data->height : 0u;

    /// <inheritdoc/>
    public ReadOnlySpan<byte> Pixels
    {
        get
        {
            if (_data == null || _data->pixels == null) return ReadOnlySpan<byte>.Empty;
            return new ReadOnlySpan<byte>(_data->pixels, checked((int)(_data->width * _data->height * 4u)));
        }
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_data == null) return;
        _resolver->free_texture(_resolver, _data);
        _data = null;
    }
}

/// <summary>
/// Owns a <see cref="ke_mesh_shape_data"/> returned by <see cref="NativeAssetResolver.ResolveMesh"/>.
/// Freed via the resolver's <c>free_mesh</c> slot on dispose.
/// </summary>
public sealed unsafe class ResolvedMeshData : IDisposable
{
    private ke_asset_resolver* _resolver;
    private ke_mesh_shape_data _data;
    private bool _disposed;

    internal ResolvedMeshData(ke_asset_resolver* resolver, ke_mesh_shape_data data)
    {
        _resolver = resolver;
        _data = data;
    }

    /// <summary>Vertex data as a span. Valid only while this instance is not disposed.</summary>
    public ReadOnlySpan<ke_vertex> Vertices
    {
        get
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            return new ReadOnlySpan<ke_vertex>(_data.vertices, checked((int)_data.vertex_count));
        }
    }

    /// <summary>Index data as a span. Valid only while this instance is not disposed.</summary>
    public ReadOnlySpan<ushort> Indices
    {
        get
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            return new ReadOnlySpan<ushort>(_data.indices, checked((int)_data.index_count));
        }
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        fixed (ke_mesh_shape_data* p = &_data)
            _resolver->free_mesh(_resolver, p);
    }
}

/// <summary>
/// Owns a <see cref="ke_font_data"/> returned by <see cref="NativeAssetResolver.ResolveFont"/>.
/// Freed via the resolver's <c>free_font</c> slot on dispose.
/// </summary>
public sealed unsafe class ResolvedFontData : IDisposable
{
    private ke_asset_resolver* _resolver;
    private ke_font_data* _data;

    internal ResolvedFontData(ke_asset_resolver* resolver, ke_font_data* data)
    {
        _resolver = resolver;
        _data     = data;
    }

    /// <summary>Atlas RGBA8 pixel data. Valid only while this instance is not disposed.</summary>
    public ReadOnlySpan<byte> AtlasRgba
    {
        get
        {
            ObjectDisposedException.ThrowIf(_data == null, this);
            return new ReadOnlySpan<byte>(_data->atlas_rgba,
                checked((int)(_data->atlas_width * _data->atlas_height * 4u)));
        }
    }

    /// <summary>Atlas width in pixels.</summary>
    public uint AtlasWidth  => _data != null ? _data->atlas_width  : 0u;

    /// <summary>Atlas height in pixels.</summary>
    public uint AtlasHeight => _data != null ? _data->atlas_height : 0u;

    /// <summary>Recommended line spacing in pixels at the baked size.</summary>
    public float LineHeight => _data != null ? _data->line_height : 0f;

    /// <summary>Pixels above baseline to the top of the tallest baked glyph.</summary>
    public float Ascent => _data != null ? _data->ascent : 0f;

    /// <summary>Per-glyph layout + atlas-UV metrics. Valid only while this instance is not disposed.</summary>
    public ReadOnlySpan<ke_glyph_metrics> Glyphs
    {
        get
        {
            ObjectDisposedException.ThrowIf(_data == null, this);
            return new ReadOnlySpan<ke_glyph_metrics>(_data->glyphs,
                checked((int)_data->glyph_count));
        }
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_data == null) return;
        _resolver->free_font(_resolver, _data);
        _data = null;
    }
}

/// <summary>
/// Managed projection of <see cref="ke_material_spec"/>. Returned by
/// <see cref="NativeAssetResolver.ResolveMaterial"/>; fully value-typed, no native lifetime.
/// </summary>
public sealed record MaterialSpec
{
    /// <summary>RGBA base color, components in [0, 1].</summary>
    public required float[] BaseColor { get; init; }

    /// <summary>Metallic factor, [0, 1].</summary>
    public required float Metallic { get; init; }

    /// <summary>Roughness factor, [0, 1].</summary>
    public required float Roughness { get; init; }

    /// <summary>Optional albedo texture path (empty string if not set).</summary>
    public required string AlbedoPath { get; init; }

    /// <summary>Optional normal-map texture path (empty string if not set).</summary>
    public required string NormalPath { get; init; }

    internal static unsafe MaterialSpec FromNative(ke_material_spec spec)
    {
        return new MaterialSpec
        {
            BaseColor   = [spec.base_color[0], spec.base_color[1], spec.base_color[2], spec.base_color[3]],
            Metallic    = spec.metallic,
            Roughness   = spec.roughness,
            AlbedoPath  = new string((sbyte*)&spec.albedo_path),
            NormalPath  = new string((sbyte*)&spec.normal_path),
        };
    }
}
