namespace KernelEngine.Core.Native;

public partial struct ke_logger
{
}

public unsafe partial struct ke_logger
{
    public void* handle;

    public int runtime_limit;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("void (*)(struct ke_logger *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, void> destroy;

    [NativeTypeName("void (*)(struct ke_logger *, int, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, int, sbyte*, sbyte*, void> log;

    [NativeTypeName("ke_result (*)(struct ke_logger *, ke_logger_sink)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, ke_logger_sink, ke_result> add_sink;
}
