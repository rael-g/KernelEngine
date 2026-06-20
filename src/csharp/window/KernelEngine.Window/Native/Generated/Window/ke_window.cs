using KernelEngine.Common.Native;

namespace KernelEngine.Window.Native;

public unsafe partial struct ke_window
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, bool> on_initialize;

    [NativeTypeName("bool (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, bool> on_shutdown;

    [NativeTypeName("ke_bool (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, byte> should_close;

    [NativeTypeName("bool (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, bool> poll_events;

    [NativeTypeName("bool (*)(struct ke_window *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, ke_error**, bool> swap_buffers;

    [NativeTypeName("bool (*)(struct ke_window *, int32_t *, int32_t *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int*, int*, ke_error**, bool> get_size;

    [NativeTypeName("void *(*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void*> get_native_handle;
}
