namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_descriptor
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;
}
