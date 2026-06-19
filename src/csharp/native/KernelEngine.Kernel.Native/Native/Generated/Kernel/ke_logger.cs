namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_logger
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_logger *, const ke_log_event *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, ke_log_event*, void> log;

    [NativeTypeName("void (*)(struct ke_logger *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, void> flush;

    [NativeTypeName("ke_result (*)(struct ke_logger *, ke_logger_sink, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, ke_logger_sink, ke_error**, ke_result> add_sink;
}

public partial struct ke_logger
{
}

public partial struct ke_logger
{
}
