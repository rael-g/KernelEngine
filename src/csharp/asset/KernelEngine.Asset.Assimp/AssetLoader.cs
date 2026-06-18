using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Asset.Assimp;

/// <summary>
/// Managed view over a single mesh from a loaded <see cref="ModelData"/>.
/// Memory is owned by the native loader; valid only while the parent <see cref="ModelData"/> is alive.
/// </summary>
internal sealed unsafe class MeshData : IModelMesh
{
    private readonly ke_vertex* _vertices;
    private readonly ushort*    _indices;
    private readonly uint       _vertexCount;
    private readonly uint       _indexCount;

    public int MaterialIndex { get; }
    public string Name { get; }

    /// <summary>Vertices exposed as managed <see cref="Vertex"/> (binary-compatible with <c>ke_vertex</c>).</summary>
    public ReadOnlySpan<Vertex> Vertices =>
        MemoryMarshal.Cast<ke_vertex, Vertex>(new ReadOnlySpan<ke_vertex>(_vertices, (int)_vertexCount));

    public ReadOnlySpan<ushort> Indices => new(_indices, (int)_indexCount);

    internal MeshData(ke_mesh_data* native)
    {
        _vertices     = native->vertices;
        _indices      = native->indices;
        _vertexCount  = native->vertex_count;
        _indexCount   = native->index_count;
        MaterialIndex = native->material_index;
        Name = Marshal.PtrToStringAnsi((nint)Unsafe.AsPointer(ref native->name.e0)) ?? string.Empty;
    }
}

/// <summary>
/// Managed view over a single material from a loaded <see cref="ModelData"/>.
/// </summary>
internal sealed class MaterialData : IModelMaterial
{
    public Vector4 BaseColor { get; }
    public float Metallic { get; }
    public float Roughness { get; }
    public int AlbedoTextureIndex { get; }
    public int NormalMapTextureIndex { get; }
    public string Name { get; }

    internal unsafe MaterialData(ke_material_data* native)
    {
        BaseColor             = new Vector4(native->base_color_r, native->base_color_g,
                                            native->base_color_b, native->base_color_a);
        Metallic              = native->metallic;
        Roughness             = native->roughness;
        AlbedoTextureIndex    = native->albedo_texture_index;
        NormalMapTextureIndex = native->normal_map_texture_index;
        Name = Marshal.PtrToStringAnsi((nint)Unsafe.AsPointer(ref native->name.e0)) ?? string.Empty;
    }
}

/// <summary>
/// Managed view over a single decoded RGBA8 texture from a loaded <see cref="ModelData"/>.
/// Memory is owned by the native loader; valid only while the parent <see cref="ModelData"/> is alive.
/// </summary>
internal sealed unsafe class TextureData : IModelTexture
{
    private readonly byte* _pixels;
    private readonly uint  _pixelByteCount;

    public uint Width { get; }
    public uint Height { get; }
    public string Path { get; }

    public ReadOnlySpan<byte> Pixels => new(_pixels, (int)_pixelByteCount);

    internal unsafe TextureData(ke_texture_data* native)
    {
        _pixels = native->pixels;
        Width   = native->width;
        Height  = native->height;
        _pixelByteCount = Width * Height * 4;
        Path = Marshal.PtrToStringAnsi((nint)Unsafe.AsPointer(ref native->path.e0)) ?? string.Empty;
    }
}

/// <summary>
/// Owns the native <c>ke_model_data</c> returned by the Assimp loader.
/// Disposing frees all native mesh, material, and texture memory.
/// </summary>
internal sealed unsafe class ModelData : IModel
{
    private ke_asset_loader* _loader;
    private ke_model_data*   _native;

    public IReadOnlyList<IModelMesh> Meshes { get; }
    public IReadOnlyList<IModelMaterial> Materials { get; }
    public IReadOnlyList<IModelTexture> Textures { get; }

    internal ModelData(ke_asset_loader* loader, ke_model_data* native)
    {
        _loader = loader;
        _native = native;

        var meshes = new IModelMesh[native->mesh_count];
        for (uint i = 0; i < native->mesh_count; i++)
            meshes[i] = new MeshData(&native->meshes[i]);
        Meshes = meshes;

        var materials = new IModelMaterial[native->material_count];
        for (uint i = 0; i < native->material_count; i++)
            materials[i] = new MaterialData(&native->materials[i]);
        Materials = materials;

        var textures = new IModelTexture[native->texture_count];
        for (uint i = 0; i < native->texture_count; i++)
            textures[i] = new TextureData(&native->textures[i]);
        Textures = textures;
    }

    public void Dispose()
    {
        if (_loader != null && _native != null)
        {
            _loader->free_model(_loader, _native);
            _loader = null;
            _native = null;
        }
    }
}

/// <summary>
/// Assimp-backed <see cref="IAssetLoader"/>. Created via
/// <c>AddAssimpAssetLoader()</c> and resolved through DI as <see cref="IAssetLoader"/>.
/// </summary>
internal sealed unsafe class AssetLoader : IAssetLoader
{
    private ke_asset_loader* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_asset_loader*, void> _destroy;
    private readonly KernelEngine.Kernel.TaskScheduler _scheduler;

    internal AssetLoader(ke_asset_loader_handle handle, KernelEngine.Kernel.TaskScheduler scheduler)
    {
        _native = handle.@ref;
        _destroy = handle.destroy;
        _scheduler = scheduler;
    }

    public IModel LoadModel(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        var pathPtr = Marshal.StringToHGlobalAnsi(path);
        try
        {
            ke_model_data* data;
            KernelException.ThrowIfFailed(
                _native->load_model(_native, (sbyte*)pathPtr, &data, null).ToManaged());
            return new ModelData(_native, data);
        }
        finally
        {
            Marshal.FreeHGlobal(pathPtr);
        }
    }

    public Task<IModel> LoadModelAsync(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);

        var tcs = new TaskCompletionSource<IModel>(TaskCreationOptions.RunContinuationsAsynchronously);

        // Store loader as nint because pointers cannot be generic type arguments.
        var state = ((nint)_native, tcs);
        var stateHandle = GCHandle.Alloc(state);

        var pathPtr = Marshal.StringToHGlobalAnsi(path);
        _native->load_model_async(
            _native,
            _scheduler.Native,
            (sbyte*)pathPtr,
            &NativeLoadCompleteCallback,
            (void*)GCHandle.ToIntPtr(stateHandle));
        Marshal.FreeHGlobal(pathPtr);

        return tcs.Task;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void NativeLoadCompleteCallback(
        ke_result result,
        ke_model_data* data,
        void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var (loaderPtr, tcs) = ((nint, TaskCompletionSource<IModel>))handle.Target!;
        handle.Free();

        if (result == ke_result.KE_OK)
            tcs.TrySetResult(new ModelData((ke_asset_loader*)loaderPtr, data));
        else
            tcs.TrySetException(new KernelException(result.ToManaged()));
    }

    public void Dispose()
    {
        if (_native != null)
        {
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
    }
}
