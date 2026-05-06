namespace KernelEngine.Kernel.Native;

public partial struct ke_allocator_stats
{
    [NativeTypeName("size_t")]
    public nuint total_allocated;

    [NativeTypeName("size_t")]
    public nuint total_freed;

    [NativeTypeName("size_t")]
    public nuint active_bytes;

    [NativeTypeName("uint32_t")]
    public uint active_allocs;
}
