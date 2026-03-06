using System.Runtime.InteropServices;

namespace KernelEngine.Asset.Assimp.Native;

/// <summary>
/// Complete model data returned by <c>ke_asset_loader::load_model</c>.
/// Owned by the loader; free with <c>ke_asset_loader::free_model</c>.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
public unsafe partial struct ke_model_data
{
    [NativeTypeName("ke_mesh_data *")]
    public ke_mesh_data* meshes;

    [NativeTypeName("uint32_t")]
    public uint mesh_count;

    [NativeTypeName("ke_material_data *")]
    public ke_material_data* materials;

    [NativeTypeName("uint32_t")]
    public uint material_count;

    [NativeTypeName("ke_texture_data *")]
    public ke_texture_data* textures;

    [NativeTypeName("uint32_t")]
    public uint texture_count;
}
