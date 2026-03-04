using KernelEngine.Core.Native;

namespace KernelEngine.Core.Logging;

public interface ILoggerSink : IDisposable
{
    unsafe ke_logger_sink NativeSink { get; }
}
