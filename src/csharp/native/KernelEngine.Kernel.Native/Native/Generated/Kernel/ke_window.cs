namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_window
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, ke_result> on_initialize;

    [NativeTypeName("ke_result (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, ke_result> on_shutdown;

    [NativeTypeName("ke_bool (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, byte> should_close;

    [NativeTypeName("ke_result (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, ke_result> poll_events;

    [NativeTypeName("ke_result (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, ke_result> swap_buffers;

    [NativeTypeName("ke_result (*)(struct ke_window *, int32_t *, int32_t *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int*, int*, ke_error**, ke_result> get_size;

    [NativeTypeName("void *(*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void*> get_native_handle;
}
