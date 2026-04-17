namespace KernelEngine.Kernel.Native;

public partial struct ke_mesh_renderer_component
{
    [NativeTypeName("uint32_t")]
    public uint mesh_handle;

    [NativeTypeName("uint32_t")]
    public uint material_handle;
}
