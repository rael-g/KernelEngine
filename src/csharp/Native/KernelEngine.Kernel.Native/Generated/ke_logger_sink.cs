namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_logger_sink
{
    public void* handle;

    [NativeTypeName("int32_t")]
    public int min_level;

    [NativeTypeName("void (*)(struct ke_logger_sink *, const ke_log_event *)")]
    public delegate* unmanaged[Cdecl]<ke_logger_sink*, ke_log_event*, void> log;

    [NativeTypeName("void (*)(struct ke_logger_sink *)")]
    public delegate* unmanaged[Cdecl]<ke_logger_sink*, void> destroy;
}
