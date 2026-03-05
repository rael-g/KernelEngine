namespace KernelEngine.Kernel.Native;

public partial struct ke_message_pipe
{
}

public unsafe partial struct ke_message_pipe
{
    public void* handle;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("void (*)(struct ke_message_pipe *)")]
    public delegate* unmanaged[Cdecl]<ke_message_pipe*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_message_pipe *, uint64_t, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_message_pipe*, ulong, void*, nuint, ke_result> broadcast;

    [NativeTypeName("ke_result (*)(struct ke_message_pipe *, struct ke_message_pipe **)")]
    public delegate* unmanaged[Cdecl]<ke_message_pipe*, ke_message_pipe**, ke_result> create_reader;

    [NativeTypeName("bool (*)(struct ke_message_pipe *, uint64_t, void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_message_pipe*, ulong, void*, nuint, bool> try_receive;

    [NativeTypeName("ke_result (*)(struct ke_message_pipe *)")]
    public delegate* unmanaged[Cdecl]<ke_message_pipe*, ke_result> pump;
}
