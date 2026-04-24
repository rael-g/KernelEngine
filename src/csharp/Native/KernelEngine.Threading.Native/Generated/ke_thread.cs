using KernelEngine.Kernel.Native;

namespace KernelEngine.Threading.Native;

public unsafe partial struct ke_thread
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_thread *, ke_allocator *)")]
    public delegate* unmanaged[Cdecl]<ke_thread*, ke_allocator*, void> destroy;

    [NativeTypeName("void (*)(struct ke_thread *)")]
    public delegate* unmanaged[Cdecl]<ke_thread*, void> join;
}
