using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using KernelEngine.Asset.Assimp.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed view over a single mesh from a loaded <see cref="ModelData"/>.
/// Memory is owned by the native loader; valid only while the parent <see cref="ModelData"/> is alive.
/// </summary>
public sealed unsafe class MeshData
{
    private readonly ke_vertex*  _vertices;
    private readonly ushort*     _indices;

    /// <summary>Vertex count.</summary>
    public uint VertexCount { get; }

    /// <summary>Index count.</summary>
    public uint IndexCount { get; }

    /// <summary>Index into <see cref="ModelData.Materials"/>; -1 = none.</summary>
    public int MaterialIndex { get; }

    /// <summary>Mesh name.</summary>
    public string Name { get; }

    /// <summary>Raw span of vertices backed by native memory.</summary>
    public ReadOnlySpan<ke_vertex> Vertices => new(_vertices, (int)VertexCount);

    /// <summary>Raw span of indices backed by native memory.</summary>
    public ReadOnlySpan<ushort> Indices => new(_indices, (int)IndexCount);

    internal MeshData(ke_mesh_data* native)
    {
        _vertices     = native->vertices;
        _indices      = native->indices;
        VertexCount   = native->vertex_count;
        IndexCount    = native->index_count;
        MaterialIndex = native->material_index;
        Name          = Marshal.PtrToStringAnsi((nint)native->name) ?? string.Empty;
    }
}

/// <summary>
/// Managed view over a single material from a loaded <see cref="ModelData"/>.
/// </summary>
public sealed class MaterialData
{
    /// <summary>PBR base color (linear RGBA).</summary>
    public Vector4 BaseColor { get; }

    /// <summary>PBR metallic factor.</summary>
    public float Metallic { get; }

    /// <summary>PBR roughness factor.</summary>
    public float Roughness { get; }

    /// <summary>Index into <see cref="ModelData.Textures"/> for the albedo map; -1 = none.</summary>
    public int AlbedoTextureIndex { get; }

    /// <summary>Index into <see cref="ModelData.Textures"/> for the normal map; -1 = none.</summary>
    public int NormalMapTextureIndex { get; }

    /// <summary>Material name.</summary>
    public string Name { get; }

    internal unsafe MaterialData(ke_material_data* native)
    {
        BaseColor             = new Vector4(native->base_color_r, native->base_color_g,
                                            native->base_color_b, native->base_color_a);
        Metallic              = native->metallic;
        Roughness             = native->roughness;
        AlbedoTextureIndex    = native->albedo_texture_index;
        NormalMapTextureIndex = native->normal_map_texture_index;
        Name                  = Marshal.PtrToStringAnsi((nint)native->name) ?? string.Empty;
    }
}

/// <summary>
/// Managed view over a single decoded RGBA8 texture from a loaded <see cref="ModelData"/>.
/// Memory is owned by the native loader; valid only while the parent <see cref="ModelData"/> is alive.
/// </summary>
public sealed unsafe class TextureData
{
    private readonly byte* _pixels;

    /// <summary>Width in pixels.</summary>
    public uint Width { get; }

    /// <summary>Height in pixels.</summary>
    public uint Height { get; }

    /// <summary>Source file path, or empty for embedded textures.</summary>
    public string Path { get; }

    /// <summary>RGBA8 pixel data backed by native memory, <c>Width × Height × 4</c> bytes.</summary>
    public ReadOnlySpan<byte> Pixels => new(_pixels, (int)(Width * Height * 4));

    internal unsafe TextureData(ke_texture_data* native)
    {
        _pixels = native->pixels;
        Width   = native->width;
        Height  = native->height;
        Path    = Marshal.PtrToStringAnsi((nint)native->path) ?? string.Empty;
    }
}

/// <summary>
/// Owns the native <c>ke_model_data</c> returned by <see cref="AssetLoader.LoadModel"/>.
/// Disposing this object frees all native mesh, material, and texture memory.
/// </summary>
public sealed unsafe class ModelData : IDisposable
{
    private KernelEngine.Asset.Assimp.Native.ke_asset_loader* _loader;
    private KernelEngine.Asset.Assimp.Native.ke_model_data*   _native;

    /// <summary>All meshes in the model.</summary>
    public MeshData[] Meshes { get; }

    /// <summary>All materials in the model.</summary>
    public MaterialData[] Materials { get; }

    /// <summary>All decoded textures in the model.</summary>
    public TextureData[] Textures { get; }

    internal ModelData(KernelEngine.Asset.Assimp.Native.ke_asset_loader* loader,
                       KernelEngine.Asset.Assimp.Native.ke_model_data*   native)
    {
        _loader = loader;
        _native = native;

        Meshes = new MeshData[native->mesh_count];
        for (uint i = 0; i < native->mesh_count; i++)
            Meshes[i] = new MeshData(&native->meshes[i]);

        Materials = new MaterialData[native->material_count];
        for (uint i = 0; i < native->material_count; i++)
            Materials[i] = new MaterialData(&native->materials[i]);

        Textures = new TextureData[native->texture_count];
        for (uint i = 0; i < native->texture_count; i++)
            Textures[i] = new TextureData(&native->textures[i]);
    }

    /// <summary>Frees all native memory associated with this model.</summary>
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
/// Wraps a <c>ke_asset_loader*</c> and provides managed access to model loading.
/// </summary>
public sealed unsafe class AssetLoader : IDisposable
{
    private KernelEngine.Asset.Assimp.Native.ke_asset_loader* _native;

    /// <summary>Creates an <see cref="AssetLoader"/> that takes ownership of the given native pointer.</summary>
    public AssetLoader(KernelEngine.Asset.Assimp.Native.ke_asset_loader* native) => _native = native;

    /// <summary>Loads a 3D model from <paramref name="path"/>. Caller must dispose the returned <see cref="ModelData"/>.</summary>
    public ModelData LoadModel(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        var pathPtr = Marshal.StringToHGlobalAnsi(path);
        try
        {
            KernelEngine.Asset.Assimp.Native.ke_model_data* data;
            KernelException.ThrowIfFailed(
                _native->load_model(_native, (sbyte*)pathPtr, &data));
            return new ModelData(_native, data);
        }
        finally
        {
            Marshal.FreeHGlobal(pathPtr);
        }
    }

    /// <summary>
    /// Asynchronously loads a 3D model from <paramref name="path"/> using <paramref name="scheduler"/>.
    /// Completes on the scheduler thread; caller must dispose the returned <see cref="ModelData"/>.
    /// </summary>
    public KeTask<ModelData> LoadModelAsync(string path, TaskScheduler scheduler)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);

        var tcs = new TaskCompletionSource<ModelData>(TaskCreationOptions.RunContinuationsAsynchronously);

        // Store loader as nint because pointers cannot be generic type arguments.
        var state = ((nint)_native, tcs);
        var stateHandle = GCHandle.Alloc(state);

        var pathPtr = Marshal.StringToHGlobalAnsi(path);
        _native->load_model_async(
            _native,
            scheduler.Native,
            (sbyte*)pathPtr,
            &NativeLoadCompleteCallback,
            (void*)GCHandle.ToIntPtr(stateHandle));
        Marshal.FreeHGlobal(pathPtr);

        return KeTask<ModelData>.FromTask(tcs.Task);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void NativeLoadCompleteCallback(
        ke_result result,
        KernelEngine.Asset.Assimp.Native.ke_model_data* data,
        void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var (loaderPtr, tcs) = ((nint, TaskCompletionSource<ModelData>))handle.Target!;
        handle.Free();

        if (result == ke_result.KE_OK)
            tcs.TrySetResult(new ModelData(
                (KernelEngine.Asset.Assimp.Native.ke_asset_loader*)loaderPtr, data));
        else
            tcs.TrySetException(new KernelException(result));
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
