namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_thread
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_thread *, ke_allocator *)")]
    public delegate* unmanaged[Cdecl]<ke_thread*, ke_allocator*, void> destroy;

    [NativeTypeName("void (*)(struct ke_thread *)")]
    public delegate* unmanaged[Cdecl]<ke_thread*, void> join;

    [NativeTypeName("ke_bool (*)(struct ke_thread *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_thread*, uint, byte> join_timeout;
}
