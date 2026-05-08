namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_system_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_system_update_func")]
    public delegate* unmanaged[Cdecl]<void*, ke_world*, float, ke_frame_packet*, void> update;

    public void* handle;

    [NativeTypeName("const uint32_t *")]
    public uint* reads;

    [NativeTypeName("uint32_t")]
    public uint read_count;

    [NativeTypeName("const uint32_t *")]
    public uint* writes;

    [NativeTypeName("uint32_t")]
    public uint write_count;
}
