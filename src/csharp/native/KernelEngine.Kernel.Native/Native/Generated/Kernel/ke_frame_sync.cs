namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_frame_sync
{
    public void* handle;

    [NativeTypeName("ke_frame_packet *(*)(struct ke_frame_sync *)")]
    public delegate* unmanaged[Cdecl]<ke_frame_sync*, ke_frame_packet*> begin_write;

    [NativeTypeName("void (*)(struct ke_frame_sync *)")]
    public delegate* unmanaged[Cdecl]<ke_frame_sync*, void> end_write;

    [NativeTypeName("ke_frame_packet *(*)(struct ke_frame_sync *)")]
    public delegate* unmanaged[Cdecl]<ke_frame_sync*, ke_frame_packet*> begin_read;

    [NativeTypeName("void (*)(struct ke_frame_sync *)")]
    public delegate* unmanaged[Cdecl]<ke_frame_sync*, void> end_read;
}
