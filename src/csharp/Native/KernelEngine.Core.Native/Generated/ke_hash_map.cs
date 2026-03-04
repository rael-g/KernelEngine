namespace KernelEngine.Core.Native;

public unsafe partial struct ke_hash_map
{
    public ke_hash_map_entry* entries;

    [NativeTypeName("size_t")]
    public nuint size;

    [NativeTypeName("size_t")]
    public nuint capacity;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    public partial struct ke_allocator
    {
    }
}
