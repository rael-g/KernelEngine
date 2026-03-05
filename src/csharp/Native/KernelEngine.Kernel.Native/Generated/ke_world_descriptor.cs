namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_world_descriptor
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_render *")]
    public ke_render* renderer;

    [NativeTypeName("struct ke_window *")]
    public ke_window* window;
}
