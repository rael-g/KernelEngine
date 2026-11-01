using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Window.Native;

public unsafe partial struct ke_window
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, KernelEngine.Result.Native.Result> on_initialize;

    [NativeTypeName("void (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void> on_shutdown;

    [NativeTypeName("bool (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, bool> should_close;

    [NativeTypeName("void (*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void> poll_events;

    [NativeTypeName("void (*)(struct ke_window *, int32_t *, int32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, int*, int*, void> get_size;

    [NativeTypeName("void *(*)(struct ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void*> get_native_handle;
}
