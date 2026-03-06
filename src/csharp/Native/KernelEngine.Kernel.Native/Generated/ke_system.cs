namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_system
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_world *, void *, float)")]
    public delegate* unmanaged[Cdecl]<ke_world*, void*, float, void> update;

    [NativeTypeName("void (*)(void *)")]
    public delegate* unmanaged[Cdecl]<void*, void> destroy;
}
