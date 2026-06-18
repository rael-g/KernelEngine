namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_window_handle
{
    public ke_window* @ref;

    [NativeTypeName("void (*)(ke_window *)")]
    public delegate* unmanaged[Cdecl]<ke_window*, void> destroy;
}
