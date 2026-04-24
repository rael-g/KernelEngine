using KernelEngine.Kernel.Native;

namespace KernelEngine.Threading.Native;

public unsafe partial struct ke_semaphore
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_semaphore *, ke_allocator *)")]
    public delegate* unmanaged[Cdecl]<ke_semaphore*, ke_allocator*, void> destroy;

    [NativeTypeName("void (*)(struct ke_semaphore *)")]
    public delegate* unmanaged[Cdecl]<ke_semaphore*, void> signal;

    [NativeTypeName("void (*)(struct ke_semaphore *)")]
    public delegate* unmanaged[Cdecl]<ke_semaphore*, void> wait;
}
