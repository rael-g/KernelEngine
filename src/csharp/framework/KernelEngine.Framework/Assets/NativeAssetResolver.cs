using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Asset;
using KernelEngine.Text;
using KernelEngine.Common.Native;
using KernelEngine.Asset.Native;
using KernelEngine.Render.Native;
using KernelEngine.Text.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Common;

namespace KernelEngine.Framework;

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
