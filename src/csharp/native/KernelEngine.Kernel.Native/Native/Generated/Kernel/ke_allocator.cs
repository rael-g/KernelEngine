namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_allocator
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_allocator *)")]
    public delegate* unmanaged[Cdecl]<ke_allocator*, void> destroy;

    [NativeTypeName("void *(*)(struct ke_allocator *, size_t, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_allocator*, nuint, nuint, void*> alloc;

    [NativeTypeName("void (*)(struct ke_allocator *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_allocator*, void*, void> free;

    [NativeTypeName("void *(*)(struct ke_allocator *, void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_allocator*, void*, nuint, void*> realloc;

    [NativeTypeName("void (*)(struct ke_allocator *)")]
    public delegate* unmanaged[Cdecl]<ke_allocator*, void> reset;
}

public partial struct ke_allocator
{
}
