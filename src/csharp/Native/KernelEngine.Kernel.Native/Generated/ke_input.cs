namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_input
{
    public void* handle;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("struct ke_message_pipe *")]
    public ke_message_pipe* message_pipe;

    [NativeTypeName("void (*)(struct ke_input *)")]
    public delegate* unmanaged[Cdecl]<ke_input*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_input *)")]
    public delegate* unmanaged[Cdecl]<ke_input*, ke_result> update;

    [NativeTypeName("bool (*)(struct ke_input *, int)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, bool> is_key_pressed;

    [NativeTypeName("bool (*)(struct ke_input *, int)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, bool> is_key_released;

    [NativeTypeName("bool (*)(struct ke_input *, int)")]
    public delegate* unmanaged[Cdecl]<ke_input*, int, bool> is_key_down;

    public partial struct ke_allocator
    {
    }

    public partial struct ke_logger
    {
    }

    public partial struct ke_message_pipe
    {
    }
}
