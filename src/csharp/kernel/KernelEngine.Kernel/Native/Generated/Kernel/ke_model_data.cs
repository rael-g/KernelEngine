namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_model_data
{
    public ke_mesh_data* meshes;

    [NativeTypeName("uint32_t")]
    public uint mesh_count;

    public ke_material_data* materials;

    [NativeTypeName("uint32_t")]
    public uint material_count;

    public ke_texture_data* textures;

    [NativeTypeName("uint32_t")]
    public uint texture_count;
}
