namespace KernelEngine.Framework.Native;

public partial struct ke_create_shadow_map_cmd
{
    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;
}
