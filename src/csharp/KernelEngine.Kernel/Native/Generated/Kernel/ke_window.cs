namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_window
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int> on_initialize;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int> on_shutdown;

    [NativeTypeName("bool (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, bool> should_close;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int> poll_events;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int> swap_buffers;

    [NativeTypeName("ke_result (*)(struct ke_window *, int32_t *, int32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int*, int*, int> get_size;

    [NativeTypeName("void *(*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void*> get_native_handle;
}
