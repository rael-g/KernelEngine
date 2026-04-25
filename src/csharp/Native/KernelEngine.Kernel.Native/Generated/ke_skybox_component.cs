namespace KernelEngine.Kernel.Native;

public partial struct ke_skybox_component
{
    [NativeTypeName("uint32_t")]
    public uint cubemap_handle;
}
