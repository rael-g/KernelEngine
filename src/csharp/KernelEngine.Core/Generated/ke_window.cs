namespace KernelEngine.Core.Native;

public unsafe partial struct ke_window
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void> destroy;

    [NativeTypeName("bool (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, byte> should_close;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_result> poll_events;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_result> swap_buffers;

    [NativeTypeName("ke_result (*)(struct ke_window *, int *, int *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int*, int*, ke_result> get_size;

    [NativeTypeName("void *(*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void*> get_native_handle;
}
