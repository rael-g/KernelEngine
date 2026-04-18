namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_world_params
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;
}
