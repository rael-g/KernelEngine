using System.Runtime.InteropServices;

namespace KernelEngine.Asset.Assimp.Native;

/// <summary>Raw CPU-side material data returned by <c>ke_asset_loader::load_model</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public unsafe partial struct ke_material_data
{
    public float base_color_r, base_color_g, base_color_b, base_color_a;
    public float metallic;
    public float roughness;

    /// <summary>Index into <c>ke_model_data.textures</c>; -1 = none.</summary>
    [NativeTypeName("int32_t")]
    public int albedo_texture_index;

    /// <summary>Index into <c>ke_model_data.textures</c>; -1 = none.</summary>
    [NativeTypeName("int32_t")]
    public int normal_map_texture_index;

    [NativeTypeName("char[64]")]
    public fixed sbyte name[64];
}
