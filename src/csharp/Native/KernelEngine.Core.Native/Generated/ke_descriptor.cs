namespace KernelEngine.Core.Native;

public unsafe partial struct ke_descriptor
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("struct ke_message_pipe *")]
    public ke_message_pipe* message_pipe;
}
