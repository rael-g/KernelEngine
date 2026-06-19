namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_render_handle
{
    public ke_render* @ref;

    [NativeTypeName("void (*)(ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, void> destroy;
}
