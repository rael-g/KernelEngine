namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_runtime_handle
{
    public ke_runtime* @ref;

    [NativeTypeName("void (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void> destroy;
}
