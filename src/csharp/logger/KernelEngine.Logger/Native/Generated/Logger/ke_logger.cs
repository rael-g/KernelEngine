using KernelEngine.Common.Native;

namespace KernelEngine.Logger.Native;

public unsafe partial struct ke_logger
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_logger *, const ke_log_event *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, ke_log_event*, void> log;

    [NativeTypeName("void (*)(struct ke_logger *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, void> flush;

    [NativeTypeName("bool (*)(struct ke_logger *, ke_logger_sink, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, ke_logger_sink, ke_error**, bool> add_sink;
}
