using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Structured logger. Dispatches events to registered sinks.
/// </summary>
public sealed unsafe class Logger : ILogger, IDisposable
{
    private ke_logger* _native;

    // GCHandles keep managed sinks alive while native code holds function pointers to them.
    private readonly List<GCHandle> _sinkHandles = [];

    internal ke_logger* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    private Logger(ke_logger* native) => _native = native;

    /// <summary>Creates a logger using the given allocator.</summary>
    public Logger(Allocator allocator)
    {
        ke_logger* logger;
        KernelException.ThrowIfFailed(NativeMethods.logger_create(allocator.Native, &logger).ToManaged());
        _native = logger;
    }

    /// <summary>Dispatches a log event to all registered sinks.</summary>
    public void Log(LogLevel level, string tag, string message)
    {
        var tagBytes = System.Text.Encoding.ASCII.GetBytes(tag + '\0');
        var msgBytes = System.Text.Encoding.ASCII.GetBytes(message + '\0');
        fixed (byte* tagPtr = tagBytes, msgPtr = msgBytes)
        {
            var evt = new ke_log_event
            {
                level = (int)level,
                tag = (sbyte*)tagPtr,
                message = (sbyte*)msgPtr,
            };
            _native->log(_native, &evt);
        }
    }

    public void Trace(string tag, string message)    => Log(LogLevel.Trace, tag, message);
    public void Debug(string tag, string message)    => Log(LogLevel.Debug, tag, message);
    public void Info(string tag, string message)     => Log(LogLevel.Info, tag, message);
    public void Warning(string tag, string message)  => Log(LogLevel.Warning, tag, message);
    public void Error(string tag, string message)    => Log(LogLevel.Error, tag, message);
    public void Critical(string tag, string message) => Log(LogLevel.Critical, tag, message);

    /// <summary>Flushes all registered sinks.</summary>
    public void Flush()
    {
        _native->flush(_native);
    }

    /// <summary>Registers a managed sink to receive all subsequent log events.</summary>
    /// <param name="sink">The sink implementation.</param>
    /// <param name="minLevel">Minimum level forwarded to this sink. Defaults to <see cref="LogLevel.Trace"/>.</param>
    public void AddSink(ILoggerSink sink, LogLevel minLevel = LogLevel.Trace)
    {
        var handle = GCHandle.Alloc(sink);
        _sinkHandles.Add(handle);

        var nativeSink = new ke_logger_sink
        {
            handle = GCHandle.ToIntPtr(handle).ToPointer(),
            min_level = (int)minLevel,
            log = &LogCallback,
            flush = &FlushCallback,
            destroy = &SinkDestroy,
        };

        _native->add_sink(_native, nativeSink);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void LogCallback(ke_logger_sink* self, ke_log_event* evt)
    {
        var sink = (ILoggerSink)GCHandle.FromIntPtr((nint)self->handle).Target!;
        string tag = Marshal.PtrToStringAnsi((nint)evt->tag) ?? string.Empty;
        string message = Marshal.PtrToStringAnsi((nint)evt->message) ?? string.Empty;
        sink.Log((LogLevel)evt->level, tag, message);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void FlushCallback(ke_logger_sink* self)
    {
        var sink = (ILoggerSink)GCHandle.FromIntPtr((nint)self->handle).Target!;
        sink.Flush();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void SinkDestroy(ke_logger_sink* self)
    {
        GCHandle.FromIntPtr((nint)self->handle).Free();
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
