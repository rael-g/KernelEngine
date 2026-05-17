namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_ecs_registry
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("ke_entity")]
    public ulong next_entity;

    public void* internal_data;
}
