using System.Runtime.InteropServices;
using KernelEngine.Core.Native;
using KernelEngine.Core.Logging;
using Serilog;
using Serilog.Events;

namespace KernelEngine.Logging.Serilog;

public unsafe class SerilogSink : ILoggerSink
{
    private static ILogger? _staticLogger;
    private ke_logger_sink _nativeSink;

    public ke_logger_sink NativeSink => _nativeSink;

    public SerilogSink(ILogger logger)
    {
        _staticLogger = logger;

        _nativeSink = new ke_logger_sink
        {
            handle = null,
            log = &OnLog,
            destroy = &OnDestroy
        };
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static void OnLog(ke_logger_sink* self, ke_log_event* ev)
    {
        if (_staticLogger == null || ev == null) return;

        string tagStr = Marshal.PtrToStringAnsi((IntPtr)ev->tag) ?? "unknown";
        string msgStr = Marshal.PtrToStringAnsi((IntPtr)ev->message) ?? "";

        var serilogLevel = ev->level switch
        {
            (int)ke_log_level.KE_LOG_LEVEL_TRACE => LogEventLevel.Verbose,
            (int)ke_log_level.KE_LOG_LEVEL_DEBUG => LogEventLevel.Debug,
            (int)ke_log_level.KE_LOG_LEVEL_INFO => LogEventLevel.Information,
            (int)ke_log_level.KE_LOG_LEVEL_WARNING => LogEventLevel.Warning,
            (int)ke_log_level.KE_LOG_LEVEL_ERROR => LogEventLevel.Error,
            (int)ke_log_level.KE_LOG_LEVEL_CRITICAL => LogEventLevel.Fatal,
            _ => LogEventLevel.Information
        };

        _staticLogger.Write(serilogLevel, "[{Tag}] {Message}", tagStr, msgStr);
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static void OnDestroy(ke_logger_sink* self)
    {
    }

    public void Dispose()
    {
        _staticLogger = null;
        GC.SuppressFinalize(this);
    }

    ~SerilogSink()
    {
        Dispose();
    }
}
