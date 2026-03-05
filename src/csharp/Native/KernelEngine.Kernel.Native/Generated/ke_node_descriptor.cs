namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_node_descriptor
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("ke_result (*)(ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_result> on_start;

    [NativeTypeName("ke_result (*)(ke_node *, float)")]
    public delegate* unmanaged[Cdecl]<ke_node*, float, ke_result> on_update;

    public void* user_data;

    public partial struct ke_allocator
    {
    }
}
