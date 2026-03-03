namespace KernelEngine.Core.Native;

public unsafe partial struct ke_array
{
    public void** data;

    [NativeTypeName("size_t")]
    public nuint size;

    [NativeTypeName("size_t")]
    public nuint capacity;

    public ke_allocator* allocator;
}
