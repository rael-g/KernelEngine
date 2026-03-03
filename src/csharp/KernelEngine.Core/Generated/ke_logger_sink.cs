namespace KernelEngine.Core.Native;

public unsafe partial struct ke_logger_sink
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_logger_sink *, int, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_logger_sink*, int, sbyte*, sbyte*, void> log;

    [NativeTypeName("void (*)(struct ke_logger_sink *)")]
    public delegate* unmanaged[Cdecl]<ke_logger_sink*, void> destroy;
}
