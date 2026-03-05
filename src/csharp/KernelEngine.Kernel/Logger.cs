using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Structured logger. Dispatches events to registered sinks.
/// </summary>
public sealed unsafe class Logger : IDisposable
{
    private ke_logger* _native;

    // GCHandles keep managed sinks alive while native code holds function pointers to them.
    private readonly List<GCHandle> _sinkHandles = [];

    public ke_logger* Native
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
        var desc = new ke_descriptor { allocator = allocator.Native };
        ke_logger* logger;
        KernelException.ThrowIfFailed(NativeMethods.logger_create(&desc, &logger));
        _native = logger;
    }

    /// <summary>Registers a managed sink to receive all subsequent log events.</summary>
    public void AddSink(ILoggerSink sink)
    {
        var handle = GCHandle.Alloc(sink);
        _sinkHandles.Add(handle);

        var nativeSink = new ke_logger_sink
        {
            handle = GCHandle.ToIntPtr(handle).ToPointer(),
            log = &LogCallback,
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
        sink.Log((ke_log_level)evt->level, tag, message);
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
