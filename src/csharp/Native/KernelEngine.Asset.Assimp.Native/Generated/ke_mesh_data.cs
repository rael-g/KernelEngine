using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Asset.Assimp.Native;

/// <summary>Raw CPU-side mesh data returned by <c>ke_asset_loader::load_model</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public unsafe partial struct ke_mesh_data
{
    [NativeTypeName("ke_vertex *")]
    public ke_vertex* vertices;

    [NativeTypeName("uint32_t")]
    public uint vertex_count;

    [NativeTypeName("uint16_t *")]
    public ushort* indices;

    [NativeTypeName("uint32_t")]
    public uint index_count;

    /// <summary>Index into <c>ke_model_data.materials</c>; -1 = none.</summary>
    [NativeTypeName("int32_t")]
    public int material_index;

    [NativeTypeName("char[64]")]
    public fixed sbyte name[64];
}
