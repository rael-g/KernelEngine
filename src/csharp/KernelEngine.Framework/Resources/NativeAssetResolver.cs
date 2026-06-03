using System.Numerics;
using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_asset_resolver</c>. Translates res:// (and
/// absolute) paths into typed CPU-side asset data via the injected image loader
/// and the framework's built-in mesh/material parsers. GPU upload is the caller's
/// responsibility (today via <see cref="ResourceManager"/>; future: a C-side
/// command queue).
/// </summary>
internal sealed unsafe class NativeAssetResolver : IDisposable
{
    private ke_asset_resolver* _native;

    public NativeAssetResolver(Allocator allocator,
                                KernelEngine.Kernel.Native.ke_image_loader* imageLoader,
                                string? projectRoot)
    {
        ke_asset_resolver* p;
        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        // ke_image_loader is identical across the two ClangSharp-generated namespaces; cross-cast.
        var imgFw = (KernelEngine.Framework.Native.ke_image_loader*)imageLoader;
        fixed (byte* rootPtr = rootBytes)
        {
            KernelException.ThrowIfFailed(
                KernelEngine.Framework.Native.NativeMethods.asset_resolver_create(
                    allocator.Native, imgFw, (sbyte*)rootPtr, &p).ToManaged());
        }
        _native = p;
    }

    /// <summary>
    /// Resolves an image path (res:// or absolute) to a managed pixel buffer. Returns null
    /// when the resolver returns NOT_FOUND (no image loader, missing file, unsupported ext).
    /// </summary>
    public TextureBuffer? ResolveTexture(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        KernelEngine.Framework.Native.ke_texture_data* data;
        ke_result r;
        fixed (byte* p = bytes)
        {
            r = _native->resolve_texture(_native, (sbyte*)p, &data);
        }
        if (r == ke_result.KE_ERROR_NOT_FOUND) return null;
        KernelException.ThrowIfFailed(r.ToManaged());
        if (data == null) return null;

        try
        {
            uint w = data->width;
            uint h = data->height;
            int  byteCount = checked((int)(w * h * 4));
            var  pixels = new byte[byteCount];
            new ReadOnlySpan<byte>(data->pixels, byteCount).CopyTo(pixels);
            return new TextureBuffer(w, h, pixels);
        }
        finally
        {
            _native->free_texture(_native, data);
        }
    }

    /// <summary>
    /// Bakes a mesh primitive (<c>res://primitives/{quad|plane|cube|sphere}</c>) into a
    /// freshly-allocated CPU buffer pair. Returns null when the resolver returns NOT_FOUND.
    /// </summary>
    public MeshShape? ResolveMesh(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_mesh_shape_data data;
        ke_result r;
        fixed (byte* p = bytes)
        {
            r = _native->resolve_mesh(_native, (sbyte*)p, &data);
        }
        if (r == ke_result.KE_ERROR_NOT_FOUND) return null;
        KernelException.ThrowIfFailed(r.ToManaged());

        try
        {
            var verts = new Vertex[data.vertex_count];
            for (uint i = 0; i < data.vertex_count; i++)
            {
                var src = data.vertices[i];
                verts[i] = new Vertex
                {
                    X = src.x, Y = src.y, Z = src.z,
                    Nx = src.nx, Ny = src.ny, Nz = src.nz,
                    U = src.u, V = src.v,
                    Tx = src.tx, Ty = src.ty, Tz = src.tz, Tw = src.tw,
                };
            }
            var idx = new ushort[data.index_count];
            for (uint i = 0; i < data.index_count; i++) idx[i] = data.indices[i];
            return new MeshShape(verts, idx);
        }
        finally
        {
            _native->free_mesh(_native, &data);
        }
    }

    /// <summary>
    /// Parses a <c>.material</c> file via the C plugin and surfaces the resulting spec
    /// as a managed record. Returns null on a missing file.
    /// </summary>
    public MaterialSpec? ResolveMaterial(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        ke_material_spec spec;
        ke_result r;
        fixed (byte* p = bytes)
        {
            r = _native->resolve_material(_native, (sbyte*)p, &spec);
        }
        if (r == ke_result.KE_ERROR_NOT_FOUND) return null;
        KernelException.ThrowIfFailed(r.ToManaged());

        // Fixed buffers in ClangSharp bindings are already address-stable inside the local
        // struct copy; read directly via the indexer-as-pointer trick.
        string? albedo = ReadCString(&spec.albedo_path.e0);
        string? normal = ReadCString(&spec.normal_path.e0);
        return new MaterialSpec(
            BaseColor: new Vector4(spec.base_color[0], spec.base_color[1], spec.base_color[2], spec.base_color[3]),
            Metallic:  spec.metallic,
            Roughness: spec.roughness,
            AlbedoPath: albedo,
            NormalPath: normal);
    }

    private static string? ReadCString(sbyte* p)
    {
        if (p == null || *p == 0) return null;
        return Marshal.PtrToStringUTF8((nint)p);
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}

/// <summary>Decoded RGBA8 pixel buffer plus its dimensions, owned by the caller.</summary>
public sealed record TextureBuffer(uint Width, uint Height, byte[] Pixels);

/// <summary>
/// Managed projection of <c>ke_material_spec</c>: PBR parameters plus res:// paths for
/// any referenced textures (caller resolves them downstream).
/// </summary>
public sealed record MaterialSpec(
    Vector4 BaseColor,
    float   Metallic,
    float   Roughness,
    string? AlbedoPath,
    string? NormalPath);
