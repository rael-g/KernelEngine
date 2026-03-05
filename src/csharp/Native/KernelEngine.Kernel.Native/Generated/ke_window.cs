namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_window
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_result> on_initialize;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_result> on_shutdown;

    [NativeTypeName("bool (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, bool> should_close;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_result> poll_events;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_result> swap_buffers;

    [NativeTypeName("ke_result (*)(struct ke_window *, int *, int *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int*, int*, ke_result> get_size;

    [NativeTypeName("void *(*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void*> get_native_handle;
}
