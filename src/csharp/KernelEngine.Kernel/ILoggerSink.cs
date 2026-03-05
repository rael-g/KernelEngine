using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Receives structured log events dispatched by a <see cref="Logger"/>.
/// </summary>
public interface ILoggerSink
{
    void Log(ke_log_level level, string tag, string message);
}
